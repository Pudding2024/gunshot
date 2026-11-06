#ifdef GS_TEST_LEGACY
#define GS_ERROR_LABEL errorCode
#define GS_ERROR_TYPE NSInteger
#define GS_NO_ERROR 0
#define GS_FAILURE 73
#else
#define GS_ERROR_LABEL error
#define GS_ERROR_TYPE id
#define GS_NO_ERROR nil
#define GS_FAILURE error
#endif
#import "host_profile.h"
#import "../Native/GSUploadDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <assert.h>
static NSString *version = @"unsupported";
static BOOL host = NO;
@interface GSProbeBundle : NSObject
@end
@implementation GSProbeBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    return [key isEqual:@"CFBundleExecutable"] ? (host ? @"GooglePhotos" : @"OtherApp") : version;
}
@end
static id MainBundle(id object, SEL selector) {
    static id b;
    if (!b)
        b = [GSProbeBundle new];
    return b;
}
@interface GSPrivateResult : NSObject
@end
@implementation GSPrivateResult
- (NSString *)description {
    assert(!"must not inspect object content");
    return @"SECRET_TOKEN";
}
@end
static NSUInteger called;
static id lastResult, lastError;
static BOOL lastSuccess;
@interface GMUUploadRequest : NSObject
- (void)start;
- (void)startFetcher;
- (void)didCompleteWithSuccess:(_Bool)success
            resultantMediaItem:(id)result
                GS_ERROR_LABEL:(GS_ERROR_TYPE)error;
@end
@implementation GMUUploadRequest
- (void)start {
    called++;
}
- (void)startFetcher {
    called++;
}
- (void)didCompleteWithSuccess:(_Bool)success
            resultantMediaItem:(id)result
                GS_ERROR_LABEL:(GS_ERROR_TYPE)error {
    called++;
    lastResult = result;
#ifdef GS_TEST_LEGACY
    lastError = error ? @(error) : nil;
#else
    lastError = error;
#endif
    lastSuccess = success;
}
@end
@interface GMULivePhotoSingleUploadRequest : NSObject
- (void)start;
- (void)didCompleteWithError:(id)error resultantMediaItem:(id)result;
@end
@implementation GMULivePhotoSingleUploadRequest
- (void)start {
    called++;
}
- (void)didCompleteWithError:(id)error resultantMediaItem:(id)result {
    called++;
    lastResult = result;
    lastError = error;
}
@end
@interface GMUUploadMediaRequest : NSObject
- (void)uploadFetcherDidCompleteWithData:(id)data error:(id)error;
@end
@implementation GMUUploadMediaRequest
- (void)uploadFetcherDidCompleteWithData:(id)data error:(id)error {
    called++;
    lastResult = data;
    lastError = error;
}
@end
// Wrong signature must be reported as unmatched, never patched.
@interface GMUAssetUploadRequest : NSObject
- (BOOL)start;
@end
@implementation GMUAssetUploadRequest
- (BOOL)start {
    called++;
    return YES;
}
@end
static id scottyData, scottyError;
static void Scotty(id object, SEL selector, id asset, BOOL cellular, BOOL background, id start,
                   id progress, id released, void (^completion)(id, id)) {
    called++;
    assert(cellular && !background);
    assert(asset == scottyData);
    if (completion)
        completion(scottyData, scottyError);
}
static void Stateless(id object, SEL selector, id asset, BOOL cellular, id progress,
                      void (^completion)(id, id)) {
    called++;
    assert(!cellular);
    assert(asset == scottyData);
    if (completion)
        completion(scottyData, scottyError);
}
int main(void) {
    @autoreleasepool {

#ifndef GS_TEST_LEGACY
        Class scotty =
            objc_allocateClassPair(NSObject.class,
                                   "_TtC84googlemac_iPhone_Shared_Photos_Upload_Request_Scotty_"
                                   "ScottyUploadServiceImpl_ImplLib23ScottyUploadServiceImpl",
                                   0);
        SEL scottySelector =
            NSSelectorFromString(@"uploadWithAsset:shouldAllowCellular:useBackgroundSession:start:"
                                 @"progress:onDataReleased:completionHandler:");
        SEL statelessSelector = NSSelectorFromString(
            @"statelessUploadWithAsset:shouldAllowCellular:progress:completionHandler:");
        class_addMethod(scotty, scottySelector, (IMP)Scotty,
                        "v64@0:8@\"GMUUploadAsset\"16B24B28@?<v@?B>32@?<v@?d>40@?<v@?>48@?<v@?@"
                        "\"NSData\"@\"NSError\">56");
        class_addMethod(
            scotty, statelessSelector, (IMP)Stateless,
            "v44@0:8@\"GMUUploadAsset\"16B24@?<v@?d>28@?<v@?@\"NSData\"@\"NSError\">36");
        objc_registerClassPair(scotty);
#endif

        method_setImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)),
                                 (IMP)MainBundle);
        GSInstallUploadDiagnostics();
        assert(!GSUploadDiagnosticsAvailable());
        host = YES;
        version = GSFixtureVersion;
        GSInstallUploadDiagnostics();
        assert(GSUploadDiagnosticsAvailable());
        GMUUploadRequest *request = [GMUUploadRequest new];
        [request start];
        assert(called == 1 && [GSUploadDiagnosticsSnapshot()[@"events"] count] == 0);
        GSSetUploadDiagnostics(YES);
        id result = [GSPrivateResult new], error = [GSPrivateResult new];
        [request start];
        [request startFetcher];
        [request didCompleteWithSuccess:YES resultantMediaItem:result GS_ERROR_LABEL:GS_NO_ERROR];
        assert(lastResult == result && lastError == nil && lastSuccess);
        [request didCompleteWithSuccess:NO resultantMediaItem:nil GS_ERROR_LABEL:GS_FAILURE];
