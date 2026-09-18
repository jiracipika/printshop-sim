#!/usr/bin/env python3
"""Reproducible release Web export for Print Shop Sim.

Pipeline (stdlib + Godot only):
  1. Compute source state: full HEAD SHA and truthful dirty status. Generated
     output (web/build/) and local log artifacts are excluded from dirtiness.
  2. Temporarily stamp scripts/Version.gd with the exact HEAD SHA (+ "-dirty"
     marker when the source tree is dirty). Original file bytes are always
     restored in a finally block, on success and failure alike.
  3. Clear stale generated output first: the four required export files and
     build-info.json are removed before the engine runs, so a failed or
     zero-output export can never be masked by (or leave behind) stale
     artifacts from a previous build. Deletion is constrained to those known
     names inside web/build/ — source files and arbitrary paths are never
     touched, and custom --output targets other than the documented
     web/build/index.html are rejected up front.
  4. Run `godot --headless --export-release Web web/build/index.html` with a
     finite timeout, capturing combined output; exit 0 is not trusted if the
     output contains "SCRIPT ERROR" or "Parse Error".
  5. Validate that index.html, index.js, index.wasm and index.pck exist and
     are nonempty.
  6. Write web/build/build-info.json with the full source SHA and the
     truthful (pre-stamp) dirty status.

No-HEAD repositories (fresh `git init`, or not a repo at all) are handled
honestly: the stamp is "unknown", head_found=false and the tree is reported
dirty rather than pretending a clean pin.

Unit tests inject a fake engine process; real exports must run this script
directly. See tests/test_build_web.py and docs/worker-build-pipeline.md.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Callable, List, Optional, Sequence, Tuple

PROJECT_DIR_DEFAULT = Path(__file__).resolve().parent.parent
VERSION_GD_REL = Path("scripts/Version.gd")
OUTPUT_REL = Path("web/build/index.html")
BUILD_INFO_REL = Path("web/build/build-info.json")
REQUIRED_OUTPUTS = ("index.html", "index.js", "index.wasm", "index.pck")
DIRTY_SUFFIX = "-dirty"
UNKNOWN_SHA = "unknown"

# Finite upper bound for the real engine subprocess (bounded builds; a hung
# godot must not block a CI worker forever). Unit tests may shrink this.
ENGINE_TIMEOUT_SECONDS = 900

# Godot prints these on stderr/stdout even when the export exit code is 0
# (e.g. a script compile error can still yield a stale/broken pack).
ENGINE_FAILURE_MARKERS = ("SCRIPT ERROR", "Parse Error")

# Paths that never count as source dirtiness: generated build output and
# local-only logs/config. vercel.json is deliberately NOT listed here: it is
# deployment source configuration and must count as dirtiness. Order does not
# matter; match on POSIX-style strings.
NON_SOURCE_PREFIXES = (
    "web/build/",
    ".baseline_logs/",
    ".vercel/",
)
NON_SOURCE_SUFFIXES = (".log",)

GIT_SHA_RE = re.compile(r'const GIT_SHA := ".*"')
VERSION_RE = re.compile(r'const VERSION := "([^"]*)"')

EngineRunner = Callable[[Sequence[str], Path], "subprocess.CompletedProcess"]


class BuildError(Exception):
    """Fatal, user-visible build failure."""


def _norm(path: str) -> str:
    p = path.replace("\\", "/")
    return p[2:] if p.startswith("./") else p


def is_non_source_path(path: str) -> bool:
    # git status collapses untracked directories (e.g. `?? web/build/`),
    # so a trailing slash means "this whole directory".
    p = _norm(path).lstrip("/").rstrip("/")
    return (
        any(p == pre.rstrip("/") or p.startswith(pre) for pre in NON_SOURCE_PREFIXES)
        or p.endswith(NON_SOURCE_SUFFIXES)
    )


# --------------------------------------------------------------------------
# Git state
# --------------------------------------------------------------------------

def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
    )


def head_sha(repo: Path) -> Tuple[Optional[str], Optional[str]]:
    """Return (full_sha, short_sha); (None, None) when HEAD cannot resolve."""
    proc = _git(repo, "rev-parse", "HEAD")
    if proc.returncode != 0:
        return None, None
    full = proc.stdout.strip()
    short = _git(repo, "rev-parse", "--short", "HEAD").stdout.strip()
    return full, short


def dirty_paths(repo: Path) -> Tuple[List[str], List[str]]:
    """Return (source_dirty_paths, excluded_paths) from porcelain status."""
    proc = _git(repo, "status", "--porcelain")
    if proc.returncode != 0 or proc.stdout is None:
        # Not a repo (or git broken): treat everything as unknown/dirty.
        return [], []
    source: List[str] = []
    excluded: List[str] = []
    for line in proc.stdout.splitlines():
        if len(line) < 4:
            continue
        entry = line[3:].strip()
        if " -> " in entry:  # rename: keep the destination
            entry = entry.split(" -> ", 1)[1]
        entry = entry.strip('"')
        if not entry:
            continue
        (excluded if is_non_source_path(entry) else source).append(entry)
    return source, excluded


def compute_source_state(repo: Path) -> dict:
    full, short = head_sha(repo)
    source_dirty, excluded = dirty_paths(repo)
    dirty = bool(source_dirty) or full is None
    return {
        "head_found": full is not None,
        "git_sha_full": full,
        "git_sha_short": short,
        "source_dirty": dirty,
        "source_dirty_paths": source_dirty,
        "excluded_from_dirty": excluded,
    }


def stamp_label(state: dict) -> str:
    if not state["head_found"]:
        return UNKNOWN_SHA
    label = state["git_sha_full"]
    assert label is not None
    return label + (DIRTY_SUFFIX if state["source_dirty"] else "")


# --------------------------------------------------------------------------
# Version.gd stamping (always restored)
# --------------------------------------------------------------------------

@contextmanager
def stamped_version(project_dir: Path, label: str):
    """Temporarily stamp GIT_SHA in scripts/Version.gd; restore in finally."""
    version_gd = project_dir / VERSION_GD_REL
    if not version_gd.is_file():
        raise BuildError(f"missing {VERSION_GD_REL}")
    original = version_gd.read_bytes()
    text = original.decode("utf-8")
    if not GIT_SHA_RE.search(text):
        raise BuildError(
            f"no `const GIT_SHA := \"...\"` line found in {VERSION_GD_REL}"
        )
    try:
        version_gd.write_text(
            GIT_SHA_RE.sub(f'const GIT_SHA := "{label}"', text),
            encoding="utf-8",
        )
        yield
    finally:
        version_gd.write_bytes(original)


def read_project_version(project_dir: Path) -> str:
    text = (project_dir / VERSION_GD_REL).read_text(encoding="utf-8")
    match = VERSION_RE.search(text)
    return match.group(1) if match else UNKNOWN_SHA


# --------------------------------------------------------------------------
# Export
# --------------------------------------------------------------------------

def default_engine_runner(cmd: Sequence[str], cwd: Path) -> subprocess.CompletedProcess:
    """Real engine invocation: finite timeout, combined captured output."""
    return subprocess.run(
        list(cmd),
        cwd=str(cwd),
        capture_output=True,
        text=True,
        timeout=ENGINE_TIMEOUT_SECONDS,
    )


def validate_output_path(project_dir: Path, output: Path) -> Path:
    """Restrict --output to the documented web/build/index.html target.

    A custom target would need matching file basenames AND build-info handling
    to stay consistent; until that exists, only the documented default is
    accepted. This also guarantees deletion in clear_generated_outputs() is
    always confined to web/build/.
    """
    out_dir = (project_dir / output).parent.resolve()
    allowed_dir = (project_dir / OUTPUT_REL).parent.resolve()
    if out_dir != allowed_dir or output.name != OUTPUT_REL.name:
        raise BuildError(
            f"unsupported --output {output}: only the documented target "
            f"{OUTPUT_REL} is supported (custom targets are not wired up yet)"
        )
    return project_dir / output


def clear_generated_outputs(project_dir: Path, output: Path) -> None:
    """Remove stale required outputs + build-info before the engine runs.

    Deletion is constrained: only the known REQUIRED_OUTPUTS names and the
    build-info file, and only inside the export output directory, which
    validate_output_path() has already pinned to web/build/. Source files and
    arbitrary user paths are never touched. The directory is created fresh so
    a clean checkout works.
    """
    out_dir = (project_dir / output).parent
    out_dir.mkdir(parents=True, exist_ok=True)
    out_dir_resolved = out_dir.resolve()
    stale = [out_dir / name for name in REQUIRED_OUTPUTS]
    stale.append(project_dir / BUILD_INFO_REL)
    for path in stale:
        resolved = path.resolve()
        # Defensive: never delete anything outside the pinned build directory
        # (build-info.json lives there too for the documented output).
        if resolved.parent != out_dir_resolved:
            raise BuildError(f"refusing to delete unexpected path: {resolved}")
        if resolved.is_file():
            resolved.unlink()


def _engine_failure(proc: subprocess.CompletedProcess) -> Optional[str]:
    """Return a failure description if the engine run looks failed."""
    if proc.returncode != 0:
        return f"export failed (exit {proc.returncode})"

    def _out(p) -> str:
        out = getattr(p, "stdout", None) or ""
        err = getattr(p, "stderr", None) or ""
        return (out if isinstance(out, str) else "") + (
            err if isinstance(err, str) else ""
        )

    text = _out(proc)
    for marker in ENGINE_FAILURE_MARKERS:
        if marker in text:
            return f"export failed (exit 0 but engine reported {marker!r})"
    return None


def run_export(
    project_dir: Path,
    engine: str,
    output: Path,
    runner: EngineRunner = default_engine_runner,
) -> subprocess.CompletedProcess:
    cmd = [engine, "--headless", "--export-release", "Web", str(output)]
    return runner(cmd, project_dir)


def validate_outputs(project_dir: Path, output: Path) -> dict:
    out_dir = (project_dir / output).parent
    info = {}
    missing = []
    for name in REQUIRED_OUTPUTS:
        path = out_dir / name
        ok = path.is_file() and path.stat().st_size > 0
        info[name] = path.stat().st_size if ok else 0
        if not ok:
            missing.append(name)
    if missing:
        raise BuildError(
            "export output incomplete; missing or empty: " + ", ".join(missing)
        )
    return info


def write_build_info(
    project_dir: Path,
    state: dict,
    stamped: str,
    engine: str,
    output_sizes: dict,
) -> Path:
    info = {
        "version": read_project_version(project_dir),
        "git_sha_full": state["git_sha_full"],
        "git_sha": state["git_sha_short"],
        "head_found": state["head_found"],
        "source_dirty": state["source_dirty"],
        "stamped_sha": stamped,
        "engine": engine,
        "outputs": output_sizes,
        "notes": (
            "git_sha_full/source_dirty describe the SOURCE tree at build time "
            "(generated output and local logs excluded from dirtiness). "
            "stamped_sha is what scripts/Version.gd contained during export."
        )
        + (
            " No git HEAD was resolvable; build is not reproducibly pinned."
            if not state["head_found"]
            else ""
        ),
    }
    if state["source_dirty"]:
        info["source_dirty_paths"] = state["source_dirty_paths"]
    if state["excluded_from_dirty"]:
        info["excluded_from_dirty"] = state["excluded_from_dirty"]
    path = project_dir / BUILD_INFO_REL
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(info, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def build(
    project_dir: Path,
    engine: str = "godot",
    output: Path = OUTPUT_REL,
    engine_runner: EngineRunner = default_engine_runner,
) -> dict:
    project_dir = project_dir.resolve()
    output = validate_output_path(project_dir, output)
    state = compute_source_state(project_dir)
    label = stamp_label(state)
    with stamped_version(project_dir, label):
        # Clear stale artifacts INSIDE the stamp context, right before the
        # engine runs, so no old output can mask a failed/no-output export.
        clear_generated_outputs(project_dir, output)
        proc = run_export(project_dir, engine, output, runner=engine_runner)
        failure = _engine_failure(proc)
        if failure:
            detail = (proc.stderr or proc.stdout or "").strip()
            raise BuildError(f"{failure}:\n{detail}" if detail else failure)
        sizes = validate_outputs(project_dir, output)
    info_path = write_build_info(project_dir, state, label, engine, sizes)
    return {"state": state, "stamped": label, "outputs": sizes, "build_info": info_path}


def print_state(project_dir: Path) -> None:
    state = compute_source_state(project_dir)
    state["stamped_label"] = stamp_label(state)
    print(json.dumps(state, indent=2, sort_keys=True))


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--project-dir", type=Path, default=PROJECT_DIR_DEFAULT)
    parser.add_argument("--engine", default="godot")
    parser.add_argument(
        "--output",
        type=Path,
        default=OUTPUT_REL,
        help=(
            "export target path relative to the project; only the documented "
            "default web/build/index.html is currently supported"
        ),
    )
    parser.add_argument(
        "--print-state",
        action="store_true",
        help="print computed git source state as JSON and exit (no stamp, no export)",
    )
    args = parser.parse_args(argv)
    try:
        if args.print_state:
            print_state(args.project_dir)
            return 0
        result = build(args.project_dir, engine=args.engine, output=args.output)
    except BuildError as exc:
        print(f"build_web: ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"Stamped Version.gd with: {result['stamped']}")
    for name, size in sorted(result["outputs"].items()):
        print(f"  {name}: {size} bytes")
    print(f"Build info: {result['build_info']}")
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
