#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>
#import <Cordova/CDVPlugin.h>
#import "ShelfController.h"

@interface Baker : CDVPlugin
{
	  NSDictionary *notificationMessage;
    NSString* eventHandlerCallbackId;
}

@property (nonatomic, strong) NSDictionary *notificationMessage;
@property (strong, nonatomic) ShelfController *shelfController;
@property (strong) NSString* eventHandlerCallbackId;


- (void)applicationWillHandleNewsstandNotificationOfContent:(NSString *)contentName;
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo;
- (void)applicationDidBecomeActive:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationWillResignActive:(UIApplication *)application;
- (void)createNotificationChecker:(NSNotification *)notification;
- (void)handleReceiveEvent:(NSNotification *)notification;
+ (NSDictionary *)issueToDictionnary:(BakerIssue *)issue;
@end
