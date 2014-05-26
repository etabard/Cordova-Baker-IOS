#import "BakerLocalizedString.h"

@implementation BakerLocalizedString

+ (BakerLocalizedString *)sharedInstance {
    static dispatch_once_t once;
    static BakerLocalizedString *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    
    self = [super init];
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
    NSArray* languages = [defs objectForKey:@"AppleLanguages"];
    NSString *current = [[languages objectAtIndex:0] retain];
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] resourcePath], @"Baker.bundle"];
    bundle = [NSBundle bundleWithPath:bundlePath];
    bundle = [NSBundle bundleWithPath:[bundle pathForResource:current ofType:@"lproj" ]];

    return self;
}

- (NSString *)NSLocalizedString:(NSString *)key
{
	return NSLocalizedStringFromTableInBundle(key, @"Baker", bundle ,nil);
}

@end