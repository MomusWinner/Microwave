package ld

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import linalg "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "lib:ve"
import vemath "lib:ve/math"

TARGET_FPS :: 120
FIXED_DELTA_TIME :: 1.0 / TARGET_FPS

BACKGROUND := linerize_color(vec4{0.13, 0.13, 0.15, 1})

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
	// settings
	s:          struct {
		// item_info by name
		coal_item:       string,
		default_item:    string,
		items:           map[string]Item_Info,
		speed_of_hanger: f32,
		combinations:    [dynamic]Combination_Info,
		pipe:            Pipe_Info,
		timer_values:    map[int]int,
	},
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
		bg:               Sound,
		item_sounds:      map[string]Sound,
		microwave_beep:   Sound,
		microwave_close:  Sound,
		microwave_finish: Sound,
		microwave_open:   Sound,
		microwave_start:  Sound,
		microwave_switch: Sound,
	},
	models:     struct {
		ground:                Model,
		enemy:                 Model,
		pipe:                  Model,
		rope:                  Model,
		hp:                    Model,
		microwave:             Model,
		microwave_door:        Model,
		microwave_open_button: Model,
		microwave_button:      Model,
		microwave_thingamagic: Model,
		items:                 map[string]Model,
	},
	stextures:  map[string]ve.Texture,
	primitives: struct {
		square: ve.Mesh,
	},
	fonts:      struct {
		kiwisoda: ve.Font,
		segment:  ve.Font,
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

	R.fonts.segment = ve.load_font(
		"assets/SevenSegment.ttf",
		ve.Create_Font_Info {
			size = 64,
			padding = 2,
			atlas_width = 2024,
			atlas_height = 1024,
			regions = {{start = 32, size = 128}},
			default_char = '?',
		},
	)

	init_debug_drawer()
	defer destroy_debug_drawer()

	init_music()
	defer destroy_music()

	load_sounds()
	defer destroy_sounds()

	load_pipelines()
	load_models()
	load_game_settings()

	G.r = create_renderer()

	p_camera: ve.Camera
	ve.init_camera(&p_camera)
	init_player_controller(&G.player, {0, 1, 0}, p_camera)

	G.scenes.menu_scane = create_menu_scene()
	G.scenes.menu_scane.init(&G.scenes.menu_scane)
	G.scenes.game_scane = create_game_scene()
	G.scenes.game_scane.init(&G.scenes.game_scane)

	G.scenes.current_scene = &G.scenes.menu_scane

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

		G.r.lsource.camera.target = {0, 0, 1}
		// speed: f32 = 0.4
		// radius: f32 = 5
		// G.r.lsource.camera.position = vec3 {
		// 	math.cos_f32(cast(f32)ve.time_get_total() * speed) * radius,
		// 	math.sin_f32(cast(f32)ve.time_get_total() * speed) * radius,main
		// 	G.r.lsource.camera.position.z,
		// }

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
		// log.info(1 / ve.time_get_delta())
	}
	ve.wait_render_completion()

	G.scenes.menu_scane.destroy(&G.scenes.menu_scane)
	G.scenes.game_scane.destroy(&G.scenes.game_scane)

	ve.destroy_font(&R.fonts.kiwisoda)
	ve.destroy_font(&R.fonts.segment)
	destroy_render(&G.r)
	destroy_models()

	ve.close()
}

load_sounds :: proc() {
	// R.sounds.bg = load_bg_music("assets/sounds/bg1.mp3")
	R.sounds.microwave_beep = load_sound("assets/sounds/microwave_beep.mp3")
	R.sounds.microwave_close = load_sound("assets/sounds/microwave_close.mp3")
	R.sounds.microwave_finish = load_sound("assets/sounds/microwave_finish.mp3")
	R.sounds.microwave_open = load_sound("assets/sounds/microwave_open.mp3")
	R.sounds.microwave_start = load_sound("assets/sounds/microwave_start.mp3")
	R.sounds.microwave_switch = load_sound("assets/sounds/microwave_switch.mp3")
}

destroy_sounds :: proc() {
	destroy_sound(&R.sounds.bg)
}

