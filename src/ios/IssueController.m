//
//  IssueViewController.m
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

#import <QuartzCore/QuartzCore.h>

#import "IssueController.h"
#import "SSZipArchive.h"
#ifdef BAKER_NEWSSTAND
#import "PurchasesManager.h"
#endif

#import "Utils.h"

@implementation IssueController

#pragma mark - Synthesis

@synthesize issue;
@synthesize actionButton;
@synthesize archiveButton;
@synthesize progressBar;
@synthesize spinner;
@synthesize loadingLabel;
@synthesize priceLabel;

@synthesize issueCover;
@synthesize titleLabel;
@synthesize infoLabel;

@synthesize currentStatus;

#pragma mark - Init

- (id)initWithBakerIssue:(BakerIssue *)bakerIssue
{
    self = [super init];
    if (self) {
        self.issue = bakerIssue;
        self.currentStatus = nil;

        purchaseDelayed = NO;

        #ifdef BAKER_NEWSSTAND
        purchasesManager = [PurchasesManager sharedInstance];
        [self addPurchaseObserver:@selector(handleIssueRestored:) name:@"notification_issue_restored"];

        [self addIssueObserver:@selector(handleDownloadStarted:) name:self.issue.notificationDownloadStartedName];
        [self addIssueObserver:@selector(handleDownloadProgressing:) name:self.issue.notificationDownloadProgressingName];
        [self addIssueObserver:@selector(handleDownloadFinished:) name:self.issue.notificationDownloadFinishedName];
        [self addIssueObserver:@selector(handleDownloadError:) name:self.issue.notificationDownloadErrorName];
        [self addIssueObserver:@selector(handleUnzipError:) name:self.issue.notificationUnzipErrorName];

        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        for (NKAssetDownload *asset in [nkLib downloadingAssets]) {
            if ([asset.issue.name isEqualToString:self.issue.ID]) {
                NSLog(@"[BakerShelf] Resuming abandoned Newsstand download: %@", asset.issue.name);
                [self.issue downloadWithAsset:asset];
            }
        }

        #endif
    }
    return self;
}



#pragma mark - Memory management

- (void)dealloc
{
    [issue release];
    [actionButton release];
    [archiveButton release];
    [progressBar release];
    [spinner release];
    [loadingLabel release];
    [priceLabel release];
    [issueCover release];
    [titleLabel release];
    [infoLabel release];
    [currentStatus release];

    [super dealloc];
}

#pragma mark - Issue management

