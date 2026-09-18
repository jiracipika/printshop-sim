"""Unit tests for tools/build_web.py.

MOCKED UNIT TESTS: the Godot engine is never invoked. The engine process is
replaced by an injectable fake (FakeEngine) that succeeds or fails on demand,
so stamp/restore behavior is covered on both paths.

These results DO NOT prove a real export works. The real Godot export is run
separately by the parent/integration worker via tools/build_web.sh — see
docs/worker-build-pipeline.md for the distinction.
"""

import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from typing import List, Optional, Sequence

TOOLS_DIR = Path(__file__).resolve().parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import build_web  # noqa: E402

VERSION_CONTENT = textwrap.dedent(
    """\
    extends Node

    const VERSION := "0.0.1"
    const GIT_SHA := "9d42ef7"  # stamped by tools/build_web.sh at export time

    func label() -> String:
    \tif GIT_SHA.is_empty():
    \t\treturn "Alpha %s" % VERSION
    \treturn "Alpha %s Git: %s" % [VERSION, GIT_SHA]
    """
)

HEAD_FULL = "a" * 40


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True
    )


class FakeEngine:
    """Injectable fake godot process for unit tests ONLY (no real export)."""

    def __init__(
        self,
        exit_code: int = 0,
        stderr: str = "",
        produce: bool = True,
        output_text: str = "",
        write_build_info: bool = False,
    ):
        self.exit_code = exit_code
        self.stderr = stderr
        self.produce = produce
        self.output_text = output_text
        self.write_build_info = write_build_info
        self.calls: List[List[str]] = []

    def __call__(self, cmd: Sequence[str], cwd: Path) -> subprocess.CompletedProcess:
        self.calls.append(list(cmd))
        # The fake targets the real engine's output path (last cmd element),
        # mirroring how godot derives its export directory from the target.
        target = Path(cmd[-1])
        out_dir = Path(cwd) / target.parent
        if self.exit_code == 0 and self.produce:
            out_dir.mkdir(parents=True, exist_ok=True)
            for name in build_web.REQUIRED_OUTPUTS:
                (out_dir / name).write_bytes(b"fake-" + name.encode())
        if self.write_build_info:
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / "build-info.json").write_text(
                json.dumps({"stale": True}), encoding="utf-8"
            )
        return subprocess.CompletedProcess(
            list(cmd),
            self.exit_code,
            stdout=self.output_text,
            stderr=self.stderr,
        )


