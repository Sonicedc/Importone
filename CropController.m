#import "CropController.h"
#import <math.h>
@interface IPWaveformView () <UIGestureRecognizerDelegate>
@property double gestureStart;
@property double gestureEnd;
@property double gestureCenter;
@property NSInteger dragEdge;
@property CGFloat gestureX;
@property CAShapeLayer *waveLayer;
@property CAShapeLayer *accentLayer;
@property CAShapeLayer *accentMask;
@property CAShapeLayer *selectionLayer;
@property CAShapeLayer *bracketLayer;
@property CAShapeLayer *playheadLayer;
@property CGSize pathSize;
@end
@implementation IPWaveformView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.layer.cornerRadius = 14; self.clipsToBounds = YES;
        _playhead = -1; _dragEdge = -1;
        self.waveLayer=[CAShapeLayer layer]; self.accentLayer=[CAShapeLayer layer];
        self.accentMask=[CAShapeLayer layer]; self.accentLayer.mask=self.accentMask;
        self.selectionLayer=[CAShapeLayer layer]; self.bracketLayer=[CAShapeLayer layer]; self.playheadLayer=[CAShapeLayer layer];
        for (CALayer *layer in @[self.selectionLayer,self.waveLayer,self.accentLayer,self.bracketLayer,self.playheadLayer]) [self.layer addSublayer:layer];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
        hold.minimumPressDuration = 0.3; hold.delegate = self;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [pan requireGestureRecognizerToFail:hold];
        [self addGestureRecognizer:hold]; [self addGestureRecognizer:pan];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        self.accessibilityLabel = @"Ringtone selection";
        self.accessibilityHint = @"Adjust the selection position. Drag either bracket to change its length.";
    } return self;
}
- (double)span { return self.zoomed ? MIN(8,MAX(0.5,self.duration)) : MIN(80,MAX(0.5,self.duration*1.4)); }
- (double)centerTime { return self.dragEdge>=0 ? self.gestureCenter : (self.start+self.end)/2; }
- (CGFloat)xForTime:(double)time { return (time - self.centerTime + self.span / 2) / self.span * self.bounds.size.width; }
- (void)setSelectionFrom:(double)start to:(double)end {
    double minimum=MIN(0.25,self.duration);
    _start=MAX(0,MIN(self.duration-minimum,start));
    _end=MAX(_start+minimum,MIN(MIN(self.duration,_start+40),end));
    _playhead=-1;
    self.accessibilityValue=[NSString stringWithFormat:@"%.2f to %.2f seconds",self.start,self.end];
    [self setNeedsLayout]; if (self.selectionChanged) self.selectionChanged(self.start);
}
- (void)setSelectionStart:(double)start {
    double length=self.end>self.start ? self.end-self.start : MIN(40,self.duration);
    start=MAX(0,MIN(self.duration-length,start)); [self setSelectionFrom:start to:start+length];
}
- (void)setPeaks:(NSArray<NSNumber *> *)peaks { _peaks=[peaks copy]; self.pathSize=CGSizeZero; [self setNeedsLayout]; }
- (void)setPlayhead:(double)playhead { _playhead=playhead; [self setNeedsLayout]; }
- (void)accessibilityIncrement { [self setSelectionStart:self.start + 0.1]; }
- (void)accessibilityDecrement { [self setSelectionStart:self.start - 0.1]; }
- (NSInteger)edgeAtX:(CGFloat)x {
    CGFloat left=fabs(x-[self xForTime:self.start]),right=fabs(x-[self xForTime:self.end]);
    return MIN(left,right)<=30 ? (left<right ? 0 : 1) : -1;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    return ![recognizer isKindOfClass:UILongPressGestureRecognizer.class] || [self edgeAtX:[recognizer locationInView:self].x]>=0;
}
- (void)beginDrag:(NSInteger)edge {
    self.gestureCenter=self.centerTime; self.gestureStart=self.start; self.gestureEnd=self.end; self.dragEdge=edge;
}
- (void)adjustBy:(double)delta {
    double minimum=MIN(0.25,self.duration);
    if (self.dragEdge==0) [self setSelectionFrom:MAX(MAX(0,self.gestureEnd-40),MIN(self.gestureEnd-minimum,self.gestureStart+delta)) to:self.gestureEnd];
    else if (self.dragEdge==1) [self setSelectionFrom:self.gestureStart to:MAX(self.gestureStart+minimum,MIN(MIN(self.duration,self.gestureStart+40),self.gestureEnd+delta))];
    else [self setSelectionStart:self.gestureStart-delta];
}
- (void)pan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state==UIGestureRecognizerStateBegan) [self beginDrag:[self edgeAtX:[recognizer locationInView:self].x]];
    if (recognizer.state==UIGestureRecognizerStateBegan || recognizer.state==UIGestureRecognizerStateChanged)
        [self adjustBy:[recognizer translationInView:self].x/MAX(1,self.bounds.size.width)*self.span];
    else { self.dragEdge=-1; [self setNeedsLayout]; }
}
- (void)hold:(UILongPressGestureRecognizer *)recognizer {
    CGFloat x=[recognizer locationInView:self].x;
    if (recognizer.state==UIGestureRecognizerStateBegan) {
        NSInteger edge=[self edgeAtX:x]; if (edge<0) return;
        [self beginDrag:edge]; self.zoomEdge=edge; self.gestureX=x;
        self.zoomed=YES;
        self.gestureCenter=(edge ? self.end : self.start)+self.span/2-x/MAX(1,self.bounds.size.width)*self.span; [self setNeedsLayout];
        UISelectionFeedbackGenerator *feedback=[UISelectionFeedbackGenerator new]; [feedback selectionChanged];
    } else if (recognizer.state==UIGestureRecognizerStateChanged) [self adjustBy:(x-self.gestureX)/MAX(1,self.bounds.size.width)*self.span];
    else { self.zoomed=NO; self.dragEdge=-1; [self setNeedsLayout]; }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; [self setNeedsLayout]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=self.bounds.size.width,height=self.bounds.size.height; if (width<=0 || height<=0) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    UIColor *accent=[UIColor colorWithRed:0.48 green:0.35 blue:0.88 alpha:1];
    // The envelope is built once in audio coordinates. Scrubbing only translates it;
    // changing selection or playing never samples or reconstructs the waveform.
    if (!CGSizeEqualToSize(self.pathSize,self.bounds.size)) {
        UIBezierPath *envelope=[UIBezierPath bezierPath]; NSUInteger count=self.peaks.count;
        for (NSUInteger i=0;i<count;i++) {
            CGFloat y=height/2-MAX(0.015,self.peaks[i].doubleValue)*(height-44)/2;
            CGPoint point=CGPointMake((double)i/MAX(1,count-1)*self.duration,y);
            if (i==0) [envelope moveToPoint:point]; else [envelope addLineToPoint:point];
        }
        for (NSInteger i=(NSInteger)count-1;i>=0;i--) [envelope addLineToPoint:CGPointMake((double)i/MAX(1,count-1)*self.duration,height/2+MAX(0.015,self.peaks[i].doubleValue)*(height-44)/2)];
        [envelope closePath]; self.waveLayer.path=envelope.CGPath; self.accentLayer.path=envelope.CGPath; self.pathSize=self.bounds.size;
    }
    CGFloat scale=width/self.span,origin=[self xForTime:0];
    for (CAShapeLayer *layer in @[self.waveLayer,self.accentLayer]) {
        layer.bounds=CGRectMake(0,0,self.duration,height); layer.anchorPoint=CGPointZero; layer.position=CGPointMake(origin,0); layer.affineTransform=CGAffineTransformMakeScale(scale,1);
    }
    self.waveLayer.fillColor=UIColor.tertiaryLabelColor.CGColor; self.accentLayer.fillColor=accent.CGColor;
    self.accentMask.frame=CGRectMake(0,0,self.duration,height);
    self.accentMask.path=[UIBezierPath bezierPathWithRect:CGRectMake(self.start,0,self.end-self.start,height)].CGPath;
    CGFloat left=[self xForTime:self.start],right=[self xForTime:self.end];
    self.selectionLayer.path=[UIBezierPath bezierPathWithRect:CGRectMake(left,8,right-left,height-16)].CGPath;
    self.selectionLayer.fillColor=[accent colorWithAlphaComponent:0.08].CGColor;
    UIBezierPath *brackets=[UIBezierPath bezierPath];
    for (NSNumber *edge in @[@0,@1]) {
        CGFloat x=edge.boolValue ? right : left,direction=edge.boolValue ? -1 : 1;
        [brackets moveToPoint:CGPointMake(x+direction*10,10)]; [brackets addLineToPoint:CGPointMake(x,10)];
        [brackets addLineToPoint:CGPointMake(x,height-10)]; [brackets addLineToPoint:CGPointMake(x+direction*10,height-10)];
    }
    self.bracketLayer.path=brackets.CGPath; self.bracketLayer.fillColor=nil; self.bracketLayer.strokeColor=accent.CGColor; self.bracketLayer.lineWidth=3;
    UIBezierPath *cursor=[UIBezierPath bezierPath];
    if (self.playhead>=self.start && self.playhead<=self.end) { CGFloat x=[self xForTime:self.playhead]; [cursor moveToPoint:CGPointMake(x,15)]; [cursor addLineToPoint:CGPointMake(x,height-15)]; }
    self.playheadLayer.path=cursor.CGPath; self.playheadLayer.strokeColor=UIColor.labelColor.CGColor; self.playheadLayer.lineWidth=1;
    [CATransaction commit];
}
@end
@interface IPCropController ()
@property AVAsset *asset;
@property IPWaveformView *waveform;
@property UILabel *rangeLabel;
@property UILabel *statusLabel;
@property UIButton *playButton;
@property UIActivityIndicatorView *spinner;
@property AVAssetReader *reader;
@property AVPlayer *player;
@property id playbackObserver;
@property BOOL playing;
@property (atomic) BOOL closed;
@property NSUInteger playbackGeneration;
@property NSString *previousCategory;
@property NSString *previousMode;
@property AVAudioSessionCategoryOptions previousOptions;
@property BOOL observingPlayer;
@end
@implementation IPCropController
- (instancetype)initWithAsset:(AVAsset *)asset { if ((self=[super init])) self.asset=asset; return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Crop Ringtone"; self.modalInPresentation=YES;
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Use Selection" style:UIBarButtonItemStylePlain target:self action:@selector(accept)];
    self.navigationItem.rightBarButtonItem.enabled=NO;
    UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll];
    self.waveform=[IPWaveformView new]; self.waveform.duration=CMTimeGetSeconds(self.asset.duration);
    self.waveform.userInteractionEnabled=NO;
    self.rangeLabel=[UILabel new]; self.rangeLabel.font=[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular]; self.rangeLabel.textAlignment=NSTextAlignmentCenter;
    self.statusLabel=[UILabel new]; self.statusLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.statusLabel.textColor=UIColor.secondaryLabelColor; self.statusLabel.numberOfLines=0; self.statusLabel.textAlignment=NSTextAlignmentCenter;
    self.statusLabel.text=@"Loading waveform…";
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; [self.spinner startAnimating];
    self.playButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self updatePreviewButton]; self.playButton.enabled=NO;
    [self.playButton addTarget:self action:@selector(togglePreview) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.waveform,self.rangeLabel,self.playButton,self.spinner,self.statusLabel]];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=16; stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],[self.waveform.heightAnchor constraintEqualToConstant:170],[self.playButton.heightAnchor constraintEqualToConstant:44]]];
    __weak IPCropController *weakSelf=self;
    self.waveform.selectionChanged=^(double start){ [weakSelf stopPreview]; [weakSelf updateRange]; };
    [self.waveform setSelectionStart:0];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopPreview) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopPreview) name:AVAudioSessionInterruptionNotification object:nil];
    [self loadWaveform];
}
- (void)updateRange {
    long start=lround(self.waveform.start*100), end=lround(self.waveform.end*100);
    self.rangeLabel.text=[NSString stringWithFormat:@"%02ld:%02ld.%02ld  –  %02ld:%02ld.%02ld  ·  %.2f s",start/6000,(start/100)%60,start%100,end/6000,(end/100)%60,end%100,self.waveform.end-self.waveform.start];
}
- (void)loadWaveform {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil;
        AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:self.asset error:&error]; self.reader=reader;
        AVAssetTrack *track=[self.asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        AVAssetReaderTrackOutput *output=track ? [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVLinearPCMBitDepthKey:@16,AVLinearPCMIsFloatKey:@NO,AVLinearPCMIsBigEndianKey:@NO,AVLinearPCMIsNonInterleaved:@NO}] : nil;
        output.alwaysCopiesSampleData=NO;
        if (!output || ![reader canAddOutput:output]) { [self waveformFailed:error.localizedDescription ?: @"This audio cannot be decoded for trimming."]; return; }
        [reader addOutput:output];
        if (self.closed || ![reader startReading]) { if (!self.closed) [self waveformFailed:reader.error.localizedDescription ?: @"This audio cannot be decoded for trimming."]; return; }
        const NSUInteger count=4096; float peaks[count]; memset(peaks,0,sizeof(peaks)); double duration=CMTimeGetSeconds(self.asset.duration);
        while (!self.closed && reader.status==AVAssetReaderStatusReading) { @autoreleasepool {
            CMSampleBufferRef buffer=[output copyNextSampleBuffer]; if (!buffer) break;
            CMBlockBufferRef block=CMSampleBufferGetDataBuffer(buffer);
            const AudioStreamBasicDescription *format=CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(buffer));
            size_t length=block ? CMBlockBufferGetDataLength(block) : 0;
            if (format && format->mSampleRate>0 && format->mChannelsPerFrame && length) {
                NSMutableData *bytes=[NSMutableData dataWithLength:length];
                if (CMBlockBufferCopyDataBytes(block,0,length,bytes.mutableBytes)==kCMBlockBufferNoErr) {
                    const int16_t *samples=bytes.bytes; NSUInteger channels=format->mChannelsPerFrame, frames=length/(sizeof(int16_t)*channels);
                    double base=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer));
                    if (isfinite(base)) for (NSUInteger frame=0;frame<frames;frame++) {
                        double time=base+frame/format->mSampleRate; if (time<0 || time>duration) continue;
                        NSUInteger bin=MIN(count-1,(NSUInteger)(time/duration*count));
                        for (NSUInteger channel=0;channel<channels;channel++) peaks[bin]=MAX(peaks[bin],fabsf(samples[frame*channels+channel]/32768.0f));
                    }
                }
            }
            CFRelease(buffer);
        } }
        if (self.closed) { [reader cancelReading]; return; }
        if (reader.status!=AVAssetReaderStatusCompleted) { [self waveformFailed:reader.error.localizedDescription ?: @"The waveform could not be read."]; return; }
        float maximum=0; for (NSUInteger i=0;i<count;i++) maximum=MAX(maximum,peaks[i]);
        NSMutableArray *values=[NSMutableArray arrayWithCapacity:count]; for (NSUInteger i=0;i<count;i++) [values addObject:@(maximum>0 ? sqrtf(peaks[i]/maximum) : 0)];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.closed) return;
            self.reader=nil; self.waveform.peaks=values; self.waveform.userInteractionEnabled=YES; [self.waveform setNeedsDisplay];
            [self.spinner stopAnimating]; self.spinner.hidden=YES;
            self.statusLabel.text=@"Swipe the waveform to move your selection. Drag either bracket to shorten or extend it, up to 40 seconds. Hold a bracket to zoom in and fine-tune.";
            self.playButton.enabled=YES; self.navigationItem.rightBarButtonItem.enabled=YES;
        });
    });
}
- (void)waveformFailed:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.closed) return; [self.spinner stopAnimating]; self.spinner.hidden=YES; self.statusLabel.text=message; });
}
- (void)updatePreviewButton {
    UIButtonConfiguration *configuration=UIButtonConfiguration.plainButtonConfiguration;
    configuration.imagePadding=8;
    configuration.image=[UIImage systemImageNamed:self.playing ? @"pause.fill" : @"play.fill"];
    configuration.attributedTitle=[[NSAttributedString alloc] initWithString:self.playing ? @"Pause" : @"Play Selection" attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]}];
    self.playButton.configuration=configuration;
}
- (void)stopPreview {
    self.playbackGeneration++; self.playing=NO; [self.player pause];
    if (self.playbackObserver) { [self.player removeTimeObserver:self.playbackObserver]; self.playbackObserver=nil; }
    self.waveform.playhead=-1; [self.waveform setNeedsDisplay];
    [self updatePreviewButton];
}
- (void)togglePreview {
    if (self.playing) { [self stopPreview]; return; }
    AVAudioSession *session=AVAudioSession.sharedInstance;
    if (!self.previousCategory) { self.previousCategory=session.category; self.previousMode=session.mode; self.previousOptions=session.categoryOptions; }
    NSError *error;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:&error] || ![session setActive:YES error:&error]) { self.statusLabel.text=error.localizedDescription ?: @"Audio preview is unavailable."; return; }
    if (!self.player) {
        self.player=[AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:self.asset]];
        [self.player.currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL]; self.observingPlayer=YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopPreview) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewFailed) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.player.currentItem];
    }
    self.player.currentItem.forwardPlaybackEndTime=CMTimeMakeWithSeconds(self.waveform.end,60000);
    self.playing=YES; NSUInteger generation=++self.playbackGeneration;
    [self updatePreviewButton];
    __weak IPCropController *weakSelf=self;
    [self.player seekToTime:CMTimeMakeWithSeconds(self.waveform.start,60000) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished){ dispatch_async(dispatch_get_main_queue(), ^{
        IPCropController *controller=weakSelf;
        if (!controller || !finished || !controller.playing || controller.closed || generation!=controller.playbackGeneration) return;
        controller.playbackObserver=[controller.player addPeriodicTimeObserverForInterval:CMTimeMake(1,20) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){
            IPCropController *owner=weakSelf; double position=CMTimeGetSeconds(time);
            if (!owner.playing) return;
            if (position>=owner.waveform.start+40) { [owner stopPreview]; return; }
            owner.waveform.playhead=position; [owner.waveform setNeedsDisplay];
        }];
        [controller.player play];
    }); }];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqual:@"status"] && object==self.player.currentItem) {
        if (self.player.currentItem.status==AVPlayerItemStatusFailed) dispatch_async(dispatch_get_main_queue(), ^{ if (!self.closed) [self previewFailed]; });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)previewFailed { [self stopPreview]; self.statusLabel.text=@"This selection could not be previewed. Try moving the window or use a different audio file."; }
