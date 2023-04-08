/*
    Inochi2D Drawable base class

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
module inochi2d.core.nodes.drawable;
public import inochi2d.core.nodes.defstack;
import inochi2d.integration;
import inochi2d.fmt.serialize;
import inochi2d.math;
import derelict.gles.gles2;
import std.exception;
import inochi2d.core;

package(inochi2d) {
    void inInitDrawable() {

    }

    bool doGenerateBounds = false;
}

/**
    Sets whether Inochi2D should keep track of the bounds
*/
void inSetUpdateBounds(bool state) {
    doGenerateBounds = state;
}

/**
    Nodes that are meant to render something in to the Inochi2D scene
    Other nodes don't have to render anything and serve mostly other 
    purposes.

    The main types of Drawables are Parts and Masks
*/

@TypeId("Drawable")
abstract class Drawable : Node {
private:
    void updateIndices() {
        version (InDoesRender) {
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
            glBufferData(GL_ELEMENT_ARRAY_BUFFER, data.indices.length*ushort.sizeof, data.indices.ptr, GL_STATIC_DRAW);
        }
    }

    void updateVertices() {
        version (InDoesRender) {

            // Important check since the user can change this every frame
            glBindBuffer(GL_ARRAY_BUFFER, vbo);
            glBufferData(GL_ARRAY_BUFFER, data.vertices.length*vec2.sizeof, data.vertices.ptr, GL_DYNAMIC_DRAW);
        }

        // Zero-fill the deformation delta
        this.deformation.length = vertices.length;
        foreach(i; 0..deformation.length) {
            this.deformation[i] = vec2(0, 0);
        }
        this.updateDeform();
    }

    void updateDeform() {
        // Important check since the user can change this every frame
        enforce(
            deformation.length == vertices.length, 
            "Data length mismatch, if you want to change the mesh you need to change its data with Part.rebuffer."
        );

        version (InDoesRender) {

            glBindBuffer(GL_ARRAY_BUFFER, dbo);
            glBufferData(GL_ARRAY_BUFFER, this.deformation.length*vec2.sizeof, this.deformation.ptr, GL_DYNAMIC_DRAW);
        }

        this.updateBounds();
    }

protected:
    /**
        OpenGL Index Buffer Object
    */
    GLuint ibo;

    /**
        OpenGL Vertex Buffer Object
    */
    GLuint vbo;

    /**
        OpenGL Vertex Buffer Object for deformation
    */
    GLuint dbo;

    /**
        The mesh data of this part

        NOTE: DO NOT MODIFY!
        The data in here is only to be used for reference.
    */
    MeshData data;

    /**
        Binds Index Buffer for rendering
    */
    final void bindIndex() {
        version (InDoesRender) {
            // Bind element array and draw our mesh
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
            glDrawElements(GL_TRIANGLES, cast(int)data.indices.length, GL_UNSIGNED_SHORT, null);
        }
    }

    abstract void renderMask(bool dodge = false);

    /**
        Allows serializing self data (with pretty serializer)
    */
    override
    void serializeSelf(ref InochiSerializer serializer) {
        super.serializeSelf(serializer);
        serializer.putKey("mesh");
        serializer.serializeValue(data);
    }

    override
    SerdeException deserializeFromFghj(Fghj data) {
        import std.stdio : writeln;
        super.deserializeFromFghj(data);
        if (auto exc = data["mesh"].deserializeValue(this.data)) return exc;

        this.vertices = this.data.vertices.dup;

        // Update indices and vertices
        this.updateIndices();
        this.updateVertices();
        return null;
    }

    void onDeformPushed(ref Deformation deform) { }

package(inochi2d):
    final void notifyDeformPushed(ref Deformation deform) {
        onDeformPushed(deform);
    }

public:

    /**
        Constructs a new drawable surface
    */
    this(Node parent = null) {
        super(parent);

        version(InDoesRender) {

            // Generate the buffers
            glGenBuffers(1, &vbo);
            glGenBuffers(1, &ibo);
            glGenBuffers(1, &dbo);
        }

        // Create deformation stack
        this.deformStack = DeformationStack(this);
    }

