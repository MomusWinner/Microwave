package ld

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/slashpath"
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

	if !os.is_dir(root_dir) {
		log.panicf("Couldn't load model. Path \"%s\" is not exist", path, location = loc)
	}

	model_dir := fmt.tprintf("%s/model.obj", root_dir)

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
