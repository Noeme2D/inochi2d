/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/

/*
    Inochi2D OpenGL ES 2.0 Port
    Copyright © 2023, Noeme2D Workgroup
    Distributed under the 2-Clause BSD License, see LICENSE file.

    Authors: Leo Li, Ruiqi Niu
*/
#version 100
precision highp float;
varying vec2 texUVs;

uniform sampler2D tex;
uniform float threshold;

void main() {
    vec4 color = texture2D(tex, texUVs);
    if (color.a <= threshold) discard;
    gl_FragColor = vec4(1, 1, 1, 1);
}
