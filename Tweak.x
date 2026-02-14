#import <UIKit/UIKit.h>
#include <spawn.h>
#include <stdlib.h>
#include <unistd.h>

@interface CCUIModularControlCenterOverlayViewController : UIViewController
@end

@interface MTMaterialLayer : CALayer
@property (nonatomic, copy, readwrite) NSString *recipeName;
@property (atomic, assign, readonly) CGRect visibleRect;
@end

@interface MTMaterialView : UIView
@property (nonatomic, copy) NSString *recipeName;
@property (nonatomic, copy) NSString *groupNameBase;
@end

@interface CALayer ()
@property (atomic, assign, readwrite) id unsafeUnretainedDelegate;
@property (assign) BOOL continuousCorners;
@end

@interface CCUIContentModuleContentContainerView : UIView
@end

@interface UIView (CC18PrivateHierarchy)
- (UIViewController *)_viewControllerForAncestor;
@end

@interface UIView (CC18Private)
- (void)_setContinuousCornerRadius:(double)radius;
- (void)setContinuousCornerRadius:(double)radius;
@end

static Class CCUIContentModuleContentContainerViewClass;
static Class MTMaterialViewClass;
static Class CCUIButtonModuleViewClass;
static Class MRUNowPlayingViewClass;
static Class CCUIContinuousSliderViewClass;
static NSArray *MTMaterialRecipeNames;

static UIView *findSubviewOfClass(UIView *view, Class cls) {
    if (!cls) return nil;
    if ([view isKindOfClass:cls]) return view;
    for (UIView *sub in view.subviews) {
        UIView *m = findSubviewOfClass(sub, cls);
        if (m) return m;
    }
    return nil;
}

static BOOL cc18_shouldSkipModuleContainer(UIView *container) {
    if (!container) return YES;
    CGRect bounds = container.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    if (w >= 120 && h >= 120) {
        CGFloat ratio = (w > 0 && h > 0) ? (w / h) : 1;
        if (ratio >= 0.75 && ratio <= 1.35) return YES;
    }
    if (MRUNowPlayingViewClass && findSubviewOfClass(container, MRUNowPlayingViewClass) != nil) return YES;
    if ([container respondsToSelector:@selector(_viewControllerForAncestor)]) {
        UIViewController *vc = [container _viewControllerForAncestor];
        NSString *name = vc ? NSStringFromClass([vc class]) : @"";
        if ([name rangeOfString:@"Connectivity" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"MRUNowPlaying" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"Wireless" options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES;
    }
    return NO;
}

static BOOL cc18_isSliderPillShape(CGSize size) {
    CGFloat w = size.width, h = size.height;
    if (w < 1 || h < 1) return NO;
    CGFloat mn = fmin(w, h), mx = fmax(w, h);
    return (mx / mn > 2.0f) && (mn <= 130.0f);
}

static BOOL isControlCenterView(UIView *view) {
    for (UIView *v = view; v; v = v.superview)
        if ([NSStringFromClass([v class]) hasPrefix:@"CCUI"]) return YES;
    return NO;
}

static CGFloat calculatedRadius(CGRect visibleRect, CGFloat radius) {
    CGFloat width = visibleRect.size.width;
    CGFloat height = visibleRect.size.height;
    if (CGSizeEqualToSize(visibleRect.size, [UIScreen mainScreen].bounds.size) || width <= 60 || height <= 60) return radius;
    if (height >= 300 && height <= 400 && width >= 100 && width <= 200) return radius;
    if ((fabs(width - height) < 1.0 || width >= 250) && height <= 76) return floor(MIN(width, height) / 2.0);
    if (width <= 120 && height > 200) return floor(MIN(width, height) / 2.0);
    return 25;
}

static CGFloat radiusForModuleButton(CGSize size);

static BOOL cc18_layerViewHasWindow(CALayer *layer) {
    id d = layer.delegate;
    if (!d || ![d respondsToSelector:@selector(window)]) return NO;
    return [(UIView *)d window] != nil;
}

%hook MTMaterialLayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    if (!cc18_layerViewHasWindow(self)) return radius;
    if ([MTMaterialRecipeNames containsObject:self.recipeName])
        radius = calculatedRadius(self.visibleRect, radius);
    return radius;
}
- (void)setCornerRadius:(CGFloat)radius {
    if (!cc18_layerViewHasWindow(self)) { %orig(radius); return; }
    if ([MTMaterialRecipeNames containsObject:self.recipeName])
        radius = calculatedRadius(self.visibleRect, radius);
    %orig(radius);
}
%end

%hook MTMaterialView
- (void)layoutSubviews {
    %orig;
    if (!self.window) return;
    for (UIView *v = self.superview; v; v = v.superview) {
        if (![v isKindOfClass:CCUIContentModuleContentContainerViewClass]) continue;
        if (cc18_shouldSkipModuleContainer(v)) return;
        break;
    }
    NSString *recipe = self.recipeName;
    NSString *group = self.groupNameBase;
    BOOL isCCModule = [recipe isEqualToString:@"modules"] ||
        [recipe isEqualToString:@"moduleFill.highlight.generatedRecipe"] ||
        (group.length && [group rangeOfString:@"ControlCenter" options:NSCaseInsensitiveSearch].location != NSNotFound);
    if (!isCCModule || CGRectIsEmpty(self.bounds)) return;
    CGRect b = self.bounds;
    BOOL isPill = cc18_isSliderPillShape(b.size);
    BOOL isSmallTile = (b.size.width <= 100 && b.size.height <= 100);
    if (!isPill && !isSmallTile) return;
    CGFloat r = radiusForModuleButton(b.size);
    self.layer.cornerRadius = r;
    self.layer.continuousCorners = YES;
    self.layer.masksToBounds = YES;
    self.clipsToBounds = YES;
}
%end

%hook CALayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    if (!cc18_layerViewHasWindow(self)) return radius;
    if ([self.superlayer.unsafeUnretainedDelegate isKindOfClass:CCUIButtonModuleViewClass])
        radius = calculatedRadius(self.visibleRect, radius);
    return radius;
}
- (void)setCornerRadius:(CGFloat)radius {
    if (!cc18_layerViewHasWindow(self)) { %orig(radius); return; }
    if ([self.superlayer.unsafeUnretainedDelegate isKindOfClass:CCUIButtonModuleViewClass])
        radius = calculatedRadius(self.visibleRect, radius);
    %orig(radius);
}
%end