    /**
        Constructs a new drawable surface
    */
    this(MeshData data, Node parent = null) {
        this(data, inCreateUUID(), parent);
    }

    /**
        Constructs a new drawable surface
    */
    this(MeshData data, uint uuid, Node parent = null) {
        super(uuid, parent);
        this.data = data;
        this.deformStack = DeformationStack(this);

        // Set the deformable points to their initial position
        this.vertices = data.vertices.dup;

        version(InDoesRender) {
            
            // Generate the buffers
            glGenBuffers(1, &vbo);
            glGenBuffers(1, &ibo);
            glGenBuffers(1, &dbo);
        }

        // Update indices and vertices
        this.updateIndices();
        this.updateVertices();
    }

    ref vec2[] vertices() {
        return data.vertices;
    }

    /**
        Deformation offset to apply
    */
    vec2[] deformation;

    /**
        The bounds of this drawable
    */
    vec4 bounds;

    /**
        Deformation stack
    */
    DeformationStack deformStack;

    /**
        Refreshes the drawable, updating its vertices
    */
    final void refresh() {
        this.updateVertices();
    }
    
    /**
        Refreshes the drawable, updating its deformation deltas
    */
    final void refreshDeform() {
        this.updateDeform();
    }

    override
    void beginUpdate() {
        deformStack.preUpdate();
        super.beginUpdate();
    }

    /**
        Updates the drawable
    */
    override
    void update() {
        super.update();
        deformStack.update();
        this.updateDeform();
    }

    /**
        Draws the drawable
    */
    override
    void drawOne() {
        super.drawOne();
    }

    /**
        Draws the drawable without any processing
    */
    void drawOneDirect(bool forMasking) { }

    override
    string typeId() { return "Drawable"; }

    /**
        Updates the drawable's bounds
    */
    void updateBounds() {
        if (!doGenerateBounds) return;

        // Calculate bounds
        Transform wtransform = transform;
        bounds = vec4(wtransform.translation.xyxy);
        foreach(i, vertex; vertices) {
            vec2 vertOriented = vec2(transform.matrix * vec4(vertex+deformation[i], 0, 1));
            if (vertOriented.x < bounds.x) bounds.x = vertOriented.x;
            if (vertOriented.y < bounds.y) bounds.y = vertOriented.y;
            if (vertOriented.x > bounds.z) bounds.z = vertOriented.x;
            if (vertOriented.y > bounds.w) bounds.w = vertOriented.y;
        }
    }

    /**
        Returns the mesh data for this Part.
    */
    final ref MeshData getMesh() {
        return this.data;
    }

    /**
        Changes this mesh's data
    */
    void rebuffer(ref MeshData data) {
        this.data = data;
        this.updateIndices();
        this.updateVertices();
    }
    
    /**
        Resets the vertices of this drawable
    */
    final void reset() {
        vertices[] = data.vertices;
    }
}

version (InDoesRender) {
    /**
        Begins a mask

        This causes the next draw calls until inBeginMaskContent/inBeginDodgeContent or inEndMask 
        to be written to the current mask.

        This also clears whatever old mask there was.
    */
    void inBeginMask(bool hasMasks) {

        // Enable and clear the stencil buffer so we can write our mask to it
        glEnable(GL_STENCIL_TEST);
        glClearStencil(hasMasks ? 0 : 1);
        glClear(GL_STENCIL_BUFFER_BIT);
    }

    /**
        End masking

        Once masking is ended content will no longer be masked by the defined mask.
    */
    void inEndMask() {

        // We're done stencil testing, disable it again so that we don't accidentally mask more stuff out
        glStencilMask(0xFF);
        glStencilFunc(GL_ALWAYS, 1, 0xFF);   
        glDisable(GL_STENCIL_TEST);
    }

    /**
        Starts masking content

        NOTE: This have to be run within a inBeginMask and inEndMask block!
    */
    void inBeginMaskContent() {

        glStencilFunc(GL_EQUAL, 1, 0xFF);
        glStencilMask(0x00);
    }
}