/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTDevSettings.h"

#import <objc/runtime.h>

#import "RCTBridge+Private.h"
#import "RCTBridgeModule.h"
#import "RCTDevMenu.h"
#import "RCTEventDispatcher.h"
#import "RCTLog.h"
#import "RCTProfile.h"
#import "RCTSourceCode.h"
#import "RCTUtils.h"
#import "RCTWebSocketProxy.h"

NSNotificationName const kRCTDevSettingsDidUpdateNotification = @"RCTDevSettingsDidUpdateNotification";
NSString * const kRCTDevSettingsUpdatedSettingsKey = @"RCTDevSettingsUpdatedSettingsKey";

NSString * const kRCTDevSettingProfilingEnabled = @"profilingEnabled";
NSString * const kRCTDevSettingHotLoadingEnabled = @"hotLoadingEnabled";
NSString * const kRCTDevSettingLiveReloadEnabled = @"liveReloadEnabled";
NSString * const kRCTDevSettingIsInspectorShown = @"showInspector";
NSString * const kRCTDevSettingIsDebuggingRemotely = @"isDebuggingRemotely";
NSString * const kRCTDevSettingExecutorOverrideClass = @"executor-override";

NSString * const kRCTDevSettingsUserDefaultsKey = @"RCTDevMenu";

@interface RCTDevSettingsUserDefaultsDataSource : NSObject <RCTDevSettingsDataSource>

@property (nonatomic, strong) NSMutableDictionary *settings;
@property (nonatomic, strong) NSMutableSet *keysChanged;

@end

@implementation RCTDevSettingsUserDefaultsDataSource

- (instancetype)init
{
  return [self initWithDefaultValues:nil];
}

- (instancetype)initWithDefaultValues:(NSDictionary *)defaultValues
{
  if (self = [super init]) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_userDefaultsDidChange)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    if (defaultValues) {
      [self _reloadWithDefaults:defaultValues];
    }
    [self _userDefaultsDidChange];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateStoredSettingWithValue:(id)value forKey:(NSString *)key
{
  RCTAssert((key != nil), [NSString stringWithFormat:@"%@: Tried to update nil key", [self class]]);

  id currentValue = _settings[key];
  if (currentValue == value || [currentValue isEqual:value]) {
    return;
  }
  if (value) {
    _settings[key] = value;
  } else {
    [_settings removeObjectForKey:key];
  }
  if (!_keysChanged) {
    _keysChanged = [NSMutableSet set];
  }
  [_keysChanged addObject:key];
  [[NSUserDefaults standardUserDefaults] setObject:_settings forKey:kRCTDevSettingsUserDefaultsKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (id)storedSettingForKey:(NSString *)key
{
  return _settings[key];
}

- (void)_userDefaultsDidChange
{
  NSDictionary *userInfo;
  if (_keysChanged) {
    userInfo = @{ kRCTDevSettingsUpdatedSettingsKey: [_keysChanged allObjects] };
    _keysChanged = nil;
  }
  _settings = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kRCTDevSettingsUserDefaultsKey]];
  [[NSNotificationCenter defaultCenter] postNotificationName:kRCTDevSettingsDidUpdateNotification object:self userInfo:userInfo];
}