#ifdef GS_TEST_LEGACY
        assert(lastResult == nil && [lastError integerValue] == 73 && !lastSuccess);
#else
        assert(lastResult == nil && lastError == error && !lastSuccess);
#endif
        [[GMULivePhotoSingleUploadRequest new] didCompleteWithError:error
                                                 resultantMediaItem:result];
        assert(lastResult == result && lastError == error);
        [[GMUUploadMediaRequest new] uploadFetcherDidCompleteWithData:result error:error];
        assert(lastResult == result && lastError == error);
        assert([[GMUAssetUploadRequest new] start]);
        NSDictionary *snapshot = GSUploadDiagnosticsSnapshot();
        assert([snapshot[@"appVersion"] isEqual:GSFixtureVersion]);
        assert([snapshot[@"events"] count] == 6 && called == 8);
        NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        assert(![text containsString:@"SECRET_TOKEN"] && [text containsString:@"GSPrivateResult"]);
#ifndef GS_TEST_LEGACY
        scottyData = result;
        scottyError = error;
        __block NSUInteger completions = 0;
        void (^completion)(id, id) = ^(id data, id failure) {
            assert(data == result && failure == error);
            completions++;
        };
        ((void (*)(id, SEL, id, BOOL, BOOL, id, id, id, id))objc_msgSend)(
            [scotty new], scottySelector, result, YES, NO, nil, nil, nil, completion);
        ((void (*)(id, SEL, id, BOOL, id, id))objc_msgSend)([scotty new], statelessSelector, result,
                                                            NO, nil, completion);
        assert(completions == 2 && called == 10 &&
               [GSUploadDiagnosticsSnapshot()[@"events"] count] == 10);
#endif
        for (int i = 0; i < 300; i++)
            [request start];
        snapshot = GSUploadDiagnosticsSnapshot();
        assert([snapshot[@"events"] count] == 256 &&
               [snapshot[@"observedCount"] integerValue] == (
#ifdef GS_TEST_LEGACY
                                                                306
#else
                                                                310
#endif
                                                                ));
        GSSetUploadDiagnostics(NO);
        [request start];
        assert([GSUploadDiagnosticsSnapshot()[@"observedCount"] integerValue] == (
#ifdef GS_TEST_LEGACY
                                                                                     306
#else
                                                                                     310
#endif
                                                                                     ));
        return 0;
    }
}