static void applyCC18Radius(UIView *self, double *radiusPtr) {
    if (!isControlCenterView(self)) return;
    CGRect rect = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    *radiusPtr = (double)calculatedRadius(rect, (CGFloat)*radiusPtr);
}

%hook UIView
- (void)_setContinuousCornerRadius:(double)radius {
    applyCC18Radius(self, &radius);
    %orig(radius);
}
- (void)setContinuousCornerRadius:(double)radius {
    applyCC18Radius(self, &radius);
    %orig(radius);
}
%end

static void applyRadiusToMaterialViewsOnly(UIView *view, CGFloat radius, NSInteger depth) {
    if (depth > 6 || !view.window) return;
    if ([view isKindOfClass:MTMaterialViewClass]) {
        view.layer.cornerRadius = radius;
        view.layer.continuousCorners = YES;
        view.layer.masksToBounds = YES;
        view.clipsToBounds = YES;
    }
    for (UIView *sub in [view.subviews copy])
        applyRadiusToMaterialViewsOnly(sub, radius, depth + 1);
}

static void applyRadiusToSliderBackgroundOnly(UIView *view, CGFloat radius, NSInteger depth) {
    if (depth > 8 || !view.window) return;
    if (CCUIContinuousSliderViewClass && [view isKindOfClass:CCUIContinuousSliderViewClass]) {
        view.layer.cornerRadius = radius;
        view.layer.continuousCorners = YES;
        view.layer.masksToBounds = YES;
        view.clipsToBounds = YES;
    }
    for (UIView *sub in [view.subviews copy])
        applyRadiusToSliderBackgroundOnly(sub, radius, depth + 1);
}

static CGFloat radiusForModuleButton(CGSize size) {
    CGFloat w = size.width, h = size.height;
    if (w < 1 || h < 1) return 21.0;
    return fmin(w, h) / 2.0;
}

%hook CCUIContentModuleContentContainerView
- (void)layoutSubviews {
    %orig;
    if (!self.window || CGRectIsEmpty(self.bounds) || cc18_shouldSkipModuleContainer(self)) return;
    CGRect b = self.bounds;
    BOOL isPill = cc18_isSliderPillShape(b.size);
    BOOL isSmallTile = (b.size.width <= 100 && b.size.height <= 100);
    if (!isPill && !isSmallTile) return;
    CGFloat radius = radiusForModuleButton(self.bounds.size);
    self.layer.cornerRadius = radius;
    self.layer.continuousCorners = YES;
    self.layer.masksToBounds = YES;
    self.clipsToBounds = YES;
    if ([self respondsToSelector:@selector(setContinuousCornerRadius:)])
        [(id)self setContinuousCornerRadius:(double)radius];
    applyRadiusToMaterialViewsOnly(self, radius, 0);
    if (isPill) applyRadiusToSliderBackgroundOnly(self, radius, 0);
}
%end

