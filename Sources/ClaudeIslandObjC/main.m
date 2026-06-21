#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/sysctl.h>

static NSString *const ClaudeIslandStatusPath = @"~/.claude/claude-island/status.json";
static NSString *const ClaudeIslandPositionModeKey = @"ClaudeIslandPositionMode";
static NSString *const ClaudeIslandFixedOffsetXKey = @"ClaudeIslandFixedOffsetX";
static NSString *const ClaudeIslandFixedOffsetYKey = @"ClaudeIslandFixedOffsetY";
static NSString *const ClaudeIslandPositionFixedKey = @"ClaudeIslandPositionFixed";
static NSString *const ClaudeIslandPositionDraggableKey = @"ClaudeIslandPositionDraggable";
static CGFloat const ClaudeIslandDefaultWidth = 170.0;
static CGFloat const ClaudeIslandDefaultHeight = 38.0;
static CGFloat const ClaudeIslandCameraBodyWidth = 118.0;
static CGFloat const ClaudeIslandCameraHeight = 32.5;
static CGFloat const ClaudeIslandFusionWingWidth = 18.0;
static CGFloat const ClaudeIslandCameraOverlap = 2.0;
static CGFloat const ClaudeIslandTopBleed = 2.0;
static CGFloat const ClaudeIslandInverseCornerRadius = 17.0;
static CGFloat const ClaudeIslandCameraExpandedBodyWidth = 154.0;
static NSTimeInterval const ClaudeIslandOfflineAfterSeconds = 600.0;
static NSTimeInterval const ClaudeIslandConfirmationReminderInterval = 12.0;

@interface IslandView : NSView
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) NSColor *dotColor;
@property(nonatomic) CGFloat pulsePhase;
@property(nonatomic, weak) id clickTarget;
@property(nonatomic) SEL clickAction;
@property(nonatomic, weak) id menuTarget;
@property(nonatomic, copy) NSString *positionMode;
@end

@implementation IslandView {
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _state = @"offline";
        _title = @"离线";
        _dotColor = [NSColor colorWithCalibratedRed:0.52 green:0.55 blue:0.61 alpha:1.0];
        _positionMode = ClaudeIslandPositionDraggableKey;
        _pulsePhase = 0.0;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    self.alphaValue = 0.96;
}

- (void)mouseExited:(NSEvent *)event {
    self.alphaValue = 1.0;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.type == NSEventTypeRightMouseDown || (event.modifierFlags & NSEventModifierFlagControl)) {
        [self showPositionMenu:event];
        return;
    }

    if (self.clickTarget && self.clickAction && [self.clickTarget respondsToSelector:self.clickAction]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.clickTarget performSelector:self.clickAction withObject:self];
#pragma clang diagnostic pop
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    [self showPositionMenu:event];
}

- (void)showPositionMenu:(NSEvent *)event {
    if (!self.menuTarget) {
        return;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"位置"];
    [self addPositionItemWithTitle:@"可拖动" mode:ClaudeIslandPositionDraggableKey menu:menu];
    [self addPositionItemWithTitle:@"固定" mode:ClaudeIslandPositionFixedKey menu:menu];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self nudgeMenuItemWithTitle:@"向左 1px" dx:-1 dy:0]];
    [menu addItem:[self nudgeMenuItemWithTitle:@"向右 1px" dx:1 dy:0]];
    [menu addItem:[self nudgeMenuItemWithTitle:@"向上 1px" dx:0 dy:1]];
    [menu addItem:[self nudgeMenuItemWithTitle:@"向下 1px" dx:0 dy:-1]];
    [menu addItem:[self resetOffsetMenuItem]];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 Claude Island"
                                                      action:@selector(quitClaudeIsland:)
                                               keyEquivalent:@""];
    quitItem.target = self.menuTarget;
    [menu addItem:quitItem];

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)addPositionItemWithTitle:(NSString *)title mode:(NSString *)mode menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(selectPositionMode:)
                                           keyEquivalent:@""];
    item.target = self.menuTarget;
    item.representedObject = mode;
    NSString *currentMode = [[NSUserDefaults standardUserDefaults] stringForKey:ClaudeIslandPositionModeKey] ?: ClaudeIslandPositionDraggableKey;
    item.state = [currentMode isEqualToString:mode] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
}

