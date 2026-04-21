#version 450

#extension GL_EXT_debug_printf : enable

#include "shaders/gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

// #define MAT_SIZE 2
// const int thresholdMap[MAT_SIZE * MAT_SIZE] = int[](
//     0, 2,
//     3, 1
// );

#define MAT_SIZE 4
const int thresholdMap[MAT_SIZE * MAT_SIZE] = int[](
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5
);

// #define MAT_SIZE 64
// const int thresholdMap[MAT_SIZE * MAT_SIZE] = int[](
//      0, 32,  8, 40,  2, 34, 10, 42,
//     48, 16, 56, 24, 50, 18, 58, 26,
//     12, 44,  4, 36, 14, 46,  6, 38,
//     60, 28, 52, 20, 62, 30, 54, 22,
//      3, 35, 11, 43,  1, 33,  9, 41,
//     51, 19, 59, 27, 49, 17, 57, 25,
//     15, 47,  7, 39, 13, 45,  5, 37,
//     63, 31, 55, 23, 61, 29, 53, 21
// );

#define getTexture() gTextures2D[getPostprocessingUBO(H0()).texture]

#define COLOR_COUNT 48

float getThreshold(ivec2 pixelPos) {
	int x = pixelPos.x % MAT_SIZE;
	int y = pixelPos.y % MAT_SIZE;
	int index = y * MAT_SIZE + x;
	return float(thresholdMap[index]) / (MAT_SIZE * MAT_SIZE);
}

void main() {
	// vec3 color = texture(getTexture(), fragTexCoord).rgb;

	// vec3 color = texture(gTextures2D[4], fragTexCoord).rgb;
	// debugPrintfEXT("texture: %f", getPostprocessingUBO(H0()).brightness_texture);

	vec3 hdrColor = texture(gTextures2D[getPostprocessingUBO(H0()).texture], fragTexCoord).rgb;
	vec3 bloomColor = texture(gTextures2D[getPostprocessingUBO(H0()).brightness_texture], fragTexCoord).rgb;
	hdrColor += bloomColor;
	//
	// // exposure tone mapping
	vec3 color = vec3(1.0) - exp(-hdrColor * getPostprocessingUBO(H0()).exposure);
	
	// ivec2 pixelPos = ivec2(gl_FragCoord.xy);
	ivec2 pixelPos = ivec2(textureSize(getTexture(), 0) * fragTexCoord);

	float threshold = getThreshold(pixelPos);
	
	vec3 quantized;
	for (int i = 0; i < 3; i++) {
		float newValue = color[i] + (threshold - 0.5) / float(COLOR_COUNT - 1);
		quantized[i] = floor(newValue * float(COLOR_COUNT)) / float(COLOR_COUNT - 1);
	}
	
	outColor = vec4(quantized, 1.0);
}
