#import "MLAudioInputStatusView.h"

static CGFloat const MLInputStatusViewWidth = 380.0;
static CGFloat const MLInputStatusViewHeight = 108.0;

@interface MLAudioLevelMeterView : NSView

@property (nonatomic, assign) CGFloat level;
@property (nonatomic, assign) BOOL monitoringAvailable;

@end

@implementation MLAudioLevelMeterView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        _monitoringAvailable = YES;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)setLevel:(CGFloat)level
{
    _level = MIN(1.0, MAX(0.0, level));
    [self setNeedsDisplay:YES];
}

- (void)setMonitoringAvailable:(BOOL)monitoringAvailable
{
    _monitoringAvailable = monitoringAvailable;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;

    static NSInteger const barCount = 16;
    CGFloat gap = 7.0;
    CGFloat barWidth = floor((NSWidth(self.bounds) - gap * (barCount - 1)) / barCount);
    CGFloat activeBars = self.monitoringAvailable ? self.level * barCount : 0.0;

    for (NSInteger index = 0; index < barCount; index++)
    {
        CGFloat x = index * (barWidth + gap);
        NSRect barRect = NSMakeRect(x, 3.0, barWidth, NSHeight(self.bounds) - 6.0);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:4.0 yRadius:4.0];

        BOOL active = ((CGFloat)index + 0.5) <= activeBars;
        NSColor *color = active
            ? [NSColor controlAccentColor]
            : [[NSColor separatorColor] colorWithAlphaComponent:0.45];
        [color setFill];
        [path fill];
    }
}

@end

@interface MLAudioInputStatusView ()

@property (nonatomic, strong) NSTextField *deviceLabel;
@property (nonatomic, strong) NSTextField *volumeLabel;
@property (nonatomic, strong) NSTextField *levelLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSImageView *lowVolumeIcon;
@property (nonatomic, strong) NSImageView *highVolumeIcon;
@property (nonatomic, strong, readwrite) NSSlider *volumeSlider;
@property (nonatomic, strong, readwrite) NSButton *muteCheckbox;
@property (nonatomic, strong) MLAudioLevelMeterView *levelMeterView;

@end

@implementation MLAudioInputStatusView

- (instancetype)initWithTarget:(id)target
                  volumeAction:(SEL)volumeAction
                    muteAction:(SEL)muteAction
{
    self = [super initWithFrame:NSMakeRect(0.0, 0.0, MLInputStatusViewWidth, MLInputStatusViewHeight)];
    if (self)
    {
        [self buildSubviewsWithTarget:target volumeAction:volumeAction muteAction:muteAction];
    }
    return self;
}

- (void)buildSubviewsWithTarget:(id)target volumeAction:(SEL)volumeAction muteAction:(SEL)muteAction
{
    self.deviceLabel = [self labelWithString:@"Input health" font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium]];
    self.deviceLabel.textColor = [NSColor secondaryLabelColor];
    [self addSubview:self.deviceLabel];

    self.volumeLabel = [self labelWithString:@"Input volume" font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular]];
    [self addSubview:self.volumeLabel];

    self.levelLabel = [self labelWithString:@"Input level" font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular]];
    [self addSubview:self.levelLabel];

    self.statusLabel = [self labelWithString:@"Open menu to test" font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular]];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    [self addSubview:self.statusLabel];

    self.lowVolumeIcon = [self iconViewWithSymbolName:@"mic"];
    self.highVolumeIcon = [self iconViewWithSymbolName:@"mic.fill"];
    [self addSubview:self.lowVolumeIcon];
    [self addSubview:self.highVolumeIcon];

    self.volumeSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    self.volumeSlider.minValue = 0.0;
    self.volumeSlider.maxValue = 1.0;
    self.volumeSlider.doubleValue = 0.0;
    self.volumeSlider.continuous = YES;
    self.volumeSlider.target = target;
    self.volumeSlider.action = volumeAction;
    self.volumeSlider.controlSize = NSControlSizeSmall;
    [self addSubview:self.volumeSlider];

    self.muteCheckbox = [NSButton checkboxWithTitle:@"Muted" target:target action:muteAction];
    self.muteCheckbox.controlSize = NSControlSizeSmall;
    self.muteCheckbox.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    self.muteCheckbox.toolTip = @"Reflects the device's live mute state. Toggle to mute or unmute the active input directly.";
    [self addSubview:self.muteCheckbox];

    self.levelMeterView = [[MLAudioLevelMeterView alloc] initWithFrame:NSZeroRect];
    [self addSubview:self.levelMeterView];
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font
{
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSImageView *)iconViewWithSymbolName:(NSString *)symbolName
{
    NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                               weight:NSFontWeightRegular
                                                                                                scale:NSImageSymbolScaleMedium];
    NSImage *image = [[NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil] imageWithSymbolConfiguration:configuration];
    image.template = YES;

    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    imageView.image = image;
    imageView.contentTintColor = [NSColor secondaryLabelColor];
    return imageView;
}

