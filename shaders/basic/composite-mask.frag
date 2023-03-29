/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen, Noeme2D
*/
#version 100
precision highp float;
varying vec2 texUVs;

uniform sampler2D tex;
uniform float threshold;
uniform float opacity;

void main() {
    vec4 color = texture2D(tex, texUVs) * vec4(1, 1, 1, opacity);
    if (color.a <= threshold) discard;
    gl_FragColor = vec4(1, 1, 1, 1);
}