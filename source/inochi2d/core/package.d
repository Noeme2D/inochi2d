/*
    Inochi2D Rendering

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
module inochi2d.core;

public import inochi2d.core.shader;
public import inochi2d.core.texture;
public import inochi2d.core.nodes;
public import inochi2d.core.puppet;
public import inochi2d.core.meshdata;
public import inochi2d.core.param;
public import inochi2d.core.automation;
public import inochi2d.core.animation;
public import inochi2d.integration;

import derelict.gles.gles2;
import inochi2d.math;
import std.stdio;

version(Windows) {
    // Ask Windows nicely to use dedicated GPUs :)
    export extern(C) int NvOptimusEnablement = 0x00000001;
    export extern(C) int AmdPowerXpressRequestHighPerformance = 0x00000001;
}

struct PostProcessingShader {
private:
    GLint[string] uniformCache;

public:
    Shader shader;
    this(Shader shader) {
        this.shader = shader;

        shader.use();
        shader.setUniform(shader.getUniformLocation("albedo"), 0);
    }

    /**
        Gets the location of the specified uniform
    */
    GLuint getUniform(string name) {
        if (this.hasUniform(name)) return uniformCache[name];
        GLint element = shader.getUniformLocation(name);
        uniformCache[name] = element;
        return element;
    }

    /**
        Returns true if the uniform is present in the shader cache 
    */
    bool hasUniform(string name) {
        return (name in uniformCache) !is null;
    }
}

// Internal rendering constants
private {
    // Viewport
    int inViewportWidth;
    int inViewportHeight;

    GLuint sceneVBO;

    GLuint fBuffer; // a framebuffer for final rendering
    GLuint fAlbedo; // a texture for color
    GLuint fStencil; // a renderbuffer with stencil attachment for stenciling

    GLuint cfBuffer;
    GLuint cfAlbedo;
    GLuint cfStencil;

    vec4 inClearColor;

    PostProcessingShader basicSceneShader;

    // Camera
    Camera inCamera;

    bool isCompositing;

    void renderScene(vec4 area, PostProcessingShader shaderToUse, GLuint albedo) {
        glViewport(0, 0, cast(int)area.z, cast(int)area.w);
        
        glDisable(GL_CULL_FACE);
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        shaderToUse.shader.use();
        shaderToUse.shader.setUniform(shaderToUse.getUniform("mvp"), 
            mat4.orthographic(0, area.z, area.w, 0, 0, max(area.z, area.w)) * 
            mat4.translation(area.x, area.y, 0)
        );

        // Bind the texture
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, albedo);

        // Enable points array
        glEnableVertexAttribArray(0); // verts
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4*float.sizeof, null);

        // Enable UVs array
        glEnableVertexAttribArray(1); // uvs
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4*float.sizeof, cast(float*)(2*float.sizeof));

        // Draw
        glDrawArrays(GL_TRIANGLES, 0, 6);

        // Disable the vertex attribs after use
        glDisableVertexAttribArray(0);
        glDisableVertexAttribArray(1);

        glDisable(GL_BLEND);
    }
}

// Things only available internally for Inochi2D rendering
package(inochi2d) {
    
    /**
        Initializes the renderer
    */
    void initRenderer() {
        // Initialize dynamic meshes
        inInitNodes();
        inInitDrawable();
        inInitPart();
        inInitMask();
        inInitComposite();

        inParameterSetFactory((data) {
            import fghj : deserializeValue;
            Parameter param = new Parameter;
            data.deserializeValue(param);
            return param;
        });

        // Some defaults that should be changed by app writer
        inCamera = new Camera;

        inClearColor = vec4(0, 0, 0, 0);

        version (InDoesRender) {
            
            // Shader for scene
            basicSceneShader = PostProcessingShader(new Shader(
                import("scene.vert"),
                import("scene.frag"),
                ["verts", "uvs"]
            ));

            glGenBuffers(1, &sceneVBO);

            // Generate the framebuffer we'll be using to render the model and composites
            glGenFramebuffers(1, &fBuffer);
            glGenFramebuffers(1, &cfBuffer);
            
            // Generate the color and stencil-depth textures needed
            // Note: we're not using the depth buffer but OpenGL 3.4 does not support stencil-only buffers
            // ES 2.0 port: ES 2.0 does not support stencil as textures
            // ES 2.0 port: guess what, we don't even have native stencil-with-depth support
            glGenTextures(1, &fAlbedo);
            glGenRenderbuffers(1, &fStencil);
            glGenTextures(1, &cfAlbedo);
            glGenRenderbuffers(1, &cfStencil);
        }

        // Set the viewport and by extension set the textures
        inSetViewport(640, 480);
    }
}

vec3 inSceneAmbientLight = vec3(1, 1, 1);

