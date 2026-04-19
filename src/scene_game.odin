package ld

import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:math"
import linalg "core:math/linalg/glsl"
import "core:math/rand"
import "core:slice"
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

INVALID_ID :: Id{}
Id :: uuid.Identifier

Item :: struct {
	id:   Id,
	name: string,
	box:  Bounding_Box,
}

BASE_Z :: 4.0

Angle_Value :: struct {
	value: int,
	angle: f32,
}

THINGAMAGIC_ANGLES :: [3]Angle_Value{{0, 0}, {1, linalg.PI / 2}, {2, linalg.PI}}

items: map[Id]Item
taked_item: Id = INVALID_ID

MICROWAVE_ITEM_CAPACITY :: 2

microwave: struct {
	pos:                  vec3,
	scale:                vec3,
	open_button:          Bounding_Box,
	door_width:           f32,
	spawn_pos:            vec3,
	// main
	is_working:           bool,
	// door
	close_door_box:       Bounding_Box,
	door_rotation:        f32,
	door_corner_box:      Bounding_Box,
	is_open:              bool,
	opening:              bool,
	closing:              bool,
	// thingamagic
	thingamagic_box:      Bounding_Box,
	thingamagic_pos:      vec3,
	thingamagic_value:    int, // from 0 to 2
	thingamagic_angle:    f32,
	rotating_thingamagic: bool,
	// timer
	timer_text:           Text,
	timer_seconds:        f32,
	// start button
	start_button_box:     Bounding_Box,
	start_button_pos:     vec3,
	// 0
	drop_box:             Bounding_Box,
	items:                [dynamic]Id,
}

pipe_pos: vec3 = {-3, 2.5, BASE_Z}
rope_pos: vec3 = {-5, 4.5, BASE_Z}
rope_box: Bounding_Box = {
	center    = rope_pos + vec3{0, -1.4, 0},
	half_size = {0.4, 0.7, 0.4},
}

game_scene_init :: proc(s: ^Scene) {
	init_microwave()
}

ray: Ray

game_scene_update :: proc(s: ^Scene) {
	plaer_controller_update(&G.player)
	mouse := ve.mouse_get_position()
	ray = get_screen_to_world_ray(mouse, G.player.camera, ve.screen_get_width(), ve.screen_get_height())


	// draw_line(ray.position, ray.position + ray.direction)
	// draw_box(Bounding_Box{center = ray.position, half_size = 0.1})

	update_items()
	update_microwave()

	if ve.mouse_button_is_pressed(.Left) {
		collision := ray_get_collision_bounding_box(ray, rope_box)
		if collision.hit {
			create_random_pipe_item(pipe_pos)
		} else {
		}
	}

	if ve.mouse_button_is_start_down(.Left) {
		for id, item in items {
			collision := ray_get_collision_bounding_box(ray, item.box)
			if collision.hit {
				if slice.contains(microwave.items[:], id) && !microwave.is_open {
					taked_item = INVALID_ID
					break
				}
				taked_item = id
				break
			}
		}
	}

	if ve.mouse_button_is_start_up(.Left) {
		taked_item = INVALID_ID
	}

	if taked_item != INVALID_ID {
		item := &items[taked_item]
		box := Bounding_Box {
			center    = {0, 0, BASE_Z},
			half_size = {10000, 10000, 0.001},
		}
		collision := ray_get_collision_bounding_box(ray, box)
		if collision.hit {
			item.box.center = collision.point
		}

		drop_collision := ray_get_collision_bounding_box(ray, microwave.drop_box)
		if microwave.is_open &&
		   drop_collision.hit &&
		   (len(microwave.items) < MICROWAVE_ITEM_CAPACITY || slice.contains(microwave.items[:], taked_item)) {
			drop_box := Bounding_Box {
				center    = microwave.pos,
				half_size = {10, 10, 0.001},
			}
			drop_collision := ray_get_collision_bounding_box(ray, drop_box)
			item.box.center = drop_collision.point
			if !slice.contains(microwave.items[:], taked_item) && len(microwave.items) < MICROWAVE_ITEM_CAPACITY {
				append(&microwave.items, taked_item)
			}
		} else {
			for microwave_item, i in microwave.items {
				if microwave_item == taked_item {
					unordered_remove(&microwave.items, i)
					break
				}
			}
		}
	}

	if ve.key_is_down(.C) {
		draw_box(rope_box)
		draw_items_debug()
	}
}

