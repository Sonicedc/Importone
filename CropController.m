#import "CropController.h"
#import <math.h>
@interface IPWaveformView () <UIGestureRecognizerDelegate>
@property double gestureStart;
@property CGFloat gestureX;
@end
@implementation IPWaveformView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.layer.cornerRadius = 14; self.clipsToBounds = YES;
        self.playhead = -1;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
        hold.minimumPressDuration = 0.3; hold.delegate = self;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [pan requireGestureRecognizerToFail:hold];
        [self addGestureRecognizer:hold]; [self addGestureRecognizer:pan];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        self.accessibilityLabel = @"Ringtone selection";
        self.accessibilityHint = @"Adjust the start of a 40-second selection.";
    } return self;
}
- (double)span { return self.zoomed ? 8 : 80; }
- (double)centerTime { return self.start + (self.zoomed ? self.zoomEdge * 40 : 20); }
- (CGFloat)xForTime:(double)time { return (time - self.centerTime + self.span / 2) / self.span * self.bounds.size.width; }
- (void)setSelectionStart:(double)start {
    self.start = MAX(0, MIN(MAX(0, self.duration - 40), start));
    self.playhead = -1;
    self.accessibilityValue = [NSString stringWithFormat:@"%.2f to %.2f seconds",self.start,self.start+40];
    [self setNeedsDisplay]; if (self.selectionChanged) self.selectionChanged(self.start);
}
- (void)accessibilityIncrement { [self setSelectionStart:self.start + 0.1]; }
- (void)accessibilityDecrement { [self setSelectionStart:self.start - 0.1]; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if ([recognizer isKindOfClass:UILongPressGestureRecognizer.class]) {
        CGFloat x = [recognizer locationInView:self].x;
        return fabs(x - [self xForTime:self.start]) < 30 || fabs(x - [self xForTime:self.start + 40]) < 30;
    } return YES;
}
- (void)pan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) self.gestureStart = self.start;
    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged)
        [self setSelectionStart:self.gestureStart - [recognizer translationInView:self].x / MAX(1,self.bounds.size.width) * self.span];
}
- (void)hold:(UILongPressGestureRecognizer *)recognizer {
    CGFloat x = [recognizer locationInView:self].x;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.zoomEdge = fabs(x - [self xForTime:self.start]) < fabs(x - [self xForTime:self.start + 40]) ? 0 : 1;
        self.gestureStart = self.start; self.gestureX = x; self.zoomed = YES;
        [self setSelectionStart:self.start];
        UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new]; [feedback selectionChanged];
    } else if (recognizer.state == UIGestureRecognizerStateChanged) {
        [self setSelectionStart:self.gestureStart - (x - self.gestureX) / MAX(1,self.bounds.size.width) * self.span];
    } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        self.zoomed = NO; [self setNeedsDisplay];
    }
}
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext(); CGFloat width=self.bounds.size.width, height=self.bounds.size.height;
    CGFloat left=[self xForTime:self.start], right=[self xForTime:self.start+40];
    UIColor *accent = [UIColor colorWithRed:0.48 green:0.35 blue:0.88 alpha:1];
    CGContextSetFillColorWithColor(context,[accent colorWithAlphaComponent:0.08].CGColor);
    CGContextFillRect(context,CGRectMake(MAX(0,left),8,MAX(0,MIN(width,right)-MAX(0,left)),height-16));
    for (CGFloat x=2;x<width;x+=3) {
        double time=self.centerTime-self.span/2+x/MAX(1,width)*self.span;
        if (time<0 || time>self.duration || !self.peaks.count) continue;
        NSUInteger index=MIN(self.peaks.count-1,(NSUInteger)(time/MAX(0.001,self.duration)*self.peaks.count));
        CGFloat amplitude=MAX(0.015,self.peaks[index].doubleValue)*(height-44)/2;
        CGContextSetStrokeColorWithColor(context,(time>=self.start && time<=self.start+40 ? accent : UIColor.tertiaryLabelColor).CGColor);
        CGContextSetLineWidth(context,2); CGContextMoveToPoint(context,x,height/2-amplitude); CGContextAddLineToPoint(context,x,height/2+amplitude); CGContextStrokePath(context);
    }
    CGContextSetStrokeColorWithColor(context,accent.CGColor); CGContextSetLineWidth(context,3);
    for (NSNumber *edge in @[@0,@1]) {
        CGFloat x=edge.boolValue ? right : left, direction=edge.boolValue ? -1 : 1;
        CGContextMoveToPoint(context,x+direction*10,10); CGContextAddLineToPoint(context,x,10);
        CGContextAddLineToPoint(context,x,height-10); CGContextAddLineToPoint(context,x+direction*10,height-10); CGContextStrokePath(context);
    }
    if (self.playhead >= self.start && self.playhead <= self.start+40) {
        CGFloat x=[self xForTime:self.playhead]; CGContextSetStrokeColorWithColor(context,UIColor.labelColor.CGColor); CGContextSetLineWidth(context,1);
        CGContextMoveToPoint(context,x,15); CGContextAddLineToPoint(context,x,height-15); CGContextStrokePath(context);
    }
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
    [super viewDidLoad]; self.title=@"Choose 40 Seconds"; self.modalInPresentation=YES;
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
    long start=lround(self.waveform.start*100), end=start+4000;
    self.rangeLabel.text=[NSString stringWithFormat:@"%02ld:%02ld.%02ld  –  %02ld:%02ld.%02ld  ·  40 s",start/6000,(start/100)%60,start%100,end/6000,(end/100)%60,end%100];
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
            self.statusLabel.text=@"Swipe the waveform to move the 40-second window. Hold either bracket to zoom in, then drag to fine-tune. Release to zoom out.";
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
    self.player.currentItem.forwardPlaybackEndTime=CMTimeMakeWithSeconds(self.waveform.start+40,60000);
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
    CMTimeRange range=CMTimeRangeMake(CMTimeMakeWithSeconds(self.waveform.start,60000),CMTimeMake(40,1));
    [self cleanup];
    [self.navigationController dismissViewControllerAnimated:YES completion:^{ if (self.completion) self.completion(accepted,range); }];
}
- (void)dealloc { if (self.previousCategory) [AVAudioSession.sharedInstance setCategory:self.previousCategory mode:self.previousMode options:self.previousOptions error:nil]; if (self.observingPlayer) [self.player.currentItem removeObserver:self forKeyPath:@"status"]; [NSNotificationCenter.defaultCenter removeObserver:self]; if (self.playbackObserver) [self.player removeTimeObserver:self.playbackObserver]; [self.reader cancelReading]; }
@end
