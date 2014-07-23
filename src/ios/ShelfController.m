//
//  ShelfViewController.m
//  Baker
//
//  ==========================================================================================
//
//  Copyright (c) 2010-2013, Davide Casali, Marco Colombo, Alessandro Morandi
//  Copyright (c) 2014, Andrew Krowczyk, Cédric Mériau
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification, are
//  permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this list of
//  conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice, this list of
//  conditions and the following disclaimer in the documentation and/or other materials
//  provided with the distribution.
//  Neither the name of the Baker Framework nor the names of its contributors may be used to
//  endorse or promote products derived from this software without specific prior written
//  permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "ShelfController.h"
#import "Constants.h"

#import "IssueController.h"
#import "NSData+Base64.h"
#import "NSString+Extensions.h"
#import "BakerLocalizedString.h"
#import "Utils.h"
#import "Baker.h"

@implementation ShelfController

@synthesize issues;
@synthesize issueViewControllers;
@synthesize subscribeButton;
@synthesize refreshButton;
@synthesize shelfStatus;
@synthesize subscriptionsActionSheet;
@synthesize supportedOrientation;
@synthesize blockingProgressView;
@synthesize bookToBeProcessed;
@synthesize hasSubscribed;


#pragma mark - Init

- (id)init {
    self = [super init];
    if (self) {
        #ifdef BAKER_NEWSSTAND
        purchasesManager = [PurchasesManager sharedInstance];
        [self addPurchaseObserver:@selector(handleProductsRetrieved:)
                             name:@"notification_products_retrieved"];
        [self addPurchaseObserver:@selector(handleProductsRequestFailed:)
                             name:@"notification_products_request_failed"];
        [self addPurchaseObserver:@selector(handleSubscriptionPurchased:)
                             name:@"notification_subscription_purchased"];
        [self addPurchaseObserver:@selector(handleSubscriptionFailed:)
                             name:@"notification_subscription_failed"];
        [self addPurchaseObserver:@selector(handleSubscriptionRestored:)
                             name:@"notification_subscription_restored"];
        [self addPurchaseObserver:@selector(handleRestoreFailed:)
                             name:@"notification_restore_failed"];
        [self addPurchaseObserver:@selector(handleMultipleRestores:)
                             name:@"notification_multiple_restores"];
        [self addPurchaseObserver:@selector(handleRestoredIssueNotRecognised:)
                             name:@"notification_restored_issue_not_recognised"];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(receiveBookProtocolNotification:)
                                                     name:@"notification_book_protocol"
                                                   object:nil];

        [[SKPaymentQueue defaultQueue] addTransactionObserver:purchasesManager];
        #endif

        api = [BakerAPI sharedInstance];
        issuesManager = [[IssuesManager sharedInstance] retain];
        notRecognisedTransactions = [[NSMutableArray alloc] init];

        self.shelfStatus = [[[ShelfStatus alloc] init] autorelease];
        self.issueViewControllers = [[[NSMutableArray alloc] init] autorelease];
        self.supportedOrientation = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
        self.bookToBeProcessed = nil;
        self.hasSubscribed = NO;

        #ifdef BAKER_NEWSSTAND
        [self handleRefresh:nil];

        NSMutableSet *subscriptions = [NSMutableSet setWithArray:AUTO_RENEWABLE_SUBSCRIPTION_PRODUCT_IDS];
        if ([FREE_SUBSCRIPTION_PRODUCT_ID length] > 0 && ![purchasesManager isPurchased:FREE_SUBSCRIPTION_PRODUCT_ID]) {
            [subscriptions addObject:FREE_SUBSCRIPTION_PRODUCT_ID];
        }
        [purchasesManager retrievePricesFor:subscriptions andEnableFailureNotifications:NO];
        
        

        
        #endif
    }
    return self;
}

- (id)initWithBooks:(NSArray *)currentBooks
{
    self = [self init];
    if (self) {
        self.issues = currentBooks;

        NSMutableArray *controllers = [NSMutableArray array];
        for (BakerIssue *issue in self.issues) {
            IssueController *controller = [self createIssueViewControllerWithIssue:issue];
            [controllers addObject:controller];
        }
        self.issueViewControllers = [NSMutableArray arrayWithArray:controllers];
    }
    return self;
}

#pragma mark - Memory management

- (void)dealloc
{
    [issueViewControllers release];
    [issues release];
    [subscribeButton release];
    [refreshButton release];
    [shelfStatus release];
    [subscriptionsActionSheet release];
    [supportedOrientation release];
    [blockingProgressView release];
    [issuesManager release];
    [notRecognisedTransactions release];
    [bookToBeProcessed release];

    #ifdef BAKER_NEWSSTAND
    [purchasesManager release];
    #endif

    [super dealloc];
}



