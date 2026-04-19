package ld

import "core:log"
import "lib:ve"

DEPTH_SIZE :: 2048
DOWNSCALE :: 2

@(buffer)
Postprocessing_UBO :: struct {
	texture:            ve.Texture,
	exposure:           f32,
	brightness_texture: ve.Texture,
}

Directional_Light :: struct {
	camera: ve.Buffer,
	color:  vec3,
	shadow: ve.Texture,
}

Spot_Light :: struct {
	color:    vec3,
	position: vec3,
}

SPOT_LIGHT_COUNT :: 16

@(buffer)
Light_Info_UBO :: struct {
	dir_light:   Directional_Light,
	spot_lights: [SPOT_LIGHT_COUNT]Spot_Light,
}

@(buffer)
Light_UBO :: struct {
	diffuse_color:   vec3,
	diffuse_texture: ve.Texture,
	ambient:         vec3,
	specular:        vec3,
}

Renderer :: struct {
	lsource:            Light_Source,
	ui_camera:          ve.Camera,
	//
	shadow_rt:          ve.Render_Target,
	screen_rt:          ve.Render_Target,
	//
	shadow_texture:     ve.Texture,
	screen_texture:     ve.Texture,
	brightness_texture: ve.Texture,
	//
	draw_calls:         [dynamic]Draw_Call,
	ui_draw_calls:      [dynamic]Draw_Call,
	user_camera_buffer: ve.Buffer,
	postproc_ubo:       ve.Uniform_Buffer,
}

Light_Source :: struct {
	camera: ve.Camera,
	ubo:    ve.Uniform_Buffer,
}

Draw_Call :: struct {
	mesh:     ve.Mesh,
	pipeline: ve.Graphics_Pipeline,
	trf:      mat4,
	handles:  ve.Handles,
}

create_renderer :: proc() -> Renderer {
	rt: ve.Render_Target
	ve.init_render_target(&rt, DEPTH_SIZE, DEPTH_SIZE, ._1)
	shadow_map_texture := ve.render_target_add_readable_depth_attachment(
		&rt,
		sampler_info = ve.Sampler_Info {
			mag_filter = .Linear,
			min_filter = .Linear,
			address_mode_u = .Clamp_To_Border,
			address_mode_v = .Clamp_To_Border,
			border_color = .Opaque_White,
		},
	)

	screen_rt: ve.Render_Target
	w, h := get_downscale_size()
	ve.init_render_target(&screen_rt, w, h, ._1)
	screen_texture := ve.render_target_add_color_attachment(
		&screen_rt,
		format = .RGBA_norm_u16,
		sampler_info = NEAREST_FILTER_SAMPLER,
		clear_value = BACKGROUND,
	)
	screen_brightness_texture := ve.render_target_add_color_attachment(
		&screen_rt,
		format = .RGBA_norm_u16,
		sampler_info = NEAREST_FILTER_SAMPLER,
	)
	log.info(screen_brightness_texture)
	ve.render_target_add_depth_attachment(&screen_rt)

	postproc_ubo := create_ubo_postprocessing()
	ubo_postprocessing_set_texture(postproc_ubo, screen_texture)
	ubo_postprocessing_set_brightness_texture(postproc_ubo, screen_brightness_texture)
	ubo_postprocessing_set_exposure(postproc_ubo, 0.5)

	uicamera: ve.Camera
	ve.init_camera(&uicamera, .Orthographic)
	uicamera.position = {0, 0, 1}
	uicamera.near = 0
	uicamera.far = 10
	uicamera.fov = 10

	return Renderer {
		ui_camera = uicamera,
		shadow_rt = rt,
		shadow_texture = shadow_map_texture,
		lsource = create_light_source(shadow_map_texture),
		screen_rt = screen_rt,
		screen_texture = screen_texture,
		brightness_texture = screen_brightness_texture,
		postproc_ubo = postproc_ubo,
		draw_calls = make([dynamic]Draw_Call, 0, 1000),
		ui_draw_calls = make([dynamic]Draw_Call, 0, 1000),
	}
}

destroy_render :: proc(r: ^Renderer) {
	ve.destroy_render_target(&r.shadow_rt)
	ve.destroy_render_target(&r.screen_rt)
	delete(r.draw_calls)
	delete(r.ui_draw_calls)
}

begin_renderer :: proc(r: ^Renderer, user_camera: ve.Buffer) {
	r.user_camera_buffer = user_camera

	if ve.screen_resized() {
		w, h := get_downscale_size()
		ve.render_target_resize(&r.screen_rt, w, h)
	}
}

