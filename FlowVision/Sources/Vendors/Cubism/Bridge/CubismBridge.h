/**
 * ObjC Bridge for Swift — exposes Cubism SDK through pure ObjC interfaces.
 * No C++ types in public API.
 */

#ifndef CubismBridge_h
#define CubismBridge_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CubismEngine : NSObject

+ (BOOL)startWithDevice:(id<MTLDevice>)device;
+ (void)shutdown;
+ (void)updateTime;
+ (void)beginFrameWithDevice:(id<MTLDevice>)device;
+ (void)endFrameWithDevice:(id<MTLDevice>)device;

@end

@interface CubismModelHandle : NSObject

/// Load model from filesystem path (e.g. "/path/to/Haru/", "Haru.model3.json")
- (BOOL)loadFromPath:(NSString *)dirPath
        jsonFileName:(NSString *)jsonFile
               width:(float)width
              height:(float)height
              device:(id<MTLDevice>)device
        commandQueue:(id<MTLCommandQueue>)queue;

@property (nonatomic, readonly) float canvasWidth;
@property (nonatomic, readonly) float canvasHeight;

// --- Motion ---

@property (nonatomic, readonly) NSInteger motionGroupCount;
- (NSString *)motionGroupNameAtIndex:(NSInteger)index;
- (NSInteger)motionCountInGroup:(NSString *)group;
- (NSString *)motionFileNameInGroup:(NSString *)group atIndex:(NSInteger)index;
- (void)startMotionInGroup:(NSString *)group
                   atIndex:(NSInteger)index
                  priority:(NSInteger)priority;

// --- Expression ---

@property (nonatomic, readonly) NSInteger expressionCount;
- (NSString *)expressionNameAtIndex:(NSInteger)index;
- (void)setExpression:(NSString *)name;

// --- Projection & Interaction ---

/// Override view-projection with custom visible bounds (for zoom/pan)
- (void)setViewBounds:(float)left right:(float)right bottom:(float)bottom top:(float)top;
@property (nonatomic, readonly) BOOL hasCustomViewBounds;
- (void)resetViewBounds;

/// Set drag position for look-at tracking (-1..1 range)
- (void)setDragX:(float)x y:(float)y;

/// Hit test at normalized coordinates
- (nullable NSString *)hitTestAtX:(float)x y:(float)y;

/// Enable/disable physics simulation
- (void)setPhysicsEnabled:(BOOL)enabled;

// --- Motion Time ---

@property (nonatomic, readonly) float currentMotionTime;
@property (nonatomic, readonly) float currentMotionDuration;
- (void)seekMotionTo:(float)time;

// --- Looping ---

@property (nonatomic) BOOL loopingEnabled;

// --- Update & Draw ---

- (void)updateWithSpeed:(float)speedMultiplier;

- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
               renderPassDesc:(MTLRenderPassDescriptor *)renderPass
                     viewport:(MTLViewport)viewport;

- (void)dispose;

@end

NS_ASSUME_NONNULL_END

#endif /* CubismBridge_h */
