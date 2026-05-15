/**
 * Texture Loader — loads PNG textures into Metal textures with mipmap generation.
 * Uses stb_image for PNG decoding.
 * Manual memory management (-fno-objc-arc required).
 */

#ifndef TextureLoader_h
#define TextureLoader_h

#import <string>
#import <MetalKit/MetalKit.h>
#import <Type/csmVector.hpp>

@interface TextureLoader : NSObject

typedef struct
{
    id<MTLTexture> texture;
    int width;
    int height;
    std::string fileName;
} TextureInfo;

- (id)initWithDevice:(id<MTLDevice>)device commandQueue:(id<MTLCommandQueue>)commandQueue;
- (TextureInfo*)createTextureFromPngFile:(std::string)fileName;
- (void)releaseTextures;
- (void)releaseTextureByName:(std::string)fileName;

@end

#endif /* TextureLoader_h */
