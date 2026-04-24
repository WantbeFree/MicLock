//
//  GBLaunchAtLogin.m
//  GBLaunchAtLogin
//
//  Created by Luka Mirosevic on 04/03/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//
//  Modernized for macOS 13+ with SMAppService.

#import "GBLaunchAtLogin.h"
#import <ServiceManagement/ServiceManagement.h>

static NSString * const GBSMAppServiceErrorDomain = @"SMAppServiceErrorDomain";

@implementation GBLaunchAtLogin

+ (BOOL)isLoginItem
{
    return [self status] != GBLaunchAtLoginStatusDisabled;
}

+ (GBLaunchAtLoginStatus)status
{
    SMAppServiceStatus status = [SMAppService mainAppService].status;
    switch (status)
    {
        case SMAppServiceStatusEnabled:
            return GBLaunchAtLoginStatusEnabled;

        case SMAppServiceStatusRequiresApproval:
            return GBLaunchAtLoginStatusRequiresApproval;

        case SMAppServiceStatusNotRegistered:
        case SMAppServiceStatusNotFound:
        default:
            return GBLaunchAtLoginStatusDisabled;
    }
}

+ (void)addAppAsLoginItem
{
    NSError *error = nil;
    if ([[SMAppService mainAppService] registerAndReturnError:&error] ||
        [self isIgnorableModernRegistrationError:error])
    {
        return;
    }

    NSLog(@"SMAppService register failed: %@", error);
}

+ (void)removeAppFromLoginItems
{
    NSError *error = nil;
    if ([[SMAppService mainAppService] unregisterAndReturnError:&error] ||
        [self isIgnorableModernUnregistrationError:error])
    {
        return;
    }

    NSLog(@"SMAppService unregister failed: %@", error);
}

+ (void)openLoginItemsSettings
{
    [SMAppService openSystemSettingsLoginItems];
}

+ (BOOL)isIgnorableModernRegistrationError:(NSError *)error
{
    return error != nil &&
           [error.domain isEqualToString:GBSMAppServiceErrorDomain] &&
           error.code == kSMErrorAlreadyRegistered;
}

+ (BOOL)isIgnorableModernUnregistrationError:(NSError *)error
{
    return error != nil &&
           [error.domain isEqualToString:GBSMAppServiceErrorDomain] &&
           error.code == kSMErrorJobNotFound;
}

@end
