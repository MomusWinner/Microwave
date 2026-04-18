package ld

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:time"
import "lib:ve"
import vemath "lib:ve/math"

TARGET_FPS :: 120
FIXED_DELTA_TIME :: 1.0 / TARGET_FPS

// BACKGROUND := linerize_color({0.913, 0.964, 0.882})
BACKGROUND := linerize_color(vec4{0.13, 0.13, 0.13, 1})

NEAREST_FILTER_SAMPLER :: ve.Sampler_Info {
	mag_filter     = .Nearest,
	min_filter     = .Nearest,
	address_mode_u = .Repeat,
	address_mode_v = .Repeat,
	address_mode_w = .Repeat,
	border_color   = .Transparent_Black,
	mipmap_mode    = .Nearest,
	lod_clamp      = ve.SAMPLER_LOD_CLAMP_NONE,
}

Scene :: struct {
	data:    rawptr,
	init:    proc(s: ^Scene),
	update:  proc(s: ^Scene),
	draw:    proc(s: ^Scene),
	destroy: proc(s: ^Scene),
}

Global :: struct {
	r:      Renderer,
	player: Player_Controller,
	ground: Bounding_Box,
	scenes: struct {
		current_scene: ^Scene,
		menu_scane:    Scene,
		game_scane:    Scene,
	},
}

Resources :: struct {
	pipelines:  struct {
		base:           ve.Graphics_Pipeline,
		depth_only:     ve.Graphics_Pipeline,
		light:          ve.Graphics_Pipeline,
		postprocessing: ve.Graphics_Pipeline,
		primitive:      ve.Graphics_Pipeline,
		text:           ve.Graphics_Pipeline,
		gaussian_hor:   ve.Graphics_Pipeline,
		gaussian_ver:   ve.Graphics_Pipeline,
		light_source:   ve.Graphics_Pipeline,
	},
	sounds:     struct {
		bg: Sound,
	},
	models:     struct {
		ground: Model,
		enemy:  Model,
		bullet: Model,
	},
	primitives: struct {
		square: ve.Mesh,
	},
	fonts:      struct {
		kiwisoda: ve.Font,
	},
}

G: Global
R: Resources

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	when ODIN_DEBUG {
		context.logger = log.create_console_logger()
	} else {
		context.logger = log.create_console_logger(lowest = .Warning)
	}
	defer log.destroy_console_logger(context.logger)

	ve.start(
		{
			gfx = {swapchain_sample_count = ._1, attachments = {.Depth, .Stencil}},
			window = {width = 800, height = 800, resizable = true, title = "LD"},
		},
	)

	R.fonts.kiwisoda = ve.load_font(
		"assets/KiwiSoda.ttf",
		ve.Create_Font_Info {
			size = 32,
			padding = 2,
			atlas_width = 2024,
			atlas_height = 1024,
			regions = {{start = 32, size = 128}},
			default_char = '?',
		},
		NEAREST_FILTER_SAMPLER,
	)

	G.scenes.menu_scane = create_menu_scene()
	G.scenes.menu_scane.init(&G.scenes.menu_scane)
	G.scenes.game_scane = create_game_scene()
	G.scenes.game_scane.init(&G.scenes.game_scane)

	G.scenes.current_scene = &G.scenes.menu_scane

	load_pipelines()
	load_models()

	init_debug_drawer()
	defer destroy_debug_drawer()

	init_music()
	defer destroy_music()

	load_sounds()
	defer destroy_sounds()

	// ve.cursor_set_mode(.Captured)
	G.r = create_renderer()

	p_camera: ve.Camera
	ve.init_camera(&p_camera)
	init_player_controller(&G.player, {0, 1, 0}, p_camera)

	G.ground = Bounding_Box {
		center    = {0, -GROUND_HEIGHT / 2, 0},
		half_size = {GROUND_WIDTH / 2, GROUND_HEIGHT / 2, GROUND_WIDTH / 2},
	}

	prev: time.Time
	for ve.update() {
		free_all(context.temp_allocator)

		// -- Begin Update ----------------------------------------
		if (ve.key_is_pressed(.Escape)) {
			break
		}
		when ODIN_DEBUG {
			if (ve.key_is_pressed(.R)) {
				ve.hot_reload_shaders()
			}
		}

		G.r.lsource.camera.target = 0
		speed: f32 = 0.4
		radius: f32 = 5
		G.r.lsource.camera.position = vec3 {
			math.cos_f32(cast(f32)ve.time_get_total() * speed) * radius,
			math.sin_f32(cast(f32)ve.time_get_total() * speed) * radius,
			G.r.lsource.camera.position.z,
		}


		@(static) started: bool
		if !started {
			if ve.key_is_pressed(.Enter) {
				started = true
				G.scenes.current_scene = &G.scenes.game_scane
			}
			when ODIN_DEBUG {
				started = true
				G.scenes.current_scene = &G.scenes.game_scane
			}
		}
		G.scenes.current_scene.update(G.scenes.current_scene)
		// -- End Update ----------------------------------------

		// -- Begin Draw ----------------------------------------
		ve.begin_pass()

		begin_debug_drawer()

		begin_renderer(
			&G.r,
			ve.camera_get_buffer(G.player.camera, cast(f32)ve.screen_get_width() / cast(f32)ve.screen_get_height()),
		)

		G.scenes.current_scene.draw(G.scenes.current_scene)

		end_renderer(&G.r)

		end_debug_drawer()

		ve.end_pass()
		// -- End Draw ----------------------------------------

		target_delta_time: f64 = (1.0 / TARGET_FPS) * f64(time.Second)
		target_delta_duration := time.Duration(target_delta_time)
		frame_duration := time.diff(prev, time.now())
		if frame_duration < target_delta_duration {
			time.accurate_sleep(target_delta_duration - frame_duration)
		}
		prev = time.now()
	}
	ve.wait_render_completion()

	G.scenes.menu_scane.destroy(&G.scenes.menu_scane)
	G.scenes.game_scane.destroy(&G.scenes.game_scane)

	ve.destroy_font(&R.fonts.kiwisoda)
	destroy_render(&G.r)
	destroy_models()

	ve.close()
}

load_sounds :: proc() {
	R.sounds.bg = load_bg_music("assets/sounds/bg1.mp3")
}

destroy_sounds :: proc() {
	destroy_sound(&R.sounds.bg)
}

load_models :: proc() {
	R.primitives.square = ve.create_primitive_square()

	R.models.ground = create_model_from_mesh(
		ve.create_primitive_cube({GROUND_WIDTH / 2, GROUND_HEIGHT / 2, GROUND_WIDTH / 2}),
	)
	model_add_single_material(&R.models.ground, create_light_material(color = {0.4, 0.2, 0}))

	R.models.bullet = create_model_from_mesh(ve.create_primitive_cube(0.1))
	model_add_single_material(&R.models.bullet, create_light_source_material(color = {1, 1, 1}))

	//Nightstand, Couch, LoveChan
	texture := ve.load_texture("assets/models/Couch/texture.png", sampler_info = NEAREST_FILTER_SAMPLER)
	R.models.enemy = load_model("assets/models/Couch")
	model_add_single_material(&R.models.enemy, create_light_material(texture))
}

destroy_models :: proc() {
	ve.destroy_mesh(&R.primitives.square)

	destroy_model(&R.models.bullet)
	destroy_model(&R.models.enemy)
	destroy_model(&R.models.ground)
}
