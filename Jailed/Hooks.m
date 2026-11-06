#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../UI/GSPanel.h"
#import "../UI/GSAccountMenu.h"
#import "../Native/GSNativeRouting.h"
#import "../Native/GSPhotosIntegration.h"
#import "../Native/GSAccountConnection.h"
#import "../Native/GSUploadMonitor.h"
#import "SideloadKeychain.h"
#import "SideloadIdentity.h"

// Independent Objective-C hooks; the deb also ships Substrate for injector compatibility.
static id (*GSOriginalActivityInit)(id, SEL, NSArray *, NSArray *);
static id GSActivityInit(id object, SEL selector, NSArray *items, NSArray *activities) {
    NSMutableArray *all = activities ? [activities mutableCopy] : [NSMutableArray array];
    GSUploadActivity *upload = [GSUploadActivity new];
    if ([upload canPerformWithActivityItems:items])
        [all addObject:upload];
    return GSOriginalActivityInit(object, selector, items, all);
}
__attribute__((constructor)) static void GSLoadJailed(void) {
    @autoreleasepool {
        GSInstallSideloadIdentity();
        GSInstallSideloadKeychain(); // SSO reads its Keychain mode during initialization.
        // LC's guest bundle is resolved lazily on the main queue, after guest setup.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *executable =
                [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
            if (![executable isEqualToString:@"GooglePhotos"])
                return;
            // Recheck after host frameworks / the LiveContainer guest have initialized.
            GSInstallSideloadIdentity();
            GSInstallSideloadKeychain();
            GSStartAccountConnection();
            [NSNotificationCenter.defaultCenter
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) {
                            GSResumeAccountConnection();
                        }];
            GSInstallAccountMenu();
            GSStartBackupIntegration();
            Method activity = class_getInstanceMethod(UIActivityViewController.class,
                                                      @selector(initWithActivityItems:
                                                                applicationActivities:));
            if (activity)
                GSOriginalActivityInit =
                    (void *)method_setImplementation(activity, (IMP)GSActivityInit);
        });
    }
}