class TempProjectMixin(unittest.TestCase):
    """Temporary fixture project: a git repo with a clean baseline commit."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.project = Path(tmp.name)
        self.write_version(VERSION_CONTENT)
        (self.project / "project.godot").write_text("; fixture\n")
        scenes = self.project / "scenes"
        scenes.mkdir()
        (scenes / "Main.tscn").write_text("[node]\n")
        # Mirror the real repo: generated output and logs are ignored, so git
        # never reports them (they cannot make the tree dirty in production).
        # vercel.json is intentionally NOT ignored without a tracking rule
        # here; dirtiness of it is asserted via is_non_source_path below.
        (self.project / ".gitignore").write_text(
            "web/build/\n.baseline_logs/\n*.log\n.vercel/\n"
        )
        for args in (("init",), ("config", "user.email", "t@example.com"),
                     ("config", "user.name", "T"), ("add", "-A"),
                     ("commit", "-m", "fixture")):
            proc = git(self.project, *args)
            self.assertEqual(proc.returncode, 0, proc.stderr)

    def write_version(self, content: str) -> None:
        path = self.project / "scripts" / "Version.gd"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def read_version(self) -> str:
        return (self.project / "scripts" / "Version.gd").read_text()

    def committed_version(self) -> str:
        proc = git(self.project, "show", "HEAD:scripts/Version.gd")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout

    def head_full(self) -> str:
        proc = git(self.project, "rev-parse", "HEAD")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout.strip()

    def mark_dirty(self, relpath: str) -> None:
        p = self.project / relpath
        p.write_text(p.read_text() + "\n# dirty\n")


class TestStampRestore(TempProjectMixin):
    def test_restored_after_success_and_build_info_written(self):
        engine = FakeEngine(exit_code=0)
        head = self.head_full()
        result = build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        # Version.gd restored byte-for-byte to committed content.
        self.assertEqual(self.read_version(), self.committed_version())
        self.assertEqual(self.read_version(), VERSION_CONTENT)
        # Fake engine got the standard export command (output resolved
        # against the project dir by build()).
        self.assertEqual(
            engine.calls[0][:4],
            ["godot-fake", "--headless", "--export-release", "Web"],
        )
        self.assertEqual(
            Path(engine.calls[0][4]).resolve(),
            (self.project / build_web.OUTPUT_REL).resolve(),
        )
        self.assertEqual(result["stamped"], head)
        self.assertFalse(result["state"]["source_dirty"])
        info = json.loads((self.project / "web/build/build-info.json").read_text())
        self.assertEqual(info["git_sha_full"], head)
        self.assertEqual(info["stamped_sha"], head)
        self.assertFalse(info["source_dirty"])
        for name in build_web.REQUIRED_OUTPUTS:
            self.assertGreater(info["outputs"][name], 0)

    def test_dirty_tree_stamps_full_sha_with_dirty_marker(self):
        self.mark_dirty("project.godot")  # real source change -> dirty
        seen: dict = {}

        def recording_engine(cmd: Sequence[str], cwd: Path):
            # Snapshot what the "engine" sees mid-export.
            seen["version_gd"] = (Path(cwd) / "scripts" / "Version.gd").read_text()
            fake = FakeEngine(exit_code=0)
            return fake(cmd, cwd)

        result = build_web.build(
            self.project, engine="godot-fake", engine_runner=recording_engine
        )
        head = self.head_full()
        self.assertTrue(result["state"]["source_dirty"])
        self.assertEqual(result["stamped"], head + "-dirty")
        self.assertIn(f'const GIT_SHA := "{head}-dirty"', seen["version_gd"])
        # Restored afterwards regardless.
        self.assertEqual(self.read_version(), VERSION_CONTENT)
        info = json.loads((self.project / "web/build/build-info.json").read_text())
        self.assertTrue(info["source_dirty"])
        self.assertEqual(info["git_sha_full"], head)
        self.assertIn("project.godot", info["source_dirty_paths"])

    def test_restored_after_engine_failure(self):
        self.mark_dirty("project.godot")
        engine = FakeEngine(exit_code=2, stderr="boom: template missing")
        with self.assertRaises(build_web.BuildError) as ctx:
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertIn("boom", str(ctx.exception))
        # Failure path still restores the original file.
        self.assertEqual(self.read_version(), VERSION_CONTENT)
        self.assertEqual(self.read_version(), self.committed_version())

    def test_restored_on_missing_outputs_after_successful_exit(self):
        # Engine exits 0 but produces nothing -> validation must fail, and
        # Version.gd must still be restored.
        engine = FakeEngine(exit_code=0, produce=False)
        with self.assertRaises(build_web.BuildError) as ctx:
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertIn("index.wasm", str(ctx.exception))
        self.assertEqual(self.read_version(), VERSION_CONTENT)
        self.assertEqual(self.read_version(), self.committed_version())


class TestSourceState(TempProjectMixin):
    def test_generated_output_and_logs_excluded_from_dirtiness(self):
        # Layer 1: paths matching the real repo's .gitignore are never even
        # reported by git, so the tree stays clean for the developer.
        state = build_web.compute_source_state(self.project)
        self.assertFalse(state["source_dirty"])
        self.assertEqual(state["source_dirty_paths"], [])
        # Layer 2 (defense in depth): even if something under those paths IS
        # reported (e.g. ignore rules missing), build_web must not count it
        # as source dirtiness.
        self.assertTrue(build_web.is_non_source_path("web/build/junk.js"))
        self.assertTrue(build_web.is_non_source_path("web/build/"))  # untracked-dir form
        self.assertTrue(build_web.is_non_source_path(".baseline_logs/run.log"))
        self.assertTrue(build_web.is_non_source_path("debug.log"))
        # vercel.json is SOURCE configuration: it must count as dirtiness.
        self.assertFalse(build_web.is_non_source_path("vercel.json"))
        self.assertNotIn("vercel.json", getattr(build_web, "NON_SOURCE_NAMES", set()))
        # Necessary game assets / custom shell must NOT be excluded.
        self.assertFalse(build_web.is_non_source_path("scenes/Main.tscn"))
        self.assertFalse(build_web.is_non_source_path("web_shell/index.html"))
        self.assertFalse(build_web.is_non_source_path("icon.svg"))

    def test_scene_source_change_still_counts_as_dirty(self):
        self.mark_dirty("scenes/Main.tscn")
        state = build_web.compute_source_state(self.project)
        self.assertTrue(state["source_dirty"])
        self.assertIn("scenes/Main.tscn", state["source_dirty_paths"])

    def test_no_head_reported_honestly(self):
        # Detach to a commit, then delete the branch ref: HEAD resolves via
        # detached state is fine, so instead simulate no repo at all.
        import shutil

        with tempfile.TemporaryDirectory() as other:
            other = Path(other)
            (other / "scripts").mkdir()
            shutil.copy(self.project / "scripts" / "Version.gd",
                        other / "scripts" / "Version.gd")
            state = build_web.compute_source_state(other)
            self.assertFalse(state["head_found"])
            self.assertIsNone(state["git_sha_full"])
            self.assertEqual(build_web.stamp_label(state), build_web.UNKNOWN_SHA)
            self.assertTrue(state["source_dirty"])


class TestStampingUnit(TempProjectMixin):
    def test_stamped_version_context_restores_on_exception(self):
        original = self.read_version()
        try:
            with build_web.stamped_version(self.project, "deadbeef"):
                self.assertIn('const GIT_SHA := "deadbeef"', self.read_version())
                raise RuntimeError("simulated crash")
        except RuntimeError:
            pass
        self.assertEqual(self.read_version(), original)

    def test_missing_gd_sha_line_fails_fast(self):
        self.write_version("extends Node\nconst OTHER := 1\n")
        with self.assertRaises(build_web.BuildError):
            with build_web.stamped_version(self.project, "x"):
                pass


class TestStaleOutputAndClearing(TempProjectMixin):
    """Regression: stale generated output must never mask a bad export."""

    def seed_stale_outputs(self):
        out_dir = self.project / "web" / "build"
        out_dir.mkdir(parents=True, exist_ok=True)
        for name in build_web.REQUIRED_OUTPUTS:
            (out_dir / name).write_bytes(b"STALE")
        (out_dir / "build-info.json").write_text(
            json.dumps({"stale": True}), encoding="utf-8"
        )

    def test_fresh_checkout_no_output_dir_succeeds(self):
        # No web/ directory at all: build must create it and succeed.
        self.assertFalse((self.project / "web").exists())
        engine = FakeEngine(exit_code=0)
        result = build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertTrue((self.project / "web/build/index.html").is_file())
        for name in build_web.REQUIRED_OUTPUTS:
            self.assertGreater(result["outputs"][name], 0)
        info = json.loads((self.project / "web/build/build-info.json").read_text())
        self.assertEqual(info["stamped_sha"], self.head_full())

    def test_stale_outputs_cannot_mask_failed_export(self):
        self.seed_stale_outputs()
        engine = FakeEngine(exit_code=2, stderr="boom")
        with self.assertRaises(build_web.BuildError):
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        # Stale required outputs were cleared before the engine ran and were
        # NOT resurrected by the failed run.
        for name in build_web.REQUIRED_OUTPUTS:
            self.assertFalse((self.project / "web/build" / name).exists(),
                             f"stale {name} survived failed export")

    def test_stale_outputs_cannot_mask_zero_output_export(self):
        self.seed_stale_outputs()
        engine = FakeEngine(exit_code=0, produce=False)
        with self.assertRaises(build_web.BuildError) as ctx:
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertIn("index.wasm", str(ctx.exception))
        for name in build_web.REQUIRED_OUTPUTS:
            self.assertFalse((self.project / "web/build" / name).exists())

    def test_build_info_invalidated_on_engine_failure(self):
        self.seed_stale_outputs()
        engine = FakeEngine(exit_code=1, stderr="fatal")
        with self.assertRaises(build_web.BuildError):
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertFalse(
            (self.project / "web/build/build-info.json").exists(),
            "stale build-info.json survived a failed export",
        )

    def test_build_info_invalidated_on_zero_output_export(self):
        self.seed_stale_outputs()
        engine = FakeEngine(exit_code=0, produce=False)
        with self.assertRaises(build_web.BuildError):
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertFalse((self.project / "web/build/build-info.json").exists())

    def test_stale_outputs_cleared_but_sources_untouched(self):
        self.seed_stale_outputs()
        # A source-looking file inside web/build must survive the clearing.
        keep = self.project / "web/build/README-source.txt"
        keep.write_text("not a build artifact")
        engine = FakeEngine(exit_code=0)
        build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertTrue(keep.is_file(), "clearing deleted an unknown file")
        self.assertEqual(self.read_version(), VERSION_CONTENT)


class TestEngineFailureMarkers(TempProjectMixin):
    def test_script_error_fails_even_with_rc0(self):
        engine = FakeEngine(
            exit_code=0,
            produce=True,
            output_text="Godot Engine v4\nSCRIPT ERROR: Parse Error: bad token\n",
        )
        with self.assertRaises(build_web.BuildError) as ctx:
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertIn("SCRIPT ERROR", str(ctx.exception))
        self.assertEqual(self.read_version(), VERSION_CONTENT)

    def test_parse_error_in_stderr_fails_with_rc0(self):
        engine = FakeEngine(
            exit_code=0, stderr="Parse Error: unexpected end of file"
        )
        with self.assertRaises(build_web.BuildError) as ctx:
            build_web.build(self.project, engine="godot-fake", engine_runner=engine)
        self.assertIn("Parse Error", str(ctx.exception))


class TestDefaultRunnerContract(TempProjectMixin):
    def test_default_runner_captures_output_with_finite_timeout(self):
        import unittest.mock

        seen: dict = {}

        def fake_run(cmd, **kwargs):
            seen.update(kwargs)
            seen["cmd"] = cmd
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with unittest.mock.patch.object(build_web.subprocess, "run", fake_run):
            proc = build_web.default_engine_runner(
                ["godot", "--headless"], cwd=self.project
            )
        self.assertEqual(proc.returncode, 0)
        self.assertTrue(seen.get("capture_output"))
        self.assertTrue(seen.get("text"))
        timeout = seen.get("timeout")
        self.assertIsNotNone(timeout)
        assert isinstance(timeout, (int, float))  # narrows for the assertions
        self.assertGreater(timeout, 0)
        self.assertLess(timeout, 10**9)  # finite, not "forever"


class TestOutputRestriction(TempProjectMixin):
    def test_custom_output_target_rejected(self):
        engine = FakeEngine(exit_code=0)
        with self.assertRaises(build_web.BuildError) as ctx:
            build_web.build(
                self.project,
                engine="godot-fake",
                output=Path("dist/index.html"),
                engine_runner=engine,
            )
        self.assertIn("unsupported --output", str(ctx.exception))
        # Engine must never have run.
        self.assertEqual(engine.calls, [])

    def test_output_pointing_at_source_rejected(self):
        engine = FakeEngine(exit_code=0)
        with self.assertRaises(build_web.BuildError):
            build_web.build(
                self.project,
                engine="godot-fake",
                output=Path("scripts/Version.gd"),
                engine_runner=engine,
            )
        self.assertEqual(self.read_version(), VERSION_CONTENT)
        self.assertEqual(engine.calls, [])

    def test_documented_output_accepted(self):
        engine = FakeEngine(exit_code=0)
        build_web.build(
            self.project,
            engine="godot-fake",
            output=build_web.OUTPUT_REL,
            engine_runner=engine,
        )
        self.assertEqual(len(engine.calls), 1)


if __name__ == "__main__":
    unittest.main()