- (void)_reloadWithDefaults:(NSDictionary *)defaultValues
{
  NSDictionary *existingSettings = [[NSUserDefaults standardUserDefaults] objectForKey:kRCTDevSettingsUserDefaultsKey];
  _settings = (existingSettings) ? [existingSettings mutableCopy] : [NSMutableDictionary dictionary];
  for (NSString *key in [defaultValues keyEnumerator]) {
    if (!_settings[key]) {
      _settings[key] = defaultValues[key];
    }
  }
  [[NSUserDefaults standardUserDefaults] setObject:_settings forKey:kRCTDevSettingsUserDefaultsKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

@interface RCTDevSettings () <RCTBridgeModule, RCTInvalidating, RCTWebSocketProxyDelegate>
{
  NSURLSessionDataTask *_liveReloadUpdateTask;
  NSURL *_liveReloadURL;
  BOOL _isJSLoaded;
  NSString *_executorOverride;
}

@property (nonatomic, strong) Class executorClass;
@property (nonatomic, readwrite, strong) id<RCTDevSettingsDataSource> dataSource;

@end

@implementation RCTDevSettings

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

- (instancetype)init
{
  // default behavior is to use NSUserDefaults
  NSDictionary *defaultValues = @{
    kRCTDevSettingShakeToShowDevMenu: @YES,
  };
  RCTDevSettingsUserDefaultsDataSource *dataSource = [[RCTDevSettingsUserDefaultsDataSource alloc] initWithDefaultValues:defaultValues];
  return [self initWithDataSource:dataSource];
}

- (instancetype)initWithDataSource:(id<RCTDevSettingsDataSource>)dataSource
{
  if (self = [super init]) {
    _dataSource = dataSource;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jsLoaded:)
                                                 name:RCTJavaScriptDidLoadNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_dataSourceDidUpdate:)
                                                 name:kRCTDevSettingsDidUpdateNotification
                                               object:_dataSource];
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      self->_executorOverride = [self settingForKey:kRCTDevSettingExecutorOverrideClass];
    });
    
    // Delay setup until after Bridge init
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf _dataSourceDidUpdate:nil];
      [weakSelf connectPackager];
    });
  }
  return self;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (void)invalidate
{
  [_liveReloadUpdateTask cancel];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateSettingWithValue:(id)value forKey:(NSString *)key
{
  [_dataSource updateStoredSettingWithValue:value forKey:key];
}

- (id)settingForKey:(NSString *)key
{
  return [_dataSource storedSettingForKey:key];
}

- (BOOL)isRemoteDebugAvailable
{
#if RCT_DEV
  Class jsDebuggingExecutorClass = objc_lookUpClass("RCTWebSocketExecutor");
  return (jsDebuggingExecutorClass != nil);
#else
  return NO;
#endif
}

- (BOOL)isHotLoadingAvailable
{
#if RCT_DEV
  return _bridge.bundleURL && !_bridge.bundleURL.fileURL; // Only works when running from server
#else
  return NO;
#endif
}

- (BOOL)isLiveReloadAvailable
{
  return (_liveReloadURL != nil);
}

RCT_EXPORT_METHOD(reload)
{
  [_bridge requestReload];
}

RCT_EXPORT_METHOD(setIsDebuggingRemotely:(BOOL)enabled)
{
  [self updateSettingWithValue:@(enabled) forKey:kRCTDevSettingIsDebuggingRemotely];
}

- (void)_remoteDebugSettingDidChange
{
  BOOL enabled = (self.isRemoteDebugAvailable && [[self settingForKey:kRCTDevSettingIsDebuggingRemotely] boolValue]);
  Class executorOverrideClass = [self settingForKey:kRCTDevSettingExecutorOverrideClass];
  Class jsDebuggingExecutorClass = (executorOverrideClass) ?: NSClassFromString(@"RCTWebSocketExecutor");
  self.executorClass = enabled ? jsDebuggingExecutorClass : nil;
}

RCT_EXPORT_METHOD(setProfilingEnabled:(BOOL)enabled)
{
  [self updateSettingWithValue:@(enabled) forKey:kRCTDevSettingProfilingEnabled];
}

- (void)_profilingSettingDidChange
{
  BOOL enabled = [[self settingForKey:kRCTDevSettingProfilingEnabled] boolValue];
  if (_liveReloadURL && enabled != RCTProfileIsProfiling()) {
    if (enabled) {
      [_bridge startProfiling];
    } else {
      [_bridge stopProfiling:^(NSData *logData) {
        RCTProfileSendResult(self->_bridge, @"systrace", logData);
      }];
    }
  }
}

RCT_EXPORT_METHOD(setLiveReloadEnabled:(BOOL)enabled)
{
  [self updateSettingWithValue:@(enabled) forKey:kRCTDevSettingLiveReloadEnabled];
}

- (void)_liveReloadSettingDidChange
{
  BOOL liveReloadEnabled = (self.isLiveReloadAvailable && [[self settingForKey:kRCTDevSettingLiveReloadEnabled] boolValue]);
  if (liveReloadEnabled) {
    [self _pollForLiveReload];
  } else {
    [_liveReloadUpdateTask cancel];
    _liveReloadUpdateTask = nil;
  }
}

RCT_EXPORT_METHOD(setHotLoadingEnabled:(BOOL)enabled)
{
  [self updateSettingWithValue:@(enabled) forKey:kRCTDevSettingHotLoadingEnabled];
}

- (void)_hotLoadingSettingDidChange
{
  BOOL hotLoadingEnabled = (self.isHotLoadingAvailable && [[self settingForKey:kRCTDevSettingHotLoadingEnabled] boolValue]);
  if (RCTGetURLQueryParam(_bridge.bundleURL, @"hot").boolValue != hotLoadingEnabled) {
    _bridge.bundleURL = RCTURLByReplacingQueryParam(_bridge.bundleURL, @"hot",
                                                    hotLoadingEnabled ? @"true" : nil);
    [_bridge reload];
  }
}

RCT_EXPORT_METHOD(toggleElementInspector)
{
  BOOL value = [[self settingForKey:kRCTDevSettingIsInspectorShown] boolValue];
  [self updateSettingWithValue:@(!value) forKey:kRCTDevSettingIsInspectorShown];
}

- (void)_inspectorSettingDidChange
{
  if (_isJSLoaded) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"toggleElementInspector" body:nil];
#pragma clang diagnostic pop
  }
}

