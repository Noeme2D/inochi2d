/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen, Noeme2D
*/
#version 100
precision highp float;
varying vec2 texUVs;

uniform sampler2D albedo;
uniform sampler2D emissive;
uniform sampler2D bumpmap;

uniform float opacity;
uniform vec3 multColor;
uniform vec3 screenColor;

void main() {
    // Sample texture
    vec4 texColor = texture2D(albedo, texUVs);

    // Screen color math
    vec3 screenOut = vec3(1.0) - ((vec3(1.0)-(texColor.xyz)) * (vec3(1.0)-(screenColor*texColor.a)));
    
    // Multiply color math + opacity application.
    gl_FragData[0] = vec4(screenOut.xyz, texColor.a) * vec4(multColor.xyz, 1) * opacity;

    // Emissive
    gl_FragData[1] = texture2D(emissive, texUVs) * gl_FragData[0].a;

    // Bumpmap
    gl_FragData[2] = texture2D(bumpmap, texUVs) * gl_FragData[0].a;
}