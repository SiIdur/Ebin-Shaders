#version 410 compatibility
#define gbuffers_shadow
#define vsh
#define ShaderStage -2
#include "/lib/Syntax.glsl"


attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec4 at_tangent;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;

uniform float sunAngle;
uniform float frameTimeCounter;

varying vec4 color;
varying vec2 texcoord;
varying vec2 vertLightmap;

#include "/lib/Settings.glsl"
#include "/lib/Utility.glsl"
#include "/lib/Uniform/Shadow_View_Matrix.vsh"

vec2 GetDefaultLightmap() {
	vec2 lightmapCoord = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.st;
	
	return clamp01((lightmapCoord * pow2(1.031)) - 0.032).rg;
}

vec3 GetWorldSpacePositionShadow() {
	return transMAD(shadowModelViewInverse, transMAD(gl_ModelViewMatrix, gl_Vertex.xyz));
}

#include "/lib/Vertex/Waving.vsh"
#include "/lib/Vertex/Vertex_Displacements.vsh"

#include "/lib/Misc/Bias_Functions.glsl"

vec3 vertNormal = normalize(mat3(shadowViewMatrix) * gl_Normal); //doesn't seem like we need to pass this to fragment

vec4 ProjectShadowMap(vec4 position) {
	position = vec4(projMAD(shadowProjection, transMAD(shadowViewMatrix, position.xyz)), position.z * shadowProjection[2].w + shadowProjection[3].w);
	
	float biasCoeff = GetShadowBias(position.xy);
	
	position.xy /= biasCoeff;
	
	float acne  = 25.0 * pow(clamp01(1.0 - vertNormal.z), 4.0) * float(mc_Entity.x > 0.0);
	      acne += 0.3 + pow2(biasCoeff) * 6.0;
	
	position.z += acne / shadowMapResolution;
	
	position.z /= 4.0; // Shrink the domain of the z-buffer. This counteracts the noticable issue where far terrain would not have shadows cast, especially when the sun was near the horizon
	
	return position;
}


void main() {
#ifndef WATER_SHADOW
	if (abs(mc_Entity.x - 8.5) < 0.6) { gl_Position = vec4(-1.0); return; }
#endif
	
#ifdef HIDE_ENTITIES
	if (mc_Entity.x < 0.5) { gl_Position = vec4(-1.0); return; }
#endif
	
#ifdef TIME_OVERRIDE
	CalculateShadowView();
#endif
	
	color        = gl_Color;
	texcoord     = gl_MultiTexCoord0.st;
	vertLightmap = GetDefaultLightmap();
	
	vec3 position  = GetWorldSpacePositionShadow();
	     position += CalculateVertexDisplacements(position);
	
	gl_Position = ProjectShadowMap(position.xyzz);
	
	
	color.rgb *= clamp01(vertNormal.z);
	
	if (   mc_Entity.x == 0 // If the vertex is an entity
		&& abs(position.x) < 1.2
		&& position.y > -0.1 &&  position.y < 2.2 // Check if the vertex is A bounding box around the player, so that at least non-near entities still cast shadows
		&& abs(position.z) < 1.2) {
	#ifndef PLAYER_SHADOW
		color.a = 0.0;
	#elif !defined PLAYER_GI_BOUNCE
		color.rgb = vec3(0.0);
	#endif
	}
}
