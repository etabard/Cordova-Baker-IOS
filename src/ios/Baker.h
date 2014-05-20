#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>
#import <Cordova/CDVPlugin.h>

@interface Baker : CDVPlugin
{
	NSDictionary *notificationMessage;
}

@property (nonatomic, strong) NSDictionary *notificationMessage;

- (void)applicationWillHandleNewsstandNotificationOfContent:(NSString *)contentName;
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
- (void)didReceiveRemoteNotification;
- (void)applicationDidBecomeActive:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationWillResignActive:(UIApplication *)application;
- (void)createNotificationChecker:(NSNotification *)notification;

@end
