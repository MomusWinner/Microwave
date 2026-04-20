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

game_over :: proc() {
	game_is_over = true
}

INVALID_ID :: Id{}
Id :: uuid.Identifier

Item :: struct {
	id:           Id,
	name:         string,
	box:          Bounding_Box,
	acceleration: vec3,
	velocity:     vec3,
}

BASE_Z :: 5.0

Angle_Value :: struct {
	value: int,
	angle: f32,
}

THINGAMAGIC_ANGLES :: [3]Angle_Value{{0, 0}, {1, linalg.PI / 2}, {2, linalg.PI}}

items: map[Id]Item
taked_item: Id = INVALID_ID

MICROWAVE_ITEM_CAPACITY :: 2

kinematic_box: [dynamic]Bounding_Box

microwave: Microwave
Microwave :: struct {
	pos:                             vec3,
	scale:                           vec3,
	door_width:                      f32,
	spawn_pos:                       vec3,
	// main
	is_working:                      bool,
	// door
	close_door_box:                  Bounding_Box,
	door_rotation:                   f32,
	door_corner_box:                 Bounding_Box,
	is_open:                         bool,
	opening:                         bool,
	closing:                         bool,
	// thingamagic
	thingamagic_box:                 Bounding_Box,
	thingamagic_pos:                 vec3,
	thingamagic_value:               int, // from 0 to 2
	thingamagic_angle:               f32,
	rotating_thingamagic:            bool,
	// timer
	timer_text:                      Text,
	timer_seconds:                   f32,
	//open_button
	open_button:                     Bounding_Box,
	start_open_button_anim:          bool,
	start_open_button_anim_time:     f32,
	start_open_button_anim_elapsed:  f32,
	start_open_button_anim_pos:      vec3,
	// start button
	start_button_box:                Bounding_Box,
	start_start_button_anim:         bool,
	start_start_button_anim_time:    f32,
	start_start_button_anim_elapsed: f32,
	start_start_button_anim_pos:     vec3,
	// 0
	drop_box:                        Bounding_Box,
	items:                           [dynamic]Id,
}

Card :: struct {
	name:  string,
	model: Model,
	pos:   vec3,
}

MAX_CARDS :: 4
CARD_SCALE :: 1
card_positions := [MAX_CARDS]vec3 {
	vec3{-0.5, 0.5, -0.02},
	vec3{0.5, 0.5, -0.02},
	vec3{-0.5, -0.5, -0.02},
	vec3{0.5, -0.5, -0.02},
}

task_board: Task_Board
Task_Board :: struct {
	pos:              vec3,
	scale:            f32,
	start_pos_offset: vec3,
	rotation:         mat4,
	end_pos_offset:   vec3,
	opening:          bool,
	opening_t:        f32,
	closing:          bool,
	closing_t:        f32,
	is_open:          bool,
	elapsed_time:     f32,
	cards:            [dynamic]Card,
	consumed_items:   map[string]bool,
}

pipe_pos: vec3

// ROPE
start_rope_pos: vec3
rope_pos: vec3
get_rope_box :: proc() -> Bounding_Box {
	return Bounding_Box{center = rope_pos + vec3{0, 0, 0}, half_size = {0.4, 0.9, 0.4}}
}
rope_take_offset_y: f32
rope_pull_distance: f32
rope_pulled: bool
rope_is_taked: bool

// hp
hp_pos: vec3
hp_width: f32
hp_max_size: f32
hp_saturation: f32

game_is_over: bool

game_over_text: Text

eating_t: f32
eating_item: Id

game_scene_init :: proc(s: ^Scene) {
	bg_start(R.sounds.bg)

	game_over_text = create_text(&R.fonts.kiwisoda, "GAME OVER\nPress Enter to Restart", {0, 0.0, 0}, {1, 1, 1}, 0.01)
	text_set_position(
		&game_over_text,
		game_over_text.pos - {game_over_text.width / 2, game_over_text.height / 2 + 0.3, 1},
	)

	pipe_pos = {-3.7, 2.5, BASE_Z}
	eating_item = INVALID_ID

	// ROPE
	start_rope_pos = {-2.5, 2.8, BASE_Z}
	rope_pos = start_rope_pos
	rope_take_offset_y = 0
	rope_pull_distance = 0.9
	rope_pulled = false
	rope_is_taked = false

	// hp
	hp_pos = {2.913, 0.0, 6.744}
	hp_width = 0.3
	hp_max_size = 30
	hp_saturation = 0.5

	game_is_over = false

	append(&kinematic_box, Bounding_Box{half_size = {100, 0.5, 100}, center = {0, -0.5, 0}})
	init_microwave()
	init_task_board()
}