/**
    Begins rendering to the framebuffer
*/
void inBeginScene() {
    glEnable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);

    // Make sure to reset our viewport if someone has messed with it
    glViewport(0, 0, inViewportWidth, inViewportHeight);

    // Bind our framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, fBuffer);

    glClearColor(inClearColor.r, inClearColor.g, inClearColor.b, inClearColor.a);
    glClear(GL_COLOR_BUFFER_BIT);

    // Everything else is the actual texture used by the meshes at id 0
    glActiveTexture(GL_TEXTURE0);

    // Finally we render to all buffers
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
}

/**
    Begins a composition step
*/
void inBeginComposite() {

    // We don't allow recursive compositing
    if (isCompositing) return;
    isCompositing = true;

    glBindFramebuffer(GL_FRAMEBUFFER, cfBuffer);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    // Everything else is the actual texture used by the meshes at id 0
    glActiveTexture(GL_TEXTURE0);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
}

/**
    Ends a composition step, re-binding the internal framebuffer
*/
void inEndComposite() {

    // We don't allow recursive compositing
    if (!isCompositing) return;
    isCompositing = false;

    glBindFramebuffer(GL_FRAMEBUFFER, fBuffer);
    glFlush();
}

/**
    Ends rendering to the framebuffer
*/
void inEndScene() {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    glFlush();
}

/**
    Gets the global camera
*/
Camera inGetCamera() {
    return inCamera;
}

/**
    Sets the global camera, allows switching between cameras
*/
void inSetCamera(Camera camera) {
    inCamera = camera;
}

/**
    Draw scene to area
*/
void inDrawScene(vec4 area) {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    float[] data = [
        area.x,         area.y+area.w,          0, 0,
        area.x,         area.y,                 0, 1,
        area.x+area.z,  area.y+area.w,          1, 0,
        
        area.x+area.z,  area.y+area.w,          1, 0,
        area.x,         area.y,                 0, 1,
        area.x+area.z,  area.y,                 1, 1,
    ];

    glBindBuffer(GL_ARRAY_BUFFER, sceneVBO);
    glBufferData(GL_ARRAY_BUFFER, 24*float.sizeof, data.ptr, GL_DYNAMIC_DRAW);
    renderScene(area, basicSceneShader, fAlbedo);
}

void incCompositePrepareRender() {
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, cfAlbedo);
}

/**
    Gets the Inochi2D composite render image

    DO NOT MODIFY THIS IMAGE!
*/
GLuint inGetCompositeImage() {
    return cfAlbedo;
}

/**
    Sets the viewport area to render to
*/
void inSetViewport(int width, int height) nothrow {

    // Skip resizing when not needed.
    if (width == inViewportWidth && height == inViewportHeight) return;

    inViewportWidth = width;
    inViewportHeight = height;

    version(InDoesRender) {
        // Render Framebuffer
        glBindTexture(GL_TEXTURE_2D, fAlbedo);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glBindRenderbuffer(GL_RENDERBUFFER, fStencil);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);

        glBindFramebuffer(GL_FRAMEBUFFER, fBuffer);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fAlbedo, 0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, fStencil);


        // Composite framebuffer
        glBindTexture(GL_TEXTURE_2D, cfAlbedo);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glBindRenderbuffer(GL_RENDERBUFFER, cfStencil);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);

        glBindFramebuffer(GL_FRAMEBUFFER, cfBuffer);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, cfAlbedo, 0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, cfStencil);
        
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        glViewport(0, 0, width, height);
    }
}

/**
    Gets the viewport
*/
void inGetViewport(out int width, out int height) nothrow {
    width = inViewportWidth;
    height = inViewportHeight;
}

/**
    Returns length of viewport data for extraction
*/
size_t inViewportDataLength() {
    return inViewportWidth * inViewportHeight * 4;
}

/**
    Sets the background clear color
*/
void inSetClearColor(float r, float g, float b, float a) {
    inClearColor = vec4(r, g, b, a);
}

/**

*/
void inGetClearColor(out float r, out float g, out float b, out float a) {
    r = inClearColor.r;
    g = inClearColor.g;
    b = inClearColor.b;
    a = inClearColor.a;
}

/**
    UDA for sub-classable parts of the spec
    eg. Nodes and Automation can be extended by
    adding new subclasses that aren't in the base spec.
*/
struct TypeId { string id; }

/**
    Different modes of interpolation between values.
*/
enum InterpolateMode {

    /**
        Round to nearest
    */
    Nearest,
    
    /**
        Linear interpolation
    */
    Linear,

    /**
        Round to nearest
    */
    Stepped,

    /**
        Cubic interpolation
    */
    Cubic,

    /**
        Interpolation using beziér splines
    */
    Bezier,

    COUNT
}