static char *cc18_env[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/var/jb/usr/bin:/var/jb/bin", NULL };

static void cc18_run_argv(const char *path1, const char *path2, char *const argv[]) {
    pid_t pid;
    if (posix_spawnp(&pid, argv[0], NULL, NULL, argv, cc18_env) == 0) return;
    if (posix_spawn(&pid, path1, NULL, NULL, argv, cc18_env) == 0) return;
    if (path2) posix_spawn(&pid, path2, NULL, NULL, argv, cc18_env);
}

static void cc18_respring(void) {
    char *a[] = {"sbreload", NULL};
    cc18_run_argv("/usr/bin/sbreload", "/var/jb/usr/bin/sbreload", a);
}
static void cc18_uicache(void) {
    char *a[] = {"uicache", "-a", NULL};
    cc18_run_argv("/usr/bin/uicache", "/var/jb/usr/bin/uicache", a);
}
static void cc18_userspace_reboot(void) {
    char *a[] = {"launchctl", "reboot", "userspace", NULL};
    cc18_run_argv("/bin/launchctl", "/var/jb/bin/launchctl", a);
}

%hook CCUIModularControlCenterOverlayViewController
- (void)setPresentationState:(NSInteger)state {
    %orig;
    UIView *view = self.view;
    if (!view) return;
    CGFloat buttonSize = 20;
    CGFloat yOffset = 23;
    CGFloat safeRight = view.window.safeAreaInsets.right ?: 36;

    UIButton *power = [view viewWithTag:998];
    if (!power) {
        power = [UIButton buttonWithType:UIButtonTypeSystem];
        power.tag = 998;
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular];
        [power setImage:[[UIImage systemImageNamed:@"power"] imageByApplyingSymbolConfiguration:config] forState:UIControlStateNormal];
        power.tintColor = [UIColor systemRedColor];
        power.alpha = 0.0;
        power.transform = CGAffineTransformMakeScale(0.6, 0.6);
        if (@available(iOS 14.0, *)) {
            UIMenu *menu = [UIMenu menuWithTitle:@"" children:@[
                [UIAction actionWithTitle:@"Respring" image:[UIImage systemImageNamed:@"arrow.clockwise.circle"] identifier:nil handler:^(__kindof UIAction *a){ cc18_respring(); }],
                [UIAction actionWithTitle:@"UICache" image:[UIImage systemImageNamed:@"paintbrush.fill"] identifier:nil handler:^(__kindof UIAction *a){ cc18_uicache(); }],
                [UIAction actionWithTitle:@"Userspace Reboot" image:[UIImage systemImageNamed:@"bolt.fill"] identifier:nil handler:^(__kindof UIAction *a){ cc18_userspace_reboot(); }]
            ]];
            [power setMenu:menu];
            [power setShowsMenuAsPrimaryAction:YES];
        }
        [view addSubview:power];
    }
    power.frame = CGRectMake(view.bounds.size.width - safeRight - buttonSize - 10, yOffset - 10, buttonSize + 15, buttonSize + 15);
    if (state == 1) {
        [UIView animateWithDuration:0.45 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            power.alpha = 1.0;
            power.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else if (state == 3) {
        [UIView animateWithDuration:0.2 animations:^{
            power.alpha = 0.0;
            power.transform = CGAffineTransformMakeScale(0.6, 0.6);
        }];
    }
}
%end

%ctor {
    CCUIContentModuleContentContainerViewClass = NSClassFromString(@"CCUIContentModuleContentContainerView");
    MTMaterialViewClass = NSClassFromString(@"MTMaterialView");
    CCUIButtonModuleViewClass = NSClassFromString(@"CCUIButtonModuleView");
    MRUNowPlayingViewClass = NSClassFromString(@"MRUNowPlayingView");
    CCUIContinuousSliderViewClass = NSClassFromString(@"CCUIContinuousSliderView");
    MTMaterialRecipeNames = @[@"modules", @"moduleFill.highlight.generatedRecipe"];
}
