/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTDevMenu.h"

#import "RCTDevSettings.h"
#import "RCTKeyCommands.h"
#import "RCTLog.h"
#import "RCTUtils.h"

#if RCT_DEV

static NSString *const RCTShowDevMenuNotification = @"RCTShowDevMenuNotification";
NSString * const kRCTDevSettingShakeToShowDevMenu = @"shakeToShow";

@implementation UIWindow (RCTDevMenu)

- (void)RCT_motionEnded:(__unused UIEventSubtype)motion withEvent:(UIEvent *)event
{
  if (event.subtype == UIEventSubtypeMotionShake) {
    [[NSNotificationCenter defaultCenter] postNotificationName:RCTShowDevMenuNotification object:nil];
  }
}

@end

typedef NS_ENUM(NSInteger, RCTDevMenuType) {
  RCTDevMenuTypeButton,
  RCTDevMenuTypeToggle
};

@interface RCTDevMenuItem ()

@property (nonatomic, assign, readonly) RCTDevMenuType type;
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *selectedTitle;
@property (nonatomic, copy) id value;

@end

@implementation RCTDevMenuItem
{
  id _handler; // block
}

- (instancetype)initWithType:(RCTDevMenuType)type
                         key:(NSString *)key
                       title:(NSString *)title
               selectedTitle:(NSString *)selectedTitle
                     handler:(id /* block */)handler
{
  if ((self = [super init])) {
    _type = type;
    _key = [key copy];
    _title = [title copy];
    _selectedTitle = [selectedTitle copy];
    _handler = [handler copy];
    _value = nil;
  }
  return self;
}

RCT_NOT_IMPLEMENTED(- (instancetype)init)

+ (instancetype)buttonItemWithTitle:(NSString *)title
                            handler:(void (^)(void))handler
{
  return [[self alloc] initWithType:RCTDevMenuTypeButton
                                key:nil
                              title:title
                      selectedTitle:nil
                            handler:handler];
}

+ (instancetype)toggleItemWithKey:(NSString *)key
                            title:(NSString *)title
                    selectedTitle:(NSString *)selectedTitle
                          handler:(void (^)(BOOL selected))handler
{
  return [[self alloc] initWithType:RCTDevMenuTypeToggle
                                key:key
                              title:title
                      selectedTitle:selectedTitle
                            handler:handler];
}

- (void)callHandler
{
  switch (_type) {
    case RCTDevMenuTypeButton: {
      if (_handler) {
        ((void(^)())_handler)();
      }
      break;
    }
    case RCTDevMenuTypeToggle: {
      if (_handler) {
        ((void(^)(BOOL selected))_handler)([_value boolValue]);
      }
      break;
    }
  }
}

@end

@interface RCTDevMenu () <RCTBridgeModule, RCTInvalidating>

@end

@implementation RCTDevMenu
{
  UIAlertController *_actionSheet;
  NSArray<RCTDevMenuItem *> *_presentedItems;
  NSMutableArray<RCTDevMenuItem *> *_extraMenuItems;
  NSString *_webSocketExecutorName;
}

@synthesize bridge = _bridge;

+ (NSString *)moduleName { return @"RCTDevMenu"; }

+ (void)initialize
{
  // We're swizzling here because it's poor form to override methods in a category,
  // however UIWindow doesn't actually implement motionEnded:withEvent:, so there's
  // no need to call the original implementation.
  RCTSwapInstanceMethods([UIWindow class], @selector(motionEnded:withEvent:), @selector(RCT_motionEnded:withEvent:));
}

- (instancetype)init
{
  if ((self = [super init])) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showOnShake)
                                                 name:RCTShowDevMenuNotification
                                               object:nil];

    _extraMenuItems = [NSMutableArray new];

    __weak RCTDevMenu *weakSelf = self;

    [_extraMenuItems addObject:[RCTDevMenuItem toggleItemWithKey:kRCTDevSettingIsInspectorShown
                                                 title:@"Show Inspector"
                                         selectedTitle:@"Hide Inspector"
                                               handler:nil]];

    _webSocketExecutorName = [_bridge.devSettings settingForKey:@"websocket-executor-name"] ?: @"JS Remotely";

