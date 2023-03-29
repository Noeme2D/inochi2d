/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen, Noeme2D
*/
#version 100
uniform mat4 mvp;
uniform vec2 offset;

attribute vec2 verts;
attribute vec2 uvs;
attribute vec2 deform;

varying vec2 texUVs;

void main() {
    gl_Position = mvp * vec4(verts.x-offset.x+deform.x, verts.y-offset.y+deform.y, 0, 1);
    texUVs = uvs;
}
