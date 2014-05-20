#import "AppDelegate+notification.h"
#import "Baker.h"
#import <objc/runtime.h>

static char launchNotificationKey;

@implementation AppDelegate (notification)

- (id) getCommandInstance:(NSString*)className
{
	return [self.viewController getCommandInstance:className];
}

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
    Method original, swizzled;
    
    original = class_getInstanceMethod(self, @selector(init));
    swizzled = class_getInstanceMethod(self, @selector(swizzled_init));
    method_exchangeImplementations(original, swizzled);
}

- (AppDelegate *)swizzled_init
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNotificationChecker:)
               name:@"UIApplicationDidFinishLaunchingNotification" object:nil];
	
	// This actually calls the original init method over in AppDelegate. Equivilent to calling super
	// on an overrided method, this is not recursive, although it appears that way. neat huh?
	return [self swizzled_init];
}

// This code will be called immediately after application:didFinishLaunchingWithOptions:. We need
// to process notifications in cold-start situations
- (void)createNotificationChecker:(NSNotification *)notification
{
	if (notification)
	{
		NSDictionary *launchOptions = [notification userInfo];
		if (launchOptions)
			self.launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
	}
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    Baker *pushHandler = [self getCommandInstance:@"Baker"];
    [pushHandler didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    Baker *pushHandler = [self getCommandInstance:@"Baker"];
    [pushHandler didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    NSLog(@"didReceiveNotification");
    
    // Get application state for iOS4.x+ devices, otherwise assume active
    UIApplicationState appState = UIApplicationStateActive;
    if ([application respondsToSelector:@selector(applicationState)]) {
        appState = application.applicationState;
    }
    
    if (appState == UIApplicationStateActive) {
        Baker *pushHandler = [self getCommandInstance:@"Baker"];
        pushHandler.notificationMessage = userInfo;
        [pushHandler didReceiveRemoteNotification];
    } else {
        //save it for later
        self.launchNotification = userInfo;
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSLog(@"active");
    Baker *pushHandler = nil;

    pushHandler = [self getCommandInstance:@"Baker"];
    [pushHandler applicationDidBecomeActive:application];
    //zero badge
    application.applicationIconBadgeNumber = 0;

    if (self.launchNotification) {
        pushHandler = [self getCommandInstance:@"Baker"];
		    pushHandler.notificationMessage = self.launchNotification;
        self.launchNotification = nil;
        [pushHandler performSelectorOnMainThread:@selector(didReceiveRemoteNotification) withObject:pushHandler waitUntilDone:NO];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"enter background");
    Baker *pushHandler = nil;

    pushHandler = [self getCommandInstance:@"Baker"];
    [pushHandler applicationDidEnterBackground:application];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    NSLog(@"application will resign active");
    Baker *pushHandler = nil;

    pushHandler = [self getCommandInstance:@"Baker"];
    [pushHandler applicationDidEnterBackground:application];
}


// The accessors use an Associative Reference since you can't define a iVar in a category
// http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/Chapters/ocAssociativeReferences.html
- (NSMutableArray *)launchNotification
{
   return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
    objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
		[super dealloc];
    self.launchNotification	= nil; // clear the association and release the object
}

@end