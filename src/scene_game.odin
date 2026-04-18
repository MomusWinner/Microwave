package ld

import "core:fmt"
import "core:log"
import linalg "core:math/linalg/glsl"
import "core:math/rand"
import "core:strings"
import "lib:ve"

create_game_scene :: proc() -> Scene {
	return Scene {
		init = game_scene_init,
		update = game_scene_update,
		draw = game_scene_draw,
		destroy = game_scene_destroy,
	}
}

Item :: struct {
	name: string,
	box:  Bounding_Box,
}

BASE_Z :: 4.0

items: [dynamic]Item
taked_item: int = -1

microwave: struct {
	door_rotation:      f32,
	pos:                vec3,
	scale:              vec3,
	open_button:        Bounding_Box,
	open_button_offset: vec3,
	is_open:            bool,
	start_open:         bool,
}

game_scene_init :: proc(s: ^Scene) {
	microwave.pos = vec3{0, 0, BASE_Z + 1}
	microwave.scale = 0.5
	microwave.open_button = Bounding_Box {
		half_size = {0.1, 0.1, 0.01},
	}
	microwave.open_button_offset = {-1.4238784, 0.46030712, -1.2224146}
	lights := ubo_light_info_get_spot_lights(G.r.lsource.ubo)
	lights[0].position = microwave.pos + {0, 1, 0} * microwave.scale
	lights[0].color = {1, 1, 0.5}
}

ray: Ray

game_scene_update :: proc(s: ^Scene) {
	plaer_controller_update(&G.player)
	mouse := ve.mouse_get_position()
	ray = get_screen_to_world_ray(mouse, G.player.camera, ve.screen_get_width(), ve.screen_get_height())

	rope := Bounding_Box {
		center    = {-2, 2.5, BASE_Z},
		half_size = {0.05, 2, 0.05},
	}

	draw_box(Bounding_Box{center = {-1, 2.5, BASE_Z}, half_size = {0.3, 1, 0.3}})
	draw_box(rope)

	draw_line(ray.position, ray.position + ray.direction)
	draw_box(Bounding_Box{center = ray.position, half_size = 0.1}, color = {1, 0, 0})

	update_items()
	update_microwave()

	if ve.mouse_button_is_pressed(.Left) {
		collision := ray_get_collision_bounding_box(ray, rope)
		if collision.hit {
			create_random_pipe_item({-1, 2.5, BASE_Z})
		} else {
		}
	}

	@(static) first_down := true

	if ve.mouse_button_is_down(.Left) {
		if first_down {
			for item, i in items {
				collision := ray_get_collision_bounding_box(ray, item.box)
				if collision.hit {
					taked_item = i
					break
				}
				taked_item = -1
			}
		}
		first_down = false
	}


	if ve.mouse_button_is_up(.Left) {
		taked_item = -1
		first_down = true
	}

	if taked_item != -1 {
		box := Bounding_Box {
			center    = {0, 0, BASE_Z},
			half_size = {10000, 10000, 0.001},
		}
		collision := ray_get_collision_bounding_box(ray, box)
		assert(collision.hit)
		items[taked_item].box.center = collision.point
	}

	if ve.key_is_down(.C) {
		draw_items_debug()
	}
}

game_scene_draw :: proc(s: ^Scene) {
	trf: ve.Transform
	ve.init_trf(&trf)
	ve.trf_set_position(&trf, {0, -GROUND_HEIGHT / 2, 0})
	renderer_draw_model(&G.r, R.models.ground, ve.trf_get_matrix(trf))

	draw_microwave()

	draw_items()
	// renderer_draw_model(&G.r, R.models.test)
	// renderer_draw_model(&G.r, R.models.enemy)
	// draw_bullets()
}

game_scene_destroy :: proc(s: ^Scene) {
}

update_microwave :: proc() {
	if ve.mouse_button_is_pressed(.Left) {
		collision := ray_get_collision_bounding_box(ray, microwave.open_button)
		if collision.hit {
			microwave.start_open = true
		}
	}

	if (microwave.start_open) {
		microwave.door_rotation -= ve.time_get_delta()
		if microwave.door_rotation < -linalg.PI / 2 {
			microwave.door_rotation = -linalg.PI / 2
			microwave.start_open = false
			microwave.is_open = true
		}
	}
	// update_vec3_from_keyboard(&microwave.open_button_offset)

	microwave.open_button.center = microwave.pos + microwave.open_button_offset * microwave.scale
	draw_box(microwave.open_button)
}