#ifdef BAKER_NEWSSTAND
- (void)handleRefresh:(NSNotification *)notification {
    [self setrefreshStateEnabled:NO];
  
    [issuesManager refresh:^(BOOL status) {
        if(status) {
            self.issues = issuesManager.issues;

            [shelfStatus load];
            for (BakerIssue *issue in self.issues) {
                issue.price = [shelfStatus priceFor:issue.productID];
            }

          
            
            void (^updateIssues)() = ^{
                // Step 1: remove controllers for issues that no longer exist
                __block NSMutableArray *discardedControllers = [NSMutableArray array];
                [self.issueViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    IssueController *ivc = (IssueController *)obj;
                    
                    if (![self bakerIssueWithID:ivc.issue.ID]) {
                        [discardedControllers addObject:ivc];
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueDeleted" object:[NSDictionary dictionaryWithObjectsAndKeys:[Baker issueToDictionnary:ivc.issue],@"issue", nil]];
                    }
                }];
                [self.issueViewControllers removeObjectsInArray:discardedControllers];
                
                // Step 2: add controllers for issues that did not yet exist (and refresh the ones that do exist)
                [self.issues enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    // NOTE: this block changes the issueViewController array while looping
                    BakerIssue *issue = (BakerIssue *)obj;
                    
                    IssueController *existingIvc = [self issueViewControllerWithID:issue.ID];
                    
                    if (existingIvc) {
                        NSLog(@"existing issue controller %@", issue.ID);
                        existingIvc.issue = issue;
                    } else {
                        IssueController *newIvc = [self createIssueViewControllerWithIssue:issue];
                        [self.issueViewControllers insertObject:newIvc atIndex:idx];
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueAdded" object:[NSDictionary dictionaryWithObjectsAndKeys:[Baker issueToDictionnary:newIvc.issue],@"issue", [NSNumber numberWithLong:idx],@"index", nil]];
                    }
                }];
                
            };
            
            
            updateIssues();
           
            
            [purchasesManager retrievePurchasesFor:[issuesManager productIDs] withCallback:^(NSDictionary *purchases) {
                // List of purchases has been returned, so we can refresh all issues
                [self.issueViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    //refresh drawing
                    NSLog(@"Retrieve purchase from app store %@", [(IssueController*)obj issue].productID);
                    [(IssueController *)obj refresh];
                }];

                [self refreshSubscribeState];
                [self setrefreshStateEnabled:YES];
            }];

            [purchasesManager retrievePricesFor:issuesManager.productIDs andEnableFailureNotifications:NO];
        } else {
            [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"INTERNET_CONNECTION_UNAVAILABLE_TITLE"]
                              message:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"INTERNET_CONNECTION_UNAVAILABLE_MESSAGE"]
                          buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"INTERNET_CONNECTION_UNAVAILABLE_CLOSE"]];

            [self setrefreshStateEnabled:YES];
        }
    }];
}

- (IssueController *)issueViewControllerWithID:(NSString *)ID {
    __block IssueController* foundController = nil;
    [self.issueViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        IssueController *ivc = (IssueController *)obj;
        if ([ivc.issue.ID isEqualToString:ID]) {
            foundController = ivc;
            *stop = YES;
        }
    }];
    return foundController;
}

- (BakerIssue *)bakerIssueWithID:(NSString *)ID {
    __block BakerIssue *foundIssue = nil;
    [self.issues enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        BakerIssue *issue = (BakerIssue *)obj;
        if ([issue.ID isEqualToString:ID]) {
            foundIssue = issue;
            *stop = YES;
        }
    }];
    return foundIssue;
}

- (IssueController *)createIssueViewControllerWithIssue:(BakerIssue *)issue
{
    IssueController *controller = [[[IssueController alloc] initWithBakerIssue:issue] autorelease];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleReadIssue:) name:@"read_issue_request" object:controller];
    return controller;
}

#pragma mark - Store Kit
- (void)handleSubscribeButtonPressed:(NSNotification *)notification {
    if (subscriptionsActionSheet.visible) {
        [subscriptionsActionSheet dismissWithClickedButtonIndex:(subscriptionsActionSheet.numberOfButtons - 1) animated:YES];
    } else {
        self.subscriptionsActionSheet = [self buildSubscriptionsActionSheet];
        [subscriptionsActionSheet showFromBarButtonItem:self.subscribeButton animated:YES];
    }
}

