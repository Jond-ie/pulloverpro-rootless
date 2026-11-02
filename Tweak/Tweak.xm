// PullOver Pro (rootless) — SpringBoard hooks.
// Original by c1d3r (Will Smillie), GPL-3.0. iOS 15-27 rootless and RootHide support: Jond-ie.
// Changes from the original: the licence check, the What's New sheet and the
// activation alert are gone, and the window is attached to SpringBoard's scene.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "headers.h"
#import "PullOverWindow.h"
#import "POApplicationHelper.h"

static PullOverWindow *window;

@interface SpringBoard (PullOver)
- (void)addActiveOrientationObserver:(id)observer;
@end

// Hides the drawer in landscape when "Hide in Landscape" is on.
@interface POOrientationObserver : NSObject
+ (instancetype)shared;
@end

@implementation POOrientationObserver
+ (instancetype)shared {
    static POOrientationObserver *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}
- (void)activeInterfaceOrientationWillChangeToOrientation:(long long)orientation {}
- (void)activeInterfaceOrientationDidChangeToOrientation:(long long)orientation willAnimateWithDuration:(double)duration fromOrientation:(long long)from {
    if (!window || ![[POApplicationHelper settings][@"hideInLandscape"] boolValue]) return;
    BOOL portrait = (orientation == UIInterfaceOrientationPortrait);
    if (!portrait && [window.controller isOpened]) {
        [window.controller endHosting];
        [window.controller close];
    }
    [UIView animateWithDuration:0.2 animations:^{
        window.rootViewController.view.alpha = portrait ? 1 : 0;
    }];
}
@end

// Settings changed in the settings page: re-read them and rebuild the drawer
// so every option applies without a respring.
static void POPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [POApplicationHelper reloadSettings];
        BOOL enabled = [[POApplicationHelper settings][@"enabled"] boolValue];
        if (enabled && !window) {
            window = [PullOverWindow sharedWindow];
            [window makeKeyAndVisible];
        }
        [window applySettings];
    });
}

// "Close When Going Home" (on by default): the Home button, the home swipe and anything else
// that lands on the Home Screen tucks the pulled-over app away.
static BOOL POCloseOnHome(void) {
    return [[POApplicationHelper settings][@"closeOnHome"] boolValue];
}

// Commands from other tweaks (POShared.h). Ignored while the drawer is hidden:
// switched off, on the Lock Screen, or in landscape with "Hide in Landscape" on.
static void POCommand(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *command = [(__bridge NSString *)name lastPathComponent];
    dispatch_async(dispatch_get_main_queue(), ^{
        PullOverViewController *controller = window.controller;
        if (!controller || window.hidden || window.alpha == 0 || controller.view.alpha == 0) return;
        BOOL open = [command isEqualToString:@"open"] || ([command isEqualToString:@"toggle"] && !controller.isOpened);
        if (open) {
            if (controller.isOpened) return;
            if (controller.handle.isNubbed) controller.handle.isNubbed = NO;
            [controller open];
        } else if (controller.isOpened) {
            [controller close];
        }
    });
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(UIApplication *)arg1{
    %orig;

    if (![[POApplicationHelper settings][@"enabled"] boolValue]) return;

    window = [PullOverWindow sharedWindow];
    window.alpha = 0;
    [window makeKeyAndVisible];
    [window applySettings];

    // Orientation: SpringBoard's own observer list (same API on iOS 15-27)
    // instead of hooking noteInterfaceOrientationChanged:, which iOS 27 dropped.
    if ([self respondsToSelector:@selector(addActiveOrientationObserver:)]) {
        [self addActiveOrientationObserver:[POOrientationObserver shared]];
    }
}

// Remember the front app (nil = Home Screen). _accessibilityFrontMostApplication
// is not declared on iOS 27, frontDisplayDidChange: exists on 15-27.
-(void)frontDisplayDidChange:(id)display{
    %orig;
    NSString *front = [display respondsToSelector:@selector(bundleIdentifier)] ? [display bundleIdentifier] : nil;
    POSetFrontMostBundleId(front);
    // Back on the Home Screen. The transition hook above already closed the drawer as the animation
    // began; this is the fallback, and re-attaches the app when the drawer stays open.
    if (!front && [window.controller isOpened]) {
        if (POCloseOnHome()) {
            dispatch_async(dispatch_get_main_queue(), ^{ [window.controller close]; });
        } else {
            // Staying open: going home sends every app to the background, the pulled-over one too
            // (it shows black). Attach it again once the Home Screen has settled.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                PullOverViewController *c = window.controller;
                if (![c isOpened]) return;
                [c endHosting];
                c.isOpened = YES;
            });
        }
    }
}
%end

// Closes the drawer as the trip home STARTS (swipe released, Home pressed, an action), so it slides away
// with iOS's own animation. Same API on iOS 15-27. unlockedEnvironmentMode 1 = Home Screen.
@protocol POLayoutState <NSObject>
- (long long)unlockedEnvironmentMode;
@end
@protocol POLayoutTransitionContext <NSObject>
- (id<POLayoutState>)toLayoutState;
@end
%hook SBFluidSwitcherViewController
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig;
    if (![window.controller isOpened] || !POCloseOnHome()) return;
    id<POLayoutState> to = [context respondsToSelector:@selector(toLayoutState)] ? [(id<POLayoutTransitionContext>)context toLayoutState] : nil;
    if ([to respondsToSelector:@selector(unlockedEnvironmentMode)] && [to unlockedEnvironmentMode] == 1) {
        [window.controller close];
    }
}
%end

%hook SBFluidSwitcherGestureManager
-(void)grabberTongueBeganPulling:(id)arg1 withDistance:(double)arg2 andVelocity:(double)arg3 {
    if ([window.controller isOpened] && POCloseOnHome()){
        [window.controller close];
        [self grabberTongueCanceledPulling:arg1 withDistance:arg2 andVelocity:arg3];
    }else{
        %orig;
    }
}
%end

%hook SBHomeHardwareButton
-(void)singlePressUp:(id)arg1{
    if ([window.controller isOpened] && POCloseOnHome()){
        [window.controller close];
    }else{
        %orig;
    }
}
%end

%hook SBLockHardwareButton
-(void)singlePress:(id)arg1 {
    if ([window.controller isOpened]){
        [window.controller close];
    }
    %orig;
}
%end

%hook SBLockStateAggregator
-(void)_updateLockState{
    %orig;
    if (!window) return;
    unsigned long long state = [self respondsToSelector:@selector(lockState)] ? [self lockState] : 0;
    [UIView animateWithDuration:0.2 animations:^{
        window.alpha = (state == 0) ? 1 : 0;
    }];
}
%end

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, POPrefsChanged,
                                    CFSTR(POPrefsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    for (NSString *name in @[@POOpenNotification, @POCloseNotification, @POToggleNotification]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, POCommand,
                                        (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