ray: Ray

last_taked_pos: vec3
last_taked_velocity: vec3

get_item :: proc(id: Id) -> ^Item {
	return &items[id]
}

get_item_info :: proc(id: Id) -> Item_Info {
	return R.s.items[get_item(id).name]
}

play_item_drop_sound :: proc(id: Id) {
	sound_restart(&R.sounds.item_sounds[get_item_info(id).sound_drop])
}

play_item_pickup_sound :: proc(id: Id) {
	sound_restart(&R.sounds.item_sounds[get_item_info(id).sound_pickup])
}

play_item_eat_sound :: proc(id: Id) {
	sound_restart(&R.sounds.item_sounds[get_item_info(id).sound_eat])
}

eat_item :: proc(id: Id) {
	item := items[id]
	item_info := R.s.items[item.name]
	remove_item(eating_item)
	hp_saturation += item_info.saturation
	if hp_saturation > 1 {
		hp_saturation = 1
	}
	complete_card(item.name)
}

game_scene_update :: proc(s: ^Scene) {
	if game_is_over {
		if ve.key_is_pressed(.Enter) {
			game_scene_reset()
			game_scene_init(s)
		}
		return
	}

	hp_saturation -= R.s.speed_of_hanger * ve.time_get_delta()
	if hp_saturation < 0 {
		game_over()
	}

	if (ve.key_is_pressed(.E) || ve.mouse_button_is_pressed(.Right)) && eating_item == INVALID_ID {
		if taked_item != INVALID_ID {
			eating_item = taked_item
			taked_item = INVALID_ID
			eating_t = 0
		}
	}

	if eating_item != INVALID_ID {
		eating_t += ve.time_get_delta() * 10
		item := get_item(eating_item)
		item.box.center = linalg.lerp(item.box.center, G.player.camera.position, eating_t)
		// eating_pos
		if eating_t > 1 {
			play_item_eat_sound(eating_item)
			eat_item(eating_item)
			eating_item = INVALID_ID
			eating_t = 0
		}
	}

	update_task_board()
	plaer_controller_update(&G.player)
	mouse := ve.mouse_get_position()
	ray = get_screen_to_world_ray(mouse, G.player.camera, ve.screen_get_width(), ve.screen_get_height())
	// draw_line(ray.position, ray.position + ray.direction)
	// draw_box(Bounding_Box{center = ray.position, half_size = 0.1})

	update_items()
	update_microwave()
	update_rope()

	if ve.mouse_button_is_start_down(.Left) {
		for id, item in items {
			collision := ray_get_collision_bounding_box(ray, item.box)
			if collision.hit {
				if slice.contains(microwave.items[:], id) && !microwave.is_open {
					continue
				}
				if eating_item == id {
					continue
				}
				taked_item = id
				play_item_pickup_sound(taked_item)
				break
			}
		}
	}

	if ve.mouse_button_is_start_up(.Left) {
		if taked_item != INVALID_ID {
			item := &items[taked_item]
			item.velocity = last_taked_velocity * 0.3
			play_item_drop_sound(taked_item)
			taked_item = INVALID_ID
		}
	}

	if taked_item != INVALID_ID {
		item := &items[taked_item]

		current_pos := item.box.center
		dt := ve.time_get_delta()
		if dt > 0 {
			last_taked_velocity = (current_pos - last_taked_pos) / dt
			last_taked_velocity.z = 0
		}

		last_taked_pos = current_pos

		item.acceleration = 0
		item.velocity = 0
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
		draw_box(get_rope_box())
		draw_items_debug()
		for k, i in kinematic_box {
			if i == 0 do continue
			draw_box(k)
		}
	}
}

