package ld

import sm "core:container/small_array"
import "lib:ve"

load_pipelines :: proc() {
	R.pipelines.base = create_base_pipeline()
	R.pipelines.depth_only = create_depth_only_pipeline()
	R.pipelines.light = create_light_pipeline()
	R.pipelines.postprocessing = create_postprocessing_pipeline()
	R.pipelines.primitive = create_primitive_pipeline()
	R.pipelines.text = create_text_pipeline()
	R.pipelines.gaussian_hor = create_gaussian_blur_pipeline(true)
	R.pipelines.gaussian_ver = create_gaussian_blur_pipeline(false)
	R.pipelines.light_source = create_light_source_pipeline()
}

create_base_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}

	when !ODIN_DEBUG {
		vert := #load("../shaders/base.vert.spv")
		frag := #load("../shaders/base.frag.spv")
	} else {
		vert := "shaders/base.vert"
		frag := "shaders/base.frag"
	}

	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = vert},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = frag},
	)

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages
	// create_info.blending_info.attachment_infos = _get_blending_infos()

	return ve.create_graphics_pipeline(create_info)
}

create_text_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, text_shader_attribute())


	stages := ve.Stage_Infos{}

	when !ODIN_DEBUG {
		vert := #load("../shaders/text.vert.spv")
		frag := #load("../shaders/text.frag.spv")
	} else {
		vert := "shaders/text.vert"
		frag := "shaders/text.frag"
	}

	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = vert},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = frag},
	)

	create_info := ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		blending_info = {attachment_infos = _get_blending_infos()},
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {}, front_face = .Clockwise},
		depth = {
			enable = true,
			write_enable = true,
			compare_op = .Less,
			bounds_test_enable = false,
			min_bounds = 0,
			max_bounds = 0,
		},
		stencil = {enable = false},
	}

	return ve.create_graphics_pipeline(create_info)
}

create_light_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = "shaders/light.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = "shaders/light.frag"},
	)

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_depth_only_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(&stages, ve.Pipeline_Stage_Info{stage = .Vertex, source = "shaders/light.vert"})

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.depth.bias = {
		enable          = true,
		clamp           = 1.25,
		constant_factor = 0,
		slope_factor    = 4.75,
	}

	return ve.create_graphics_pipeline(create_info)
}

@(private = "file")
_get_base_create_pipeline_info :: proc() -> ve.Create_Pipeline_Info {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())

	return ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {.Back}, front_face = .Counter_Clockwise},
		depth = {
			enable = true,
			write_enable = true,
			compare_op = .Less,
			bounds_test_enable = false,
			min_bounds = 0,
			max_bounds = 0,
		},
	}
}

@(private = "file")
_get_blending_infos :: proc() -> ve.Blending_Infos {
	bleding := ve.Blending_Infos{}
	sm.append(
		&bleding,
		ve.Blending_Info {
			src_color_blend_factor = .Src_Alpha,
			dst_color_blend_factor = .One_Minus_Src_Alpha,
			color_blend_op = .Add,
			src_alpha_blend_factor = .One,
			dst_alpha_blend_factor = .Zero,
			alpha_blend_op = .Add,
			color_write_mask = {.R, .G, .B, .A},
		},
	)
	return bleding
}

create_postprocessing_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = "shaders/postprocessing.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = "shaders/postprocessing.frag"},
	)

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.depth.enable = false

	return ve.create_graphics_pipeline(create_info)
}

create_primitive_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = "shaders/primitive.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = "shaders/primitive.frag"},
	)

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_gaussian_blur_pipeline :: proc(horizontal: b32) -> ve.Graphics_Pipeline {
	consts := ve.Shader_Constants{}
	sm.append(&consts, ve.Shader_Constant{id = 0, value = {bool = horizontal}})

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = "shaders/gaussian_blur.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = "shaders/gaussian_blur.frag", consts = consts},
	)

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_light_source_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, source = "shaders/light_source.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, source = "shaders/light_source.frag"},
	)

	create_info := _get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}
