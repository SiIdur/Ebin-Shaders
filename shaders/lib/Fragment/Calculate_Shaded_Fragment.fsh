struct Shading { // Scalar light levels
	float sunlight;
	float diffuse;
	float skylight;
	float torchlight;
	float ambient;
};

struct Lightmap { // Vector light levels with color
	vec3 sunlight;
	vec3 skylight;
	vec3 torchlight;
	vec3 ambient;
	vec3 GI;
};


#include "/lib/Misc/Bias_Functions.glsl"
#include "/lib/Fragment/Sunlight_Shading.fsh"

float GetHeldLight(vec3 viewSpacePosition, vec3 normal, float handMask) {
	const mat2x3 lightPos = mat2x3(
	     0.16, -0.05, -0.1,
	    -0.16, -0.05, -0.1);
	
	mat2x3 lightRay = mat2x3(
	    viewSpacePosition - lightPos[0],
	    viewSpacePosition - lightPos[1]);
	
	vec2 falloff = vec2(inversesqrt(length2(lightRay[0])), inversesqrt(length2(lightRay[1])));
	
	falloff *= clamp01(vec2(dot(normal, lightPos[0] * falloff[0]), dot(normal, lightPos[1] * falloff[1]))) * 0.35 + 0.65;
	
	vec2 hand  = max0(falloff - 0.0625);
	     hand  = mix(hand, vec2(2.0), handMask * vec2(greaterThan(viewSpacePosition.x * vec2(1.0, -1.0), vec2(0.0))));
	     hand *= vec2(heldBlockLightValue, heldBlockLightValue2) / 16.0;
	
	return hand.x + hand.y;
}

vec3 ComputeAmbientDiffuseLight(vec3 diffuseColor, vec3 normal, vec3 viewVector, float skyLightmap, MatData mat) {
	#if ShaderStage == 1
		vec3 reflectedSky = integrateDiffuseIBL(viewVector, normal, mat.roughness, mat.f0) * mat.AO;
	#else
		vec3 reflectedSky = vec3(1.0);
	#endif

	diffuseColor *= reflectedSky * skyLightmap;
	return diffuseColor;
}

vec3 ComputeDirectShading(vec3 diffuseColor, mat2x3 position, vec3 normal, vec3 vertNormal, vec3 viewVector, float skyLightmap, Mask mask, MatData mat) {
	float illuminance = sunIlluminance * GetLambertianShading(normal, mask);
	vec3 diffuse = (diffuseColor * DisneyDiffuse(viewVector, lightVector, normal, mat.roughness) / PI) * (1.0 - mat.f0);

	float shadows = ComputeSunlight(position[1], 1.0, vertNormal);

	return (diffuse) * illuminance * shadows;
}

vec3 CalculateShadedFragment(vec3 diffuseColor, mat2x3 position, vec3 normal, vec3 vertNormal, float torchLightmap, float skyLightmap, vec3 GI, Mask mask, MatData mat) {
	Shading shading;

	vec3 viewVector = -normalize(position[0]);
	vec3 sunlight = ComputeDirectShading(diffuseColor, position, normal, vertNormal, viewVector, skyLightmap, mask, mat);

	shading.sunlight  = ComputeSunlight(position[1], 1.0, vertNormal);
	
	
	shading.torchlight  = 1.0 - pow(clamp01(torchLightmap - 0.075), 4.0);
	shading.torchlight  = 1.0 / pow(shading.torchlight, 2.0) - 1.0;
	shading.torchlight += GetHeldLight(position[0], normal, mask.hand);
	
	shading.skylight = pow(skyLightmap, 2.0);
	
	shading.ambient = 1.0 + (1.0 - eyeBrightnessSmooth.g / 240.0) * 1.7;
	
	
	Lightmap lightmap;
	
	lightmap.sunlight = sunlight * sunlightColor;
	
	lightmap.skylight = ComputeAmbientDiffuseLight(diffuseColor, normal, viewVector, skyLightmap, mat);
	
	
	
	lightmap.GI = GI * diffuseColor / PI;
	
	lightmap.ambient = vec3(shading.ambient);
	
	lightmap.torchlight = shading.torchlight * vec3(0.7, 0.3, 0.1);
	
	
	return vec3(
	    lightmap.sunlight
	+   lightmap.skylight
	+   lightmap.GI 
	//+   lightmap.ambient    * 0.015 * AMBIENT_LIGHT_LEVEL
	//+   lightmap.torchlight * 6.0   * TORCH_LIGHT_LEVEL
	    );
}
