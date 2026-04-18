package ld

import "core:log"
import "lib:ve"

@(buffer)
Base_Ubo :: struct {
	color:   vec3,
	texture: ve.Texture,
}

create_base_material :: proc(texture: ve.Texture = ve.INVALID_TEXTURE_HANDLE, color: vec3 = {1, 1, 1}) -> Material {
	ubo := create_ubo_base()
	if texture != ve.INVALID_TEXTURE_HANDLE {
		ubo_base_set_texture(ubo, texture)
	}
	ubo_base_set_color(ubo, color)
	return Material{ubo = ubo, pipeline = R.pipelines.base}
}

create_light_source_material :: proc(color: vec3 = {1, 1, 1}) -> Material {
	ubo := create_ubo_base()
	ubo_base_set_color(ubo, color)
	return Material{ubo = ubo, pipeline = R.pipelines.light_source}
}
