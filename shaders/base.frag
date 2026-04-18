#version 450

#include "./shaders/gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
	if ( !isHandleValid(getBaseUBO(H0()).texture) ) {
		outColor = vec4(texture(gTextures2D[getBaseUBO(H0()).texture], fragTexCoord).rgb,1);
	} else {
		outColor = vec4(getBaseUBO(H0()).color, 1);
	}
	outColor = vec4(getBaseUBO(H0()).color, 1);
}