- (void)actionButtonPressed:(UIButton *)sender
{
    NSString *status = [self.issue getStatus];
    if ([status isEqualToString:@"remote"] || [status isEqualToString:@"purchased"]) {
    #ifdef BAKER_NEWSSTAND
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueDownload" object:self]; // -> Baker Analytics Event
        [self download];
    #endif
    } else if ([status isEqualToString:@"downloaded"] || [status isEqualToString:@"bundled"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueOpen" object:self]; // -> Baker Analytics Event
        [self read];
    } else if ([status isEqualToString:@"downloading"]) {
        // TODO: assuming it is supported by NewsstandKit, implement a "Cancel" operation
    } else if ([status isEqualToString:@"purchasable"]) {
    #ifdef BAKER_NEWSSTAND
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssuePurchase" object:self]; // -> Baker Analytics Event
        [self buy];
    #endif
    }
}
#ifdef BAKER_NEWSSTAND
- (void)download {
    [self.issue download];
}
- (void)buy {
    [self addPurchaseObserver:@selector(handleIssuePurchased:) name:@"notification_issue_purchased"];
    [self addPurchaseObserver:@selector(handleIssuePurchaseFailed:) name:@"notification_issue_purchase_failed"];

    if (![purchasesManager purchase:self.issue.productID]) {
        // Still retrieving SKProduct: delay purchase
        purchaseDelayed = YES;

        [self removePurchaseObserver:@"notification_issue_purchased"];
        [self removePurchaseObserver:@"notification_issue_purchase_failed"];

        [purchasesManager retrievePriceFor:self.issue.productID];

        self.issue.transientStatus = BakerIssueTransientStatusUnpriced;
        [self refresh];
    } else {
        self.issue.transientStatus = BakerIssueTransientStatusPurchasing;
        [self refresh];
    }
}
- (void)handleIssuePurchased:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];

    if ([transaction.payment.productIdentifier isEqualToString:issue.productID]) {

        [self removePurchaseObserver:@"notification_issue_purchased"];
        [self removePurchaseObserver:@"notification_issue_purchase_failed"];

        [purchasesManager markAsPurchased:transaction.payment.productIdentifier];

        if ([purchasesManager finishTransaction:transaction]) {
            if (!transaction.originalTransaction) {
                // Do not show alert on restoring a transaction
                [Utils showAlertWithTitle:NSLocalizedString(@"ISSUE_PURCHASE_SUCCESSFUL_TITLE", nil)
                                  message:[NSString stringWithFormat:NSLocalizedString(@"ISSUE_PURCHASE_SUCCESSFUL_MESSAGE", nil), self.issue.title]
                              buttonTitle:NSLocalizedString(@"ISSUE_PURCHASE_SUCCESSFUL_CLOSE", nil)];
            }
        } else {
            [Utils showAlertWithTitle:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_TITLE", nil)
                              message:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_MESSAGE", nil)
                          buttonTitle:NSLocalizedString(@"TRANSACTION_RECORDING_FAILED_CLOSE", nil)];
        }

        self.issue.transientStatus = BakerIssueTransientStatusNone;

        [purchasesManager retrievePurchasesFor:[NSSet setWithObject:self.issue.productID] withCallback:^(NSDictionary *purchases) {
            [self refresh];
        }];
    }
}
- (void)handleIssuePurchaseFailed:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];

    if ([transaction.payment.productIdentifier isEqualToString:issue.productID]) {
        // Show an error, unless it was the user who cancelled the transaction
        if (transaction.error.code != SKErrorPaymentCancelled) {
            [Utils showAlertWithTitle:NSLocalizedString(@"ISSUE_PURCHASE_FAILED_TITLE", nil)
                              message:[transaction.error localizedDescription]
                          buttonTitle:NSLocalizedString(@"ISSUE_PURCHASE_FAILED_CLOSE", nil)];
        }

        [self removePurchaseObserver:@"notification_issue_purchased"];
        [self removePurchaseObserver:@"notification_issue_purchase_failed"];

        self.issue.transientStatus = BakerIssueTransientStatusNone;
        [self refresh];
    }
}

- (void)handleIssueRestored:(NSNotification *)notification {
    SKPaymentTransaction *transaction = [notification.userInfo objectForKey:@"transaction"];

    if ([transaction.payment.productIdentifier isEqualToString:issue.productID]) {
        [purchasesManager markAsPurchased:transaction.payment.productIdentifier];

        if (![purchasesManager finishTransaction:transaction]) {
            NSLog(@"[BakerShelf] Could not confirm purchase restore with remote server for %@", transaction.payment.productIdentifier);
        }

        self.issue.transientStatus = BakerIssueTransientStatusNone;
        [self refresh];
    }
}

- (void)setPrice:(NSString *)price {
    self.issue.price = price;
    if (purchaseDelayed) {
        purchaseDelayed = NO;
        [self buy];
    } else {
        [self refresh];
    }
}
#endif
- (void)read
{
    self.issue.transientStatus = BakerIssueTransientStatusOpening;
    [self refresh];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"read_issue_request" object:self];
}

#pragma mark - Newsstand download management