- (NSMenuItem *)nudgeMenuItemWithTitle:(NSString *)title dx:(NSInteger)dx dy:(NSInteger)dy {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(nudgeFixedPosition:)
                                           keyEquivalent:@""];
    item.target = self.menuTarget;
    item.representedObject = @{@"dx": @(dx), @"dy": @(dy)};
    return item;
}

- (NSMenuItem *)resetOffsetMenuItem {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"重置微调"
                                                  action:@selector(resetFixedPositionOffset:)
                                           keyEquivalent:@""];
    item.target = self.menuTarget;
    return item;
}

- (void)setState:(NSString *)state title:(NSString *)title dotColor:(NSColor *)dotColor pulsePhase:(CGFloat)pulsePhase {
    _state = [state copy];
    _title = [title copy];
    _dotColor = dotColor;
    _pulsePhase = pulsePhase;
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    CGFloat horizontalInset = bounds.size.height > 45.0 ? 0.0 : 1.0;
    CGFloat verticalInset = bounds.size.height > 45.0 ? 0.0 : 1.0;
    NSRect capsuleRect = NSInsetRect(bounds, horizontalInset, verticalInset);
    NSBezierPath *capsule = [self islandShapeForRect:capsuleRect];
    BOOL cameraFusion = [self isCameraFusionMode];
    NSColor *fillColor = cameraFusion
        ? [NSColor colorWithCalibratedWhite:0.0 alpha:0.98]
        : [NSColor colorWithCalibratedWhite:0.02 alpha:0.88];
    [fillColor setFill];
    [capsule fill];
    [self drawFusionWingIfNeededInRect:capsuleRect];
    [self drawConfirmationRingIfNeededForPath:capsule inRect:capsuleRect];

    if (!cameraFusion) {
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.14] setStroke];
        [capsule setLineWidth:1.0];
        [capsule stroke];
    }

    CGFloat contentOffset = [self contentOffsetForFusionMode];
    CGFloat contentCenterY = cameraFusion ? bounds.size.height / 2.0 + 1.0 : bounds.size.height / 2.0;
    NSPoint dotCenter = NSMakePoint(contentOffset + (cameraFusion ? 28 : 30), contentCenterY);
    [self drawLuminousCoreAt:dotCenter];

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:(cameraFusion ? 14 : 15) weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize textSize = [self.title sizeWithAttributes:attributes];
    CGFloat textX = contentOffset + (cameraFusion ? 44 : 46);
    CGFloat textWidth = MAX(40, bounds.size.width - textX - 10);
    NSRect textRect = NSMakeRect(textX, contentCenterY - textSize.height / 2.0 - 0.5, textWidth, textSize.height);
    [self.title drawInRect:textRect withAttributes:attributes];
}

- (BOOL)needsConfirmationAttention {
    return [self.state isEqualToString:@"waiting"] || [self.state isEqualToString:@"permission"];
}

- (void)drawConfirmationRingIfNeededForPath:(NSBezierPath *)path inRect:(NSRect)rect {
    if (![self needsConfirmationAttention]) {
        return;
    }

    CGFloat breath = (sin(self.pulsePhase * 1.35) + 1.0) / 2.0;
    NSColor *ringColor = [NSColor colorWithCalibratedRed:1.0
                                                   green:0.72
                                                    blue:0.24
                                                   alpha:0.42 + breath * 0.38];
    [ringColor setStroke];
    [path setLineWidth:1.4 + breath * 0.7];
    [path stroke];

    NSRect glowRect = NSInsetRect(rect, -2.0 - breath * 1.4, -2.0 - breath * 1.4);
    NSBezierPath *glow = [self islandShapeForRect:glowRect];
    [[NSColor colorWithCalibratedRed:1.0 green:0.66 blue:0.18 alpha:0.10 + breath * 0.12] setStroke];
    [glow setLineWidth:2.0];
    [glow stroke];
}