load_game_settings :: proc() {
	settings_path := "assets/game.json"
	if !os.is_file(settings_path) {
		log.panicf("Couldn't load game settings. Path \"%s\" is not exist", settings_path)
	}

	settings_data, ok := ve.read_file(settings_path, context.temp_allocator)
	if !ok do log.panic("Couldn't read game settings")

	j, err := json.parse(settings_data, allocator = context.temp_allocator)
	if err != .None do log.panicf("Couldn't parse game settings: %v", err)
	fields := j.(json.Object)
	load_items(fields["objects"].(json.Array))
	load_pipe(fields["pipe"].(json.Object))
	load_combinations(fields["combinations"].(json.Array))

	R.s.default_item = strings.clone(fields["default_object"].(json.String))
	R.s.coal_item = strings.clone(fields["coal_object"].(json.String))
	R.s.speed_of_hanger = cast(f32)fields["speed_of_hanger"].(json.Float)

	timer_values_json := fields["timer_values"].(json.Array)
	if len(timer_values_json) != 3 {
		log.panic("Incorrect game settings: timer_values should contains only 3 values")
	}
	for value, i in timer_values_json {
		R.s.timer_values[i] = cast(int)value.(json.Float)
	}

	log.info(R.s.items)
}

Item_Info :: struct {
	name:          string,
	saturation:    f32,
	model_path:    string,
	box:           Bounding_Box,
	scale:         vec3,
	rotation:      vec3,
	origin_offset: vec3,
	trf:           mat4,
	sound_drop:    string,
	sound_pickup:  string,
	sound_eat:     string,
}

load_items :: proc(array: json.Array) {
	for item_json in array {
		item := item_json.(json.Object)
		name := strings.clone(item["name"].(json.String))
		model_path := strings.clone(item["model"].(json.String))
		_, model_loaded := R.models.items[model_path]
		if !model_loaded {
			model := load_item_model(model_path)
			R.models.items[model_path] = model
		}

		saturation := cast(f32)item["saturation"].(json.Float)

		drop_sound := strings.clone(item["sound_drop"].(json.String))
		_, has_drop := R.sounds.item_sounds[drop_sound]
		if !has_drop {
			R.sounds.item_sounds[drop_sound] = load_sound(drop_sound)
		}
		eat_sound := strings.clone(item["sound_eat"].(json.String))
		_, has_eat := R.sounds.item_sounds[eat_sound]
		if !has_eat {
			R.sounds.item_sounds[eat_sound] = load_sound(eat_sound)
		}
		pickup_sound := strings.clone(item["sound_pickup"].(json.String))
		_, has_pickup := R.sounds.item_sounds[pickup_sound]
		if !has_pickup {
			R.sounds.item_sounds[pickup_sound] = load_sound(pickup_sound)
		}

		box_size := prase_vec3_from_string(item["box"].(json.String))
		box := Bounding_Box {
			half_size = box_size / 2,
		}

		trf: ve.Transform
		origin_offset := prase_vec3_from_string(item["origin_offset"].(json.String))
		scale := prase_vec3_from_string(item["scale"].(json.String))
		rotation := prase_vec3_from_string(item["rotation"].(json.String))
		rotation = linalg.radians(rotation)

		trf.position = origin_offset
		trf.scale = scale
		ve.trf_rotate(&trf, {1, 0, 0}, rotation.x)
		ve.trf_rotate(&trf, {0, 1, 0}, rotation.y)
		ve.trf_rotate(&trf, {0, 0, 1}, rotation.z)

		R.s.items[name] = Item_Info {
			name          = name,
			saturation    = saturation,
			model_path    = model_path,
			sound_drop    = drop_sound,
			sound_pickup  = pickup_sound,
			sound_eat     = eat_sound,
			box           = box,
			scale         = scale,
			rotation      = rotation,
			origin_offset = origin_offset,
			trf           = ve.trf_get_matrix(trf),
		}
	}
}

Combination_To_Info :: struct {
	item:    string,
	percent: f32,
}

Combination_Info :: struct {
	from:        [dynamic]string,
	timer_value: int,
	to:          [dynamic]Combination_To_Info,
}

