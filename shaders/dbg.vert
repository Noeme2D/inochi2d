/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen, Noeme2D
*/
#version 100
uniform mat4 mvp;
attribute vec3 verts;

varying vec2 texUVs;

void main() {
    gl_Position = mvp * vec4(verts.x, verts.y, verts.z, 1);
}
