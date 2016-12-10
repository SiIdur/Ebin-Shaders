#version 410 compatibility
#define composite0
#define fsh
#define ShaderStage 0
#include "/lib/Syntax.glsl"

/* DRAWBUFFERS:56 */

const bool shadowtex1Mipmap    = true;
const bool shadowcolor0Mipmap  = true;
const bool shadowcolor1Mipmap  = true;

const bool shadowtex1Nearest   = true;
const bool shadowcolor0Nearest = false;
const bool shadowcolor1Nearest = false;

uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D gdepthtex;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;
uniform sampler2D shadowcolor;
uniform sampler2D shadowcolor1;
uniform sampler2D shadowtex1;
uniform sampler2DShadow shadow;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

uniform int isEyeInWater;

varying vec2 texcoord;

#include "/lib/Settings.glsl"
#include "/lib/Utility.glsl"
#include "/lib/Debug.glsl"
#include "/lib/Uniform/Projection_Matrices.fsh"
#include "/lib/Uniform/Shading_Variables.glsl"
#include "/lib/Uniform/Shadow_View_Matrix.fsh"
#include "/lib/Fragment/Masks.fsh"
#include "/lib/Misc/Calculate_Fogfactor.glsl"

float GetDepth(vec2 coord) {
	return textureRaw(gdepthtex, coord).x;
}

float GetDepthLinear(vec2 coord) {	
	return (near * far) / (textureRaw(gdepthtex, coord).x * (near - far) + far);
}

vec3 CalculateViewSpacePosition(vec3 screenPos) {
	screenPos = screenPos * 2.0 - 1.0;
	
	return projMAD(projInverseMatrix, screenPos) / (screenPos.z * projInverseMatrix[2].w + projInverseMatrix[3].w);
}

vec3 ProjectEquirectangularImage(vec2 coord) {
	cvec2 coordToLongLat = vec2(2.0 * PI, PI);
	      coord.y -= 0.5;
	vec2 longLat = coord * coordToLongLat;
	float longitude = longLat.x;
	float latitude = longLat.y - (2.0 * PI);

	float cos_lat = cos(latitude);
	float cos_long = cos(longitude);
	float sin_lat = sin(latitude);
	float sin_long = sin(longitude);

	return normalize(vec3(cos_lat * sin_long, sin_lat, cos_lat * cos_long));
}

vec3 GetNormal(vec2 coord) {
	return DecodeNormal(textureRaw(colortex4, coord).xy);
}


vec2 GetDitherred2DNoise(vec2 coord, float n) { // Returns a random noise pattern ranging {-1.0 to 1.0} that repeats every n pixels
	coord *= vec2(viewWidth, viewHeight);
	coord  = mod(coord, vec2(n));
	coord /= noiseTextureResolution;
	return texture2D(noisetex, coord).xy;
}

#include "/lib/Misc/Bias_Functions.glsl"
#include "/lib/Fragment/Sunlight_Shading.fsh"
#include "/lib/Fragment/Sky.fsh"

#ifndef GI_ENABLED
	#define ComputeGlobalIllumination(a, b, c, d, e, f) vec3(0.0)
