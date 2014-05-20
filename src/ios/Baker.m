#import "Baker.h"
#import "Constants.h"
#import "BakerAPI.h"
#import "IssuesManager.h"

@implementation Baker

@synthesize notificationMessage;

- (void)setup: (CDVInvokedUrlCommand*)command
{
	#ifdef BAKER_NEWSSTAND

    NSLog(@"====== Baker Newsstand Mode enabled wouhou haha ======");
    [BakerAPI generateUUIDOnce];
    // Let the device know we want to handle Newsstand push notifications
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeNewsstandContentAvailability |UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert)];

    #ifdef DEBUG
    // For debug only... so that you can download multiple issues per day during development
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NKDontThrottleNewsstandContentNotifications"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    #endif

   #endif

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNotificationChecker:)
               name:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    

    if (notificationMessage)			// if there is a pending startup notification
			[self didReceiveRemoteNotification];	// go ahead and process it

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"OK"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)applicationWillHandleNewsstandNotificationOfContent:(NSString *)contentName
{
	NSLog(@"will handle newsstand notifications");
    #ifdef BAKER_NEWSSTAND
    IssuesManager *issuesManager = [IssuesManager sharedInstance];
    PurchasesManager *purchasesManager = [PurchasesManager sharedInstance];
    __block BakerIssue *targetIssue = nil;

    [issuesManager refresh:^(BOOL status) {
        if (contentName) {
            for (BakerIssue *issue in issuesManager.issues) {
                if ([issue.ID isEqualToString:contentName]) {
                    targetIssue = issue;
                    break;
                }
            }
        } else {
            targetIssue = [issuesManager.issues objectAtIndex:0];
        }

        [purchasesManager retrievePurchasesFor:[issuesManager productIDs] withCallback:^(NSDictionary *_purchases) {

            NSString *targetStatus = [targetIssue getStatus];
            NSLog(@"[AppDelegate] Push Notification - Target status: %@", targetStatus);

            if ([targetStatus isEqualToString:@"remote"] || [targetStatus isEqualToString:@"purchased"]) {
                [targetIssue download];
            } else if ([targetStatus isEqualToString:@"purchasable"] || [targetStatus isEqualToString:@"unpriced"]) {
                NSLog(@"[AppDelegate] Push Notification - You are not entitled to download issue '%@', issue not purchased yet", targetIssue.ID);
            } else if (![targetStatus isEqualToString:@"remote"]) {
                NSLog(@"[AppDelegate] Push Notification - Issue '%@' in download or already downloaded", targetIssue.ID);
            }
        }];
    }];
    #endif
}

+ (void)createNotificationChecker:(NSNotification *)notification
{
	// Check if the app is runnig in response to a notification
		NSDictionary *launchOptions = [notification userInfo] ;
    NSDictionary *payload = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (payload) {
        NSDictionary *aps = [payload objectForKey:@"aps"];
        if (aps && [aps objectForKey:@"content-available"]) {

            __block UIBackgroundTaskIdentifier backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
                backgroundTask = UIBackgroundTaskInvalid;
            }];

            // Credit where credit is due. This semaphore solution found here:
            // http://stackoverflow.com/a/4326754/2998
            dispatch_semaphore_t sema = NULL;
            sema = dispatch_semaphore_create(0);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [self applicationWillHandleNewsstandNotificationOfContent:[payload objectForKey:@"content-name"]];
                [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
                backgroundTask = UIBackgroundTaskInvalid;
                dispatch_semaphore_signal(sema);
            });

            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
            dispatch_release(sema);
        }
    }
}

#ifdef BAKER_NEWSSTAND
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
    NSString *apnsToken = [[deviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    apnsToken = [apnsToken stringByReplacingOccurrencesOfString:@" " withString:@""];

    NSLog(@"[AppDelegate] My token (as NSData) is: %@", deviceToken);
    NSLog(@"[AppDelegate] My token (as NSString) is: %@", apnsToken);

    [[NSUserDefaults standardUserDefaults] setObject:apnsToken forKey:@"apns_token"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    BakerAPI *api = [BakerAPI sharedInstance];
    [api postAPNSToken:apnsToken];
}
#endif

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
	NSLog(@"[AppDelegate] Push Notification - Device Token, review: %@", error);
}

- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    #ifdef BAKER_NEWSSTAND
    NSDictionary *aps = [userInfo objectForKey:@"aps"];
    if (aps && [aps objectForKey:@"content-available"]) {
        [self applicationWillHandleNewsstandNotificationOfContent:[userInfo objectForKey:@"content-name"]];
    }
    #endif
}
- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))handler
{
    #ifdef BAKER_NEWSSTAND
    NSDictionary *aps = [userInfo objectForKey:@"aps"];
    if (aps && [aps objectForKey:@"content-available"]) {
        [self applicationWillHandleNewsstandNotificationOfContent:[userInfo objectForKey:@"content-name"]];
    }
    #endif
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

  #ifdef BAKER_NEWSSTAND
  // Opening the application means all new items can be considered as "seen".
  [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
  #endif


}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
  // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

  #ifdef BAKER_NEWSSTAND
  // Everything that happened while the application was opened can be considered as "seen"
  [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
  #endif

}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"applicationWillResignActiveNotification" object:nil];
}

@end