game_scene_draw :: proc(s: ^Scene) {
	if game_is_over {
		draw_uitext(&game_over_text)
	}

	trf: ve.Transform
	ve.init_trf(&trf)
	renderer_draw_model(&G.r, R.models.ground, linalg.mat4Translate(G.ground.center))
	renderer_draw_model(&G.r, R.models.pipe, linalg.mat4Translate(pipe_pos))
	renderer_draw_model(&G.r, R.models.rope, linalg.mat4Translate(rope_pos))
	draw_microwave()

	renderer_draw_model(
		&G.r,
		R.models.hp,
		linalg.mat4Translate(hp_pos) * linalg.mat4Scale({hp_width, hp_max_size * (hp_saturation / 1), hp_width}),
	)

	draw_items()
	draw_task_board()
}

game_scene_reset :: proc() {
	clear(&items)
	clear(&kinematic_box)

	destroy_text(&game_over_text)

	clear(&task_board.cards)
	clear(&task_board.consumed_items)
	task_board = Task_Board{}

	sound_stop(&R.sounds.microwave_beep)
	sound_stop(&R.sounds.microwave_close)
	sound_stop(&R.sounds.microwave_finish)
	sound_stop(&R.sounds.microwave_open)
	sound_stop(&R.sounds.microwave_start)
	sound_stop(&R.sounds.microwave_switch)

	delete(microwave.items)
	microwave = Microwave{}
}

game_scene_destroy :: proc(s: ^Scene) {

}

task_board_get_start_pos :: proc() -> vec3 {
	return G.player.camera.position + task_board.start_pos_offset
}

task_board_get_end_pos :: proc() -> vec3 {
	return G.player.camera.position + task_board.end_pos_offset
}

complete_card :: proc(name: string) {
	for c, i in task_board.cards {
		if c.name == name {
			task_board.consumed_items[name] = true
			ordered_remove(&task_board.cards, i)
			break
		}
	}
}

get_next_recommendation :: proc() -> []string {
	recommendations := make([dynamic]string, context.temp_allocator)

	for _, item in R.s.items {
		has_combo := false
		for combo in R.s.combinations {
			for to in combo.to {
				if to.item == item.name {
					has_combo = true
					break
				}
			}
			if has_combo do break
		}

		if !has_combo && item.name not_in task_board.consumed_items {
			append(&recommendations, item.name)
		}
	}


	for consumed_item in task_board.consumed_items {
		for combo in R.s.combinations {
			if !slice.contains(combo.from[:], consumed_item) do continue

			all_consumed := true
			for from_item in combo.from {
				if from_item not_in task_board.consumed_items {
					all_consumed = false
					break
				}
			}

			if all_consumed {
				for to_item in combo.to {
					if to_item.item in R.s.items {
						append(&recommendations, to_item.item)
					}
				}
			}
		}
	}

	unique_recs := make([dynamic]string, context.temp_allocator)
	for rec in recommendations {
		if rec not_in task_board.consumed_items && !slice.contains(unique_recs[:], rec) {

			already_added := false
			for c in task_board.cards {
				if c.name == rec {
					already_added = true
					break
				}
			}

			if !already_added {
				append(&unique_recs, rec)
			}
		}
	}

	return unique_recs[:]
}

create_card :: proc(item: Item_Info) -> Card {
	model := Model {
		meshes = slice.clone(R.models.card[:]),
	}
	model_add_single_material(&model, create_light_material(item.card))
	card := Card {
		name  = item.name,
		model = model,
	}
	append(&task_board.cards, card)
	i := len(task_board.cards) - 1
	task_board.cards[i].pos = card_positions[i]
	return card
}

init_task_board :: proc() {
	task_board.start_pos_offset = {0, -1, 4}
	task_board.end_pos_offset = {0, -5, 1}
	task_board.pos = {0, -100, 0}
	task_board.rotation = linalg.mat4Rotate(vec3{1, 0, 0}, linalg.PI / 9.0)
	task_board.scale = 1.4
	task_board.is_open = false
	task_board.opening = false
	task_board.closing = false
	task_board.elapsed_time = 0
}