game_scene_draw :: proc(s: ^Scene) {
	trf: ve.Transform
	ve.init_trf(&trf)
	ve.trf_set_position(&trf, {0, -GROUND_HEIGHT / 2, 0})
	renderer_draw_model(&G.r, R.models.ground, ve.trf_get_matrix(trf))
	renderer_draw_model(&G.r, R.models.pipe, linalg.mat4Translate(pipe_pos))
	renderer_draw_model(&G.r, R.models.rope, linalg.mat4Translate(rope_pos))
	draw_microwave()

	draw_items()
}

game_scene_destroy :: proc(s: ^Scene) {
}

find_combination :: proc() -> (Combination_Info, bool) {
	log.info(R.s.combinations)
	names := make([dynamic]string, len(microwave.items), context.temp_allocator)
	for item_id, i in microwave.items {
		item := items[item_id]
		names[i] = item.name
	}

	for c in R.s.combinations {
		if c.timer_value != microwave.thingamagic_value do continue
		for c_name in c.from {
			if !slice.contains(names[:], c_name) {
				continue
			}
		}
		if len(names) != len(c.from) do continue
		return c, true
	}

	return {}, false
}

init_microwave :: proc() {
	microwave.pos = vec3{0, 0, BASE_Z + 1}
	microwave.scale = 1
	microwave.open_button = Bounding_Box {
		half_size = microwave.scale * {0.2, 0.1, 0.1},
		center    = microwave.pos + microwave.scale * {-1.439889, 0.43842125, -1.10038829},
	}
	microwave.close_door_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{2.153, 1.084, -3.194},
		half_size = vec3{0.3, 1, 0.3} * microwave.scale,
	}

	microwave.thingamagic_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{-1.427, 1.274, -0.845},
		half_size = vec3{0.3, 0.3, 0.3} * microwave.scale,
	}
	microwave.thingamagic_pos = microwave.pos + microwave.scale * {-1.4271961, 1.1810113, -1.1490066}

	microwave.spawn_pos = microwave.pos + 1 * microwave.scale

	microwave.timer_text = create_text(
		&R.fonts.segment,
		"00:00",
		microwave.pos + microwave.scale * vec3{-1.15, 1.629, -0.9999},
		{1, 0, 0},
		0.004 * microwave.scale.x,
	)

	microwave.start_button_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{-1.5658, 0.759148, -0.960555},
		half_size = 0.1 * microwave.scale,
	}
	microwave.start_button_pos = microwave.pos + microwave.scale * {-1.4271961, 1.1810113, -1.1490066}

	microwave.drop_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{0.47175516, 1.0606446, -1.898627},
		half_size = vec3{0.8, 0.5, 1.3} * microwave.scale,
	}

	lights := ubo_light_info_get_spot_lights(G.r.lsource.ubo)
	lights[0].position = microwave.pos + {0, 1, 0} * microwave.scale
	lights[0].color = {1, 1, 0.5}
}

set_timer_seconds :: proc(seconds: int) {
	MAX_MINUTES :: 99
	MAX_SECONDS :: 99
	timer_string: string

	if seconds > MAX_MINUTES * 60 + MAX_SECONDS {
		timer_string = "99:99"
		text_set_string(&microwave.timer_text, timer_string)
		return
	}

	minutes := seconds / 60
	remaining_seconds := seconds % 60

	if minutes > MAX_MINUTES || remaining_seconds > MAX_SECONDS {
		timer_string = "99:99"
		text_set_string(&microwave.timer_text, timer_string)
		return
	}

	timer_string = fmt.tprintf("%02d:%02d", minutes, remaining_seconds)
	text_set_string(&microwave.timer_text, timer_string)
}