#elif GI_MODE == 1
vec3 ComputeGlobalIllumination(vec3 worldSpacePosition, vec3 normal, float skyLightmap, cfloat radius, vec2 noise, Mask mask) {
	float LodCoeff = clamp01(1.0 - length(worldSpacePosition) / shadowDistance);
	
	float depthLOD	= 2.0 * LodCoeff;
	float sampleLOD	= 5.0 * LodCoeff;
	
	vec3 shadowViewPosition = transMAD(shadowViewMatrix, worldSpacePosition + gbufferModelViewInverse[3].xyz);
	
	vec2 basePos = shadowViewPosition.xy * diagonal2(shadowProjection) + shadowProjection[3].xy;
	
	normal = mat3(shadowViewMatrix) * mat3(gbufferModelViewInverse) * -normal;
	
	vec3 projMult = mat3(shadowProjectionInverse) * -vec3(1.0, 1.0, 8.0);
	vec3 projDisp = shadowViewPosition.xyz - shadowProjectionInverse[3].xyz - vec3(0.0, 0.0, 0.5 * projMult.z);
	
	cvec3 sampleMax = vec3(0.0, 0.0, radius * radius);
	
	cfloat brightness = radius * radius;
	cfloat scale      = radius / 256.0;
	
	noise *= scale;
	
	vec3 GI = vec3(0.0);

	cint loopCount = int((sqrt(GI_SAMPLE_COUNT) - 1.0) * 0.5);
	
	for (int i = -loopCount; i < loopCount; i++) {
		for(int j = -loopCount; j < loopCount; j++) {
			vec2 offset = vec2(i, j) * scale * (1.0 / loopCount) + noise;
		
			vec3 samplePos = vec3(basePos.xy + offset, 0.0);
			
			vec2 mapPos = BiasShadowMap(samplePos.xy) * 0.5 + 0.5;
			
			samplePos.z = texture2DLod(shadowtex1, mapPos, depthLOD).x;
			
			vec3 sampleDiff = samplePos * projMult + projDisp.xyz;
			
			float sampleLengthSqrd = length2(sampleDiff);
			
			vec3 shadowNormal;
				shadowNormal.xy = texture2DLod(shadowcolor1, mapPos, sampleLOD).xy * 2.0 - 1.0;
				shadowNormal.z  = sqrt(1.0 - length2(shadowNormal.xy));
			
			vec3 lightCoeffs   = vec3(finversesqrt(sampleLengthSqrd) * sampleDiff * mat2x3(normal, shadowNormal), sampleLengthSqrd);
				lightCoeffs   = max(lightCoeffs, sampleMax);
				lightCoeffs.x = mix(lightCoeffs.x, 1.0, GI_TRANSLUCENCE);
				lightCoeffs.y = fsqrt(lightCoeffs.y);
			
			vec3 flux = sRGB2L(texture2DLod(shadowcolor, mapPos, sampleLOD).rgb) * sunIlluminance * sunlightColor;
			
			GI += flux * lightCoeffs.x * lightCoeffs.y / lightCoeffs.z;
		}
	}
	
	GI /= GI_SAMPLE_COUNT;
	
	return GI * brightness;
}
#endif

vec3 CalculateSkyDome(vec2 coord, float depth) {
	vec3 equirectangle = ProjectEquirectangularImage(coord);
	return calculateSkyIBL(equirectangle, vec3(0.0), 1.0, 0.0, false, 1.0);
}

void main() {
	float depth0 = GetDepth(texcoord);
	gl_FragData[1] = vec4(CalculateSkyDome(texcoord, depth0), 1.0);
	
	if (depth0 >= 1.0) { return; }

	

	vec2 noise2D = GetDitherred2DNoise(texcoord * COMPOSITE0_SCALE, 4.0) * 2.0 - 1.0;
	
	vec2 texure4 = textureRaw(colortex4, texcoord).rg;
	
	vec4  decode4       = Decode4x8F(texure4.r);
	Mask  mask          = CalculateMasks(decode4.r);
	float smoothness    = decode4.g;
	float torchLightmap = decode4.b;
	float skyLightmap   = decode4.a;
	
	float depth1 = (mask.hand > 0.5 ? depth0 : textureRaw(depthtex1, texcoord).x);
	
	mat2x3 backPos;
	backPos[0] = CalculateViewSpacePosition(vec3(texcoord, depth1));
	backPos[1] = mat3(gbufferModelViewInverse) * backPos[0];
	
	if (depth0 != depth1) {
		vec2 decode0 = Decode16(texture2D(colortex0, texcoord).b);
		
		mask.water = float(decode0.g >= 1.0);
	}
	
	
	if (depth1 >= 1.0 || isEyeInWater != mask.water)
		{ gl_FragData[0] = vec4(vec3(0.0), 1.0); exit(); return; }
	
	
	vec3 normal = DecodeNormalU(texure4.g) * mat3(gbufferModelViewInverse);
	
	vec3 GI = ComputeGlobalIllumination(backPos[1], normal, skyLightmap, GI_RADIUS, noise2D, mask);
	
	
	gl_FragData[0] = vec4(GI, 1.0);
	
	exit();
}
