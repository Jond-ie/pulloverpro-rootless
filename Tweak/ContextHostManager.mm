#import "ContextHostManager.h"
#import "POLog.h"

static NSString *const kPresenterID = @"com.johndie.pulloverpro";

@implementation ContextHostManager {
    NSString *_bundleId;
    __weak FBScene *_scene;
    _UIScenePresenter *_presenter;
    BOOL _weForegrounded;   // only send the app back if we brought it forward
}

+ (instancetype)sharedInstance {
    static ContextHostManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

// The app's main scene. Its identifier looks like "sceneID:<bundle id>-default";
// prefer that one when an app has several scenes.
- (FBScene *)sceneForBundleId:(NSString *)bundleId {
    Class managerClass = NSClassFromString(@"FBSceneManager");
    if (!bundleId || ![managerClass respondsToSelector:@selector(sharedInstance)]) return nil;
    FBSceneManager *manager = [managerClass sharedInstance];
    if (![manager respondsToSelector:@selector(scenesPassingTest:)]) return nil;

    NSSet *scenes = [manager scenesPassingTest:^BOOL(FBScene *scene) {
        return [scene.clientProcess.bundleIdentifier isEqualToString:bundleId];
    }];
    FBScene *best = nil;
    for (FBScene *scene in scenes) {
        if ([scene.identifier hasSuffix:@"-default"]) return scene;
        if (!best) best = scene;
    }
    return best;
}

- (void)openApplication:(NSString *)bundleId suspended:(BOOL)suspended {
    Class service = NSClassFromString(@"FBSSystemService");
    if (!bundleId || ![service respondsToSelector:@selector(sharedService)]) return;
    NSDictionary *options = suspended ? @{@"__ActivateSuspended": @YES} : @{@"__UnlockDevice": @YES};
    [[service sharedService] openApplication:bundleId options:options withResult:^(NSError *error) {
        POLog(@"open %@ suspended=%d -> %@", bundleId, suspended, error ?: @"ok");
    }];
}

- (void)launchInBackground:(NSString *)bundleId {
    if ([self sceneForBundleId:bundleId]) return;
    [self openApplication:bundleId suspended:YES];
}

- (void)openFullScreen:(NSString *)bundleId {
    [self openApplication:bundleId suspended:NO];
}

- (void)setScene:(FBScene *)scene foreground:(BOOL)foreground {
    if (![scene respondsToSelector:@selector(updateSettingsWithBlock:)]) return;
    [scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
        settings.foreground = foreground;
    }];
}

- (UIView *)hostViewForBundleID:(NSString *)bundleId {
    if (_presenter && [_bundleId isEqualToString:bundleId] && !_presenter.invalidated) {
        return _presenter.presentationView;
    }
    if (_bundleId) [self stopHostingForBundleID:_bundleId];

    FBScene *scene = [self sceneForBundleId:bundleId];
    POLog(@"host %@: scene=%@", bundleId, scene.identifier);
    if (!scene || ![scene respondsToSelector:@selector(uiPresentationManager)]) return nil;

    _weForegrounded = !scene.settings.foreground;
    if (_weForegrounded) [self setScene:scene foreground:YES];

    _UIScenePresenter *presenter = [scene.uiPresentationManager createPresenterWithIdentifier:kPresenterID];
    if (!presenter) return nil;
    [presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
        context.appearanceStyle = 2;   // live content, not a snapshot
        context.backgroundColorWhileNotHosting = UIColor.clearColor;
    }];
    [presenter activate];
    POLog(@"host %@: presenter=%@ view=%@ wasForeground=%d", bundleId, presenter, presenter.presentationView, !_weForegrounded);

    _bundleId = [bundleId copy];
    _scene = scene;
    _presenter = presenter;
    return presenter.presentationView;
}

- (void)stopHostingForBundleID:(NSString *)bundleId {
    if (!_presenter) return;
    if ([_presenter respondsToSelector:@selector(deactivate)]) [_presenter deactivate];
    [_presenter invalidate];
    _presenter = nil;

    FBScene *scene = _scene;
    if (scene && _weForegrounded) [self setScene:scene foreground:NO];
    _scene = nil;
    _bundleId = nil;
    _weForegrounded = NO;
}

- (BOOL)isHostViewHosting:(UIView *)hostView {
    return hostView && _presenter && !_presenter.invalidated && hostView == _presenter.presentationView;
}

@end
