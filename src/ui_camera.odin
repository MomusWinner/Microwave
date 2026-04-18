package ld

import lin "core:math/linalg/glsl"
import "lib:ve"
import "lib:ve/math"

@(buffer)
Camera_UBO :: struct {
	view:       mat4,
	projection: mat4,
	position:   vec3,
}

UI_Camera :: struct {
	ubo: ve.Uniform_Buffer, // Camera_UBO
}

init_uicamera :: proc(c: ^UI_Camera) {
	c.ubo = create_ubo_camera()
}

uicamera_get_buffer :: proc(c: ^UI_Camera) -> ve.Buffer {
	// projection := math.ortho(0, cast(f32)ve.screen_get_width(), 0, cast(f32)ve.screen_get_height(), -1.0, 10.0)
	// ubo_camera_set_projection(c.ubo, projection)
	// ubo_camera_set_view(c.ubo, 1)
	// return ve.ubo_get_buffer(c.ubo)

	projection := math.ortho(0, cast(f32)500, 0, cast(f32)500, -1.0, 10.0)
	ubo_camera_set_projection(c.ubo, projection)
	ubo_camera_set_view(c.ubo, 1)
	return ve.ubo_get_buffer(c.ubo)
}

set_uicamera :: proc(c: ^UI_Camera) {
	ve.set_camera_buffer(uicamera_get_buffer(c))
}
