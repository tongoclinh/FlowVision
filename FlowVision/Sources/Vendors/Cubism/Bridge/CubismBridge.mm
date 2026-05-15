/**
 * ObjC Bridge implementation.
 * Wraps C++ Cubism SDK classes for Swift consumption.
 * Added: loadFromPath, setViewBounds, setDragX:y:, hitTestAtX:y:, setPhysicsEnabled.
 */

#import "CubismBridge.h"
#import "Allocator.h"
#import "Pal.h"
#import "TextureLoader.h"
#import "CubismModel.h"

#import <CubismFramework.hpp>
#import <Math/CubismMatrix44.hpp>
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import <Rendering/Metal/CubismDeviceInfo_Metal.hpp>

using namespace Csm;
using namespace Live2D::Cubism::Framework::Rendering;

// ---------------------------------------------------------------------------
// CubismEngine
// ---------------------------------------------------------------------------

static Allocator s_allocator;
static CubismFramework::Option s_option;
static BOOL s_initialized = NO;

@implementation CubismEngine

+ (BOOL)startWithDevice:(id<MTLDevice>)device
{
    if (s_initialized) return YES;

    s_option.LogFunction = Pal::PrintMessageLn;
    s_option.LoggingLevel = CubismFramework::Option::LogLevel_Verbose;
    s_option.LoadFileFunction = Pal::LoadFileAsBytes;
    s_option.ReleaseBytesFunction = Pal::ReleaseBytes;

    CubismFramework::StartUp(&s_allocator, &s_option);
    CubismFramework::Initialize();
    CubismRenderer_Metal::SetConstantSettings(device);
    Pal::UpdateTime();

    s_initialized = YES;
    return YES;
}

+ (void)shutdown
{
    if (!s_initialized) return;
    CubismDeviceInfo_Metal::ReleaseAllDeviceInfo();
    CubismFramework::Dispose();
    s_initialized = NO;
}

+ (void)updateTime
{
    Pal::UpdateTime();
}

+ (void)beginFrameWithDevice:(id<MTLDevice>)device
{
    CubismDeviceInfo_Metal* info = CubismDeviceInfo_Metal::GetDeviceInfo(device);
    info->GetOffscreenManager()->BeginFrameProcess();
}

+ (void)endFrameWithDevice:(id<MTLDevice>)device
{
    CubismDeviceInfo_Metal* info = CubismDeviceInfo_Metal::GetDeviceInfo(device);
    info->GetOffscreenManager()->EndFrameProcess();
    info->GetOffscreenManager()->ReleaseStaleRenderTextures();
}

@end

// ---------------------------------------------------------------------------
// CubismModelHandle
// ---------------------------------------------------------------------------

@interface CubismModelHandle () {
    CubismModelWrapper* _model;
    TextureLoader* _textureLoader;
    BOOL _hasCustomViewBounds;
    float _customLeft, _customRight, _customBottom, _customTop;
}
@end

@implementation CubismModelHandle

- (instancetype)init
{
    self = [super init];
    if (self) {
        _model = NULL;
        _textureLoader = nil;
        _hasCustomViewBounds = NO;
    }
    return self;
}

- (BOOL)loadFromPath:(NSString *)dirPath
        jsonFileName:(NSString *)jsonFile
               width:(float)width
              height:(float)height
              device:(id<MTLDevice>)device
        commandQueue:(id<MTLCommandQueue>)queue
{
    [self dispose];

    NSString* fullDir = dirPath;
    if (![fullDir hasSuffix:@"/"]) {
        fullDir = [fullDir stringByAppendingString:@"/"];
    }

    Pal::SetResourceBasePath([fullDir UTF8String]);

    _textureLoader = [[TextureLoader alloc] initWithDevice:device commandQueue:queue];
    _model = new CubismModelWrapper();
    _model->LoadAssets("", [jsonFile UTF8String], width, height, _textureLoader);

    return (_model->GetModel() != NULL);
}

// --- Canvas ---

- (float)canvasWidth
{
    if (!_model || !_model->GetModel()) return 1.0f;
    return _model->GetModel()->GetCanvasWidth();
}

- (float)canvasHeight
{
    if (!_model || !_model->GetModel()) return 1.0f;
    return _model->GetModel()->GetCanvasHeight();
}

// --- Motions ---

- (NSInteger)motionGroupCount
{
    if (!_model || !_model->GetModelSetting()) return 0;
    return _model->GetModelSetting()->GetMotionGroupCount();
}

- (NSString *)motionGroupNameAtIndex:(NSInteger)index
{
    if (!_model || !_model->GetModelSetting()) return @"";
    const csmChar* name = _model->GetModelSetting()->GetMotionGroupName((csmInt32)index);
    return [NSString stringWithUTF8String:name];
}

