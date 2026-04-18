#version 450

#include "./shaders/gen_types.h"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;

void main() {
	gl_Position = getCamera().projection * getCamera().view * getModel() * vec4(inPosition, 1.0);
}
