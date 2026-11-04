class_name MeshKit
extends RefCounted

## Shared primitive-mesh helpers (v0.61.x bugfix dedup). ShopFront.gd and
## CustomerActor.gd carried identical private copies of these; both now call
## the kit. Pure code motion — no mesh geometry, material or node changes, so
## draw-call and mesh-node budgets are unchanged.
##
## Primitive meshes come back centered on the origin; offset_arrays translates
## a primitive's vertex arrays so several primitives can share one ArrayMesh
## surface set. Pure translation — normals and tangents carry over unchanged.


static func offset_arrays(src: PrimitiveMesh, offset: Vector3) -> Array:
	var arrays: Array = src.get_mesh_arrays()
	var verts := PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
	for i in range(verts.size()):
		verts[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays


static func box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