- (void)setExecutorClass:(Class)executorClass
{
  if (_executorClass != executorClass) {
    _executorClass = executorClass;
    _executorOverride = nil;
  }
  
  if (_bridge.executorClass != executorClass) {
    
    // TODO (6929129): we can remove this special case test once we have better
    // support for custom executors in the dev menu. But right now this is
    // needed to prevent overriding a custom executor with the default if a
    // custom executor has been set directly on the bridge
    if (executorClass == Nil &&
        _bridge.executorClass != objc_lookUpClass("RCTWebSocketExecutor")) {
      return;
    }
    
    _bridge.executorClass = executorClass;
    [_bridge reload];
  }
}

#pragma mark - internal

- (void)_dataSourceDidUpdate:(NSNotification *)notification
{
  BOOL updateAllProperties = YES;
  NSArray *propertiesToUpdate = @[ kRCTDevSettingProfilingEnabled ];
  if (notification && notification.userInfo) {
    propertiesToUpdate = [notification.userInfo objectForKey:kRCTDevSettingsUpdatedSettingsKey];
    updateAllProperties = NO;
  }
  for (NSString *property in propertiesToUpdate) {
    if (updateAllProperties || [property isEqualToString:kRCTDevSettingHotLoadingEnabled]) {
      [self _hotLoadingSettingDidChange];
    }
    if (updateAllProperties || [property isEqualToString:kRCTDevSettingLiveReloadEnabled]) {
      [self _liveReloadSettingDidChange];
    }
    if (updateAllProperties ||
        [property isEqualToString:kRCTDevSettingIsDebuggingRemotely] ||
        [property isEqualToString:kRCTDevSettingExecutorOverrideClass]) {
      [self _remoteDebugSettingDidChange];
    }
    if (updateAllProperties || [property isEqualToString:kRCTDevSettingProfilingEnabled]) {
      [self _profilingSettingDidChange];
    }
    if ([property isEqualToString:kRCTDevSettingIsInspectorShown]) {
      // don't check `updateAllProperties` here because this is a stateless event dispatch to JS
      [self _inspectorSettingDidChange];
    }
  }
}