- (void)handleDownloadStarted:(NSNotification *)notification {
    [self refresh];
}
- (void)handleDownloadProgressing:(NSNotification *)notification {
    float bytesWritten = [[notification.userInfo objectForKey:@"totalBytesWritten"] floatValue];
    float bytesExpected = [[notification.userInfo objectForKey:@"expectedTotalBytes"] floatValue];

    if ([self.currentStatus isEqualToString:@"connecting"]) {
        self.issue.transientStatus = BakerIssueTransientStatusDownloading;
        [self refresh];
    }
    [self.progressBar setProgress:(bytesWritten / bytesExpected) animated:YES];
}
- (void)handleDownloadFinished:(NSNotification *)notification {
    self.issue.transientStatus = BakerIssueTransientStatusNone;
    [self refresh];
}
- (void)handleDownloadError:(NSNotification *)notification {
    [Utils showAlertWithTitle:NSLocalizedString(@"DOWNLOAD_FAILED_TITLE", nil)
                      message:NSLocalizedString(@"DOWNLOAD_FAILED_MESSAGE", nil)
                  buttonTitle:NSLocalizedString(@"DOWNLOAD_FAILED_CLOSE", nil)];

    self.issue.transientStatus = BakerIssueTransientStatusNone;
    [self refresh];
}
- (void)handleUnzipError:(NSNotification *)notification {
    [Utils showAlertWithTitle:NSLocalizedString(@"UNZIP_FAILED_TITLE", nil)
                      message:NSLocalizedString(@"UNZIP_FAILED_MESSAGE", nil)
                  buttonTitle:NSLocalizedString(@"UNZIP_FAILED_CLOSE", nil)];

    self.issue.transientStatus = BakerIssueTransientStatusNone;
    [self refresh];
}

#pragma mark - Newsstand archive management

#ifdef BAKER_NEWSSTAND
- (void)archive
{
    UIAlertView *updateAlert = [[UIAlertView alloc]
                                initWithTitle: NSLocalizedString(@"ARCHIVE_ALERT_TITLE", nil)
                                message: NSLocalizedString(@"ARCHIVE_ALERT_MESSAGE", nil)
                                delegate: self
                                cancelButtonTitle: NSLocalizedString(@"ARCHIVE_ALERT_BUTTON_CANCEL", nil)
                                otherButtonTitles: NSLocalizedString(@"ARCHIVE_ALERT_BUTTON_OK", nil), nil];
    [updateAlert show];
    [updateAlert release];
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(buttonIndex == 1){
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BakerIssueArchive" object:self]; // -> Baker Analytics Event
        
        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:self.issue.ID];
        NSString *name = nkIssue.name;
        NSDate *date = nkIssue.date;

        [nkLib removeIssue:nkIssue];

        nkIssue = [nkLib addIssueWithName:name date:date];
        self.issue.path = [[nkIssue contentURL] path];

        [self refresh];
    }
}
#endif

#pragma mark - Helper methods

- (void)addPurchaseObserver:(SEL)notificationSelector name:(NSString *)notificationName {
    #ifdef BAKER_NEWSSTAND
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:notificationSelector
                                                 name:notificationName
                                               object:purchasesManager];
    #endif
}

- (void)removePurchaseObserver:(NSString *)notificationName {
    #ifdef BAKER_NEWSSTAND
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:notificationName
                                                  object:purchasesManager];
    #endif
}

- (void)addIssueObserver:(SEL)notificationSelector name:(NSString *)notificationName {
    #ifdef BAKER_NEWSSTAND
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:notificationSelector
                                                 name:notificationName
                                               object:nil];
    #endif
}

- (void)refresh
{
    [self refresh:[self.issue getStatus]];
}

