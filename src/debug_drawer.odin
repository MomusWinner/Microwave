package ld

import "core:log"
import "core:math"
import linalg "core:math/linalg/glsl"
import "lib:ve"

DEBUG_DRAWER :: #config(DEBUG_DRAWER, ODIN_DEBUG)

@(private = "file")
drawer: struct {
	cube:     ve.Mesh,
	ubo_pool: [dynamic]ve.Uniform_Buffer,
	used_ubo: [dynamic]ve.Uniform_Buffer,
}

@(buffer)
Primitive_UBO :: struct {
	color: vec3,
}

init_debug_drawer :: proc(pool_size: int = 500) {
	when DEBUG_DRAWER {
		drawer.cube = ve.create_primitive_cube()
		drawer.ubo_pool = make([dynamic]ve.Uniform_Buffer, pool_size)
		for _, i in drawer.ubo_pool {
			drawer.ubo_pool[i] = create_ubo_primitive()
		}
		drawer.used_ubo = make([dynamic]ve.Uniform_Buffer, 0, pool_size)
	}
}

destroy_debug_drawer :: proc() {
	when DEBUG_DRAWER {
		delete(drawer.ubo_pool)
		delete(drawer.used_ubo)
	}
}

begin_debug_drawer :: proc() {
}

end_debug_drawer :: proc() {
	when DEBUG_DRAWER {
		for ubo in drawer.used_ubo {
			append(&drawer.ubo_pool, ubo)
		}
		clear(&drawer.used_ubo)
	}
}

draw_line :: proc(start, end: vec3, line_width: f32 = 0.05, color: vec3 = {1, 1, 1}) {
	when DEBUG_DRAWER {
		ubo := get_primitive_ubo()
		ubo_primitive_set_color(ubo, color)

		start_end := end - start
		distance := linalg.length(start_end)
		dir := linalg.normalize(start_end)
		position: vec3 = start + dir * distance / 2
		up := vec3{0, 0, 1}
		rotation := rotation_between_vectors(up, dir)

		scale := vec3{line_width, line_width, distance / 2}
		trf := linalg.mat4Translate(position) * rotation * linalg.mat4Scale(scale)

		renderer_draw_mesh(&G.r, drawer.cube, R.pipelines.primitive, trf, {h0 = ubo})
	}
}

rotation_between_vectors :: proc(from, to: vec3) -> mat4 {
	from_norm := linalg.normalize(from)
	to_norm := linalg.normalize(to)

	dot := linalg.dot(from_norm, to_norm)

	if dot > 0.999999 {
		return mat4(1)
	} else if dot < -0.999999 {
		axis := vec3{1, 0, 0}
		if linalg.abs(axis.x) > 0.99 {
			axis = vec3{0, 0, 1}
		}
		return linalg.mat4Rotate(axis, f32(linalg.PI))
	} else {
		axis := linalg.cross(from_norm, to_norm)
		angle := linalg.acos(dot)
		return linalg.mat4Rotate(axis, angle)
	}
}

draw_box :: proc(box: Bounding_Box, color: vec3 = {1, 1, 1}) {
	when DEBUG_DRAWER {
		ubo := get_primitive_ubo()
		ubo_primitive_set_color(ubo, color)

		trf := ve.Transform {
			scale    = box.half_size,
			position = box.center,
		}
		renderer_draw_mesh(&G.r, drawer.cube, R.pipelines.primitive, ve.trf_get_matrix(trf), {h0 = ubo})
	}
}

draw_cube :: proc(position: vec3, scale: vec3 = 0.3, color: vec3 = {1, 1, 1}) {
	when DEBUG_DRAWER {
		ubo := get_primitive_ubo()
		ubo_primitive_set_color(ubo, color)
		trf := ve.Transform {
			scale    = scale,
			position = position,
		}
		renderer_draw_mesh(&G.r, drawer.cube, R.pipelines.primitive, ve.trf_get_matrix(trf), {h0 = ubo})
	}
}

@(private = "file")
get_primitive_ubo :: proc() -> ve.Uniform_Buffer {
	if len(drawer.ubo_pool) <= 0 {
		log.panic("Increate Debug Drawer pool size")
	}
	ubo := pop(&drawer.ubo_pool)
	append(&drawer.used_ubo, ubo)
	return ubo
}