- (void)layout
{
    [super layout];

    CGFloat left = 16.0;
    CGFloat labelWidth = 116.0;
    CGFloat controlLeft = left + labelWidth + 6.0;
    CGFloat right = 16.0;
    CGFloat iconSize = 18.0;
    CGFloat controlRight = NSWidth(self.bounds) - right;
    CGFloat sliderLeft = controlLeft + iconSize + 8.0;
    CGFloat sliderRight = controlRight - iconSize - 8.0;

    CGFloat muteWidth = 72.0;
    [self.muteCheckbox sizeToFit];
    muteWidth = MAX(muteWidth, NSWidth(self.muteCheckbox.frame));
    self.muteCheckbox.frame = NSMakeRect(NSWidth(self.bounds) - right - muteWidth, 84.0, muteWidth, 18.0);
    self.deviceLabel.frame = NSMakeRect(left, 86.0, NSWidth(self.bounds) - left - right - muteWidth - 8.0, 16.0);

    self.volumeLabel.frame = NSMakeRect(left, 57.0, labelWidth, 24.0);
    self.lowVolumeIcon.frame = NSMakeRect(controlLeft, 60.0, iconSize, iconSize);
    self.highVolumeIcon.frame = NSMakeRect(controlRight - iconSize, 60.0, iconSize, iconSize);
    self.volumeSlider.frame = NSMakeRect(sliderLeft, 56.0, sliderRight - sliderLeft, 24.0);

    self.levelLabel.frame = NSMakeRect(left, 25.0, labelWidth, 24.0);
    self.levelMeterView.frame = NSMakeRect(controlLeft, 24.0, controlRight - controlLeft, 28.0);
    self.statusLabel.frame = NSMakeRect(controlLeft, 6.0, controlRight - controlLeft, 16.0);
}

- (void)updateWithDeviceName:(NSString *)deviceName
                  statusText:(NSString *)statusText
                       level:(CGFloat)level
                 inputVolume:(Float32)inputVolume
             volumeAvailable:(BOOL)volumeAvailable
                       muted:(BOOL)muted
               muteAvailable:(BOOL)muteAvailable
         monitoringAvailable:(BOOL)monitoringAvailable
{
    NSString *safeDeviceName = deviceName.length > 0 ? deviceName : @"Current input";
    self.deviceLabel.stringValue = [NSString stringWithFormat:@"Input health - %@", safeDeviceName];
    self.statusLabel.stringValue = statusText.length > 0 ? statusText : @"Speak to test";

    self.muteCheckbox.enabled = muteAvailable;
    self.muteCheckbox.state = (muteAvailable && muted) ? NSControlStateValueOn : NSControlStateValueOff;
    self.muteCheckbox.alphaValue = muteAvailable ? 1.0 : 0.35;

    self.volumeSlider.enabled = volumeAvailable;
    self.volumeSlider.doubleValue = MIN(1.0, MAX(0.0, inputVolume));
    self.lowVolumeIcon.alphaValue = volumeAvailable ? 1.0 : 0.35;
    self.highVolumeIcon.alphaValue = volumeAvailable ? 1.0 : 0.35;

    self.levelMeterView.monitoringAvailable = monitoringAvailable;
    self.levelMeterView.level = level;
    self.levelMeterView.alphaValue = monitoringAvailable ? 1.0 : 0.45;
}

@end
