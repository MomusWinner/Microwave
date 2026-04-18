package ld

import "core:log"
import linalg "core:math/linalg/glsl"
import "lib:ve"

create_game_scene :: proc() -> Scene {
	return Scene {
		init = game_scene_init,
		update = game_scene_update,
		draw = game_scene_draw,
		destroy = game_scene_destroy,
	}
}

game_scene_init :: proc(s: ^Scene) {

}

game_scene_update :: proc(s: ^Scene) {
	plaer_controller_update(&G.player)
	// if ve.mouse_button_is_pressed(.Left) {
	// 	create_bullet(G.player.camera.position, 20, ve.camera_get_forward(G.player.camera))
	// }
	// update_bullets()
}

game_scene_draw :: proc(s: ^Scene) {
	trf: ve.Transform
	ve.init_trf(&trf)
	ve.trf_set_position(&trf, {0, -GROUND_HEIGHT / 2, 0})
	renderer_draw_model(&G.r, R.models.ground, ve.trf_get_matrix(trf))

	draw_box(Bounding_Box{center = {2, 0.6, 0}, half_size = {0.3, 0.6, 0.6}})

	draw_box(Bounding_Box{center = {2, 2.5, 1}, half_size = {0.3, 1, 0.3}})
	draw_box(Bounding_Box{center = {2, 2.5, 2}, half_size = {0.05, 2, 0.05}})

	// renderer_draw_model(&G.r, R.models.enemy)
	// draw_bullets()
}

game_scene_destroy :: proc(s: ^Scene) {
	// destroy_bullet_manager()
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