end_renderer :: proc(r: ^Renderer) {
	ve.begin_render_target(&r.shadow_rt)
	{
		ve.set_camera(r.lsource.camera)
		for c, i in r.draw_calls {
			ve.draw_mesh(c.mesh, R.pipelines.depth_only, c.trf)
		}
	}
	ve.end_render_target(&r.shadow_rt)

	ve.begin_render_target(&r.screen_rt)
	{
		ve.set_camera_buffer(r.user_camera_buffer)
		for c, i in r.draw_calls {
			h := c.handles
			h.h1 = r.lsource.ubo
			ve.draw_mesh(c.mesh, c.pipeline, c.trf, h)
		}
	}
	ve.end_render_target(&r.screen_rt)

	for i in 0 ..< 3 {
		// Horizontal gaussian blur
		ve.begin_render_target(&r.screen_rt, {1})
		ve.draw_mesh(R.primitives.square, R.pipelines.gaussian_hor, handles = {h0 = r.brightness_texture})
		ve.end_render_target(&r.screen_rt)

		// Vertical gaussian blur
		ve.begin_render_target(&r.screen_rt, {1})
		ve.draw_mesh(R.primitives.square, R.pipelines.gaussian_ver, handles = {h0 = r.brightness_texture})
		ve.end_render_target(&r.screen_rt)
	}

	ve.begin_draw()
	{
		ve.set_camera(r.ui_camera)
		ve.draw_mesh(R.primitives.square, R.pipelines.postprocessing, handles = ve.Handles{h0 = r.postproc_ubo})

		for c in r.ui_draw_calls {
			ve.draw_mesh(c.mesh, c.pipeline, c.trf, c.handles)
		}
	}
	ve.end_draw()

	clear(&r.draw_calls)
	clear(&r.ui_draw_calls)
}

renderer_draw_model :: proc(r: ^Renderer, m: Model, trf: mat4 = 1, handles: ve.Handles = {}) {
	assert(handles.h0 == nil, "H0 resurved for Material UBO")
	handles := handles

	if len(m.materials) == 1 {
		mtrl := m.materials[0]
		handles.h0 = mtrl.ubo
		for mesh in m.meshes {
			append(&r.draw_calls, Draw_Call{mesh = mesh, pipeline = mtrl.pipeline, trf = trf, handles = handles})
		}
	} else {
		for mesh, i in m.meshes {
			mtrl := m.materials[m.mesh_to_material[i]]
			handles.h0 = mtrl.ubo
			append(&r.draw_calls, Draw_Call{mesh = mesh, pipeline = mtrl.pipeline, trf = trf, handles = handles})
		}
	}
}

// model_draw :: proc(m: Model, trf: Maybe(mat4) = nil, handles: ve.Handles = {}, instance_count: u32 = 1) {
// 	assert(handles.h0 == nil, "H0 resurved for Material UBO")
// 	handles := handles
//
// 	if len(m.materials) == 1 {
// 		mtrl := m.materials[0]
// 		handles.h0 = mtrl.ubo
// 		for mesh in m.meshes {
// 			ve.draw_mesh(mesh, mtrl.pipeline, trf, handles)
// 		}
// 	} else {
// 		for mesh, i in m.meshes {
// 			mtrl := m.materials[m.mesh_to_material[i]]
// 			handles.h0 = mtrl.ubo
// 			ve.draw_mesh(mesh, mtrl.pipeline, trf, handles)
// 		}
// 	}
// }

renderer_draw_mesh :: proc(
	r: ^Renderer,
	mesh: ve.Mesh,
	pipeline: ve.Graphics_Pipeline,
	trf: mat4 = 1,
	handles: ve.Handles = {},
) {
	append(&r.draw_calls, Draw_Call{mesh = mesh, pipeline = pipeline, trf = trf, handles = handles})
}

uirenderer_draw_mesh :: proc(
	r: ^Renderer,
	mesh: ve.Mesh,
	pipeline: ve.Graphics_Pipeline,
	trf: mat4 = 1,
	handles: ve.Handles = {},
) {
	append(&r.ui_draw_calls, Draw_Call{mesh = mesh, pipeline = pipeline, trf = trf, handles = handles})
}

renderer_draw_mesh_from_mtrl :: proc(
	r: ^Renderer,
	mesh: ve.Mesh,
	mtrl: Material,
	trf: mat4 = 1,
	handles: ve.Handles = {},
) {

	assert(handles.h0 == nil, "H0 resurved for Material UBO")
	handles := handles
	handles.h0 = mtrl.ubo
	append(&r.draw_calls, Draw_Call{mesh = mesh, pipeline = mtrl.pipeline, trf = trf, handles = handles})
}

create_light_source :: proc(shadow_map: ve.Texture, color: vec3 = {1, 1, 1}) -> Light_Source {
	camera: ve.Camera
	ve.init_camera(&camera, .Orthographic)
	camera.position = {0.0001, 7, 0.0}
	camera.near = 0.1
	camera.far = 1000.5
	camera.fov = 10

	ubo := create_ubo_light_info()
	ubo_light_info_set_dir_light(ubo, Directional_Light{shadow = shadow_map, camera = camera.buffer, color = color})

	return Light_Source{camera = camera, ubo = ubo}
}

