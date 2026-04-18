package ld

import "core:log"
import "core:math"
import linalg "core:math/linalg/glsl"
import "lib:ve"
import rl "vendor:raylib"

// Taked from raylib

Ray :: struct {
	position:  vec3, // Ray position (origin)
	direction: vec3, // Ray direction (normalized)
}

Collision :: struct {
	point:  vec3,
	normal: vec3,
}

Ray_Collision :: struct {
	hit:      bool, // Did the ray hit something?
	distance: f32, // Distance to nearest hit
	point:    vec3, // Point of nearest hit
	normal:   vec3, // Surface normal of hit
}

// Bounding_Box :: struct {
// 	min:    vec3, // Minimum vertex box-corner
// 	max:    vec3, // Maximum vertex box-corner
// 	center: vec3,
// }

Bounding_Box :: struct {
	half_size: vec3,
	center:    vec3,
}

ray_get_collision_sphere :: proc(ray: Ray, center: vec3, radius: f32) -> Ray_Collision {
	collision: Ray_Collision

	ray_sphere_pos := center - ray.position
	vector: f32 = linalg.dot(ray_sphere_pos, ray.direction)
	distance: f32 = linalg.length(ray_sphere_pos)
	d: f32 = radius * radius - (distance * distance - vector * vector)

	collision.hit = d >= 0

	if (distance < radius) { 	//pointing outwards
		collision.distance = vector + math.sqrt(d)
		collision.point = ray.position + ray.direction * collision.distance
		collision.normal = -linalg.normalize(collision.point - center)
	} else {
		collision.distance = vector - math.sqrt(d)
		collision.point = ray.position + ray.direction * collision.distance
		collision.normal = linalg.normalize(collision.point - center)
	}

	return collision
}

ray_get_collision_bounding_box :: proc(ray: Ray, box: Bounding_Box) -> Ray_Collision {
	collision: Ray_Collision
	ray := ray

	box_min := box.center - box.half_size
	box_max := box.center + box.half_size

	insideBox: bool =
		(ray.position.x > box_min.x) &&
		(ray.position.x < box_max.x) &&
		(ray.position.y > box_min.y) &&
		(ray.position.y < box_max.y) &&
		(ray.position.z > box_min.z) &&
		(ray.position.z < box_max.z)

	if (insideBox) do ray.direction = -ray.direction

	t: [11]f32

	t[8] = 1.0 / ray.direction.x
	t[9] = 1.0 / ray.direction.y
	t[10] = 1.0 / ray.direction.z

	t[0] = (box_min.x - ray.position.x) * t[8]
	t[1] = (box_max.x - ray.position.x) * t[8]
	t[2] = (box_min.y - ray.position.y) * t[9]
	t[3] = (box_max.y - ray.position.y) * t[9]
	t[4] = (box_min.z - ray.position.z) * t[10]
	t[5] = (box_max.z - ray.position.z) * t[10]
	t[6] = cast(f32)math.max(math.max(math.min(t[0], t[1]), math.min(t[2], t[3])), math.min(t[4], t[5]))
	t[7] = cast(f32)math.min(math.min(math.max(t[0], t[1]), math.max(t[2], t[3])), math.max(t[4], t[5]))

	collision.hit = !((t[7] < 0) || (t[6] > t[7]))
	collision.distance = t[6]
	collision.point = ray.position + ray.direction * collision.distance

	// Get box center point
	collision.normal = box.center
	// Get vector center point->hit point
	collision.normal = collision.point - collision.normal
	// Scale vector to unit cube
	// NOTE: We use an additional .01 to fix numerical errors
	collision.normal = collision.normal * 2.01
	collision.normal = collision.normal / (box_max - box_min)
	// The relevant elements of the vector are now slightly larger than 1.0f (or smaller than -1.0f)
	// and the others are somewhere between -1.0 and 1.0 casting to int is exactly our wanted normal!
	collision.normal.x = cast(f32)(cast(int)collision.normal.x)
	collision.normal.y = cast(f32)(cast(int)collision.normal.y)
	collision.normal.z = cast(f32)(cast(int)collision.normal.z)

	collision.normal = linalg.normalize(collision.normal)

	if (insideBox) {
		// Reset ray.direction
		ray.direction = -ray.direction
		// Fix result
		collision.distance *= -1.0
		collision.normal = -collision.normal
	}

	return collision
}

camera_get_ray :: proc(camera: ve.Camera) -> Ray {
	return Ray{position = camera.position, direction = ve.camera_get_forward(camera)}
}

sphere_check_collision :: proc(center1: vec3, radius1: f32, center2: vec3, radius2: f32) -> bool {
	if linalg.dot(center2 - center1, center2 - center1) <= (radius1 + radius2) * (radius1 + radius2) {
		return true
	}

	return false
}