- (UIActionSheet *)buildSubscriptionsActionSheet {
    NSString *title;
    if ([api canGetPurchasesJSON]) {
        if (purchasesManager.subscribed) {
            title = [[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTIONS_SHEET_SUBSCRIBED"];
        } else {
            title =[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTIONS_SHEET_NOT_SUBSCRIBED"];
        }
    } else {
        title = [[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTIONS_SHEET_GENERIC"];
    }

    UIActionSheet *sheet = [[UIActionSheet alloc]initWithTitle:title
                                                      delegate:self
                                             cancelButtonTitle:nil
                                        destructiveButtonTitle:nil
                                             otherButtonTitles: nil];
    NSMutableArray *actions = [NSMutableArray array];

    if (!purchasesManager.subscribed) {
        if ([FREE_SUBSCRIPTION_PRODUCT_ID length] > 0 && ![purchasesManager isPurchased:FREE_SUBSCRIPTION_PRODUCT_ID]) {
            [sheet addButtonWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTIONS_SHEET_FREE"]];
            [actions addObject:FREE_SUBSCRIPTION_PRODUCT_ID];
        }

        for (NSString *productId in AUTO_RENEWABLE_SUBSCRIPTION_PRODUCT_IDS) {
            NSString *title = NSLocalizedString(productId, nil);
            NSString *price = [purchasesManager priceFor:productId];
            if (price) {
                [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@ %@", title, price]];
                [actions addObject:productId];
            }
        }
    }

    if ([issuesManager hasProductIDs]) {
        [sheet addButtonWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTIONS_SHEET_RESTORE"]];
        [actions addObject:@"restore"];
    }

    [sheet addButtonWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTIONS_SHEET_CLOSE"]];
    [actions addObject:@"cancel"];

    self.subscriptionsActionSheetActions = actions;

    sheet.cancelButtonIndex = sheet.numberOfButtons - 1;
    return sheet;
}

- (BOOL)subscribe:(NSString *)productId {

    [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerSubscriptionPurchase" object:self]; // -> Baker Analytics Event
    if (![purchasesManager purchase:productId]){
        [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_FAILED_TITLE"]
                                  message:nil
                                                                                       buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_FAILED_CLOSE"]];
        [self refreshSubscribeState];
        return false;
    } else {
        [self refreshSubscribeState];
        return true;
    }

}

- (void)handleRestoreFailed:(NSNotification *)notification {
    NSError *error = [notification.userInfo objectForKey:@"error"];
    [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"RESTORE_FAILED_TITLE"]
                      message:[error localizedDescription]
                  buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"RESTORE_FAILED_CLOSE"]];

    [self.blockingProgressView dismissWithClickedButtonIndex:0 animated:YES];

}

- (void)handleMultipleRestores:(NSNotification *)notification {
    #ifdef BAKER_NEWSSTAND
    if ([notRecognisedTransactions count] > 0) {
        NSSet *productIDs = [NSSet setWithArray:[[notRecognisedTransactions valueForKey:@"payment"] valueForKey:@"productIdentifier"]];
        NSString *productsList = [[productIDs allObjects] componentsJoinedByString:@", "];

        [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"RESTORED_ISSUE_NOT_RECOGNISED_TITLE"]
                          message:[NSString stringWithFormat:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"RESTORED_ISSUE_NOT_RECOGNISED_MESSAGE"], productsList]
                      buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"RESTORED_ISSUE_NOT_RECOGNISED_CLOSE"]];

        for (SKPaymentTransaction *transaction in notRecognisedTransactions) {
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        }
        [notRecognisedTransactions removeAllObjects];
    }
    #endif

    [self handleRefresh:nil];
    [self.blockingProgressView dismissWithClickedButtonIndex:0 animated:YES];
}

- (void)handleRestoredIssueNotRecognised:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];
    [notRecognisedTransactions addObject:transaction];
}

// TODO: this can probably be removed
//- (void)handleSubscription:(NSNotification *)notification {
//    [self setSubscribeButtonEnabled:NO];
//    [purchasesManager purchase:FREE_SUBSCRIPTION_PRODUCT_ID];
//}

- (void)handleSubscriptionPurchased:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];

    [purchasesManager markAsPurchased:transaction.payment.productIdentifier];
//    [self setSubscribeButtonEnabled:YES];

    if ([purchasesManager finishTransaction:transaction]) {
        if (!purchasesManager.subscribed) {
            [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_SUCCESSFUL_TITLE"]
                              message:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_SUCCESSFUL_MESSAGE"]
                          buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_SUCCESSFUL_CLOSE"]];

            [self handleRefresh:nil];
        }
    } else {
        [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"TRANSACTION_RECORDING_FAILED_TITLE"]
                          message:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"TRANSACTION_RECORDING_FAILED_MESSAGE"]
                      buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"TRANSACTION_RECORDING_FAILED_CLOSE"]];
    }
}

- (void)handleSubscriptionFailed:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];

    // Show an error, unless it was the user who cancelled the transaction
    if (transaction.error.code != SKErrorPaymentCancelled) {
        [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_FAILED_TITLE"]
                          message:[transaction.error localizedDescription]
                      buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"SUBSCRIPTION_FAILED_CLOSE"]];
    }
    [self refreshSubscribeState];
}