- (BOOL)isCameraFusionMode {
    return [self.positionMode isEqualToString:ClaudeIslandPositionFixedKey];
}

- (CGFloat)contentOffsetForFusionMode {
    return 0.0;
}

- (void)drawFusionWingIfNeededInRect:(NSRect)rect {
    if (![self isCameraFusionMode]) {
        return;
    }

    NSRect wingRect = NSZeroRect;
    wingRect = NSMakeRect(NSMaxX(rect) - ClaudeIslandFusionWingWidth - 1.0,
                          NSMinY(rect),
                          ClaudeIslandFusionWingWidth + 1.0,
                          rect.size.height);

    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.98] setFill];
    NSRectFill(wingRect);
}

- (NSBezierPath *)islandShapeForRect:(NSRect)rect {
    BOOL fixedFusion = [self.positionMode isEqualToString:ClaudeIslandPositionFixedKey];
    if (!fixedFusion) {
        return [NSBezierPath bezierPathWithRoundedRect:rect
                                               xRadius:rect.size.height / 2.0
                                               yRadius:rect.size.height / 2.0];
    }

    CGFloat radius = MIN(ClaudeIslandInverseCornerRadius, rect.size.height);
    CGFloat left = NSMinX(rect);
    CGFloat right = NSMaxX(rect);
    CGFloat top = NSMinY(rect);
    CGFloat bottom = NSMaxY(rect);
    CGFloat control = radius * 0.64;

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(right, top)];
    [path lineToPoint:NSMakePoint(left, top)];
    [path lineToPoint:NSMakePoint(left, bottom - radius)];
    [path curveToPoint:NSMakePoint(left + radius, bottom)
         controlPoint1:NSMakePoint(left, bottom - radius + control)
         controlPoint2:NSMakePoint(left + radius - control, bottom)];
    [path lineToPoint:NSMakePoint(right, bottom)];
    [path closePath];

    return path;
}

- (void)drawLuminousCoreAt:(NSPoint)center {
    BOOL animated = [self usesBreathingCore];
    CGFloat breath = animated ? (sin(self.pulsePhase) + 1.0) / 2.0 : 0.35;
    CGFloat errorShake = [self.state isEqualToString:@"error"] ? sin(self.pulsePhase * 6.0) * 1.2 : 0.0;
    NSPoint coreCenter = NSMakePoint(center.x + errorShake, center.y);

    NSColor *primary = self.dotColor;
    NSColor *secondary = [self coreSecondaryColor];

    CGFloat auraSize = 18.0 + breath * 8.0;
    CGFloat haloSize = 12.0 + breath * 3.0;
    CGFloat coreSize = 7.5 + breath * 1.4;

    NSRect auraRect = NSMakeRect(coreCenter.x - auraSize / 2.0,
                                 coreCenter.y - auraSize / 2.0,
                                 auraSize,
                                 auraSize);
    NSGradient *auraGradient = [[NSGradient alloc] initWithColors:@[
        [primary colorWithAlphaComponent:animated ? 0.22 + breath * 0.16 : 0.18],
        [primary colorWithAlphaComponent:0.06],
        [NSColor clearColor]
    ]];
    [auraGradient drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:auraRect] relativeCenterPosition:NSZeroPoint];

    NSRect haloRect = NSMakeRect(coreCenter.x - haloSize / 2.0,
                                 coreCenter.y - haloSize / 2.0,
                                 haloSize,
                                 haloSize);
    NSGradient *haloGradient = [[NSGradient alloc] initWithColors:@[
        [secondary colorWithAlphaComponent:0.42],
        [primary colorWithAlphaComponent:0.18],
        [NSColor clearColor]
    ]];
    [haloGradient drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:haloRect] angle:90.0];

    NSRect coreRect = NSMakeRect(coreCenter.x - coreSize / 2.0,
                                 coreCenter.y - coreSize / 2.0,
                                 coreSize,
                                 coreSize);
    NSGradient *coreGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedWhite:1.0 alpha:0.92],
        [secondary colorWithAlphaComponent:0.96],
        [primary colorWithAlphaComponent:1.0]
    ]];
    [coreGradient drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:coreRect] angle:135.0];

    NSRect glintRect = NSMakeRect(coreCenter.x - coreSize * 0.28,
                                  coreCenter.y - coreSize * 0.34,
                                  coreSize * 0.36,
                                  coreSize * 0.24);
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.68] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:glintRect] fill];
}

