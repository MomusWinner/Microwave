package ld

import "core:log"
import linalg "core:math/linalg/glsl"
import "lib:ve"
import vemath "lib:ve/math"

MOUSE_SENS: f32 = 0.05

// DAMPING :: 0.98

Player_Controller :: struct {
	camera:       ve.Camera,
	speed:        f32,
	position:     vec3,
	box:          Bounding_Box,
	height:       f32,
	// rotation
	yaw:          f32,
	pitch:        f32,
	//
	velocity:     vec3,
	acceleration: vec3,
	mass:         f32,
}

init_player_controller :: proc(p: ^Player_Controller, position: vec3, camera: ve.Camera) {
	p.height = 3.4
	p.camera = camera
	p.speed = 10
	p.position = position
	p.camera.position = position + {0, p.height, 0}
	p.box = Bounding_Box {
		half_size = {0.1, 0.5, 0.1},
	}

	p.mass = 10
}

plaer_controller_update :: proc(p: ^Player_Controller) {
	speed: f32 = 2.0 * ve.time_get_delta()

	p.box.center = p.position

	on_ground := bounding_box_check_collision_point(G.ground, p.position - {0, 0.001, 0})

	if !on_ground {
		p.velocity.y -= G_ACCELERATION * ve.time_get_delta()
	} else {
		p.velocity.y = 0
	}

	// rotation
	// m_delta := ve.mouse_get_delta()
	// p.pitch -= m_delta.y * ve.time_get_delta() * MOUSE_SENS
	// if p.pitch > 1 do p.pitch = 1
	// if p.pitch < -1 do p.pitch = -1
	// p.yaw += m_delta.x * ve.time_get_delta() * MOUSE_SENS
	// forward := vec3 { 	//
	// 	linalg.cos(p.yaw) * linalg.cos(p.pitch),
	// 	linalg.sin(p.pitch),
	// 	linalg.sin(p.yaw) * linalg.cos(p.pitch),
	// }
	// right := linalg.normalize(linalg.cross(forward, vec3{0, 1, 0}))

	forward := linalg.normalize(vec3{0, -0.2, 1})
	// forward := linalg.normalize(vec3{0, 0, 1})
	right := linalg.normalize(linalg.cross(forward, vec3{0, 1, 0}))

	if ve.key_is_pressed(.Space) && on_ground {
		p.position.y += 0.015
		player_add_force(p, {0, 1, 0} * speed * 25)
	}
	if ve.key_is_down(.W) {
		player_add_force(p, forward * {1, 0, 1} * speed)
	}
	if ve.key_is_down(.S) {
		player_add_force(p, -forward * {1, 0, 1} * speed)
	}
	if ve.key_is_down(.A) {
		player_add_force(p, -right * {1, 0, 1} * speed)
	}
	if ve.key_is_down(.D) {
		player_add_force(p, right * {1, 0, 1} * speed)
	}

	_player_controller_update_phys(p)

	p.camera.position = p.position + {0, p.height, 0}
	p.camera.target = p.camera.position + forward
}

player_add_force :: proc(p: ^Player_Controller, force: vec3) {
	p.acceleration += force * (1 / p.mass)
}

@(private)
_player_controller_update_phys :: proc(p: ^Player_Controller) {
	p.velocity += p.acceleration
	p.position += p.velocity
	p.acceleration = 0
	if linalg.length_vec3(p.velocity) < 0.001 {
		p.velocity = 0
	}
	p.velocity.xz *= DAMPING
}
