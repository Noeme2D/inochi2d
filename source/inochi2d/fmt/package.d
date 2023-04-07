/*
    Inochi2D Puppet file format

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
module inochi2d.fmt;
import inochi2d.fmt.binfmt;
public import inochi2d.fmt.serialize;
import inochi2d.integration;
import inochi2d.core;
import std.bitmanip : nativeToBigEndian;
import std.exception;
import std.path;
import std.format;
import imagefmt;
import inochi2d.fmt.io;

private bool isLoadingINP_ = false;

/**
    Gets whether the current loading state is set to INP loading
*/
bool inIsINPMode() {
    return isLoadingINP_;
}

/**
    Loads a puppet from a file
*/
T inLoadPuppet(T = Puppet)(string file) if (is(T : Puppet)) {
    import std.file : read;
    ubyte[] buffer = cast(ubyte[])read(file);

    switch(extension(file)) {

        case ".inp":
            enforce(inVerifyMagicBytes(buffer), "Invalid data format for INP puppet");
            return inLoadINPPuppet!T(buffer);

        case ".inx":
            enforce(inVerifyMagicBytes(buffer), "Invalid data format for Inochi Creator INX");
            return inLoadINPPuppet!T(buffer);

        default:
            throw new Exception("Invalid file format of %s at path %s".format(extension(file), file));
    }
}

/**
    Loads a puppet from memory
*/
Puppet inLoadPuppetFromMemory(ubyte[] data) {
    return deserialize!Puppet(cast(string)data);
}

/**
    Loads a JSON based puppet
*/
Puppet inLoadJSONPuppet(string data) {
    isLoadingINP_ = false;
    return inLoadJsonDataFromMemory!Puppet(data);
}

/**
    Loads a INP based puppet
*/
T inLoadINPPuppet(T = Puppet)(ubyte[] buffer) if (is(T : Puppet)) {
    size_t bufferOffset = 0;
    isLoadingINP_ = true;

    enforce(inVerifyMagicBytes(buffer), "Invalid data format for INP puppet");
    bufferOffset += 8; // Magic bytes are 8 bytes

    // Find the puppet data
    uint puppetDataLength;
    inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], puppetDataLength);

    string puppetData = cast(string)buffer[bufferOffset..bufferOffset+=puppetDataLength];

    enforce(inVerifySection(buffer[bufferOffset..bufferOffset+=8], TEX_SECTION), "Expected Texture Blob section, got nothing!");

    // Load textures in to memory
    version (InDoesRender) {
        inBeginTextureLoading();

        // Get amount of slots
        uint slotCount;
        inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], slotCount);

        Texture[] slots;
        foreach(i; 0..slotCount) {
            
            uint textureLength;
            inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], textureLength);

            ubyte textureType = buffer[bufferOffset++];
            if (textureLength == 0) {
                inAddTextureBinary(ShallowTexture([], 0, 0, 4));
            } else inAddTextureBinary(ShallowTexture(buffer[bufferOffset..bufferOffset+=textureLength]));
        
            // Readd to puppet so that stuff doesn't break if we re-save the puppet
            slots ~= inGetLatestTexture();
        }

        T puppet = inLoadJsonDataFromMemory!T(puppetData);
        puppet.textureSlots = slots;
        puppet.updateTextureState();
        inEndTextureLoading();
    } else version(InRenderless) {
        inCurrentPuppetTextureSlots.length = 0;

        // Get amount of slots
        uint slotCount;
        inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], slotCount);
        foreach(i; 0..slotCount) {
            
            uint textureLength;
            inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], textureLength);

            ubyte textureType = buffer[bufferOffset++];
            if (textureLength == 0) {
                continue;
            } else inCurrentPuppetTextureSlots ~= TextureBlob(textureType, buffer[bufferOffset..bufferOffset+=textureLength]);
        }

        Puppet puppet = inLoadJsonDataFromMemory!T(puppetData);
    }

    if (buffer.length >= bufferOffset + 8 && inVerifySection(buffer[bufferOffset..bufferOffset+=8], EXT_SECTION)) {
        uint sectionCount;
        inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], sectionCount);

        foreach(section; 0..sectionCount) {
            import std.json : parseJSON;

            // Get name of payload/vendor extended data
            uint sectionNameLength;
            inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], sectionNameLength);            
            string sectionName = cast(string)buffer[bufferOffset..bufferOffset+=sectionNameLength];

            // Get length of data
            uint payloadLength;
            inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], payloadLength);

            // Load the vendor JSON data in to the extData section of the puppet
            ubyte[] payload = buffer[bufferOffset..bufferOffset+=payloadLength];
            puppet.extData[sectionName] = payload;
        }
    }
    
    // We're done!
    return puppet;
}