update_microwave :: proc() {
	if ve.mouse_button_is_pressed(.Left) {
		collision := ray_get_collision_bounding_box(ray, microwave.open_button)
		if collision.hit {
			microwave.opening = true
		}
	}

	if microwave.opening {
		microwave.door_rotation -= ve.time_get_delta()
		if microwave.door_rotation < -linalg.PI / 2 {
			microwave.door_rotation = -linalg.PI / 2
			microwave.opening = false
			microwave.is_open = true
		}
	}

	if ve.mouse_button_is_pressed(.Left) {
		if microwave.is_open {
			collision := ray_get_collision_bounding_box(ray, microwave.close_door_box)
			if collision.hit {
				microwave.closing = true
			}
		}
	}

	if microwave.closing {
		microwave.door_rotation += ve.time_get_delta()
		if microwave.door_rotation > 0 {
			microwave.door_rotation = 0
			microwave.closing = false
			microwave.is_open = false
		}
	}

	if ve.key_is_down(.C) {
		draw_box(microwave.close_door_box)
		draw_box(microwave.thingamagic_box)
		draw_box(microwave.open_button)
		draw_box(microwave.start_button_box)
		draw_box(microwave.drop_box)
		// update_vec3_from_keyboard(&microwave.drop_box.center)
		// log.info("BASE", microwave.drop_box.center - microwave.pos)
	}

	if ve.mouse_button_is_start_down(.Left) {
		collision := ray_get_collision_bounding_box(ray, microwave.thingamagic_box)
		if collision.hit {
			microwave.rotating_thingamagic = true
		}
	}

	if ve.mouse_button_is_start_up(.Left) {
		if microwave.rotating_thingamagic == true {
			for v in THINGAMAGIC_ANGLES {
				if v.value == microwave.thingamagic_value {
					microwave.thingamagic_angle = v.angle
					break
				}
			}
		}
		microwave.rotating_thingamagic = false
	}

	if ve.mouse_button_is_start_down(.Left) && !microwave.is_working && !microwave.opening && !microwave.closing {
		collision := ray_get_collision_bounding_box(ray, microwave.start_button_box)
		if collision.hit {
			microwave.is_working = true
		}
	}

	if microwave.is_working {
		microwave.timer_seconds += ve.time_get_delta()
		set_timer_seconds(cast(int)microwave.timer_seconds)
		if microwave.timer_seconds > cast(f32)get_tiemr_seconds_by_current_thingamagic() {
			// WORK IS DONE
			microwave.is_working = false
			microwave.timer_seconds = 0
			set_timer_seconds(cast(int)get_tiemr_seconds_by_current_thingamagic())

			c, ok := find_combination()
			for id in microwave.items do remove_item(id)
			clear(&microwave.items)

			new_item_id: Id
			if ok {
				r := rand.float32()
				percent: f32
				for to in c.to {
					percent += to.percent
					if percent >= r {
						new_item_id = create_item(to.item, microwave.spawn_pos).id
						break
					}
				}
			} else {
				new_item_id = create_item(R.s.default_item, microwave.spawn_pos).id
			}
			append(&microwave.items, new_item_id)
		}
	}

	if ve.mouse_button_is_start_up(.Left) {
		if microwave.rotating_thingamagic == true {
			for v in THINGAMAGIC_ANGLES {
				if v.value == microwave.thingamagic_value {
					microwave.thingamagic_angle = v.angle
					break
				}
			}
		}
		microwave.rotating_thingamagic = false
	}

	if microwave.rotating_thingamagic {
		box := Bounding_Box {
			center    = microwave.thingamagic_pos,
			half_size = {1000, 1000, 0.001},
		}
		collision := ray_get_collision_bounding_box(ray, box)
		if collision.hit {
			point := collision.point
			dir := linalg.normalize(point - microwave.thingamagic_pos)
			angle := linalg.atan2(dir.y, dir.x)
			angle = angle + 2.0 * math.PI * math.ceil_f32(-angle / (2.0 * math.PI))

			half_angle := (THINGAMAGIC_ANGLES[0].angle + THINGAMAGIC_ANGLES[len(THINGAMAGIC_ANGLES) - 1].angle) / 2
			half_angle += math.PI
			if half_angle < angle || angle < THINGAMAGIC_ANGLES[0].angle {
				angle = THINGAMAGIC_ANGLES[0].angle
			}
			if math.abs(angle) > THINGAMAGIC_ANGLES[len(THINGAMAGIC_ANGLES) - 1].angle {
				angle = THINGAMAGIC_ANGLES[len(THINGAMAGIC_ANGLES) - 1].angle
			}

			nearest_value: int = 0
			nearest_angle: f32 = max(f32)

			for v in THINGAMAGIC_ANGLES {
				diff := math.abs(math.abs(angle) - math.abs(v.angle))
				if nearest_angle > diff {
					nearest_angle = diff
					nearest_value = v.value
				}
			}
			update_thingmagic_value(nearest_value)
			microwave.thingamagic_angle = angle
		}
	}

	if ve.mouse_button_is_start_down(.Left) {
		// collision := ray_get_collision_bounding_box(ray, microwave.start_button_box)
		// if collision.hit {
		//
		// }
	}
}