- (NSInteger)motionCountInGroup:(NSString *)group
{
    if (!_model || !_model->GetModelSetting()) return 0;
    return _model->GetModelSetting()->GetMotionCount([group UTF8String]);
}

- (NSString *)motionFileNameInGroup:(NSString *)group atIndex:(NSInteger)index
{
    if (!_model || !_model->GetModelSetting()) return @"";
    const csmChar* name = _model->GetModelSetting()->GetMotionFileName(
        [group UTF8String], (csmInt32)index);
    return [NSString stringWithUTF8String:name];
}

- (void)startMotionInGroup:(NSString *)group
                   atIndex:(NSInteger)index
                  priority:(NSInteger)priority
{
    if (!_model) return;
    _model->StartMotion([group UTF8String], (csmInt32)index, (csmInt32)priority);
}

// --- Expressions ---

- (NSInteger)expressionCount
{
    if (!_model || !_model->GetModelSetting()) return 0;
    return _model->GetModelSetting()->GetExpressionCount();
}

- (NSString *)expressionNameAtIndex:(NSInteger)index
{
    if (!_model || !_model->GetModelSetting()) return @"";
    const csmChar* name = _model->GetModelSetting()->GetExpressionName((csmInt32)index);
    return [NSString stringWithUTF8String:name];
}

- (void)setExpression:(NSString *)name
{
    if (!_model) return;
    _model->SetExpression([name UTF8String]);
}

// --- Projection & Interaction ---

- (void)setViewBounds:(float)left right:(float)right bottom:(float)bottom top:(float)top
{
    _hasCustomViewBounds = YES;
    _customLeft = left;
    _customRight = right;
    _customBottom = bottom;
    _customTop = top;
}

- (BOOL)hasCustomViewBounds
{
    return _hasCustomViewBounds;
}

- (void)resetViewBounds
{
    _hasCustomViewBounds = NO;
}

- (void)setDragX:(float)x y:(float)y
{
    if (!_model) return;
    _model->SetDragPosition(x, y);
}

- (nullable NSString *)hitTestAtX:(float)x y:(float)y
{
    if (!_model || !_model->GetModelSetting()) return nil;

    const csmInt32 count = _model->GetModelSetting()->GetHitAreasCount();
    for (csmInt32 i = 0; i < count; i++)
    {
        const csmChar* areaName = _model->GetModelSetting()->GetHitAreaName(i);
        if (_model->HitTest(areaName, x, y))
        {
            return [NSString stringWithUTF8String:areaName];
        }
    }
    return nil;
}

- (void)setPhysicsEnabled:(BOOL)enabled
{
    if (!_model) return;
    _model->SetPhysicsEnabled(enabled ? true : false);
}

// --- Update & Draw ---

- (void)updateWithSpeed:(float)speedMultiplier
{
    if (!_model) return;
    _model->Update(speedMultiplier);
}

- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
               renderPassDesc:(MTLRenderPassDescriptor *)renderPass
                     viewport:(MTLViewport)viewport
{
    if (!_model || !_model->GetModel()) return;

    float width = (float)viewport.width;
    float height = (float)viewport.height;
    if (width <= 0 || height <= 0) return;

    float aspectRatio = width / height;
    float canvasRatio = _model->GetModel()->GetCanvasHeight()
                      / _model->GetModel()->GetCanvasWidth();
    float displayRatio = height / width;

    CubismMatrix44 projection;
    CubismMatrix44 viewMatrix;

    if (_hasCustomViewBounds)
    {
        float customH = _customTop - _customBottom;
        float defaultViewH = (canvasRatio < displayRatio) ? (2.0f / aspectRatio) : 2.0f;
        if (customH > 0)
        {
            float zoom = defaultViewH / customH;
            float cx = (_customLeft + _customRight) / 2.0f;
            float cy = (_customBottom + _customTop) / 2.0f;
            viewMatrix.Scale(zoom, zoom);
            viewMatrix.Translate(-cx * zoom, -cy * zoom);
        }
    }

    if (canvasRatio < displayRatio) {
        _model->GetModelMatrix()->SetWidth(2.0f);
        projection.Scale(1.0f, aspectRatio);
    } else {
        _model->GetModelMatrix()->SetHeight(2.0f);
        projection.Scale(1.0f / aspectRatio, 1.0f);
    }

    projection.MultiplyByMatrix(&viewMatrix);

    _model->GetRenderer<CubismRenderer_Metal>()->StartFrame(commandBuffer, renderPass);
    _model->GetRenderer<CubismRenderer_Metal>()->SetRenderViewport(viewport);
    _model->Draw(projection);
}

// --- Lifecycle ---

- (void)dispose
{
    if (_model) { delete _model; _model = NULL; }
    if (_textureLoader) { [_textureLoader release]; _textureLoader = nil; }
    _hasCustomViewBounds = NO;
}

- (void)dealloc
{
    [self dispose];
    [super dealloc];
}

@end