#if TARGET_IPHONE_SIMULATOR

    RCTKeyCommands *commands = [RCTKeyCommands sharedInstance];

    // Toggle debug menu
    [commands registerKeyCommandWithInput:@"d"
                            modifierFlags:UIKeyModifierCommand
                                   action:^(__unused UIKeyCommand *command) {
                                     [weakSelf toggle];
                                   }];

    // Toggle element inspector
    [commands registerKeyCommandWithInput:@"i"
                            modifierFlags:UIKeyModifierCommand
                                   action:^(__unused UIKeyCommand *command) {
                                     [weakSelf.bridge.devSettings toggleElementInspector];
                                   }];

    // Reload in normal mode
    [commands registerKeyCommandWithInput:@"n"
                            modifierFlags:UIKeyModifierCommand
                                   action:^(__unused UIKeyCommand *command) {
                                     [weakSelf.bridge.devSettings updateSettingWithValue:@(NO) forKey:kRCTDevSettingIsDebuggingRemotely];
                                   }];
#endif

  }
  return self;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_settingsDidChange)
                                               name:kRCTDevSettingsDidUpdateNotification
                                             object:_bridge.devSettings.dataSource];
}

- (void)invalidate
{
  _presentedItems = nil;
  [_actionSheet dismissViewControllerAnimated:YES completion:^(void){}];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)showOnShake
{
  if ([[_bridge.devSettings settingForKey:kRCTDevSettingShakeToShowDevMenu] boolValue]) {
    [self show];
  }
}

- (void)toggle
{
  if (_actionSheet) {
    [_actionSheet dismissViewControllerAnimated:YES completion:^(void){}];
    _actionSheet = nil;
  } else {
    [self show];
  }
}

- (void)addItem:(NSString *)title handler:(void(^)(void))handler
{
  [self addItem:[RCTDevMenuItem buttonItemWithTitle:title handler:handler]];
}

- (void)addItem:(RCTDevMenuItem *)item
{
  [_extraMenuItems addObject:item];

  // Fire handler for items whose saved value doesn't match the default
  [self _settingsDidChange];
}

- (NSArray<RCTDevMenuItem *> *)_menuItemsToPresent
{
  NSMutableArray<RCTDevMenuItem *> *items = [NSMutableArray new];

  // Add built-in items

  __weak RCTDevMenu *weakSelf = self;

  [items addObject:[RCTDevMenuItem buttonItemWithTitle:@"Reload" handler:^{
    [weakSelf.bridge.devSettings reload];
  }]];

  if (!_bridge.devSettings.isRemoteDebugAvailable) {
    [items addObject:[RCTDevMenuItem buttonItemWithTitle:[NSString stringWithFormat:@"%@ Debugger Unavailable", _webSocketExecutorName] handler:^{
      UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ Debugger Unavailable", self->_webSocketExecutorName]
                                                                               message:[NSString stringWithFormat:@"You need to include the RCTWebSocket library to enable %@ debugging", self->_webSocketExecutorName]
                                                                        preferredStyle:UIAlertControllerStyleAlert];

      [RCTPresentedViewController() presentViewController:alertController animated:YES completion:NULL];
    }]];
  } else {
    BOOL isDebuggingJS = [[_bridge.devSettings settingForKey:kRCTDevSettingIsDebuggingRemotely] boolValue];
    NSString *debuggingDescription = [_bridge.devSettings settingForKey:@"websocket-executor-name"] ?: @"Remote JS";
    NSString *debugTitleJS = isDebuggingJS ? [NSString stringWithFormat:@"Stop %@ Debugging", debuggingDescription] : [NSString stringWithFormat:@"Debug %@", _webSocketExecutorName];
    [items addObject:[RCTDevMenuItem buttonItemWithTitle:debugTitleJS handler:^{
      [weakSelf.bridge.devSettings updateSettingWithValue:@(!isDebuggingJS) forKey:kRCTDevSettingIsDebuggingRemotely];
    }]];
  }

  if (_bridge.devSettings.isLiveReloadAvailable) {
    [items addObject:[RCTDevMenuItem toggleItemWithKey:kRCTDevSettingLiveReloadEnabled
                                                 title:@"Enable Live Reload"
                                         selectedTitle:@"Disable Live Reload"
                                               handler:nil]];
    [items addObject:[RCTDevMenuItem toggleItemWithKey:kRCTDevSettingProfilingEnabled
                                                 title:@"Start Systrace"
                                         selectedTitle:@"Stop Systrace"
                                               handler:nil]];
  }

  if (_bridge.devSettings.isHotLoadingAvailable) {
    [items addObject:[RCTDevMenuItem toggleItemWithKey:kRCTDevSettingHotLoadingEnabled
                                                 title:@"Enable Hot Reloading"
                                         selectedTitle:@"Disable Hot Reloading"
                                               handler:nil]];
  }

  [items addObjectsFromArray:_extraMenuItems];

  return items;
}

