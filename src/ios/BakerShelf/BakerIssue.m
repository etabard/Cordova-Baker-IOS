//
//  BakerIssue.m
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

#import "BakerIssue.h"
#import "BakerAPI.h"

#import "SSZipArchive.h"
#import "Reachability.h"
#import "Utils.h"
#import "NSURL+Extensions.h"

@implementation BakerIssue

@synthesize ID;
@synthesize title;
@synthesize info;
@synthesize date;
@synthesize url;
@synthesize preview;
@synthesize path;
@synthesize previewPath;
@synthesize bakerBook;
@synthesize coverPath;
@synthesize coverURL;
@synthesize productID;
@synthesize price;
@synthesize transientStatus;
@synthesize transientPreviewStatus;

@synthesize notificationDownloadStartedName;
@synthesize notificationDownloadProgressingName;
@synthesize notificationDownloadFinishedName;
@synthesize notificationDownloadErrorName;
@synthesize notificationUnzipErrorName;

@synthesize notificationPreviewDownloadStartedName;
@synthesize notificationPreviewDownloadProgressingName;
@synthesize notificationPreviewDownloadFinishedName;
@synthesize notificationPreviewDownloadErrorName;

-(id)initWithBakerBook:(BakerBook *)book {
    self = [super init];
    if (self) {
        self.ID = book.ID;
        self.title = book.title;
        self.info = @"";
        self.date = book.date;
        self.url = [NSURL URLWithString:book.url];
        self.path = book.path;
        self.productID = @"";
        self.price = nil;

        self.bakerBook = book;

        self.coverPath = @"";
        if (book.cover == nil) {
            // TODO: set path to a default cover (right now a blank box will be displayed)
            NSLog(@"Cover not specified for %@, probably missing from book.json", book.ID);
        } else {
            self.coverPath = [book.path stringByAppendingPathComponent:book.cover];
        }

        self.transientStatus = BakerIssueTransientStatusNone;
        self.transientPreviewStatus = BakerIssueTransientStatusNone;

        [self setNotificationDownloadNames];
    }
    return self;
}

- (void)setNotificationDownloadNames {
    self.notificationDownloadStartedName = [NSString stringWithFormat:@"notification_download_started_%@", self.ID];
    self.notificationDownloadProgressingName = [NSString stringWithFormat:@"notification_download_progressing_%@", self.ID];
    self.notificationDownloadFinishedName = [NSString stringWithFormat:@"notification_download_finished_%@", self.ID];
    self.notificationDownloadErrorName = [NSString stringWithFormat:@"notification_download_error_%@", self.ID];
    self.notificationUnzipErrorName = [NSString stringWithFormat:@"notification_unzip_error_%@", self.ID];
    
    self.notificationPreviewDownloadStartedName = [NSString stringWithFormat:@"notification_preview_download_started_%@", self.ID];
    self.notificationPreviewDownloadProgressingName = [NSString stringWithFormat:@"notification_preview_download_progressing_%@", self.ID];
    self.notificationPreviewDownloadFinishedName = [NSString stringWithFormat:@"notification_preview_download_finished_%@", self.ID];
    self.notificationPreviewDownloadErrorName = [NSString stringWithFormat:@"notification_preview_download_error_%@", self.ID];
}

#ifdef BAKER_NEWSSTAND
-(id)initWithIssueData:(NSDictionary *)issueData {
    self = [super init];
    if (self) {
        self.ID = [issueData objectForKey:@"name"];
        self.title = [issueData objectForKey:@"title"];
        self.info = [issueData objectForKey:@"info"];
        self.date = [issueData objectForKey:@"date"];
        self.coverURL = [NSURL URLWithString:[issueData objectForKey:@"cover"]];
        self.url = [NSURL URLWithString:[issueData objectForKey:@"url"]];
        if ([issueData objectForKey:@"product_id"] != [NSNull null]) {
            self.productID = [issueData objectForKey:@"product_id"];
        }
        self.price = nil;
        
        self.preview = [NSURL URLWithString:[issueData objectForKey:@"preview"]];
        
        purchasesManager = [PurchasesManager sharedInstance];

        NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        self.coverPath = [cachePath stringByAppendingPathComponent:self.ID];

        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:self.ID];
        if (nkIssue) {
            self.path = [[nkIssue contentURL] path];
        } else {
            self.path = nil;
        }
        
        NKIssue *nkIssuePreview = [nkLib issueWithName:[self.ID stringByAppendingString:@"_preview"]];
        if (nkIssuePreview) {
            self.previewPath = [[nkIssuePreview contentURL] path];
        } else {
            self.previewPath = nil;
        }


        self.bakerBook = nil;

        self.transientStatus = BakerIssueTransientStatusNone;
        self.transientPreviewStatus = BakerIssueTransientStatusNone;

        [self setNotificationDownloadNames];
    }
    return self;
}

