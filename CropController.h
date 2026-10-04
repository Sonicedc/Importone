#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@interface IPWaveformView : UIView
@property (nonatomic, copy) NSArray<NSNumber *> *peaks;
@property (nonatomic) double duration;
@property (nonatomic) double start;
@property (nonatomic) double playhead;
@property (nonatomic) BOOL zoomed;
@property (nonatomic) NSInteger zoomEdge;
@property (nonatomic, copy) void (^selectionChanged)(double);
- (void)setSelectionStart:(double)start;
@end
@interface IPCropController : UIViewController
- (instancetype)initWithAsset:(AVAsset *)asset;
@property (nonatomic, copy) void (^completion)(BOOL accepted, CMTimeRange range);
@end