- (void)handleSubscriptionRestored:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];
    NSLog(@"Handle subscription restored %@", transaction.payment.productIdentifier);
    [purchasesManager markAsPurchased:transaction.payment.productIdentifier];

    if (![purchasesManager finishTransaction:transaction]) {
        NSLog(@"Could not confirm purchase restore with remote server for %@", transaction.payment.productIdentifier);
    } else {
        [self refreshSubscribeState];
    }
}

- (void)handleProductsRetrieved:(NSNotification *)notification {
    NSSet *ids = [notification.userInfo objectForKey:@"ids"];
    BOOL issuesRetrieved = NO;

    for (NSString *productId in ids) {
        if ([productId isEqualToString:FREE_SUBSCRIPTION_PRODUCT_ID]) {
            // ID is for a free subscription
             [self refreshSubscribeState];
        } else if ([AUTO_RENEWABLE_SUBSCRIPTION_PRODUCT_IDS containsObject:productId]) {
            // ID is for an auto-renewable subscription
             [self refreshSubscribeState];
        } else {
            // ID is for an issue
            issuesRetrieved = YES;
        }
    }

    if (issuesRetrieved) {
        NSString *price;
        for (IssueController *controller in self.issueViewControllers) {
            price = [purchasesManager priceFor:controller.issue.productID];
            if (price) {
                [controller setPrice:price];
                [shelfStatus setPrice:price for:controller.issue.productID];
            }
        }
        [shelfStatus save];
    }
}

-(void)setrefreshStateEnabled:(BOOL)enabled {
    NSLog(@"Refresh mode enabled %i", enabled);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerRefreshStateChanged" object:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:enabled], @"state", nil]];
}

-(void)refreshSubscribeState {
    BOOL currentStatus = [purchasesManager subscribed];
    
    if (self.hasSubscribed != currentStatus) {
        NSLog(@"User has subscribed %i", currentStatus);

        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerSubscriptionStateChanged" object:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:currentStatus], @"state", nil]];
    }
    self.hasSubscribed = currentStatus;
    
    
}

- (void)handleProductsRequestFailed:(NSNotification *)notification {
    NSError *error = [notification.userInfo objectForKey:@"error"];

    [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"PRODUCTS_REQUEST_FAILED_TITLE"]
                      message:[error localizedDescription]
                  buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"PRODUCTS_REQUEST_FAILED_CLOSE"]];
}

#endif

#pragma mark - Navigation management

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

- (void)readIssue:(BakerIssue *)issue
{
    BakerBook *book = nil;
    NSString *status = [issue getStatus];

    #ifdef BAKER_NEWSSTAND
    if ([status isEqual:@"opening"]) {
        book = [[[BakerBook alloc] initWithBookPath:issue.path bundled:NO] autorelease];
        if (book) {
            //[self pushViewControllerWithBook:book];
        } else {
            NSLog(@"[ERROR] Book %@ could not be initialized", issue.ID);
            issue.transientStatus = BakerIssueTransientStatusNone;
            // Let's refresh everything as it's easier. This is an edge case anyway ;)
            for (IssueController *controller in issueViewControllers) {
                [controller refresh];
            }
            [Utils showAlertWithTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"ISSUE_OPENING_FAILED_TITLE"]
                              message:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"ISSUE_OPENING_FAILED_MESSAGE"]
                          buttonTitle:[[BakerLocalizedString sharedInstance] NSLocalizedString:@"ISSUE_OPENING_FAILED_CLOSE"]];
        }
    }
    #else
    if ([status isEqual:@"bundled"]) {
        book = [issue bakerBook];
        //[self pushViewControllerWithBook:book];
    }
    #endif
}
- (void)handleReadIssue:(NSNotification *)notification
{
    IssueController *controller = notification.object;
    [self readIssue:controller.issue];
}
- (void)receiveBookProtocolNotification:(NSNotification *)notification
{
    self.bookToBeProcessed = [notification.userInfo objectForKey:@"ID"];
    // [self.navigationController popToRootViewControllerAnimated:YES];
}
- (void)handleBookToBeProcessed
{
    for (IssueController *issueController in self.issueViewControllers) {
        if ([issueController.issue.ID isEqualToString:self.bookToBeProcessed]) {
            [IssueController actionButtonPressed:nil];
            break;
        }
    }

    self.bookToBeProcessed = nil;
}

#pragma mark - Helper methods

- (void)addPurchaseObserver:(SEL)notificationSelector name:(NSString *)notificationName {
    #ifdef BAKER_NEWSSTAND
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:notificationSelector
                                                 name:notificationName
                                               object:purchasesManager];
    #endif
}


@end
