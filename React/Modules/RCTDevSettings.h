/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTBridge.h"

/**
 * This notification is posted when user settings change.
 * It will be scoped to the RCTDevSettingsDataSource that posted it.
 * Its userInfo dictionary may optionally contain `kRCTDevSettingsUpdatedSettingsKey`
 * with an array of specific settings keys that changed.
 */
FOUNDATION_EXPORT NSNotificationName const kRCTDevSettingsDidUpdateNotification;
FOUNDATION_EXPORT NSString * const kRCTDevSettingsUpdatedSettingsKey;

@protocol RCTDevSettingsDataSource <NSObject>

- (void)updateStoredSettingWithValue:(id)value forKey:(NSString *)key;
- (id)storedSettingForKey:(NSString *)key;

@end

/**
 * Whether performance profiling is enabled.
 */
FOUNDATION_EXPORT NSString * const kRCTDevSettingProfilingEnabled;

/**
 * Whether hot loading is enabled.
 */
FOUNDATION_EXPORT NSString * const kRCTDevSettingHotLoadingEnabled;

/**
 * Whether automatic polling for JS code changes is enabled. Only applicable when
 * running the app from a server.
 */
FOUNDATION_EXPORT NSString * const kRCTDevSettingLiveReloadEnabled;

/**
 * Whether the element inspector is showing.
 */
FOUNDATION_EXPORT NSString * const kRCTDevSettingIsInspectorShown;

/**
 * Whether the bridge is connected to a remote JS executor.
 */
FOUNDATION_EXPORT NSString * const kRCTDevSettingIsDebuggingRemotely;
FOUNDATION_EXPORT NSString * const kRCTDevSettingExecutorOverrideClass;

@interface RCTDevSettings : NSObject

- (instancetype)initWithDataSource:(id<RCTDevSettingsDataSource>)dataSource;

@property (nonatomic, readonly) id<RCTDevSettingsDataSource> dataSource;

@property (nonatomic, readonly) BOOL isHotLoadingAvailable;
@property (nonatomic, readonly) BOOL isLiveReloadAvailable;
@property (nonatomic, readonly) BOOL isRemoteDebugAvailable;

/**
 * Update the setting with the given key.
 */
- (void)updateSettingWithValue:(id)value forKey:(NSString *)key;

/**
 * Get the setting for the given key.
 */
- (id)settingForKey:(NSString *)key;

/**
 * Manually reload the application. Equivalent to calling [bridge reload]
 * directly, but can be called from JS.
 */
- (void)reload;

/**
 * Toggle the element inspector.
 */
- (void)toggleElementInspector;

@end

@interface RCTBridge (RCTDevSettings)

@property (nonatomic, readonly) RCTDevSettings *devSettings;

@end