- (void)cleanup {
    self.closed=YES; [self.reader cancelReading]; [self stopPreview];
    if (self.observingPlayer) { [self.player.currentItem removeObserver:self forKeyPath:@"status"]; self.observingPlayer=NO; }
    if (self.previousCategory) { [AVAudioSession.sharedInstance setCategory:self.previousCategory mode:self.previousMode options:self.previousOptions error:nil]; self.previousCategory=nil; }
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.closed && (self.isBeingDismissed || self.navigationController.isBeingDismissed)) [self cleanup];
}
- (void)cancel { [self complete:NO]; }
- (void)accept { [self complete:YES]; }
- (void)complete:(BOOL)accepted {
    if (self.closed) return;
    CMTimeRange range=CMTimeRangeMake(CMTimeMakeWithSeconds(self.waveform.start,60000),CMTimeMakeWithSeconds(self.waveform.end-self.waveform.start,60000));
    [self cleanup];
    [self.navigationController dismissViewControllerAnimated:YES completion:^{ if (self.completion) self.completion(accepted,range); }];
}
- (void)dealloc { if (self.previousCategory) [AVAudioSession.sharedInstance setCategory:self.previousCategory mode:self.previousMode options:self.previousOptions error:nil]; if (self.observingPlayer) [self.player.currentItem removeObserver:self forKeyPath:@"status"]; [NSNotificationCenter.defaultCenter removeObserver:self]; if (self.playbackObserver) [self.player removeTimeObserver:self.playbackObserver]; [self.reader cancelReading]; }
@end