draw_task_board :: proc() {
	renderer_draw_model(
		&G.r,
		R.models.task_board,
		linalg.mat4Translate(task_board.pos) * task_board.rotation * linalg.mat4Scale(task_board.scale),
	)

	for card in task_board.cards {
		renderer_draw_model(
			&G.r,
			card.model,
			linalg.mat4Translate(task_board.pos) *
			task_board.rotation *
			linalg.mat4Translate(+card.pos) *
			linalg.mat4Scale(CARD_SCALE),
		)
	}
}

update_task_board :: proc() {
	task_board.elapsed_time += ve.time_get_delta()

	if task_board.elapsed_time > 1 {
		task_board.elapsed_time = 0
		recs := get_next_recommendation()
		if len(task_board.cards) < MAX_CARDS && len(recs) > 0 {
			create_card(R.s.items[recs[0]])
		}
	}

	// Open / Close
	if ve.key_is_pressed(.O) && !task_board.opening && !task_board.is_open {
		task_board.opening = true
		task_board.pos = task_board_get_end_pos()
		task_board.opening_t = 0
	}

	if task_board.opening {
		task_board.opening_t += ve.time_get_delta() * 4
		task_board.pos = linalg.lerp(task_board.pos, task_board_get_start_pos(), task_board.opening_t)

		if task_board.opening_t > 1 {
			task_board.opening = false
			task_board.is_open = true
			task_board.pos = task_board_get_start_pos()
		}
	}

	if task_board.is_open {
		task_board.pos = task_board_get_start_pos()
	}

	if ve.key_is_pressed(.O) && task_board.is_open && !task_board.closing {
		task_board.closing = true
		task_board.is_open = false
		task_board.opening = false
		task_board.pos = task_board_get_start_pos()
		task_board.closing_t = 0
	}

	if task_board.closing {
		task_board.closing_t += ve.time_get_delta() * 7
		task_board.pos = linalg.lerp(task_board.pos, task_board_get_end_pos(), task_board.closing_t)

		if task_board.closing_t > 1 {
			task_board.closing = false
			task_board.is_open = false
			task_board.pos = task_board_get_end_pos()
		}
	}
}

destroy_task_board :: proc() {

}

update_rope :: proc() {
	if ve.mouse_button_is_start_down(.Left) {
		collision := ray_get_collision_bounding_box(ray, get_rope_box())
		if collision.hit {
			rope_take_offset_y = rope_pos.y - collision.point.y
			rope_is_taked = true
			multiple_sound_play(&R.sounds.rope_pull)
		} else {
			rope_is_taked = false
		}
	}

	if ve.mouse_button_is_start_up(.Left) {
		rope_is_taked = false
		multiple_sound_play(&R.sounds.rope_pull)
	}

	if rope_is_taked {
		collision := ray_get_collision_bounding_box(
			ray,
			Bounding_Box{center = get_rope_box().center, half_size = {100, 100, 0.001}},
		)

		rope_pos.y = collision.point.y + rope_take_offset_y
		if rope_pos.y > start_rope_pos.y {
			rope_pos.y = start_rope_pos.y
		}

		if math.abs(rope_pos.y - start_rope_pos.y) >= rope_pull_distance {
			rope_pos.y = start_rope_pos.y - rope_pull_distance - 0.0001
			if !rope_pulled {
				create_random_pipe_item(pipe_pos)
			}
			rope_pulled = true
		} else {
			rope_pulled = false
		}
	} else if math.abs(rope_pos.y - start_rope_pos.y) > 0.02 {

		rope_pulled = false
		dir := linalg.normalize(start_rope_pos.y - rope_pos.y)
		rope_pos.y += dir * 1 * ve.time_get_delta()
	}
}

find_combination :: proc() -> (Combination_Info, bool) {
	names := make([dynamic]string, len(microwave.items), context.temp_allocator)
	for item_id, i in microwave.items {
		item := items[item_id]
		names[i] = item.name
	}

	for c in R.s.combinations {
		if c.timer_value != microwave.thingamagic_value do continue
		ok: bool = true
		for c_name in c.from {
			if !slice.contains(names[:], c_name) {
				ok = false
				break
			}
		}
		if !ok do continue

		if len(names) != len(c.from) do continue
		return c, true
	}

	return {}, false
}

