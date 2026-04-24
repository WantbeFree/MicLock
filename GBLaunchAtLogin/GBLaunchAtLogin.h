//
//  GBLaunchAtLogin.h
//  GBLaunchAtLogin
//
//  Created by Luka Mirosevic on 04/03/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GBLaunchAtLoginStatus)
{
    GBLaunchAtLoginStatusDisabled = 0,
    GBLaunchAtLoginStatusEnabled = 1,
    GBLaunchAtLoginStatusRequiresApproval = 2,
};

@interface GBLaunchAtLogin : NSObject

+(BOOL)isLoginItem;
+(GBLaunchAtLoginStatus)status;
+(void)addAppAsLoginItem;
+(void)removeAppFromLoginItems;
+(void)openLoginItemsSettings;

@end