- (void)refresh:(NSString *)status
{
    NSLog(@"[BakerShelf] Shelf UI - Refreshing %@ item with status from <%@> to <%@>", self.issue.ID, self.currentStatus, status);
    if ([status isEqualToString:@"remote"])
    {
        // [self.priceLabel setText:NSLocalizedString(@"FREE_TEXT", nil)];

        // [self.actionButton setTitle:NSLocalizedString(@"ACTION_REMOTE_TEXT", nil) forState:UIControlStateNormal];
        // [self.spinner stopAnimating];

        // self.actionButton.hidden = NO;
        // self.archiveButton.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.loadingLabel.hidden = YES;
        // self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"connecting"])
    {
        NSLog(@"[BakerShelf] '%@' is Connecting...", self.issue.ID);
        // [self.spinner startAnimating];

        // self.actionButton.hidden = YES;
        // self.archiveButton.hidden = YES;
        // self.progressBar.progress = 0;
        // self.loadingLabel.text = NSLocalizedString(@"CONNECTING_TEXT", nil);
        // self.loadingLabel.hidden = NO;
        // self.progressBar.hidden = YES;
        // self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"downloading"])
    {
        NSLog(@"[BakerShelf] '%@' is Downloading...", self.issue.ID);
        // [self.spinner startAnimating];

        // self.actionButton.hidden = YES;
        // self.archiveButton.hidden = YES;
        // self.progressBar.progress = 0;
        // self.loadingLabel.text = NSLocalizedString(@"DOWNLOADING_TEXT", nil);
        // self.loadingLabel.hidden = NO;
        // self.progressBar.hidden = NO;
        // self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"downloaded"])
    {
        NSLog(@"[BakerShelf] '%@' is Ready to be Read.", self.issue.ID);
        // [self.actionButton setTitle:NSLocalizedString(@"ACTION_DOWNLOADED_TEXT", nil) forState:UIControlStateNormal];
        // [self.spinner stopAnimating];

        // self.actionButton.hidden = NO;
        // self.archiveButton.hidden = NO;
        // self.loadingLabel.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"bundled"])
    {
        // [self.actionButton setTitle:NSLocalizedString(@"ACTION_DOWNLOADED_TEXT", nil) forState:UIControlStateNormal];
        // [self.spinner stopAnimating];

        // self.actionButton.hidden = NO;
        // self.archiveButton.hidden = YES;
        // self.loadingLabel.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"opening"])
    {
        // [self.spinner startAnimating];

        // self.actionButton.hidden = YES;
        // self.archiveButton.hidden = YES;
        // self.loadingLabel.text = NSLocalizedString(@"OPENING_TEXT", nil);
        // self.loadingLabel.hidden = NO;
        // self.progressBar.hidden = YES;
        // self.priceLabel.hidden = YES;
    }
    else if ([status isEqualToString:@"purchasable"])
    {
        NSLog(@"[BakerShelf] '%@' is Purchasable... %@", self.issue.ID, self.issue.price);
        // [self.actionButton setTitle:NSLocalizedString(@"ACTION_BUY_TEXT", nil) forState:UIControlStateNormal];
        // [self.spinner stopAnimating];

        // if (self.issue.price) {
        //     [self.priceLabel setText:self.issue.price];
        // }

        // self.actionButton.hidden = NO;
        // self.archiveButton.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.loadingLabel.hidden = YES;
        // self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"purchasing"])
    {
        NSLog(@"[BakerShelf] '%@' is being Purchased...", self.issue.ID);
        // [self.spinner startAnimating];

        // self.loadingLabel.text = NSLocalizedString(@"BUYING_TEXT", nil);

        // self.actionButton.hidden = YES;
        // self.archiveButton.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.loadingLabel.hidden = NO;
        // self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"purchased"])
    {
        NSLog(@"[BakerShelf] '%@' is Purchased.", self.issue.ID);
        // [self.priceLabel setText:NSLocalizedString(@"PURCHASED_TEXT", nil)];

        // [self.actionButton setTitle:NSLocalizedString(@"ACTION_REMOTE_TEXT", nil) forState:UIControlStateNormal];
        // [self.spinner stopAnimating];

        // self.actionButton.hidden = NO;
        // self.archiveButton.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.loadingLabel.hidden = YES;
        // self.priceLabel.hidden = NO;
    }
    else if ([status isEqualToString:@"unpriced"])
    {
        // [self.spinner startAnimating];

        // self.loadingLabel.text = NSLocalizedString(@"RETRIEVING_TEXT", nil);

        // self.actionButton.hidden = YES;
        // self.archiveButton.hidden = YES;
        // self.progressBar.hidden = YES;
        // self.loadingLabel.hidden = NO;
        // self.priceLabel.hidden = YES;
    }


    self.currentStatus = status;
}

@end
