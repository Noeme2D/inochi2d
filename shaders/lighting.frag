/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen, Noeme2D
*/
#version 100
#extension GL_ARB_shader_texture_lod : require
precision highp float;
precision lowp int;
varying vec2 texUVs;

uniform vec3 ambientLight;
uniform vec2 fbSize;

uniform sampler2D albedo;
uniform sampler2D emissive;
uniform sampler2D bumpmap;

// Gaussian
float gaussian(vec2 i, float sigma) {
    return exp(-0.5*dot(i /= sigma, i)) / (6.28*sigma*sigma);
}

// Bloom texture by blurring it
vec4 bloom(sampler2D sp, vec2 uv, vec2 scale) {
    float sigma = float(25) * 0.25;
    vec4 out_ = vec4(0);
    int sLOD = 4;
    int s = 25/sLOD;
    
    for ( int i = 0; i < s*s; i++ ) {
        vec2 d = vec2(i - s * (i/s), i/s)*float(sLOD) - float(25)/2.0;
        out_ += gaussian(d, sigma) * texture2DLod( sp, uv + scale * d, 2); // Cannot be verified by the verifier
    }
    
    return out_ / out_.a;
}

void main() {

    // Bloom
    gl_FragData[1] = bloom(emissive, texUVs, 1.0/fbSize);

    // Set color to the corrosponding pixel in the FBO
    vec4 light = vec4(ambientLight, 1) + gl_FragData[1];

    gl_FragData[0] = (texture2D(albedo, texUVs)*light);
    gl_FragData[2] = texture2D(bumpmap, texUVs);
}