draw_microwave :: proc() {
	renderer_draw_model(
		&G.r,
		R.models.microwave,
		linalg.mat4Translate(microwave.pos) * linalg.mat4Scale(microwave.scale),
	)

	hinge := vec3{1.8364074, 0, -0.47745836} * microwave.scale
	to_hinge := linalg.mat4Translate(-hinge)
	from_hinge := linalg.mat4Translate(hinge)

	door_trf :=
		linalg.mat4Translate(microwave.pos) *
		from_hinge *
		linalg.mat4FromQuat(linalg.quatAxisAngle({0, 1, 0}, microwave.door_rotation)) *
		to_hinge *
		linalg.mat4Scale(microwave.scale)
	renderer_draw_model(&G.r, R.models.microwave_door, door_trf)
	// renderer_draw_model(&G.r, R.models.microwave_door)
}

create_item :: proc(name: string, pos: vec3) -> ^Item {
	item_info, ok_item := R.s.items[name]
	box := item_info.box
	box.center = pos
	assert(ok_item, fmt.tprintf("Unregistered name: %s", name))
	item := Item {
		name = name,
		box  = box,
	}
	append(&items, item)
	return &items[len(items) - 1]
}

create_random_pipe_item :: proc(pos: vec3) -> ^Item {
	// R.s.pipe.items
	r := rand.float32()
	percent: f32
	item_info: Pipe_Item_Info
	find: bool
	for item in R.s.pipe.items {
		percent += item.percent
		if percent >= r {
			item_info = item
			find = true
			break
		}
	}
	if !find {
		log.panic("Incorrect pipe settings")
	}

	return create_item(item_info.name, pos)
}

update_items :: proc() {
	for &item in items {
		item_info := R.s.items[item.name]
		half_size := item_info.box.half_size
		item.box.center.y -= 1.7 * ve.time_get_delta()
		y := item.box.center.y - item.box.half_size.y
		if y < 0 {
			item.box.center.y = item.box.half_size.y
		}
	}
}

draw_items_debug :: proc() {
	for &item in items {
		item_info, ok_item := R.s.items[item.name]
		assert(ok_item)
		draw_box(item.box)
	}
}

draw_items :: proc() {
	for &item in items {
		draw_item(&item)
	}
}

draw_item :: proc(item: ^Item) {
	item_info, ok_item := R.s.items[item.name]
	assert(ok_item)
	model, ok_model := R.models.items[item_info.model_path]
	assert(ok_model)
	renderer_draw_model(&G.r, model, linalg.mat4Translate(item.box.center + item_info.origin_offset))
	// renderer_draw_model(&G.r, model, linalg.mat4Translate(item.box.center))
}

// Bullet :: struct {
// 	box:           Bounding_Box,
// 	speed:         f32,
// 	dir:           vec3,
// 	start_pos:     vec3,
// 	life_distance: f32,
// }
//
// @(private)
// bm: struct {
// 	bullets:         [dynamic]Bullet,
// 	destroy_bullets: [dynamic]int,
// }
//
// bullet_manager :: proc() {
//
// }
//
// create_bullet :: proc(pos: vec3, speed: f32, dir: vec3, life_distance: f32 = 100.0) {
// 	append(
// 		&bm.bullets,
// 		Bullet {
// 			box = Bounding_Box{half_size = {0.1, 0.1, 0.1}, center = pos},
// 			speed = speed,
// 			dir = linalg.normalize(dir),
// 			start_pos = pos,
// 			life_distance = life_distance,
// 		},
// 	)
// }
//
// update_bullets :: proc() {
// 	for &bullet, i in bm.bullets {
// 		bullet.box.center += bullet.speed * bullet.dir * ve.time_get_delta()
//
// 		if bounding_box_check_collision(bullet.box, G.ground) ||
// 		   linalg.length(bullet.box.center - bullet.start_pos) > bullet.life_distance {
// 			append(&bm.destroy_bullets, i)
// 		}
// 	}
//
// 	for i in bm.destroy_bullets {
// 		unordered_remove(&bm.bullets, i)
// 	}
// 	clear(&bm.destroy_bullets)
//
// 	lights: [SPOT_LIGHT_COUNT]Spot_Light
// 	for &bullet, i in bm.bullets {
// 		if i > SPOT_LIGHT_COUNT - 1 do break
// 		lights[i] = Spot_Light {
// 			color    = {1, 1, 1},
// 			position = bullet.box.center,
// 		}
// 	}
// 	ubo_light_info_set_spot_lights(G.r.lsource.ubo, lights[:])
// }
//
// draw_bullets :: proc() {
// 	for &bullet in bm.bullets {
// 		renderer_draw_model(&G.r, R.models.bullet, linalg.mat4Translate(bullet.box.center))
// 	}
// }
//
// destroy_bullet_manager :: proc() {
//
// }