bounding_box_check_collision :: proc(box1, box2: Bounding_Box) -> bool {
	delta := box2.center - box1.center

	return(
		abs(delta.x) <= (box1.half_size.x + box2.half_size.x) &&
		abs(delta.y) <= (box1.half_size.y + box2.half_size.y) &&
		abs(delta.z) <= (box1.half_size.z + box2.half_size.z) \
	)
}

bounding_box_check_collision_point :: proc(box: Bounding_Box, point: vec3) -> bool {
	point := point - box.center
	return abs(point.x) < box.half_size.x && abs(point.y) < box.half_size.y && abs(point.z) < box.half_size.z
}

bounding_box_check_collision_ex :: proc(box1, box2: Bounding_Box) -> (collision: Collision, hit: bool) {
	sign :: proc(x: f32) -> f32 {
		if x > 0 do return 1
		if x < 0 do return -1
		return 0
	}

	delta := box2.center - box1.center

	// Check for collision using Separating Axis Theorem
	if abs(delta.x) > (box1.half_size.x + box2.half_size.x) ||
	   abs(delta.y) > (box1.half_size.y + box2.half_size.y) ||
	   abs(delta.z) > (box1.half_size.z + box2.half_size.z) {
		return collision, false
	}

	// Calculate overlap depths
	overlap_x := (box1.half_size.x + box2.half_size.x) - abs(delta.x)
	overlap_y := (box1.half_size.y + box2.half_size.y) - abs(delta.y)
	overlap_z := (box1.half_size.z + box2.half_size.z) - abs(delta.z)

	// Find the axis with minimum overlap (penetration depth)
	min_overlap := overlap_x
	normal := vec3{sign(delta.x), 0, 0}

	if overlap_y < min_overlap {
		min_overlap = overlap_y
		normal = vec3{0, sign(delta.y), 0}
	}
	if overlap_z < min_overlap {
		min_overlap = overlap_z
		normal = vec3{0, 0, sign(delta.z)}
	}

	// Calculate collision point (center of the overlap region)
	// First, compute min and max points of both boxes
	box1_min := box1.center - box1.half_size
	box1_max := box1.center + box1.half_size
	box2_min := box2.center - box2.half_size
	box2_max := box2.center + box2.half_size

	overlap_min := vec3{max(box1_min.x, box2_min.x), max(box1_min.y, box2_min.y), max(box1_min.z, box2_min.z)}
	overlap_max := vec3{min(box1_max.x, box2_max.x), min(box1_max.y, box2_max.y), min(box1_max.z, box2_max.z)}

	collision.point = (overlap_min + overlap_max) / 2
	collision.normal = normal

	return collision, true
}


// bounding_box_check_collision_ex :: proc(box1, box2: Bounding_Box) -> (collision: Collision, hit: bool) {
// 	// Check if boxes intersect
// 	if !(box1.max.x >= box2.min.x &&
// 		   box1.min.x <= box2.max.x &&
// 		   box1.max.y >= box2.min.y &&
// 		   box1.min.y <= box2.max.y &&
// 		   box1.max.z >= box2.min.z &&
// 		   box1.min.z <= box2.max.z) {
// 		return collision, false
// 	}
//
// 	// Calculate overlap depths on each axis
// 	overlap_x := min(box1.max.x, box2.max.x) - max(box1.min.x, box2.min.x)
// 	overlap_y := min(box1.max.y, box2.max.y) - max(box1.min.y, box2.min.y)
// 	overlap_z := min(box1.max.z, box2.max.z) - max(box1.min.z, box2.min.z)
//
// 	// Find the axis with minimum overlap (penetration depth)
// 	min_overlap := overlap_x
// 	normal := vec3{1, 0, 0}
//
// 	if overlap_y < min_overlap {
// 		min_overlap = overlap_y
// 		normal = vec3{0, 1, 0}
// 	}
// 	if overlap_z < min_overlap {
// 		min_overlap = overlap_z
// 		normal = vec3{0, 0, 1}
// 	}
//
// 	// Determine sign of the normal (which direction to push)
// 	box1_center := (box1.min + box1.max) / 2
// 	box2_center := (box2.min + box2.max) / 2
//
// 	if normal.x != 0 {
// 		if box1_center.x > box2_center.x {
// 			normal.x = 1
// 		} else {
// 			normal.x = -1
// 		}
// 	} else if normal.y != 0 {
// 		if box1_center.y > box2_center.y {
// 			normal.y = 1
// 		} else {
// 			normal.y = -1
// 		}
// 	} else if normal.z != 0 {
// 		if box1_center.z > box2_center.z {
// 			normal.z = 1
// 		} else {
// 			normal.z = -1
// 		}
// 	}
//
// 	// Calculate collision point (center of the overlap region)
// 	collision.point = vec3 {
// 		max(box1.min.x, box2.min.x) + overlap_x / 2,
// 		max(box1.min.y, box2.min.y) + overlap_y / 2,
// 		max(box1.min.z, box2.min.z) + overlap_z / 2,
// 	}
// 	collision.normal = normal
//
// 	return collision, true
// }
