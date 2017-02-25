#version 410 compatibility
#define gbuffers_shadow
#define fsh
#define ShaderStage -1
#include "/lib/Syntax.glsl"


uniform sampler2D texture;

varying vec4 color;
varying vec2 texcoord;
//vertnormal not needed in fragment?, see previous change
void main() {
	vec4 diffuse = color * texture2D(texture, texcoord);
	
	gl_FragData[0] = diffuse;
}
