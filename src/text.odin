package ld

import sm "core:container/small_array"
import "core:math/linalg/glsl"
import "lib:ve"

@(buffer)
Text_UBO :: struct {
	glyph: ve.Texture,
	color: vec3,
}

Text :: struct {
	font:   ^ve.Font,
	pos:    vec2,
	size:   f32,
	text:   string,
	mesh:   ve.Mesh,
	ubo:    ve.Uniform_Buffer,
	width:  f32,
	height: f32,
}

create_text :: proc(
	font: ^ve.Font,
	text: string,
	position: vec2,
	color: vec3,
	size: f32,
	loc := #caller_location,
) -> Text {
	ubo := create_ubo_text()
	ubo_text_set_glyph(ubo, font.glyph_map)
	ubo_text_set_color(ubo, color)

	vertices, width, height := ve.create_text_mesh(font, text, size, context.temp_allocator, loc)
	vertices_size := cast(ve.Device_Size)(size_of(ve.FontVertex) * len(vertices))
	vbo := ve.create_buffer({.Vertex}, vertices_size, raw_data(vertices), loc)

	mesh := ve.Mesh {
		vbo          = vbo,
		vertex_count = len(vertices),
	}

	return Text {
		font = font,
		width = width,
		height = height,
		pos = position,
		size = size,
		ubo = ubo,
		text = text,
		mesh = mesh,
	}
}

text_set_position :: proc(text: ^Text, pos: vec2) {
	text.pos = pos
}

text_set_color :: proc(text: ^Text, color: vec3, loc := #caller_location) {
	ubo_text_set_color(text.ubo, color, loc)
}

text_set_string :: proc(text: ^Text, text_str: string, loc := #caller_location) {
	text.text = text_str
	ve.destroy_mesh(&text.mesh, loc)

	vertices, width, height := ve.create_text_mesh(text.font, text_str, text.size, context.temp_allocator, loc)
	vertices_size := cast(ve.Device_Size)(size_of(ve.FontVertex) * len(vertices))
	vbo := ve.create_buffer({.Vertex}, vertices_size, raw_data(vertices), loc)

	mesh := ve.Mesh {
		vbo          = vbo,
		vertex_count = len(vertices),
	}
	text.mesh = mesh
	text.width = width
	text.height = height
}

draw_text :: proc(text: ^Text, pipeline: ve.Graphics_Pipeline) {
	ve.draw_mesh(text.mesh, pipeline, glsl.mat4Translate(vec3{text.pos.x, text.pos.y, 1}), ve.Handles{h0 = text.ubo})
}

draw_uitext :: proc(text: ^Text) {
	uirenderer_draw_mesh(
		&G.r,
		text.mesh,
		R.pipelines.text,
		glsl.mat4Translate(vec3{text.pos.x, text.pos.y, 1}),
		ve.Handles{h0 = text.ubo},
	)
	// ve.draw_mesh(text.mesh, pipeline, glsl.mat4Translate(vec3{text.pos.x, text.pos.y, 1}), ve.Handles{h0 = text.ubo})
}

text_shader_attribute :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 0,
			format = .RGB_f32,
			offset = cast(u32)offset_of(ve.FontVertex, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(ve.FontVertex, tex_coords),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 0,
		stride = size_of(ve.FontVertex),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}
