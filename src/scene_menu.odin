package ld

import linalg "core:math/linalg/glsl"

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

menu_scene_init :: proc(s: ^Scene) {
	start_text = create_text(&R.fonts.kiwisoda, "Press Enter to Start game", {0, -4.0, 0}, {1, 1, 1}, 0.01)
	text_set_position(&start_text, start_text.pos - {start_text.width / 2, start_text.height / 2 + 0.3, 1})
}

menu_scene_update :: proc(s: ^Scene) {

}

menu_scene_draw :: proc(s: ^Scene) {
	draw_uitext(&start_text)
	renderer_draw_model(&G.r, R.models.tutorial, linalg.mat4Rotate({1, 0, 0}, linalg.PI / 3) * linalg.mat4Scale(1.8))
}

menu_scene_destroy :: proc(s: ^Scene) {

}