- (NSColor *)coreSecondaryColor {
    if ([self.state isEqualToString:@"thinking"]) return [NSColor colorWithCalibratedRed:0.58 green:0.38 blue:1.0 alpha:1.0];
    if ([self.state isEqualToString:@"running"]) return [NSColor colorWithCalibratedRed:0.30 green:0.95 blue:0.78 alpha:1.0];
    if ([self.state isEqualToString:@"waiting"]) return [NSColor colorWithCalibratedRed:1.0 green:0.86 blue:0.36 alpha:1.0];
    if ([self.state isEqualToString:@"permission"]) return [NSColor colorWithCalibratedRed:1.0 green:0.70 blue:0.34 alpha:1.0];
    if ([self.state isEqualToString:@"error"]) return [NSColor colorWithCalibratedRed:1.0 green:0.45 blue:0.48 alpha:1.0];
    if ([self.state isEqualToString:@"ready"]) return [NSColor colorWithCalibratedRed:0.58 green:0.96 blue:0.66 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.72 green:0.74 blue:0.78 alpha:1.0];
}

- (BOOL)usesBreathingCore {
    return [@[@"thinking", @"running", @"permission", @"waiting"] containsObject:self.state];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSPanel *window;
@property(nonatomic, strong) IslandView *islandView;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *positionMode;
@property(nonatomic) CGFloat pulsePhase;
@property(nonatomic) NSTimeInterval lastStatusReadAt;
@property(nonatomic) NSTimeInterval lastSoundAt;
@property(nonatomic) NSTimeInterval lastConfirmationReminderAt;
@property(nonatomic) NSTimeInterval stateEnteredAt;
@property(nonatomic, copy) NSString *currentState;
@property(nonatomic, copy) NSString *lastSoundState;
@property(nonatomic) BOOL didLoadInitialState;
@property(nonatomic) BOOL confirmationAcknowledged;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.currentState = @"offline";
    self.stateEnteredAt = [[NSDate date] timeIntervalSince1970];
    self.positionMode = [self normalizedPositionMode:[[NSUserDefaults standardUserDefaults] stringForKey:ClaudeIslandPositionModeKey]];
    [self createWindow];
    [self refreshStatus:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                  target:self
                                                selector:@selector(refreshStatus:)
                                                userInfo:nil
                                                 repeats:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersDidChange:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)createWindow {
    NSSize size = [self windowSizeForPositionMode:self.positionMode];
    NSRect frame = NSMakeRect(0, 0, size.width, size.height);

    self.window = [[NSPanel alloc] initWithContentRect:frame
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.opaque = NO;
    self.window.backgroundColor = [NSColor clearColor];
    self.window.hasShadow = YES;
    self.window.level = NSStatusWindowLevel;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                     NSWindowCollectionBehaviorFullScreenAuxiliary |
                                     NSWindowCollectionBehaviorStationary;
    self.window.movableByWindowBackground = [self.positionMode isEqualToString:ClaudeIslandPositionDraggableKey];
    self.window.hidesOnDeactivate = NO;

    self.islandView = [[IslandView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    self.islandView.clickTarget = self;
    self.islandView.clickAction = @selector(openClaudeInterface:);
    self.islandView.menuTarget = self;
    self.islandView.positionMode = self.positionMode;
    self.window.contentView = self.islandView;
    [self applyPositionModeAnimated:NO];
    [self.window orderFrontRegardless];
}

- (void)screenParametersDidChange:(NSNotification *)notification {
    [self applyPositionModeAnimated:NO];
}

- (void)selectPositionMode:(NSMenuItem *)sender {
    NSString *mode = sender.representedObject;
    if (![mode isKindOfClass:NSString.class]) {
        return;
    }

    self.positionMode = [self normalizedPositionMode:mode];
    [[NSUserDefaults standardUserDefaults] setObject:self.positionMode forKey:ClaudeIslandPositionModeKey];
    [self applyPositionModeAnimated:YES];
}

- (NSString *)normalizedPositionMode:(NSString *)mode {
    if ([mode isEqualToString:ClaudeIslandPositionDraggableKey]) {
        return ClaudeIslandPositionDraggableKey;
    }

    return ClaudeIslandPositionFixedKey;
}

- (void)quitClaudeIsland:(id)sender {
    [NSApp terminate:nil];
}

- (void)nudgeFixedPosition:(NSMenuItem *)sender {
    NSDictionary *delta = sender.representedObject;
    if (![delta isKindOfClass:NSDictionary.class]) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger currentX = [defaults integerForKey:ClaudeIslandFixedOffsetXKey];
    NSInteger currentY = [defaults integerForKey:ClaudeIslandFixedOffsetYKey];
    NSInteger dx = [delta[@"dx"] integerValue];
    NSInteger dy = [delta[@"dy"] integerValue];

    [defaults setInteger:currentX + dx forKey:ClaudeIslandFixedOffsetXKey];
    [defaults setInteger:currentY + dy forKey:ClaudeIslandFixedOffsetYKey];

    self.positionMode = ClaudeIslandPositionFixedKey;
    [defaults setObject:self.positionMode forKey:ClaudeIslandPositionModeKey];
    [self applyPositionModeAnimated:NO];
}

- (void)resetFixedPositionOffset:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:0 forKey:ClaudeIslandFixedOffsetXKey];
    [defaults setInteger:0 forKey:ClaudeIslandFixedOffsetYKey];

    self.positionMode = ClaudeIslandPositionFixedKey;
    [defaults setObject:self.positionMode forKey:ClaudeIslandPositionModeKey];
    [self applyPositionModeAnimated:NO];
}

- (void)applyPositionModeAnimated:(BOOL)animated {
    if (!self.window) {
        return;
    }

    self.window.movableByWindowBackground = [self.positionMode isEqualToString:ClaudeIslandPositionDraggableKey];
    self.islandView.positionMode = self.positionMode;
    NSRect frame = self.window.frame;
    NSSize targetSize = [self windowSizeForPositionMode:self.positionMode];
    frame.size = targetSize;

    if ([self.positionMode isEqualToString:ClaudeIslandPositionDraggableKey]) {
        frame.origin.y += self.window.frame.size.height - targetSize.height;
        [self.islandView setFrameSize:targetSize];
        if (animated) {
            [self.window.animator setFrame:frame display:YES];
        } else {
            [self.window setFrame:frame display:YES];
        }
        return;
    }

    frame.origin = [self originForPositionMode:self.positionMode windowSize:frame.size];
    [self.islandView setFrameSize:targetSize];

    if (animated) {
        [self.window.animator setFrame:frame display:YES];
    } else {
        [self.window setFrame:frame display:YES];
    }
}

- (NSSize)windowSizeForPositionMode:(NSString *)mode {
    CGFloat width = [self bodyWidthForState:self.currentState positionMode:mode];
    if ([mode isEqualToString:ClaudeIslandPositionFixedKey]) {
        return NSMakeSize(width + ClaudeIslandFusionWingWidth, ClaudeIslandCameraHeight + ClaudeIslandTopBleed);
    }

    return NSMakeSize(width, ClaudeIslandDefaultHeight);
}

- (CGFloat)bodyWidthForState:(NSString *)state positionMode:(NSString *)mode {
    BOOL fixed = [mode isEqualToString:ClaudeIslandPositionFixedKey];
    CGFloat baseWidth = fixed ? ClaudeIslandCameraBodyWidth : ClaudeIslandDefaultWidth;

    if ([state isEqualToString:@"waiting"] || [state isEqualToString:@"permission"] || [state isEqualToString:@"error"]) {
        return fixed ? ClaudeIslandCameraExpandedBodyWidth : 190.0;
    }

    if ([state isEqualToString:@"running"] || [state isEqualToString:@"thinking"]) {
        return fixed ? 136.0 : 182.0;
    }

    return baseWidth;
}

- (NSPoint)originForPositionMode:(NSString *)mode windowSize:(NSSize)size {
    NSRect fullFrame = NSScreen.mainScreen.frame;
    NSRect visibleFrame = NSScreen.mainScreen.visibleFrame;
    CGFloat centerX = NSMidX(visibleFrame);
    CGFloat y = NSMaxY(visibleFrame) - size.height - 8.0;
    CGFloat x = centerX - size.width / 2.0;

    if ([mode isEqualToString:ClaudeIslandPositionFixedKey]) {
        CGFloat bodyWidth = [self bodyWidthForState:self.currentState positionMode:mode];
        NSRect leftArea = NSScreen.mainScreen.auxiliaryTopLeftArea;
        if (!NSIsEmptyRect(leftArea)) {
            x = NSMaxX(leftArea) - bodyWidth + ClaudeIslandCameraOverlap;
            y = NSMaxY(leftArea) - size.height + ClaudeIslandTopBleed;
        } else {
            centerX = NSMidX(fullFrame);
            x = centerX - bodyWidth + ClaudeIslandCameraOverlap;
            y = NSMaxY(fullFrame) - size.height + ClaudeIslandTopBleed;
        }
    }

    CGFloat minX = NSMinX(fullFrame) + 8.0;
    CGFloat maxX = NSMaxX(fullFrame) - size.width - 8.0;
    x = MIN(MAX(x, minX), maxX);

    if ([mode isEqualToString:ClaudeIslandPositionFixedKey]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        x += [defaults integerForKey:ClaudeIslandFixedOffsetXKey];
        y += [defaults integerForKey:ClaudeIslandFixedOffsetYKey];
    }

    return NSMakePoint(x, y);
}

- (void)refreshStatus:(NSTimer *)timer {
    self.pulsePhase += 0.08;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    if (self.lastStatusReadAt == 0 || now - self.lastStatusReadAt >= 0.25) {
        self.lastStatusReadAt = now;
        NSString *expandedPath = [ClaudeIslandStatusPath stringByExpandingTildeInPath];
        NSData *data = [NSData dataWithContentsOfFile:expandedPath];
        NSString *state = @"offline";

        if (data) {
            NSError *error = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (!error && [json isKindOfClass:NSDictionary.class]) {
                NSString *decodedState = json[@"state"];
                NSNumber *updatedAt = json[@"updatedAt"];
                NSTimeInterval age = now - updatedAt.doubleValue;
                if ([decodedState isKindOfClass:NSString.class] && age <= ClaudeIslandOfflineAfterSeconds) {
                    state = decodedState;
                }
            }
        }

        if (![state isEqualToString:self.currentState]) {
            self.stateEnteredAt = now;
            self.currentState = state;
            self.confirmationAcknowledged = NO;
            if (![self stateNeedsConfirmation:state]) {
                self.lastConfirmationReminderAt = 0;
            }
            [self applyPositionModeAnimated:YES];
        } else {
            self.currentState = state;
        }

        [self playSoundIfNeededForState:state now:now];
    }

    [self playConfirmationReminderIfNeededForState:self.currentState now:now];

    [self.islandView setState:self.currentState
                        title:[self displayTitleForState:self.currentState now:now]
                     dotColor:[self colorForState:self.currentState]
                   pulsePhase:self.pulsePhase];
}

- (NSString *)displayTitleForState:(NSString *)state now:(NSTimeInterval)now {
    NSString *title = [self titleForState:state];
    if ([state isEqualToString:@"running"] || [state isEqualToString:@"thinking"]) {
        return [NSString stringWithFormat:@"%@ %@", title, [self compactDurationSince:self.stateEnteredAt now:now]];
    }

    return title;
}

- (NSString *)titleForState:(NSString *)state {
    if ([state isEqualToString:@"ready"]) return @"就绪";
    if ([state isEqualToString:@"thinking"]) return @"思考中";
    if ([state isEqualToString:@"running"]) return @"执行中";
    if ([state isEqualToString:@"waiting"]) return @"等你输入";
    if ([state isEqualToString:@"permission"]) return @"需授权";
    if ([state isEqualToString:@"error"]) return @"出错";
    return @"离线";
}

- (NSString *)compactDurationSince:(NSTimeInterval)start now:(NSTimeInterval)now {
    NSInteger elapsed = MAX(0, (NSInteger)floor(now - start));
    NSInteger minutes = elapsed / 60;
    NSInteger seconds = elapsed % 60;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (NSColor *)colorForState:(NSString *)state {
    if ([state isEqualToString:@"ready"]) return [NSColor colorWithCalibratedRed:0.34 green:0.84 blue:0.47 alpha:1.0];
    if ([state isEqualToString:@"thinking"]) return [NSColor colorWithCalibratedRed:0.23 green:0.54 blue:0.98 alpha:1.0];
    if ([state isEqualToString:@"running"]) return [NSColor colorWithCalibratedRed:0.18 green:0.72 blue:0.78 alpha:1.0];
    if ([state isEqualToString:@"waiting"]) return [NSColor colorWithCalibratedRed:1.0 green:0.69 blue:0.22 alpha:1.0];
    if ([state isEqualToString:@"permission"]) return [NSColor colorWithCalibratedRed:1.0 green:0.52 blue:0.22 alpha:1.0];
    if ([state isEqualToString:@"error"]) return [NSColor colorWithCalibratedRed:1.0 green:0.29 blue:0.36 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.52 green:0.55 blue:0.61 alpha:1.0];
}

- (void)playSoundIfNeededForState:(NSString *)state now:(NSTimeInterval)now {
    if (!self.didLoadInitialState) {
        self.didLoadInitialState = YES;
        self.lastSoundState = state;
        return;
    }

    if ([state isEqualToString:self.lastSoundState]) {
        return;
    }

    self.lastSoundState = state;
    if ([self stateNeedsConfirmation:state]) {
        self.lastConfirmationReminderAt = now;
        [self playConfirmationAlert];
        return;
    }

    if (now - self.lastSoundAt < 0.8) {
        return;
    }

    self.lastSoundAt = now;
    NSSound *sound = [NSSound soundNamed:@"Ping"];
    [sound setVolume:0.42];
    [sound play];
}

- (BOOL)stateNeedsConfirmation:(NSString *)state {
    return [state isEqualToString:@"waiting"] || [state isEqualToString:@"permission"];
}

- (void)playConfirmationReminderIfNeededForState:(NSString *)state now:(NSTimeInterval)now {
    if (![self stateNeedsConfirmation:state]) {
        return;
    }

    if (self.confirmationAcknowledged) {
        return;
    }

    if (self.lastConfirmationReminderAt <= 0) {
        self.lastConfirmationReminderAt = now;
        return;
    }

    if (now - self.lastConfirmationReminderAt >= ClaudeIslandConfirmationReminderInterval) {
        self.lastConfirmationReminderAt = now;
        [self playConfirmationAlert];
    }
}

- (void)playConfirmationAlert {
    NSArray<NSNumber *> *delays = @[@0.0, @0.16, @0.32];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSSound *sound = [NSSound soundNamed:@"Glass"] ?: [NSSound soundNamed:@"Ping"];
            [sound setVolume:0.74];
            [sound play];
        });
    }
}

