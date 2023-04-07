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

uniform sampler2D albedo;

uniform float opacity;
uniform vec3 multColor;
uniform vec3 screenColor;

void main() {
    // if texture coords out of texture, no color
    if (texUVs[0] <= 0.0 || texUVs[0] >= 1.0 || texUVs[1] <= 0.0 || texUVs[1] >= 1.0) {
        discard;
    }

    // Sample texture
    vec4 texColor = texture2D(albedo, texUVs);

    // Screen color math
    vec3 screenOut = vec3(1.0) - ((vec3(1.0)-(texColor.xyz)) * (vec3(1.0)-(screenColor*texColor.a)));
    
    // Multiply color math + opacity application.
    gl_FragData[0] = vec4(screenOut.xyz, texColor.a) * vec4(multColor.xyz, 1) * opacity;
}