-(NSString *)nkIssueContentStatusToString:(NKIssueContentStatus) contentStatus{
    if (contentStatus == NKIssueContentStatusNone) {
        return @"remote";
    } else if (contentStatus == NKIssueContentStatusDownloading) {
        return @"connecting";
    } else if (contentStatus == NKIssueContentStatusAvailable) {
        return @"downloaded";
    }
    return @"";
}
- (void)download {
    Reachability* reach = [Reachability reachabilityWithHostname:@"www.google.com"];
    if ([reach isReachable]) {
        BakerAPI *api = [BakerAPI sharedInstance];
        NSURLRequest *req = [api requestForURL:self.url method:@"GET"];

        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:self.ID];

        NKAssetDownload *assetDownload = [nkIssue addAssetWithRequest:req];
        [self downloadWithAsset:assetDownload];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadErrorName object:self userInfo:nil];
    }
}

- (void)downloadPreview {
    Reachability* reach = [Reachability reachabilityWithHostname:@"www.google.com"];
    if ([reach isReachable] && self.preview) {
        BakerAPI *api = [BakerAPI sharedInstance];
        NSURLRequest *req = [api requestForURL:self.preview method:@"GET"];
        
        NKLibrary *nkLib = [NKLibrary sharedLibrary];
        NKIssue *nkIssue = [nkLib issueWithName:[self.ID stringByAppendingString:@"_preview"]];
        NSLog(@"%@", nkIssue);
        NKAssetDownload *assetDownload = [nkIssue addAssetWithRequest:req];
        [assetDownload downloadWithDelegate:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationPreviewDownloadStartedName object:self userInfo:nil];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationPreviewDownloadErrorName object:self userInfo:nil];
    }
}

- (void)downloadWithAsset:(NKAssetDownload *)asset {
    [asset downloadWithDelegate:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadStartedName object:self userInfo:nil];
}

#pragma mark - Newsstand download management

- (void)connection:(NSURLConnection *)connection didWriteData:(long long)bytesWritten totalBytesWritten:(long long)totalBytesWritten expectedTotalBytes:(long long)expectedTotalBytes {
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithLongLong:totalBytesWritten], @"totalBytesWritten",
                              [NSNumber numberWithLongLong:expectedTotalBytes], @"expectedTotalBytes",
                              nil];
    NSString *issueID = connection.newsstandAssetDownload.issue.name;
    if ([issueID isEqualToString:self.ID]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadProgressingName object:self userInfo:userInfo];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationPreviewDownloadProgressingName object:self userInfo:userInfo];
    }
}

- (void)connectionDidFinishDownloading:(NSURLConnection *)connection destinationURL:(NSURL *)destinationURL {
    #ifdef BAKER_NEWSSTAND
    NSString *issueID = connection.newsstandAssetDownload.issue.name;
    if ([issueID isEqualToString:self.ID]) {
        [self unpackAssetDownload:connection.newsstandAssetDownload toURL:destinationURL];
    } else {
        [self previewAssetDownload:connection.newsstandAssetDownload toURL:destinationURL];
    }
    #endif
}

#ifdef BAKER_NEWSSTAND
- (void)unpackAssetDownload:(NKAssetDownload *)newsstandAssetDownload toURL:(NSURL *)destinationURL {

    UIApplication *application = [UIApplication sharedApplication];
    NKIssue *nkIssue = newsstandAssetDownload.issue;
    NSString *destinationPath = [[nkIssue contentURL] path];
    
    NSLog(@"Finished downloading : %@", destinationPath);

    __block UIBackgroundTaskIdentifier backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[BakerShelf] Newsstand - File is being unzipped to %@", destinationPath);
        BOOL unzipSuccessful = NO;
        unzipSuccessful = [SSZipArchive unzipFileAtPath:[destinationURL path] toDestination:destinationPath];
        if (!unzipSuccessful) {
            NSLog(@"[BakerShelf] Newsstand - Unable to unzip file: %@. The file may not be a valid HPUB archive.", [destinationURL path]);
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [[NSNotificationCenter defaultCenter] postNotificationName:notificationUnzipErrorName object:self userInfo:nil];
            });
        }

        NSLog(@"[BakerShelf] Newsstand - Removing temporary downloaded file %@", [destinationURL path]);
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        NSError *error;
        if ([fileMgr removeItemAtPath:[destinationURL path] error:&error] != YES){
            NSLog(@"[BakerShelf] Newsstand - Unable to delete file: %@", [error localizedDescription]);
        }

        if (unzipSuccessful) {
            // Notification and UI update have to be handled on the main thread
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadFinishedName object:self userInfo:nil];
            });
        }

        [self updateNewsstandIcon];

        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    });
}