- (void)openClaudeInterface:(id)sender {
    if ([self stateNeedsConfirmation:self.currentState]) {
        self.confirmationAcknowledged = YES;
        self.lastConfirmationReminderAt = 0;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        pid_t hostPID = [self hostPIDForClaudeCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self activateHostPID:hostPID]) {
                return;
            }

            for (NSString *bundleIdentifier in [self fallbackBundleIdentifiers]) {
                NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier].firstObject;
                if (app && [app activateWithOptions:NSApplicationActivateIgnoringOtherApps]) {
                    return;
                }
            }

            NSBeep();
        });
    });
}

- (BOOL)activateHostPID:(pid_t)hostPID {
    if (hostPID <= 0) {
        return NO;
    }

    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:hostPID];
    return app && [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

- (pid_t)hostPIDForClaudeCode {
    NSDictionary<NSNumber *, NSDictionary *> *processes = [self processTable];
    pid_t claudePID = 0;

    for (NSNumber *pidNumber in processes) {
        NSDictionary *process = processes[pidNumber];
        NSString *command = process[@"command"] ?: @"";
        if ([self isClaudeCodeCommand:command]) {
            claudePID = pidNumber.intValue;
            break;
        }
    }

    if (claudePID <= 0) {
        return 0;
    }

    pid_t currentPID = claudePID;
    for (NSInteger depth = 0; depth < 16; depth++) {
        NSDictionary *process = processes[@(currentPID)];
        if (!process) {
            break;
        }

        pid_t parentPID = [process[@"ppid"] intValue];
        if (parentPID <= 1) {
            break;
        }

        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:parentPID];
        if (app && app.bundleIdentifier.length > 0 && ![app.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
            return parentPID;
        }

        currentPID = parentPID;
    }

    return 0;
}

- (NSDictionary<NSNumber *, NSDictionary *> *)processTable {
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t length = 0;

    if (sysctl(mib, 4, NULL, &length, NULL, 0) != 0 || length == 0) {
        return @{};
    }

    struct kinfo_proc *processList = malloc(length);
    if (!processList) {
        return @{};
    }

    if (sysctl(mib, 4, processList, &length, NULL, 0) != 0) {
        free(processList);
        return @{};
    }

    NSInteger processCount = (NSInteger)(length / sizeof(struct kinfo_proc));
    NSMutableDictionary *table = [NSMutableDictionary dictionary];

    for (NSInteger index = 0; index < processCount; index++) {
        struct kinfo_proc process = processList[index];
        pid_t pid = process.kp_proc.p_pid;
        pid_t ppid = process.kp_eproc.e_ppid;
        NSString *command = [NSString stringWithUTF8String:process.kp_proc.p_comm] ?: @"";

        table[@(pid)] = @{
            @"ppid": @(ppid),
            @"command": command
        };
    }

    free(processList);

    return table;
}

- (BOOL)isClaudeCodeCommand:(NSString *)command {
    NSString *lastPathComponent = command.lastPathComponent.lowercaseString;

    if ([lastPathComponent isEqualToString:@"claude"] ||
        [lastPathComponent isEqualToString:@"claude-code"] ||
        [lastPathComponent isEqualToString:@"claude-code.cmd"]) {
        return YES;
    }

    return NO;
}

- (NSArray<NSString *> *)fallbackBundleIdentifiers {
    return @[
        @"com.apple.Terminal",
        @"com.googlecode.iterm2",
        @"com.microsoft.VSCode",
        @"com.todesktop.230313mzl4w4u92",
        @"com.mitchellh.ghostty",
        @"dev.warp.Warp-Stable",
        @"com.github.wez.wezterm"
    ];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
