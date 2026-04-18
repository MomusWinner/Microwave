package ld

import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:strconv"
import "core:strings"
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

get_screen_to_world_ray :: proc(pos: vec2, camera: ve.Camera, w, h: int) -> (ray: Ray) {
	aspect := cast(f32)w / cast(f32)h

	// Convert screen coordinates to NDC (Vulkan: Z = 0 to 1)
	ndc_x := (2.0 * pos.x / cast(f32)w) - 1.0
	ndc_y := 1.0 - (2.0 * pos.y / cast(f32)h) // Flip Y for Vulkan

	// Get projection and view matrices
	proj := ve.camera_get_projection(camera, aspect)
	view := ve.camera_get_view(camera)

	// Inverse matrices
	inv_proj := glsl.inverse_mat4(proj)
	inv_view := glsl.inverse_mat4(view)

	// Vulkan clip space: Z = 0 for near, Z = 1 for far
	near_clip := vec4{ndc_x, ndc_y, 0.0, 1.0}
	far_clip := vec4{ndc_x, ndc_y, 1.0, 1.0}

	// Transform to world space
	near_world := inv_view * inv_proj * near_clip
	far_world := inv_view * inv_proj * far_clip

	// Perspective division (important!)
	near_world /= near_world.w
	far_world /= far_world.w

	// Calculate direction
	direction := glsl.normalize(far_world.xyz - near_world.xyz)

	if (camera.type == .Perspective) {
		ray.position = camera.position
	} else {
		log.panic("unimplemented")
	}

	ray.direction = direction
	ray.direction.y *= -1

	return
}

// get_screen_to_world_ray :: proc(pos: vec2, camera: ve.Camera, w, h: int) -> (ray: Ray) {
// 	aspect := cast(f32)w / cast(f32)h
// 	ndc_x := (2.0 * pos.x / cast(f32)w) - 1.0
// 	ndc_y := 1.0 - (2.0 * pos.y) / cast(f32)h
// 	ndc_z: f32 = 1.0
// 	ndc := vec3{ndc_x, ndc_y, ndc_z}
//
// 	// Inverse projection and view matrices
// 	inv_proj := glsl.inverse_mat4(ve.camera_get_projection(camera, aspect))
// 	inv_view := glsl.inverse_mat4(ve.camera_get_view(camera))
//
// 	near_point := inv_view * inv_proj * vec4{ndc_x, ndc_y, 0, 1}
// 	far_point := inv_view * inv_proj * vec4{ndc_x, ndc_y, 1, 1}
//
// 	direction: vec3 = glsl.normalize(far_point.xyz - near_point.xyz)
//
// 	if (camera.type == .Perspective) {
// 		ray.position = camera.position
// 	} else {
// 		log.panic("unimplemented")
// 	}
//
// 	ray.direction = direction
//
// 	return
// }

// // Get a ray trace from the screen position (i.e mouse) within a specific section of the screen
// Ray GetScreenToWorldRayEx(Vector2 position, Camera camera, int width, int height)
// {
//     Ray ray = { 0 };
//
//     // Calculate normalized device coordinates
//     // NOTE: y value is negative
//     float x = (2.0f*position.x)/(float)width - 1.0f;
//     float y = 1.0f - (2.0f*position.y)/(float)height;
//     float z = 1.0f;
//
//     // Store values in a vector
//     Vector3 deviceCoords = { x, y, z };
//
//     // Calculate view matrix from camera look at
//     Matrix matView = MatrixLookAt(camera.position, camera.target, camera.up);
//
//     Matrix matProj = MatrixIdentity();
//
//     if (camera.projection == CAMERA_PERSPECTIVE)
//     {
//         // Calculate projection matrix from perspective
//         matProj = MatrixPerspective(camera.fovy*DEG2RAD, ((double)width/(double)height), rlGetCullDistanceNear(), rlGetCullDistanceFar());
//     }
//     else if (camera.projection == CAMERA_ORTHOGRAPHIC)
//     {
//         double aspect = (double)width/(double)height;
//         double top = camera.fovy/2.0;
//         double right = top*aspect;
//
//         // Calculate projection matrix from orthographic
//         matProj = MatrixOrtho(-right, right, -top, top, 0.01, 1000.0);
//     }
//
//     // Unproject far/near points
//     Vector3 nearPoint = Vector3Unproject((Vector3){ deviceCoords.x, deviceCoords.y, 0.0f }, matProj, matView);
//     Vector3 farPoint = Vector3Unproject((Vector3){ deviceCoords.x, deviceCoords.y, 1.0f }, matProj, matView);
//
//     // Unproject the mouse cursor in the near plane
//     // We need this as the source position because orthographic projects,
//     // compared to perspective doesn't have a convergence point,
//     // meaning that the "eye" of the camera is more like a plane than a point
//     Vector3 cameraPlanePointerPos = Vector3Unproject((Vector3){ deviceCoords.x, deviceCoords.y, -1.0f }, matProj, matView);
//
//     // Calculate normalized direction vector
//     Vector3 direction = Vector3Normalize(Vector3Subtract(farPoint, nearPoint));
//
//     if (camera.projection == CAMERA_PERSPECTIVE) ray.position = camera.position;
//     else if (camera.projection == CAMERA_ORTHOGRAPHIC) ray.position = cameraPlanePointerPos;
//
//     // Apply calculated vectors to ray
//     ray.direction = direction;
//
//     return ray;
// }
//

// screen_to_world_3d_ex :: proc(mouse: vec2, camera: ve.Camera, w, h: int) -> vec3 {
// 	w, h := cast(f32)w, cast(f32)h
// 	ndc_x := (2.0 * mouse.x / w) - 1.0
// 	ndc_y := (2.0 * mouse.y / h) - 1.0
// 	ndc := vec4{ndc_x, ndc_y, 1, 1.0}
//
// 	// Inverse projection and view matrices
// 	inv_proj := glsl.inverse_mat4(ve.camera_get_projection(camera, w / h))
// 	inv_view := glsl.inverse_mat4(ve.camera_get_view(camera))
//
// 	world := inv_view * inv_proj * ndc
// 	log.info("WORLD", world)
// 	return vec3{world.x, world.y, world.z}
// }
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

prase_vec3_from_string :: proc(str: string, loc := #caller_location) -> vec3 {
	split := strings.split(str, ";")
	if len(split) != 3 {
		log.panicf("Coudn't parse vec3 from string s%. vector should have only 3 component (0.0;0.0;0.0)", str, loc)
	}
	v: vec3
	ok: bool
	v.x, ok = strconv.parse_f32(split[0])
	v.y, ok = strconv.parse_f32(split[1])
	v.z, ok = strconv.parse_f32(split[2])
	if !ok {
		log.panicf("Coudn't parse vec3 from string s%", str, loc)
	}

	return v
}

update_vec3_from_keyboard :: proc(v: ^vec3, speed: f32 = 1.4) {
	speed := speed * ve.time_get_delta()
	if ve.key_is_down(.U) {
		v.x += speed
	}
	if ve.key_is_down(.J) {
		v.x -= speed
	}

	if ve.key_is_down(.I) {
		v.y += speed
	}
	if ve.key_is_down(.K) {
		v.y -= speed
	}


	if ve.key_is_down(.O) {
		v.z += speed
	}
	if ve.key_is_down(.L) {
		v.z -= speed
	}

	log.info(v)
}