- (void)_pollForLiveReload
{
  if (!_isJSLoaded || ![[self settingForKey:kRCTDevSettingLiveReloadEnabled] boolValue] || !_liveReloadURL) {
    return;
  }
  
  if (_liveReloadUpdateTask) {
    return;
  }
  
  __weak typeof(self) weakSelf = self;
  _liveReloadUpdateTask = [[NSURLSession sharedSession] dataTaskWithURL:_liveReloadURL completionHandler:
                           ^(__unused NSData *data, NSURLResponse *response, NSError *error) {
                             
                             dispatch_async(dispatch_get_main_queue(), ^{
                               __strong typeof(self) strongSelf = weakSelf;
                               if (strongSelf && [[strongSelf settingForKey:kRCTDevSettingLiveReloadEnabled] boolValue]) {
                                 NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
                                 if (!error && HTTPResponse.statusCode == 205) {
                                   [strongSelf reload];
                                 } else {
                                   if (error.code != NSURLErrorCancelled) {
                                     strongSelf->_liveReloadUpdateTask = nil;
                                     [strongSelf _pollForLiveReload];
                                   }
                                 }
                               }
                             });
                             
                           }];
  
  [_liveReloadUpdateTask resume];
}

- (void)jsLoaded:(NSNotification *)notification
{
  if (notification.userInfo[@"bridge"] != _bridge) {
    return;
  }
  
  _isJSLoaded = YES;
  
  // Check if live reloading is available
  _liveReloadURL = nil;
  RCTSourceCode *sourceCodeModule = [_bridge moduleForClass:[RCTSourceCode class]];
  if (!sourceCodeModule.scriptURL) {
    if (!sourceCodeModule) {
      RCTLogWarn(@"RCTSourceCode module not found");
    } else if (!RCTRunningInTestEnvironment()) {
      RCTLogWarn(@"RCTSourceCode module scriptURL has not been set");
    }
  } else if (!sourceCodeModule.scriptURL.fileURL) {
    // Live reloading is disabled when running from bundled JS file
    _liveReloadURL = [[NSURL alloc] initWithString:@"/onchange" relativeToURL:sourceCodeModule.scriptURL];
  }
  
  dispatch_async(dispatch_get_main_queue(), ^{
    // update state again after the bridge has finished loading
    [self _dataSourceDidUpdate:nil];
  });
}

#pragma mark - RCTWebSocketProxy

- (void)connectPackager
{
  Class webSocketManagerClass = objc_lookUpClass("RCTWebSocketManager");
  id<RCTWebSocketProxy> webSocketManager = (id <RCTWebSocketProxy>)[webSocketManagerClass sharedInstance];
  NSURL *url = [self packagerURL];
  if (url) {
    [webSocketManager setDelegate:self forURL:url];
  }
}

- (void)socketProxy:(__unused id<RCTWebSocketProxy>)sender didReceiveMessage:(NSDictionary<NSString *, id> *)message
{
  if ([self isSupportedWebSocketMessageVersion:message[@"version"]]) {
    [self processWebSocketMessageWithTarget:message[@"target"] action:message[@"action"] options:message[@"options"]];
  }
}

- (NSURL *)packagerURL
{
  NSString *host = [_bridge.bundleURL host];
  NSString *scheme = [_bridge.bundleURL scheme];
  if (!host) {
    host = @"localhost";
    scheme = @"http";
  }
  
  NSNumber *port = [_bridge.bundleURL port];
  if (!port) {
    port = @8081; // Packager default port
  }
  return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%@/message?role=shell", scheme, host, port]];
}

- (BOOL)isSupportedWebSocketMessageVersion:(NSNumber *)version
{
  NSArray<NSNumber *> *const kSupportedVersions = @[ @1 ];
  return [kSupportedVersions containsObject:version];
}

- (void)processWebSocketMessageWithTarget:(NSString *)target action:(NSString *)action options:(NSDictionary<NSString *, id> *)options
{
  if ([target isEqualToString:@"bridge"]) {
    if ([action isEqualToString:@"reload"]) {
      if ([options[@"debug"] boolValue]) {
        _bridge.executorClass = objc_lookUpClass("RCTWebSocketExecutor");
      }
      [_bridge reload];
    }
  }
}

@end

@implementation RCTBridge (RCTDevSettings)

- (RCTDevSettings *)devSettings
{
#if RCT_DEV
  return [self moduleForClass:[RCTDevSettings class]];
#else
  return nil;
#endif
}

@end
