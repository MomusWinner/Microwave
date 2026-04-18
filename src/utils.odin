package ld

import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "lib:ve"
import vemath "lib:ve/math"

vec2 :: vemath.vec2
ivec2 :: vemath.ivec2
uvec2 :: vemath.uvec2
vec3 :: vemath.vec3
ivec3 :: vemath.ivec3
uvec3 :: vemath.uvec3
vec4 :: vemath.vec4
uvec4 :: vemath.uvec4
ivec4 :: vemath.ivec4
mat4 :: vemath.mat4
quat :: vemath.quat

// screen_to_world :: proc {
// 	screen_to_world_2d,
// 	screen_to_world_3d,
// }

screen_to_world_2d :: proc(mouse: vec2, camera: ve.Camera) -> vec2 {
	return screen_to_world_2d_ex(mouse, camera, ve.screen_get_width(), ve.screen_get_height())
}

screen_to_world_2d_ex :: proc(mouse: vec2, camera: ve.Camera, w, h: int) -> vec2 {
	w, h := cast(f32)w, cast(f32)h
	ndc_x := (2.0 * mouse.x / w) - 1.0
	ndc_y := (2.0 * mouse.y / h) - 1.0

	ndc := vec4{ndc_x, ndc_y, 0.0, 1.0}

	// Inverse projection and view matrices
	inv_proj := glsl.inverse_mat4(ve.camera_get_projection(camera, w / h))
	inv_view := glsl.inverse_mat4(ve.camera_get_view(camera))

	world := inv_view * inv_proj * ndc
	return vec2{world.x, world.y}
}

screen_to_world_3d :: proc(mouse: vec2, camera: ve.Camera) -> vec3 {
	return screen_to_world_3d_ex(mouse, camera, ve.screen_get_width(), ve.screen_get_height())
}

screen_to_world_3d_ex :: proc(mouse: vec2, camera: ve.Camera, w, h: int) -> vec3 {
	w, h := cast(f32)w, cast(f32)h
	ndc_x := (2.0 * mouse.x / w) - 1.0
	ndc_y := (2.0 * mouse.y / h) - 1.0
	ndc := vec4{ndc_x, ndc_y, 1, 1.0}

	// Inverse projection and view matrices
	inv_proj := glsl.inverse_mat4(ve.camera_get_projection(camera, w / h))
	inv_view := glsl.inverse_mat4(ve.camera_get_view(camera))

	world := inv_view * inv_proj * ndc
	log.info("WORLD", world)
	return vec3{world.x, world.y, world.z}
}
// Vector3 screenToWorld(const Camera& cam, float screenX, float screenY, float ndcZ = 0.5f) {
//     updateCameraAxes(cam);
//
//     // Step 1: Screen to NDC
//     Vector3 ndc = screenToNdc(cam, screenX, screenY, ndcZ);
//
//     // Step 2: NDC to View space
//     Vector3 viewPoint;
//     if (cam.isPerspective) {
//         viewPoint = ndcToViewPerspective(cam, ndc);
//     } else {
//         viewPoint = ndcToViewOrthographic(cam, ndc);
//     }
//
//     // Step 3: View to World space
//     return viewToWorld(cam, viewPoint);
// }

linerize_color :: proc {
	linerize_color_vec3,
	linerize_color_vec4,
}

linerize_color_vec3 :: proc "contextless" (color: vec3) -> vec3 {
	pow :: proc "contextless" (value: f32) -> f32 {return math.pow_f32(value, 2.2)}
	return vec3{pow(color.x), pow(color.y), pow(color.z)}
}

linerize_color_vec4 :: proc "contextless" (color: vec4) -> vec4 {
	pow :: proc "contextless" (value: f32) -> f32 {return math.pow_f32(value, 2.2)}
	return vec4{pow(color.x), pow(color.y), pow(color.z), color.w}
}

// draw_cube :: proc(position: vec3, scale: vec3 = 0.3, color: vec3 = {1, 1, 1}) {
// 	ubo := get_primitive_ubo()
// 	ubo_primitive_set_color(ubo, color)
// 	trf := ve.Transform {
// 		scale    = scale,
// 		position = position,
// 	}
// 	renderer_draw_mesh(&G.r, drawer.cube, R.pipelines.primitive, ve.trf_get_matrix(trf), {h0 = ubo})
// }
