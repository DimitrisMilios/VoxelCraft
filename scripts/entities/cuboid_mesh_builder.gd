class_name CuboidMeshBuilder
extends RefCounted
## Builds pixel-perfect UV-mapped cuboid meshes according to standard Minecraft
## skin and entity texture layouts.

static func build_cuboid(
	size: Vector3,
	u0: float, v0: float,
	dx: float, dy: float, dz: float,
	sheet_w: float = 64.0, sheet_h: float = 64.0,
	mirror_x: bool = false
) -> ArrayMesh:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5

	var u_s: float = 1.0 / sheet_w
	var v_s: float = 1.0 / sheet_h

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var add_quad = func(
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2,
		norm: Vector3
	) -> void:
		st.set_normal(norm)
		st.set_uv(uv0)
		st.add_vertex(p0)
		st.set_uv(uv1)
		st.add_vertex(p1)
		st.set_uv(uv2)
		st.add_vertex(p2)

		st.set_uv(uv0)
		st.add_vertex(p0)
		st.set_uv(uv2)
		st.add_vertex(p2)
		st.set_uv(uv3)
		st.add_vertex(p3)

	# 1. TOP FACE (+Y)
	# Minecraft layout: U: [u0 + dz, u0 + dz + dx], V: [v0, v0 + dz]
	var top_uv0 := Vector2((u0 + dz) * u_s, (v0 + dz) * v_s)
	var top_uv1 := Vector2((u0 + dz + dx) * u_s, (v0 + dz) * v_s)
	var top_uv2 := Vector2((u0 + dz + dx) * u_s, v0 * v_s)
	var top_uv3 := Vector2((u0 + dz) * u_s, v0 * v_s)
	add_quad.call(
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
		top_uv0, top_uv1, top_uv2, top_uv3,
		Vector3(0, 1, 0)
	)

	# 2. BOTTOM FACE (-Y)
	# Minecraft layout: U: [u0 + dz + dx, u0 + dz + 2*dx], V: [v0, v0 + dz]
	var bot_uv0 := Vector2((u0 + dz + 2.0 * dx) * u_s, (v0 + dz) * v_s)
	var bot_uv1 := Vector2((u0 + dz + dx) * u_s, (v0 + dz) * v_s)
	var bot_uv2 := Vector2((u0 + dz + dx) * u_s, v0 * v_s)
	var bot_uv3 := Vector2((u0 + dz + 2.0 * dx) * u_s, v0 * v_s)
	add_quad.call(
		Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
		bot_uv0, bot_uv1, bot_uv2, bot_uv3,
		Vector3(0, -1, 0)
	)

	# 3. FRONT FACE (-Z)
	# Minecraft layout: U: [u0 + dz, u0 + dz + dx], V: [v0 + dz, v0 + dz + dy]
	var f_u_l: float = (u0 + dz) * u_s
	var f_u_r: float = (u0 + dz + dx) * u_s
	if mirror_x:
		var tmp: float = f_u_l
		f_u_l = f_u_r
		f_u_r = tmp
	var fr_uv0 := Vector2(f_u_l, (v0 + dz + dy) * v_s)
	var fr_uv1 := Vector2(f_u_r, (v0 + dz + dy) * v_s)
	var fr_uv2 := Vector2(f_u_r, (v0 + dz) * v_s)
	var fr_uv3 := Vector2(f_u_l, (v0 + dz) * v_s)
	add_quad.call(
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
		fr_uv0, fr_uv1, fr_uv2, fr_uv3,
		Vector3(0, 0, -1)
	)

	# 4. BACK FACE (+Z)
	# Minecraft layout: U: [u0 + 2*dz + dx, u0 + 2*dz + 2*dx], V: [v0 + dz, v0 + dz + dy]
	var b_u_l: float = (u0 + 2.0 * dz + dx) * u_s
	var b_u_r: float = (u0 + 2.0 * dz + 2.0 * dx) * u_s
	if mirror_x:
		var tmp: float = b_u_l
		b_u_l = b_u_r
		b_u_r = tmp
	var bk_uv0 := Vector2(b_u_l, (v0 + dz + dy) * v_s)
	var bk_uv1 := Vector2(b_u_r, (v0 + dz + dy) * v_s)
	var bk_uv2 := Vector2(b_u_r, (v0 + dz) * v_s)
	var bk_uv3 := Vector2(b_u_l, (v0 + dz) * v_s)
	add_quad.call(
		Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz),
		bk_uv0, bk_uv1, bk_uv2, bk_uv3,
		Vector3(0, 0, 1)
	)

	# 5. RIGHT FACE (+X)
	# Minecraft layout: U: [u0, u0 + dz], V: [v0 + dz, v0 + dz + dy]
	var r_u0: float = (u0 + dz) * u_s
	var r_u1: float = u0 * u_s
	if mirror_x:
		r_u0 = (u0 + 2.0 * dz + dx) * u_s
		r_u1 = (u0 + dz + dx) * u_s
	var rt_uv0 := Vector2(r_u0, (v0 + dz + dy) * v_s)
	var rt_uv1 := Vector2(r_u1, (v0 + dz + dy) * v_s)
	var rt_uv2 := Vector2(r_u1, (v0 + dz) * v_s)
	var rt_uv3 := Vector2(r_u0, (v0 + dz) * v_s)
	add_quad.call(
		Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz),
		rt_uv0, rt_uv1, rt_uv2, rt_uv3,
		Vector3(1, 0, 0)
	)

	# 6. LEFT FACE (-X)
	# Minecraft layout: U: [u0 + dz + dx, u0 + 2*dz + dx], V: [v0 + dz, v0 + dz + dy]
	var l_u0: float = (u0 + 2.0 * dz + dx) * u_s
	var l_u1: float = (u0 + dz + dx) * u_s
	if mirror_x:
		l_u0 = (u0 + dz) * u_s
		l_u1 = u0 * u_s
	var lt_uv0 := Vector2(l_u0, (v0 + dz + dy) * v_s)
	var lt_uv1 := Vector2(l_u1, (v0 + dz + dy) * v_s)
	var lt_uv2 := Vector2(l_u1, (v0 + dz) * v_s)
	var lt_uv3 := Vector2(l_u0, (v0 + dz) * v_s)
	add_quad.call(
		Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz),
		lt_uv0, lt_uv1, lt_uv2, lt_uv3,
		Vector3(-1, 0, 0)
	)

	return st.commit()
