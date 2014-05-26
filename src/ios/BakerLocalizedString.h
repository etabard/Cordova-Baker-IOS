
@interface BakerLocalizedString : NSObject {
	NSBundle *bundle;
}

+ (BakerLocalizedString *) sharedInstance;
- (id) init;
- (NSString *)NSLocalizedString:(NSString *)key;
@end