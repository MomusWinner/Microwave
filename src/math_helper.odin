package ld

import "core:log"
import "core:math/linalg/glsl"

// quat_from_direction :: proc(direction, up: glsl.vec3) -> glsl.quat {
// 	forward := glsl.normalize(direction)
// 	up_norm := glsl.normalize(up)
//
// 	right := glsl.normalize(glsl.cross(forward, up_norm))
//
// 	corrected_up := glsl.cross(right, forward)
// 	//odinfmt: disable
// 	rotation_matrix := glsl.mat4 {
// 		right.x, corrected_up.x, forward.x, 0,
// 		right.y, corrected_up.y, forward.y, 0,
// 		right.z, corrected_up.z, forward.z, 0,
// 		0, 0, 0, 1,
// 	}
// 	//odinfmt: enable
//
// 	return glsl.quatFromMat4(rotation_matrix)
// }


rotation_mat_from_direction :: proc(direction, up: glsl.vec3) -> mat4 {
	f := direction
	s := glsl.normalize(glsl.cross(f, up))
	u := glsl.cross(s, f)

	m: mat4

	m[0] = {+s.x, +u.x, -f.x, 0}
	m[1] = {+s.y, +u.y, -f.y, 0}
	m[2] = {+s.z, +u.z, -f.z, 0}
	m[3] = {0, 0, 0, 1}

	return m
}