remove_item :: proc(id: Id) {
	delete_key(&items, id)
}

get_tiemr_seconds_by_current_thingamagic :: proc() -> int {
	return R.s.timer_values[microwave.thingamagic_value]
}
get_tiemr_seconds_by_thingamagic_value :: proc(value: int) -> int {
	return R.s.timer_values[value]
}

update_thingmagic_value :: proc(value: int) {
	microwave.thingamagic_value = value
	set_timer_seconds(R.s.timer_values[microwave.thingamagic_value])
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

	renderer_draw_model(
		&G.r,
		R.models.microwave_thingamagic,
		linalg.mat4Translate(microwave.thingamagic_pos) *
		linalg.mat4FromQuat(linalg.quatAxisAngle({0, 0, 1}, microwave.thingamagic_angle - math.PI / 2)) *
		linalg.mat4Scale(microwave.scale),
	)

	renderer_draw_text(
		&microwave.timer_text,
		linalg.mat4Translate(microwave.timer_text.pos) * linalg.mat4Rotate({0, 1, 0}, math.PI),
	)


	// renderer_draw_model(&G.r, R.models.microwave_thingamagic, linalg.mat4Translate({0, 1, 0}))
	// renderer_draw_model(&G.r, R.models.microwave_door)
}

create_item :: proc(name: string, pos: vec3) -> ^Item {
	item_info, ok_item := R.s.items[name]
	box := item_info.box
	box.center = pos
	assert(ok_item, fmt.tprintf("Unregistered name: %s", name))
	item := Item {
		id   = uuid.generate_v4(),
		name = name,
		box  = box,
	}
	items[item.id] = item
	return &items[item.id]
}

create_random_pipe_item :: proc(pos: vec3) -> ^Item {
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
	for id, &item in items {
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
	for _, &item in items {
		item_info, ok_item := R.s.items[item.name]
		assert(ok_item)
		draw_box(item.box)
	}
}

draw_items :: proc() {
	for _, &item in items {
		draw_item(&item)
	}
}

draw_item :: proc(item: ^Item) {
	item_info, ok_item := R.s.items[item.name]
	assert(ok_item)
	model, ok_model := R.models.items[item_info.model_path]
	assert(ok_model)
	renderer_draw_model(&G.r, model, linalg.mat4Translate(item.box.center) * item_info.trf)
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
