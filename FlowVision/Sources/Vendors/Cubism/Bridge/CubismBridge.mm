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

#import <os/lock.h>

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

// ---------------------------------------------------------------------------
// Motion completion plumbing
//
// Cubism's FinishedMotionCallback is a plain C function pointer. To carry Swift
// closures across the bridge we keep a global motion-pointer -> record map.
// Each record holds the heap block and an unsafe back-pointer to the owning
// `CubismModelHandle` so the trampoline can clean up the handle's pending-keys
// set on natural completion. Address-reuse safety: dispose ALWAYS removes a
// handle's entries from the global map before the handle is deallocated, so
// the trampoline can only ever resolve to a still-live handle.
//
// Threading: gMotionCompletions and each handle's _pendingMotionKeys are
// shared between the (main-queue) trampoline and `dispose` (which may run on
// the loader's background queue — see CubismViewerController.loadCubismModel).
// All mutating access goes through `gMotionCompletionsLock`. Blocks are
// invoked AFTER releasing the lock to avoid re-entry deadlocks.
// ---------------------------------------------------------------------------

@class CubismModelHandle;

@interface CubismMotionCompletionRecord : NSObject {
@public
    void(^block)(void);
    __unsafe_unretained CubismModelHandle *handle;
}
@end

@implementation CubismMotionCompletionRecord
- (void)dealloc {
    [block release];
    [super dealloc];
}
@end

static NSMapTable<NSValue *, CubismMotionCompletionRecord *> *gMotionCompletions = nil;
static dispatch_once_t gMotionCompletionsOnce = 0;
static os_unfair_lock gMotionCompletionsLock = OS_UNFAIR_LOCK_INIT;

static void EnsureMotionCompletionsMap(void) {
    dispatch_once(&gMotionCompletionsOnce, ^{
        gMotionCompletions = [[NSMapTable strongToStrongObjectsMapTable] retain];
    });
}

@interface CubismModelHandle (CompletionInternal)
/// Caller MUST already hold `gMotionCompletionsLock` — this method mutates the
/// per-instance `_pendingMotionKeys` set which is shared with `dispose` (which
/// may run off-main) and the trampoline.
- (void)_dropPendingMotionKeyLocked:(NSValue *)key;
@end

static void CubismCompletionTrampoline(Csm::ACubismMotion *motion) {
    if (!motion) return;
    // Capture pointer by value — the motion object may have been freed by the
    // motion manager between this callback returning and our main-queue block
    // running. We never dereference it, only use it as a map key.
    void *motionPtr = motion;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gMotionCompletions) return;
        NSValue *key = [NSValue valueWithPointer:motionPtr];
        // Acquire the lock for the lookup + remove, then release before
        // invoking the user block (which may take time / re-enter the bridge).
        os_unfair_lock_lock(&gMotionCompletionsLock);
        CubismMotionCompletionRecord *record = [[gMotionCompletions objectForKey:key] retain];
        if (record) {
            [gMotionCompletions removeObjectForKey:key];
            // Drop the key from the owning handle's set BEFORE invoking the
            // block. Handle is guaranteed alive: dispose always purges its
            // entries from this map before the handle is deallocated.
            [record->handle _dropPendingMotionKeyLocked:key];
        }
        os_unfair_lock_unlock(&gMotionCompletionsLock);
        if (record) {
            void(^block)(void) = record->block;
            if (block) block();
            [record release];
        }
    });
}

@interface CubismModelHandle () {
    CubismModelWrapper* _model;
    TextureLoader* _textureLoader;
    BOOL _hasCustomViewBounds;
    float _customLeft, _customRight, _customBottom, _customTop;
    // NSValue-wrapped ACubismMotion* keys currently registered in gMotionCompletions
    // for this model. Used by `dispose` to drop pending blocks.
    NSMutableSet<NSValue *> *_pendingMotionKeys;
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
        _pendingMotionKeys = [[NSMutableSet alloc] init];
        EnsureMotionCompletionsMap();
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
    [self startMotionInGroup:group
                     atIndex:index
                    priority:priority
               fadeInSeconds:-1.0f
                  completion:nil];
}