load_combinations :: proc(array: json.Array) {
	for combination_json in array {
		com := combination_json.(json.Object)
		from_json := com["from"].(json.Array)
		to_json := com["to"].(json.Array)
		timer_value := cast(int)com["timer_value"].(json.Float)

		from: [dynamic]string
		for item_json in from_json {
			append(&from, strings.clone(item_json.(json.String)))
		}

		to: [dynamic]Combination_To_Info
		for com_to_json in to_json {
			com_to := com_to_json.(json.Object)
			append(
				&to,
				Combination_To_Info {
					item = strings.clone(com_to["object"].(json.String)),
					percent = cast(f32)com_to["percent"].(json.Float),
				},
			)
		}

		append(&R.s.combinations, Combination_Info{from = from, to = to, timer_value = timer_value})
	}
}

Pipe_Info :: struct {
	items: [dynamic]Pipe_Item_Info,
}

Pipe_Item_Info :: struct {
	name:    string,
	percent: f32,
}

load_pipe :: proc(j: json.Object) {
	items_json := j["objects"].(json.Array)
	pipe_info := Pipe_Info{}

	for item_json in items_json {
		item := item_json.(json.Object)
		name := strings.clone(item["name"].(json.String))
		percent := cast(f32)item["percent"].(json.Float)
		append(&pipe_info.items, Pipe_Item_Info{name = name, percent = percent})
	}
	R.s.pipe = pipe_info
	log.info(R.s.pipe)
}

load_models :: proc() {
	R.primitives.square = ve.create_primitive_square()

	R.models.ground = create_model_from_mesh(
		ve.create_primitive_cube({GROUND_WIDTH / 2, GROUND_HEIGHT / 2, GROUND_WIDTH / 2}),
	)
	model_add_single_material(&R.models.ground, create_light_material(color = {0.4, 0.2, 0}))

	microwave_texture := load_texture("assets/models/microwave/microwavetexture.png")
	microwave_door_texture := load_texture("assets/models/microwave/door_UV.png")
	microwave_button_texture := load_texture("assets/models/microwave/buttons_UV.png")
	R.models.microwave = load_model("assets/models/microwave/microwave.obj")
	R.models.microwave_door = load_model("assets/models/microwave/door.obj")
	R.models.microwave_button = load_model("assets/models/microwave/button.obj")
	R.models.microwave_open_button = load_model("assets/models/microwave/open_button.obj")
	R.models.microwave_thingamagic = load_model("assets/models/microwave/thingamagic.obj")
	model_add_single_material(&R.models.microwave, create_light_material(microwave_texture))
	model_add_single_material(&R.models.microwave_door, create_light_material(color = {0.3, 0.3, 0.3}))
	model_add_single_material(&R.models.microwave_button, create_light_material(color = {0.8, 0.2, 0.2}))
	model_add_single_material(&R.models.microwave_open_button, create_light_material(color = {0.2, 0.3, 0.2}))
	model_add_single_material(&R.models.microwave_thingamagic, create_light_material(color = {0.2, 0.3, 0.2}))
	// model_add_single_material(&r.models.microwave_door, create_light_material(microwave_door_texture))
	// model_add_single_material(&r.models.microwave_button, create_light_material(microwave_button_texture))
	// model_add_single_material(&r.models.microwave_open_button, create_light_material(microwave_button_texture))
	// model_add_single_material(&r.models.microwave_thingamagic, create_light_material(microwave_button_texture))

	R.models.hp = load_item_model("assets/models/hp")
	R.models.pipe = load_item_model("assets/models/pipe")
	R.models.rope = load_item_model("assets/models/rope")

	//Nightstand, Couch, LoveChan
	texture := ve.load_texture("assets/models/Couch/texture.png", sampler_info = NEAREST_FILTER_SAMPLER)
	R.models.enemy = load_model("assets/models/Couch/model.obj")
	model_add_single_material(&R.models.enemy, create_light_material(texture))
}

destroy_models :: proc() {
	ve.destroy_mesh(&R.primitives.square)

	destroy_model(&R.models.pipe)
	destroy_model(&R.models.rope)
	destroy_model(&R.models.enemy)
	destroy_model(&R.models.ground)
}
