#version 450

#extension GL_EXT_debug_printf : enable

#include "./shaders/gen_types.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec3 fragPos;
layout(location = 3) in vec4 fragPosLightSpace;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outBrightColor;

#define getLightInfo() getLightInfoUBO(H1())
#define getShadowMap() gTextures2D[getLightInfo().dir_light.shadow]
#define getLightSourceCamera() getCameraByHandle(getLightInfo().dir_light.camera)

#define getLight(i) getLightInfoUBO(H1()).spot_lights[i]

float textureProj(vec4 shadowCoord, vec2 off) {
	float shadow = 0;
	float dist = texture(getShadowMap(), shadowCoord.xy + off).r;

	if (dist  < shadowCoord.z) {
		shadow = 1;
	}

	if (shadowCoord.z > 1.0) {
		shadow = 0;
	}
	
	return shadow;
}

float filterPCF(vec4 sc) {
	ivec2 texDim = textureSize(getShadowMap(), 0);
	float scale = 1;
	float dx = scale * 1.0 / float(texDim.x);
	float dy = scale * 1.0 / float(texDim.y);

	float shadowFactor = 0.0;
	int count = 0;
	int range = 2;
	
	for (int x = -range; x <= range; x++) {
		for (int y = -range; y <= range; y++) {
			shadowFactor += textureProj(sc, vec2(dx*x, dy*y));
			count++;
		}
	}

	return shadowFactor / count;
}

vec3 calculateDirLighting() {
	vec3 normal = normalize(fragNormal);
	vec3 lightColor = getLightInfo().dir_light.color;

  vec3 lightFragDir = normalize(getLightSourceCamera().position - fragPos);
	vec3 lightDir = normalize(- (getLightSourceCamera().target - getLightSourceCamera().position));

	float theta = dot(lightFragDir, lightDir); 
	float epsilon = getLightInfo().dir_light.cut_off - getLightInfo().dir_light.outer_cut_off;
	float intensity = clamp((theta - getLightInfo().dir_light.outer_cut_off) / epsilon, 0.0, 1.0);
	// float intensity = 1;

	// diffuse
	float diff = max(dot(lightDir, normal), 0.0);
	vec3 diffuse = diff * lightColor;

	// specular
	vec3 viewDir = normalize(getCamera().position - fragPos);
	float spec = 0.0;
	vec3 halfwayDir = normalize(lightDir + viewDir);
	spec = pow(max(dot(normal, halfwayDir), 0.0), 64.0);
	vec3 specular = spec * lightColor;

	return (specular + diffuse) * intensity;
}

vec3 calculateSpotLighting() {
	vec3 normal = normalize(fragNormal);
	// lighting
	vec3 lighting = vec3(0.0);

	for (int i = 0; i < 16; i++) {
		// diffuse
		vec3 lightDir = normalize(getLight(i).position - fragPos);
		float diff = max(dot(lightDir, normal), 0.0);
		vec3 diffuse = vec3(getLight(i).color) * diff;
		vec3 result = diffuse;
		// attenuation (use quadratic as we have gamma correction)
		float distance = length(fragPos - getLight(i).position);
		result *= 1.0 / (distance * distance);
		lighting += result;
	}

	return lighting;
}

void main() {
	float shadow = filterPCF(fragPosLightSpace / fragPosLightSpace.w);

	vec3 color;
	if ( !isHandleValid(getLightUBO(H0()).diffuse_texture) ) {
		color = getLightUBO(H0()).diffuse_color;
	}
	else {
		color = getLightUBO(H0()).diffuse_color * texture(gTextures2D[getLightUBO(H0()).diffuse_texture], fragTexCoord).rgb;
	}

	vec3 ambient = getLightUBO(H0()).ambient; //* lightColor;

	vec3 dirLighting = calculateDirLighting();
	vec3 spotLighting = calculateSpotLighting();

	// calculate shadow
	vec3 lighting = (ambient + (1.0 - shadow) * (dirLighting ) + spotLighting) * color;

	outColor = vec4(lighting, 1);

	float brightness = dot(outColor.rgb, vec3(0.2126, 0.7152, 0.0722));
	if(brightness > 1.0)
		outBrightColor = vec4(outColor.rgb, 1.0);
	else
		outBrightColor = vec4(0.0, 0.0, 0.0, 1.0);
}
