/**
 * Texture Loader implementation.
 * Manual memory management — compile with -fno-objc-arc.
 */

#import "TextureLoader.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#define STBI_NO_STDIO
#define STBI_ONLY_PNG
#define STB_IMAGE_IMPLEMENTATION
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcomma"
#pragma clang diagnostic ignored "-Wunused-function"
#import "stb_image.h"
#pragma clang diagnostic pop
#import "Pal.h"

@interface TextureLoader ()

@property (nonatomic) id<MTLDevice> device;
@property (nonatomic) id<MTLCommandQueue> commandQueue;
@property (nonatomic) Csm::csmVector<TextureInfo*> textures;

@end

@implementation TextureLoader

- (id)initWithDevice:(id<MTLDevice>)device commandQueue:(id<MTLCommandQueue>)commandQueue
{
    self = [super init];
    if (self)
    {
        _device = device;
        _commandQueue = commandQueue;
    }
    return self;
}

- (void)dealloc
{
    [self releaseTextures];
    [super dealloc];
}

- (TextureInfo*)createTextureFromPngFile:(std::string)fileName
{
    for (Csm::csmUint32 i = 0; i < _textures.GetSize(); i++)
    {
        if (_textures[i]->fileName == fileName)
        {
            return _textures[i];
        }
    }

    int width, height, channels;
    unsigned int size;
    unsigned char* png;
    unsigned char* address;

    address = Pal::LoadFileAsBytes(fileName, &size);
    if (address == NULL)
    {
        Pal::PrintLogLn("[TextureLoader] Failed to load file: %s", fileName.c_str());
        return NULL;
    }

    png = stbi_load_from_memory(
        address,
        static_cast<int>(size),
        &width,
        &height,
        &channels,
        STBI_rgb_alpha);

    if (png == NULL)
    {
        Pal::PrintLogLn("[TextureLoader] stbi_load_from_memory failed: %s", fileName.c_str());
        Pal::ReleaseBytes(address);
        return NULL;
    }

    MTLTextureDescriptor *textureDescriptor = [[[MTLTextureDescriptor alloc] init] autorelease];
    textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    textureDescriptor.width = width;
    textureDescriptor.height = height;
    textureDescriptor.storageMode = MTLStorageModeShared;

    int widthLevels = ceil(log2(width));
    int heightLevels = ceil(log2(height));
    int mipCount = (heightLevels > widthLevels) ? heightLevels : widthLevels;
    textureDescriptor.mipmapLevelCount = mipCount;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];

    NSUInteger bytesPerRow = 4 * width;
    MTLRegion region = {
        { 0, 0, 0 },
        { (NSUInteger)width, (NSUInteger)height, 1 }
    };

    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:png
               bytesPerRow:bytesPerRow];

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder generateMipmapsForTexture:texture];
    [blitEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    stbi_image_free(png);
    Pal::ReleaseBytes(address);

    TextureInfo* textureInfo = new TextureInfo;
    textureInfo->fileName = fileName;
    textureInfo->width = width;
    textureInfo->height = height;
    textureInfo->texture = texture;
    _textures.PushBack(textureInfo);

    Pal::PrintLogLn("[TextureLoader] Loaded texture: %s (%dx%d)", fileName.c_str(), width, height);

    return textureInfo;
}

- (void)releaseTextures
{
    for (Csm::csmUint32 i = 0; i < _textures.GetSize(); i++)
    {
        [_textures[i]->texture release];
        delete _textures[i];
    }
    _textures.Clear();
}

- (void)releaseTextureByName:(std::string)fileName
{
    for (Csm::csmUint32 i = 0; i < _textures.GetSize(); i++)
    {
        if (_textures[i]->fileName == fileName)
        {
            [_textures[i]->texture release];
            delete _textures[i];
            _textures.Remove(i);
            break;
        }
    }
}

@end