get_downscale_size :: proc() -> (int, int) {
	return cast(int)(cast(f32)ve.screen_get_width() / DOWNSCALE), cast(int)(cast(f32)ve.screen_get_height() / DOWNSCALE)
}

create_light_material :: proc(
	texture: ve.Texture = ve.INVALID_TEXTURE_HANDLE,
	color: vec3 = {1, 0.5, 0.5},
) -> Material {
	ubo := create_ubo_light()
	if texture != ve.INVALID_TEXTURE_HANDLE {
		ubo_light_set_diffuse_texture(ubo, texture)
	}
	ubo_light_set_diffuse_texture(ubo, texture)
	ubo_light_set_ambient(ubo, 0.1)
	ubo_light_set_diffuse_color(ubo, color)

	return Material{ubo = ubo, pipeline = R.pipelines.light}
}

// CUBE_COUNT :: 16
// LIGHT_COUNT :: 4
//
// Light :: struct {
// 	color:    vec3,
// 	position: vec3,
// }
//
// @(buffer)
// Multilight_UBO :: struct {
// 	lights: [LIGHT_COUNT]Light,
// 	color:  vec3,
// }
//
// @(buffer)
// HDR_UBO :: struct {
// 	exposure: f32,
// 	scene:    ve.Texture,
// 	bloom:    ve.Texture,
// }
//
// @(buffer)
// Gaussian_Blur_UBO :: struct {
// 	blur: ve.Texture,
// }
//
// @(buffer)
// Light_Source_UBO :: struct {
// 	color: vec3,
// }
//
// Light_Source :: struct {
// 	trf:     ve.Transform,
// 	box_ubo: ve.Uniform_Buffer,
// }
//
// Bloom_Scene_Data :: struct {
// 	camera:                ve.Camera,
// 	square:                ve.Mesh,
// 	cube:                  ve.Mesh,
// 	cube_trfs:             [CUBE_COUNT]ve.Transform,
// 	light_sources:         [LIGHT_COUNT]Light_Source,
// 	rt:                    ve.Render_Target,
// 	// Buffers
// 	light_box_ubo:         ve.Uniform_Buffer,
// 	multilight_ubo:        ve.Uniform_Buffer,
// 	hdr_ubo:               ve.Uniform_Buffer,
// 	blur_ubo:              ve.Uniform_Buffer,
// 	// Pipelines
// 	blur_hor_pipeline:     ve.Graphics_Pipeline,
// 	blur_ver_pipeline:     ve.Graphics_Pipeline,
// 	multilight_pipeline:   ve.Graphics_Pipeline,
// 	hdr_pipeline:          ve.Graphics_Pipeline,
// 	light_source_pipeline: ve.Graphics_Pipeline,
// }
//
// create_bloom_scene :: proc() -> Scene {
// 	return Scene {
// 		init = bloom_scene_init,
// 		update = bloom_scene_update,
// 		draw = bloom_scene_draw,
// 		destroy = bloom_scene_destroy,
// 	}
// }
//
// bloom_scene_init :: proc(s: ^Scene) {
// 	d := new(Bloom_Scene_Data)
//
// 	ve.cursor_set_mode(.Disabled)
//
// 	ve.init_camera(&d.camera)
// 	d.camera.position = {0, 0, 2}
//
// 	ve.init_render_target(&d.rt, ve.screen_get_width(), ve.screen_get_height(), ._4)
// 	hdr_color_attachmetn := ve.render_target_add_color_attachment(&d.rt, format = .RGBA_norm_u16)
// 	bright_color_attachmetn := ve.render_target_add_color_attachment(&d.rt, format = .RGBA_norm_u16)
// 	ve.render_target_add_depth_attachment(&d.rt)
//
// 	d.square = ve.create_primitive_square()
// 	d.cube = ve.create_primitive_cube()
//
//
// 	d.hdr_pipeline = create_hdr_pipeline()
// 	d.hdr_ubo = create_ubo_hdr()
// 	ubo_hdr_set_scene(d.hdr_ubo, hdr_color_attachmetn)
// 	ubo_hdr_set_bloom(d.hdr_ubo, bright_color_attachmetn)
// 	ubo_hdr_set_exposure(d.hdr_ubo, 0.5)
//
// 	d.blur_hor_pipeline = create_gaussian_blur_pipeline(true)
// 	d.blur_ver_pipeline = create_gaussian_blur_pipeline(false)
//
// 	d.blur_ubo = create_ubo_gaussian_blur()
// 	ubo_gaussian_blur_set_blur(d.blur_ubo, bright_color_attachmetn)
//
// 	d.multilight_pipeline = create_multilight_pipeline()
// 	d.multilight_ubo = create_ubo_multilight()
// 	ubo_multilight_set_color(d.multilight_ubo, {0.5, 0.5, 0.5})
//
// 	Z :: -10
// 	lights: [LIGHT_COUNT]Light = {
// 		Light{position = {4.8, 0, Z}, color = ({1, 0, 0} * 5)},
// 		Light{position = {1.6, 0, Z}, color = ({0, 1, 0} * 5)},
// 		Light{position = {-1.6, 0, Z}, color = ({0, 0.2, 1} * 5)},
// 		Light{position = {-4.8, 0, Z}, color = ({1, 1, 0} * 5)},
// 	}
// 	ubo_multilight_set_lights(d.multilight_ubo, lights[:])
//
// 	for i in 0 ..< CUBE_COUNT {
// 		ve.init_trf(&d.cube_trfs[i])
// 		x: f32 = cast(f32)i - CUBE_COUNT / 2
// 		y := rand.float32_range(-1.5, 1.5)
// 		z := rand.float32_range(-1.5, 1.5) + Z
// 		ve.trf_set_position(&d.cube_trfs[i], {x, y, z})
// 		ve.trf_set_scale(&d.cube_trfs[i], rand.float32_range(0.3, 0.5))
// 		axis: vec3 = {rand.float32(), rand.float32(), rand.float32()}
// 		ve.trf_rotate(&d.cube_trfs[i], axis, rand.float32_range(-math.PI, math.PI))
// 	}
//
// 	d.light_source_pipeline = create_light_source_pipeline()
// 	for i in 0 ..< LIGHT_COUNT {
// 		light: Light_Source
// 		ve.init_trf(&light.trf)
// 		ve.trf_set_position(&light.trf, lights[i].position)
// 		ve.trf_set_scale(&light.trf, 0.3)
// 		light.box_ubo = create_ubo_light_source()
// 		ubo_light_source_set_color(light.box_ubo, lights[i].color)
// 		d.light_sources[i] = light
// 	}
//
// 	s.data = d
// }
//
// bloom_scene_update :: proc(s: ^Scene) {
// 	d := cast(^Bloom_Scene_Data)s.data
// 	ve.camera_update_simple_controller(&d.camera)
//
// 	exp := ubo_hdr_get_exposure(d.hdr_ubo)
// 	speed: f32 = 1.0
// 	if (ve.key_is_down(.Up)) {
// 		ubo_hdr_set_exposure(d.hdr_ubo, exp + speed * ve.time_get_delta())
// 	}
// 	if (ve.key_is_down(.Down)) {
// 		ubo_hdr_set_exposure(d.hdr_ubo, exp - speed * ve.time_get_delta())
// 	}
// }
//
// bloom_scene_draw :: proc(s: ^Scene) {
// 	d := cast(^Bloom_Scene_Data)s.data
//
// 	if (ve.screen_resized()) {
// 		ve.render_target_resize(&d.rt, ve.screen_get_width(), ve.screen_get_height())
// 	}
//
// 	ve.begin_pass()
//
// 	ve.set_camera(d.camera)
//
// 	ve.begin_render_target(&d.rt)
// 	for &t in d.cube_trfs {
// 		ve.draw_mesh(d.cube, d.multilight_pipeline, ve.trf_get_matrix(t), {h0 = d.multilight_ubo})
// 	}
// 	for &l in d.light_sources {
// 		ve.draw_mesh(d.cube, d.light_source_pipeline, ve.trf_get_matrix(l.trf), {h0 = l.box_ubo})
// 	}
// 	ve.end_render_target(&d.rt)
//
// 	for i in 0 ..< 3 {
// 		// Horizontal gaussian blur
// 		ve.begin_render_target(&d.rt, {1})
// 		ve.draw_mesh(d.square, d.blur_hor_pipeline, handles = {h0 = d.blur_ubo})
// 		ve.end_render_target(&d.rt)
//
// 		// Vertical gaussian blur
// 		ve.begin_render_target(&d.rt, {1})
// 		ve.draw_mesh(d.square, d.blur_ver_pipeline, handles = {h0 = d.blur_ubo})
// 		ve.end_render_target(&d.rt)
// 	}
//
// 	ve.begin_draw()
// 	{
// 		ve.draw_mesh(d.square, d.hdr_pipeline, handles = {h0 = d.hdr_ubo})
// 	}
// 	ve.end_draw()
//
// 	ve.end_pass()
// }
//
// bloom_scene_destroy :: proc(s: ^Scene) {
// 	d := cast(^Bloom_Scene_Data)s.data
//
// 	ve.destroy_render_target(&d.rt)
// 	ve.destroy_mesh(&d.cube)
// 	ve.destroy_mesh(&d.square)
//
// 	free(d)
// }