- (void)startMotionInGroup:(NSString *)group
                   atIndex:(NSInteger)index
                  priority:(NSInteger)priority
             fadeInSeconds:(float)fadeInSeconds
                completion:(void(^)(void))completion
{
    if (!_model) {
        // Caller still expects exactly-one or zero callback. Without a model we
        // never started a motion, so do not fire the block.
        return;
    }

    Csm::ACubismMotion::FinishedMotionCallback cb = completion ? &CubismCompletionTrampoline : NULL;
    Csm::ACubismMotion *motion = _model->StartMotionEx([group UTF8String],
                                                       (Csm::csmInt32)index,
                                                       (Csm::csmInt32)priority,
                                                       (Csm::csmFloat32)fadeInSeconds,
                                                       cb);

    if (!completion) return;

    if (motion == NULL) {
        // Motion rejected (priority filter, missing file). The trampoline will
        // never fire — invoke the completion now so the caller doesn't deadlock.
        dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }

    NSValue *key = [NSValue valueWithPointer:motion];

    CubismMotionCompletionRecord *record = [[CubismMotionCompletionRecord alloc] init];
    record->block = [completion copy];
    record->handle = self;

    os_unfair_lock_lock(&gMotionCompletionsLock);
    // If a record is already registered for this motion (e.g. same group/index
    // restarted before its predecessor finished), drop the old one — the SDK
    // will not fire two completions for a single motion handler swap.
    CubismMotionCompletionRecord *existing = [gMotionCompletions objectForKey:key];
    if (existing != nil) {
        // Clear the existing owner's pending key first (may be a different handle).
        [existing->handle _dropPendingMotionKeyLocked:key];
        [gMotionCompletions removeObjectForKey:key];
    }
    [gMotionCompletions setObject:record forKey:key];
    [_pendingMotionKeys addObject:key];
    os_unfair_lock_unlock(&gMotionCompletionsLock);

    [record release];
}

- (void)_dropPendingMotionKeyLocked:(NSValue *)key
{
    if (key) [_pendingMotionKeys removeObject:key];
}

- (void)stopAllMotions
{
    if (_model) _model->StopAllMotions();
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

- (float)currentMotionTime
{
    if (!_model) return 0.0f;
    return _model->GetCurrentMotionTime();
}

- (float)currentMotionDuration
{
    if (!_model) return 0.0f;
    return _model->GetCurrentMotionDuration();
}

- (void)seekMotionTo:(float)time
{
    if (!_model) return;
    _model->SeekMotionTo(time);
}

- (BOOL)loopingEnabled
{
    return _model ? _model->IsLoopingEnabled() : NO;
}

- (void)setLoopingEnabled:(BOOL)loopingEnabled
{
    if (_model) _model->SetLoopingEnabled(loopingEnabled);
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
    // dispose may be called from the loader's background thread (see
    // CubismViewerController.loadCubismModel which kicks loadFromPath off
    // a Task.detached, and loadFromPath calls -dispose first). The lock
    // around gMotionCompletions / _pendingMotionKeys lets that path coexist
    // safely with the main-queue trampoline.
    os_unfair_lock_lock(&gMotionCompletionsLock);
    if (_pendingMotionKeys.count > 0 && gMotionCompletions) {
        for (NSValue *key in _pendingMotionKeys) {
            [gMotionCompletions removeObjectForKey:key];
        }
        [_pendingMotionKeys removeAllObjects];
    }
    os_unfair_lock_unlock(&gMotionCompletionsLock);

    if (_model) { delete _model; _model = NULL; }
    if (_textureLoader) { [_textureLoader release]; _textureLoader = nil; }
    _hasCustomViewBounds = NO;
}

- (void)dealloc
{
    [self dispose];
    [_pendingMotionKeys release];
    [super dealloc];
}

@end