- (void)previewAssetDownload:(NKAssetDownload *)newsstandAssetDownload toURL:(NSURL *)destinationURL {
    
    UIApplication *application = [UIApplication sharedApplication];
    NKIssue *nkIssue = newsstandAssetDownload.issue;
    NSString *destinationPath = [[nkIssue contentURL] path];
    destinationPath = [destinationPath stringByAppendingString:@"/preview.pdf"];
    NSLog(@"Finished downloading : %@", [destinationURL path]);

    
    __block UIBackgroundTaskIdentifier backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    }];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[BakerShelf] Newsstand - Move preview %@ to %@", [destinationURL path], destinationPath);
        
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        NSError *error;
        if ([fileMgr moveItemAtPath:[destinationURL path] toPath:destinationPath error:&error] != YES){
            NSLog(@"[BakerShelf] Newsstand - Unable to move file: %@", [error localizedDescription]);
        }
        
        // Notification and UI update have to be handled on the main thread
        dispatch_async(dispatch_get_main_queue(), ^(void) {
           [[NSNotificationCenter defaultCenter] postNotificationName:notificationPreviewDownloadFinishedName object:self userInfo:nil];
        });
        
        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    });
}

- (void)updateNewsstandIcon {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];

    UIImage *coverImage = [UIImage imageWithContentsOfFile:self.coverPath];
    if (coverImage) {
        [[UIApplication sharedApplication] setNewsstandIconImage:coverImage];
    }
}
#endif

- (void)connectionDidResumeDownloading:(NSURLConnection *)connection totalBytesWritten:(long long)totalBytesWritten expectedTotalBytes:(long long)expectedTotalBytes {
    // Nothing to do for now
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"Connection error when trying to download %@: %@", [connection currentRequest].URL, [error localizedDescription]);

    [connection cancel];

    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:error forKey:@"error"];
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationDownloadErrorName object:self userInfo:userInfo];
}

#endif

-(void)getCoverWithCache:(bool)cache andBlock:(void(^)(UIImage *img))completionBlock {
    UIImage *image = [UIImage imageWithContentsOfFile:self.coverPath];
    if (cache && image) {
        completionBlock(image);
    } else {
        if (self.coverURL) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
                NSData *imageData = [NSData dataWithContentsOfURL:self.coverURL];
                UIImage *image = [UIImage imageWithData:imageData];
                if (image) {
                    [imageData writeToFile:self.coverPath atomically:YES];
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        completionBlock(image);
                    });
                }
            });
        }
    }
}

-(NSString *)getStatus {
#ifdef BAKER_NEWSSTAND
    switch (self.transientStatus) {
        case BakerIssueTransientStatusDownloading:
            return @"downloading";
            break;
        case BakerIssueTransientStatusOpening:
            return @"opening";
            break;
        case BakerIssueTransientStatusPurchasing:
            return @"purchasing";
            break;
        default:
            break;
    }

    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    NKIssue *nkIssue = [nkLib issueWithName:self.ID];
    NSString *nkIssueStatus = [self nkIssueContentStatusToString:[nkIssue status]];
    if ([nkIssueStatus isEqualToString:@"remote"] && self.productID) {
        if ([purchasesManager isPurchased:self.productID]) {
            return @"purchased";
        } else if (self.price) {
            return @"purchasable";
        } else {
            return @"unpriced";
        }
    } else {
        return nkIssueStatus;
    }
#else
    return @"bundled";
#endif
}

-(NSString *)getPreviewStatus {
#ifdef BAKER_NEWSSTAND
    if (!self.preview) {
        return @"none";
    }
    switch (self.transientStatus) {
        case BakerIssueTransientStatusDownloading:
            return @"downloading";
            break;
        default:
            break;
    }
    
    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    NKIssue *nkIssuePreview = [nkLib issueWithName:[self.ID stringByAppendingString:@"_preview"]];
    NSString *nkIssuePreviewStatus = [self nkIssueContentStatusToString:[nkIssuePreview status]];
    return nkIssuePreviewStatus;
#else
    return @"bundled";
#endif
}

-(void)dealloc {
    [ID release];
    [title release];
    [info release];
    [date release];
    [url release];
    [preview release];
    [path release];
    [previewPath release];
    [bakerBook release];
    [coverPath release];
    [coverURL release];

    [notificationUnzipErrorName release];
    [notificationDownloadErrorName release];
    [notificationDownloadFinishedName release];
    [notificationDownloadProgressingName release];

    [super dealloc];
}

@end
