package ld

import linalg "core:math/linalg/glsl"
import "lib:ve"

create_menu_scene :: proc() -> Scene {
	return Scene {
		init = menu_scene_init,
		update = menu_scene_update,
		draw = menu_scene_draw,
		destroy = menu_scene_destroy,
	}
}

@(private = "file")
start_text: Text

elapsed_time: f32
START_TIME :: 3

menu_scene_init :: proc(s: ^Scene) {
	start_text = create_text(&R.fonts.kiwisoda, "Press Enter to Start game", {0, -4.0, 0}, {1, 1, 1}, 0.01)
	text_set_position(&start_text, start_text.pos - {start_text.width / 2, start_text.height / 2 + 0.3, 1})
	elapsed_time = 0
}

menu_scene_update :: proc(s: ^Scene) {
	elapsed_time += ve.time_get_delta()

	if ve.key_is_pressed(.Enter) && elapsed_time > START_TIME {
		started = true
		G.scenes.current_scene = &G.scenes.game_scane
	}
}

menu_scene_draw :: proc(s: ^Scene) {
	if elapsed_time > START_TIME {
		draw_uitext(&start_text)
	}
	r_draw_model(&G.r, R.models.tutorial, linalg.mat4Rotate({1, 0, 0}, linalg.PI / 3) * linalg.mat4Scale(1.8))
}

menu_scene_destroy :: proc(s: ^Scene) {

}