- (void)_settingsDidChange
{
  // Fire handlers for items whose values have changed.
  // _presentedItems already includes _extraMenuItems if it exists.
  NSArray<RCTDevMenuItem *> *allItems = (_presentedItems) ?: _extraMenuItems;
  
  for (RCTDevMenuItem *item in allItems) {
    if (item.key && item.type != RCTDevMenuTypeButton) {
      id value = [_bridge.devSettings settingForKey:item.key];
      if (value != item.value && ![value isEqual:item.value]) {
        item.value = value;
        [item callHandler];
      }
    }
  }
}

RCT_EXPORT_METHOD(show)
{
  if (_actionSheet || !_bridge || RCTRunningInAppExtension()) {
    return;
  }

  NSString *title = [NSString stringWithFormat:@"React Native: Development (%@)", [_bridge class]];
  // On larger devices we don't have an anchor point for the action sheet
  UIAlertControllerStyle style = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone ? UIAlertControllerStyleActionSheet : UIAlertControllerStyleAlert;
  _actionSheet = [UIAlertController alertControllerWithTitle:title
                                                     message:@""
                                              preferredStyle:style];

  NSArray<RCTDevMenuItem *> *items = [self _menuItemsToPresent];
  for (RCTDevMenuItem *item in items) {
    switch (item.type) {
      case RCTDevMenuTypeButton: {
        [_actionSheet addAction:[UIAlertAction actionWithTitle:item.title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                         _actionSheet = nil;
                                                         [item callHandler];
                                                       }]];
        break;
      }
      case RCTDevMenuTypeToggle: {
        BOOL selected = [[_bridge.devSettings settingForKey:item.key] boolValue];
        [_actionSheet addAction:[UIAlertAction actionWithTitle:(selected ? item.selectedTitle : item.title)
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                         // after the setting updates, item.handler will be called in _settingsDidChange.
                                                         _actionSheet = nil;
                                                         BOOL value = [[self->_bridge.devSettings settingForKey:item.key] boolValue];
                                                         [self->_bridge.devSettings updateSettingWithValue:@(!value) forKey:item.key];
                                                       }]];
        break;
      }
    }
  }

  [_actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *action) {
                                                   _actionSheet = nil;
                                                 }]];

  _presentedItems = items;
  [RCTPresentedViewController() presentViewController:_actionSheet animated:YES completion:^(void){}];
}

#pragma mark - deprecated methods and properties

#define WARN_DEPRECATED_DEV_MENU_EXPORT() RCTLogWarn(@"Using deprecated method %s, use RCTDevSettings instead", __func__)

- (void)setShakeToShow:(BOOL)shakeToShow
{
  [_bridge.devSettings updateSettingWithValue:@(shakeToShow) forKey:kRCTDevSettingShakeToShowDevMenu];
}

- (BOOL)shakeToShow
{
  return [[_bridge.devSettings settingForKey:kRCTDevSettingShakeToShowDevMenu] boolValue];
}

RCT_EXPORT_METHOD(reload)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  [_bridge.devSettings reload];
}

RCT_EXPORT_METHOD(debugRemotely:(BOOL)enableDebug)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  [_bridge.devSettings updateSettingWithValue:@(enableDebug) forKey:kRCTDevSettingIsDebuggingRemotely];
}

RCT_EXPORT_METHOD(setProfilingEnabled:(BOOL)enabled)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  [_bridge.devSettings updateSettingWithValue:@(enabled) forKey:kRCTDevSettingProfilingEnabled];
}

- (BOOL)profilingEnabled
{
  return [_bridge.devSettings settingForKey:kRCTDevSettingProfilingEnabled];
}

RCT_EXPORT_METHOD(setLiveReloadEnabled:(BOOL)enabled)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  [_bridge.devSettings updateSettingWithValue:@(enabled) forKey:kRCTDevSettingLiveReloadEnabled];
}

- (BOOL)liveReloadEnabled
{
  return [_bridge.devSettings settingForKey:kRCTDevSettingLiveReloadEnabled];
}

RCT_EXPORT_METHOD(setHotLoadingEnabled:(BOOL)enabled)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  [_bridge.devSettings updateSettingWithValue:@(enabled) forKey:kRCTDevSettingHotLoadingEnabled];
}

- (BOOL)hotLoadingEnabled
{
  return [_bridge.devSettings settingForKey:kRCTDevSettingHotLoadingEnabled];
}

@end

#else // Unavailable when not in dev mode

@implementation RCTDevMenu

- (void)show {}
- (void)reload {}
- (void)addItem:(NSString *)title handler:(dispatch_block_t)handler {}
- (void)addItem:(RCTDevMenu *)item {}

@end

#endif

@implementation  RCTBridge (RCTDevMenu)

- (RCTDevMenu *)devMenu
{
#if RCT_DEV
  return [self moduleForClass:[RCTDevMenu class]];
#else
  return nil;
#endif
}

@end
