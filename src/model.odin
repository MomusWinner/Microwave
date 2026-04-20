package ld

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/slashpath"
import "core:strconv"
import "core:strings"
import "lib:ve"
import "vendor:cgltf"

Material :: struct {
	ubo:      ve.Uniform_Buffer,
	pipeline: ve.Graphics_Pipeline,
}

Model :: struct {
	meshes:           []ve.Mesh,
	materials:        []Material,
	mesh_to_material: []int,
}

Model_Meta_JSON :: struct {
	has_texture: bool,
	color:       string,
}

load_model :: proc(path: string, loc := #caller_location) -> Model {
	root_dir := slashpath.clean(path, context.temp_allocator)

	if !os.is_file(root_dir) {
		log.panicf("Couldn't load model. Path \"%s\" is not exist", path, location = loc)
	}

	model_dir := root_dir

	meshes := ve.load_meshes(model_dir)

	model := Model {
		meshes = meshes,
	}

	return model
}

create_model_from_mesh :: proc(mesh: ve.Mesh) -> Model {
	meshes := make([]ve.Mesh, 1)
	meshes[0] = mesh
	return Model{meshes = meshes}
}

destroy_model :: proc(m: ^Model) {
	delete(m.meshes)
	delete(m.materials)
	delete(m.mesh_to_material)
}

model_add_single_material :: proc(m: ^Model, mtrl: Material) {
	m.materials = make([]Material, 1)
	m.materials[0] = mtrl
}

load_item_model :: proc(path: string) -> Model {
	meta_path := fmt.tprintf("%s/%s", path, "meta.json")
	if !os.is_file(meta_path) {
		log.panicf("Couldn't load model meta.json. Path \"%s\" is not exist", meta_path)
	}

	meta_data, m_ok := ve.read_file(meta_path, context.temp_allocator)
	if !m_ok do log.panic("Couldn't load file by path: %s", path)
	meta_json, err := json.parse(meta_data, allocator = context.temp_allocator)
	if err != .None do log.panicf("Couldn't parse model (%s) meta.json: %v", path, err)
	fields := meta_json.(json.Object)
	model_path := fields["model"]

	model := load_model(fmt.tprintf("%s/%s", path, model_path))

	materials: [dynamic]Material

	for m in fields["materials"].(json.Array) {
		mtrl := m.(json.Object)
		mtrl_name := mtrl["name"].(json.String)
		texture_path := mtrl["texture"].(json.String)
		color := prase_vec3_from_string(mtrl["color"].(json.String))

		texture: ve.Texture = ve.INVALID_TEXTURE_HANDLE

		if texture_path != "" {
			if texture_path[0] == '/' {
				texture = load_texture(texture_path)
			} else {
				texture = ve.load_texture(fmt.tprintf("%s/%s", path, texture_path))
			}
		}

		switch mtrl_name {
		case "light":
			append(&materials, create_light_material(texture, color))
		case:
			log.panic("Unsuported material name:", mtrl_name)
		}
	}

	if len(materials) == 0 {
		log.panic("Add materials to ", path)
	}

	if len(materials) == 1 {
		log.info("Add single material", materials[0])
		model_add_single_material(&model, materials[0])
		return model
	}

	mesh_to_material := make([dynamic]int, len(model.meshes))
	if len(model.meshes) != len(fields["mesh_to_material"].(json.Array)) {
		log.panic("Incorrect mesh count or invalid meta", path)
	}
	for m, i in fields["mesh_to_material"].(json.Array) {
		index := cast(int)m.(json.Float)
		mesh_to_material[i] = cast(int)index
	}

	model.mesh_to_material = mesh_to_material[:]
	return model
}

load_texture :: proc(path: string) -> ve.Texture {
	texture, ok := R.stextures[path]
	if ok do return texture

	t := ve.load_texture(path)
	R.stextures[path] = t
	return t
}