init_microwave :: proc() {
	microwave.pos = vec3{0, 0, BASE_Z + 2.2}
	microwave.scale = 1

	append(&kinematic_box, Bounding_Box{center = microwave.pos - {1.7, 0, -0.3}, half_size = {1., 3, 1}})
	append(&kinematic_box, Bounding_Box{center = microwave.pos + {2.5, 0, 0.1}, half_size = {1., 3, 1}})
	append(&kinematic_box, Bounding_Box{center = microwave.pos - {0, 0.5, 0}, half_size = {4, 0.8, 1}})

	microwave.close_door_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{2.153, 1.084, -3.194},
		half_size = vec3{0.3, 1, 0.3} * microwave.scale,
	}

	microwave.spawn_pos = microwave.pos + {0, 0.7, 0} * microwave.scale

	microwave.timer_text = create_text(
		&R.fonts.segment,
		"00:00",
		microwave.pos + microwave.scale * vec3{-1.15, 1.629, -0.9999},
		{1, 0, 0},
		0.004 * microwave.scale.x,
	)

	// Thingamagic
	microwave.thingamagic_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{-1.427, 1.274, -0.845},
		half_size = vec3{0.3, 0.3, 0.3} * microwave.scale,
	}
	microwave.thingamagic_pos = microwave.pos + microwave.scale * {-1.4271961, 1.1810113, -1.1490066}
	update_thingmagic_value(0)


	// Start button
	microwave.start_button_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{-1.5658, 0.759148, -0.960555},
		half_size = 0.1 * microwave.scale,
	}
	microwave.start_start_button_anim_time = 0.5

	// Open button
	microwave.open_button = Bounding_Box {
		half_size = microwave.scale * {0.2, 0.1, 0.1},
		center    = microwave.pos + microwave.scale * {-1.439889, 0.43842125, -1.10038829},
	}
	microwave.start_open_button_anim_time = 0.5
	//

	microwave.drop_box = Bounding_Box {
		center    = microwave.pos + microwave.scale * vec3{0.37175516, 1.0606446, -0.398627},
		half_size = vec3{0.85, 0.4, 0.8} * microwave.scale,
	}

	lights := ubo_light_info_get_spot_lights(G.r.lsource.ubo)
	lights[0].position = microwave.pos + {0, 2, 0} * microwave.scale
	lights[0].color = {2, 2, 1}
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
	if ve.mouse_button_is_pressed(.Left) && !microwave.is_working {
		collision := ray_get_collision_bounding_box(ray, microwave.open_button)
		if collision.hit {
			microwave.opening = true
			microwave.start_open_button_anim = true
			sound_restart(&R.sounds.microwave_open)
		}
	}

	if microwave.start_open_button_anim {
		microwave.start_open_button_anim_elapsed += ve.time_get_delta()
		offset := math.sin(1 + (microwave.start_open_button_anim_elapsed / microwave.start_open_button_anim_time) * 2)
		offset *= 0.1
		microwave.start_open_button_anim_pos.z = offset
		if microwave.start_open_button_anim_elapsed > microwave.start_open_button_anim_time {
			microwave.start_open_button_anim = false
			microwave.start_open_button_anim_elapsed = 0
			microwave.start_open_button_anim_pos = 0
		}
	}

	if microwave.opening {
		microwave.door_rotation -= 3 * ve.time_get_delta()
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

				sound_start(&R.sounds.microwave_close)
			}
		}
	}

	if microwave.closing {
		microwave.door_rotation += 4 * ve.time_get_delta()
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

	if ve.mouse_button_is_start_down(.Left) &&
	   len(microwave.items) != 0 &&
	   !microwave.is_working &&
	   !microwave.opening &&
	   !microwave.closing {
		collision := ray_get_collision_bounding_box(ray, microwave.start_button_box)
		if collision.hit {
			microwave.is_working = true
			microwave.start_start_button_anim = true
			sound_restart(&R.sounds.microwave_start)
		}
	}

	if microwave.start_start_button_anim {
		microwave.start_start_button_anim_elapsed += ve.time_get_delta()
		offset := math.sin(1 + (microwave.start_start_button_anim_elapsed / microwave.start_start_button_anim_time) * 2)
		offset *= 0.1
		microwave.start_start_button_anim_pos.z = offset
		if microwave.start_start_button_anim_elapsed > microwave.start_start_button_anim_time {
			microwave.start_start_button_anim = false
			microwave.start_start_button_anim_elapsed = 0
			microwave.start_start_button_anim_pos = 0
		}
	}

	if microwave.is_working {
		microwave.timer_seconds += ve.time_get_delta()
		set_timer_seconds(cast(int)microwave.timer_seconds)
		if microwave.timer_seconds > cast(f32)get_tiemr_seconds_by_current_thingamagic() {
			// WORK IS DONE

			sound_stop(&R.sounds.microwave_start)
			sound_start(&R.sounds.microwave_finish)

			microwave.is_working = false
			microwave.timer_seconds = 0
			set_timer_seconds(cast(int)get_tiemr_seconds_by_current_thingamagic())

			c, find_comb := find_combination()

			item_count := len(microwave.items)
			remove_items := make([]Id, len(microwave.items), context.temp_allocator)
			copy_slice(remove_items[:], microwave.items[:])
			for id in remove_items do remove_item(id)
			clear(&microwave.items)

			new_item_id: Id

			if item_count < microwave.thingamagic_value + 1 {
				new_item_id = create_item(R.s.coal_item, microwave.spawn_pos).id
			} else if find_comb {
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
}

remove_item :: proc(id: Id) {
	delete_key(&items, id)
	for m_id, i in microwave.items {
		if m_id == id {
			ordered_remove(&microwave.items, i)
			break
		}
	}
}

get_tiemr_seconds_by_current_thingamagic :: proc() -> int {
	return R.s.timer_values[microwave.thingamagic_value]
}
get_tiemr_seconds_by_thingamagic_value :: proc(value: int) -> int {
	return R.s.timer_values[value]
}

update_thingmagic_value :: proc(value: int) {
	if microwave.thingamagic_value == value do return
	microwave.thingamagic_value = value
	set_timer_seconds(R.s.timer_values[microwave.thingamagic_value])
	sound_restart(&R.sounds.microwave_switch)
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

	renderer_draw_model(
		&G.r,
		R.models.microwave_button,
		linalg.mat4Translate({0, 0, -0.1} + microwave.pos + microwave.start_start_button_anim_pos) *
		linalg.mat4Scale(microwave.scale),
	)

	renderer_draw_model(
		&G.r,
		R.models.microwave_open_button,
		linalg.mat4Translate(microwave.pos + microwave.start_open_button_anim_pos) * linalg.mat4Scale(microwave.scale),
	)
	renderer_draw_model(
		&G.r,
		R.models.microwave_button_holders,
		linalg.mat4Translate(microwave.pos) * linalg.mat4Scale(microwave.scale),
	)
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
	multiple_sound_play(&R.sounds.pipe)

	return create_item(item_info.name, pos)
}

GRAVITY :: 9.8
DAMPING :: 0.98

COLLISION_ITERATIONS :: 2
POSITION_CORRECTION_FACTOR :: 0.3

RESTITUTION_ITEM_ITEM :: 0.1
RESTITUTION_ITEM_KINEMATIC :: 0.2
RESTITUTION_GROUND :: 1.5

FRICTION :: 0.35

VELOCITY_STOP_THRESHOLD :: 0.1

update_items :: proc() {
	dt := ve.time_get_delta()

	for id, &item in items {
		item.acceleration.y = -GRAVITY
		item.velocity += item.acceleration * dt

		item.velocity.x *= DAMPING
		item.velocity.z *= DAMPING

		item.box.center += item.velocity * dt
	}

	for iteration in 0 ..< COLLISION_ITERATIONS {
		for id1, &item1 in items {
			for id2, &item2 in items {
				if id1 == id2 do continue

				if bounding_boxes_overlap(item1.box, item2.box) {
					resolve_collision(&item1, &item2)
				}
			}
		}

		for id, &item in items {
			for &kin_box in kinematic_box {
				if bounding_boxes_overlap(item.box, kin_box) {
					resolve_collision_with_kinematic(&item, kin_box)
				}
			}
		}

		for id, &item in items {
			bottom_y := item.box.center.y - item.box.half_size.y
			if bottom_y < 0 {
				item.box.center.y = item.box.half_size.y
				if item.velocity.y < 0 {
					item.velocity.y = -item.velocity.y * RESTITUTION_GROUND
					if abs(item.velocity.y) < VELOCITY_STOP_THRESHOLD {
						item.velocity.y = 0
					}
				}
			}
		}
	}
}

bounding_boxes_overlap :: proc(box1, box2: Bounding_Box) -> bool {
	delta := box1.center - box2.center
	total_half_size := box1.half_size + box2.half_size
	return abs(delta.x) < total_half_size.x && abs(delta.y) < total_half_size.y && abs(delta.z) < total_half_size.z
}

resolve_collision :: proc(item1, item2: ^Item) {
	delta := item1.box.center - item2.box.center
	total_half_size := item1.box.half_size + item2.box.half_size

	overlap := total_half_size - linalg.abs(delta)

	min_overlap := overlap.x
	axis := vec3{1, 0, 0}

	if overlap.y < min_overlap {
		min_overlap = overlap.y
		axis = vec3{0, 1, 0}
	}
	if overlap.z < min_overlap {
		min_overlap = overlap.z
		axis = vec3{0, 0, 1}
	}

	dir := vec3{linalg.sign(delta.x), linalg.sign(delta.y), linalg.sign(delta.z)}
	if delta.x == 0 do dir.x = 0
	if delta.y == 0 do dir.y = 0
	if delta.z == 0 do dir.z = 0

	correction := axis * min_overlap * dir
	item1.box.center += correction * POSITION_CORRECTION_FACTOR
	item2.box.center -= correction * POSITION_CORRECTION_FACTOR

	relative_velocity := item1.velocity - item2.velocity
	velocity_along_axis := linalg.dot(relative_velocity, axis)

	if velocity_along_axis < 0 {
		impulse := (1 + RESTITUTION_ITEM_ITEM) * velocity_along_axis * 0.3 // Уменьшил импульс
		item1.velocity -= axis * impulse
		item2.velocity += axis * impulse

		if axis.y == 0 {
			item1.velocity.x *= FRICTION
			item1.velocity.z *= FRICTION
			item2.velocity.x *= FRICTION
			item2.velocity.z *= FRICTION
		}
	}

	if abs(velocity_along_axis) < 0.01 && min_overlap > 0.01 {
		return
	}
}

resolve_collision_with_kinematic :: proc(item: ^Item, kin_box: Bounding_Box) {
	delta := item.box.center - kin_box.center
	total_half_size := item.box.half_size + kin_box.half_size

	overlap := total_half_size - linalg.abs(delta)

	min_overlap := overlap.x
	axis := vec3{1, 0, 0}

	if overlap.y < min_overlap {
		min_overlap = overlap.y
		axis = vec3{0, 1, 0}
	}
	if overlap.z < min_overlap {
		min_overlap = overlap.z
		axis = vec3{0, 0, 1}
	}

	dir := vec3{linalg.sign(delta.x), linalg.sign(delta.y), linalg.sign(delta.z)}
	if delta.x == 0 do dir.x = 0
	if delta.y == 0 do dir.y = 0
	if delta.z == 0 do dir.z = 0

	correction := axis * min_overlap * dir
	item.box.center += correction

	velocity_along_axis := linalg.dot(item.velocity, axis)
	if velocity_along_axis < 0 {
		item.velocity -= axis * (1 + RESTITUTION_ITEM_KINEMATIC) * velocity_along_axis * 0.5

		if axis.y == 0 {
			item.velocity.x *= FRICTION
			item.velocity.z *= FRICTION
		}

		if abs(item.velocity.y) < VELOCITY_STOP_THRESHOLD {
			item.velocity.y = 0
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
