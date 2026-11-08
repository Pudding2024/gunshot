#import "../Media/GSBatchImport.h"
#import "../Media/GSExporter.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <assert.h>
#include <stdatomic.h>

// Exercise the real PhotoKit exporter, 32 KiB IPC importer and batch worker.
// Opaque bytes stand in for PhotoKit originals; no codec or network is mocked
// as successfully decoding these bytes.
static NSUInteger Queued, Written;
static BOOL IncludeUnreadable;
static atomic_int ActiveExports, PeakExports;
static NSArray *ExpectedResources;
static NSArray *FixtureResources;
static BOOL RejectAppend;
static NSMutableArray<NSMutableData *> *Received;
static NSData *OriginalBytes(BOOL movie) {
    NSMutableData *bytes = [NSMutableData dataWithLength:70013];
    uint8_t *p = bytes.mutableBytes;
    for (NSUInteger i = 0; i < bytes.length; i++)
        p[i] = (uint8_t)(i * 17 + (movie ? 3 : 7));
    memcpy(p,
           "\0\0\0\x18"
           "ftyp",
           8);
    memcpy(p + 8, movie ? "qt  " : "heic", 4);
    return bytes;
}
@implementation PHAsset
+ (PHFetchResult *)fetchAssetsWithLocalIdentifiers:(NSArray *)ids options:(id)options {
    assert(NO);
    return nil;
}
@end
@interface PHAssetResource ()
@property (nonatomic) BOOL unreadable;
@end
@implementation PHAssetResource
+ (NSArray *)assetResourcesForAsset:(PHAsset *)asset {
    if (FixtureResources)
        return FixtureResources;
    PHAssetResource *photo = [PHAssetResource new];
    photo.type = PHAssetResourceTypePhoto;
    photo.uniformTypeIdentifier = @"public.heic";
    photo.originalFilename =
        asset.localIdentifier.intValue % 2 ? @"original.HEIC" : @"original.heif";
    photo.unreadable = IncludeUnreadable && asset.localIdentifier.intValue == 30;
    if (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) {
        PHAssetResource *video = [PHAssetResource new];
        video.type = PHAssetResourceTypePairedVideo;
        video.uniformTypeIdentifier = @"com.apple.quicktime-movie";
        video.originalFilename = @"original.MOV";
        return @[ photo, video ];
    }
    return @[ photo ];
}
@end
@implementation PHAssetResourceRequestOptions
@end
@implementation PHAssetResourceManager
+ (instancetype)defaultManager {
    static id manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [self new];
    });
    return manager;
}
- (void)writeDataForAssetResource:(PHAssetResource *)resource
                           toFile:(NSURL *)url
                          options:(PHAssetResourceRequestOptions *)options
                completionHandler:(void (^)(NSError *))completion {
    assert(!NSThread.isMainThread && options.networkAccessAllowed);
    int active = atomic_fetch_add(&ActiveExports, 1) + 1;
    if (active > atomic_load(&PeakExports))
        atomic_store(&PeakExports, active);
    assert(active == 1);
    [NSThread sleepForTimeInterval:0.001];
    atomic_fetch_sub(&ActiveExports, 1);
    if (resource.unreadable) {
        completion([NSError errorWithDomain:@"private-resource-error" code:99 userInfo:nil]);
        return;
    }
    Written++;
    NSError *error = nil;
    [OriginalBytes(resource.type == PHAssetResourceTypePairedVideo ||
                   resource.type == PHAssetResourceTypeFullSizePairedVideo ||
                   resource.type == PHAssetResourceTypeVideo ||
                   resource.type == PHAssetResourceTypeFullSizeVideo) writeToURL:url
                                                                         options:0
                                                                           error:&error];
    completion(error);
}
@end
BOOL GSNativeIdentityMatches(NSString *identifier) {
    assert(NSThread.isMainThread);
    return [identifier isEqual:@"fixture"];
}
NSDictionary *GSRequest(NSDictionary *request, NSError **error) {
    assert(!NSThread.isMainThread);
    NSString *op = request[@"op"];
    if ([op isEqual:@"accounts"])
        return @{@"selected" : @"fixture@example.com"};
    if ([op isEqual:@"options"])
        return @{@"quality" : @"original"};
    if ([op isEqual:@"begin"]) {
        assert([request[@"quality"] isEqual:@"original"] &&
               [request[@"account"] isEqual:@"fixture@example.com"] &&
               [request[@"timestamp"] longLongValue] == 123);
        ExpectedResources = request[@"resources"];
        Received = [NSMutableArray array];
        for (NSDictionary *resource in ExpectedResources) {
            assert([resource[@"size"] intValue] == 70013);
            [Received addObject:[NSMutableData data]];
        }
        return @{@"id" : @"fixture-job"};
    }
    if ([op isEqual:@"append"]) {
        if (RejectAppend) {
            if (error)
                *error = [NSError errorWithDomain:@"fixture-chunk-failure" code:70 userInfo:nil];
            return nil;
        }
        NSMutableData *bytes = Received [[request [@"index"] unsignedIntegerValue]];
        assert(bytes.length == [request[@"offset"] unsignedIntegerValue]);
        NSData *chunk = [[NSData alloc] initWithBase64EncodedString:request[@"data"] options:0];
        assert(chunk.length > 0 && chunk.length <= 32768);
        [bytes appendData:chunk];
        return @{};
    }
    if ([op isEqual:@"seal"]) {
        for (NSUInteger i = 0; i < Received.count; i++) {
            BOOL movie = [ExpectedResources[i][@"name"] isEqual:@"original.MOV"];
            assert([Received[i] isEqual:OriginalBytes(movie)]);
        }
        Queued++;
        return @{@"id" : @"fixture-job"};
    }
    if ([op isEqual:@"cancel"])
        return @{};
    assert(NO);
    return nil;
}
static PHAssetResource *Resource(PHAssetResourceType type, NSString *name, NSString *uti) {
    PHAssetResource *resource = [PHAssetResource new];
    resource.type = type;
    resource.originalFilename = name;
    resource.uniformTypeIdentifier = uti;
    return resource;
}
static NSString *ExpectedFilename(NSString *originalName, NSString *preferredExtension) {
    NSString *originalExtension = originalName.pathExtension;
    NSString *extension =
        [preferredExtension caseInsensitiveCompare:originalExtension] == NSOrderedSame
            ? originalExtension
            : preferredExtension;
    return [[originalName stringByDeletingPathExtension] stringByAppendingPathExtension:extension];
}
static void CheckRendition(NSArray *resources, PHAssetMediaType media, BOOL live, NSArray *names) {
    FixtureResources = resources;
    PHAsset *asset = [PHAsset new];
    asset.mediaType = media;
    asset.mediaSubtypes = live ? PHAssetMediaSubtypePhotoLive : 0;
    NSURL *directory =
        [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                   stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    assert([NSFileManager.defaultManager createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil]);
    NSError *error = nil;
    NSArray *files = GSExportAsset(asset, directory, &error);
    if (names) {
        assert(!error && [[files valueForKey:@"lastPathComponent"] isEqual:names]);
        if (!live && media == PHAssetMediaTypeImage) {
            NSUInteger before = Queued;
            assert(GSImportFiles(files, @"fixture@example.com", @"original",
                                 [NSDate dateWithTimeIntervalSince1970:123], &error));
            assert(Queued == before + 1 && ExpectedResources.count == names.count);
            RejectAppend = YES;
            assert(!GSImportFiles(files, @"fixture@example.com", @"original",
                                  [NSDate dateWithTimeIntervalSince1970:123], &error));
            // This read used to retain a freed NSError after the chunk pool drained.
            assert([error.domain isEqual:@"fixture-chunk-failure"] && error.code == 70);
            RejectAppend = NO;
        }
    } else
        assert(!files && error);
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    FixtureResources = nil;
}
static NSDictionary *Run(void) {
    __block NSDictionary *done = nil;
    assert(GSStartBatchImport(
        60, @"album", YES,
        ^id(NSUInteger index) {
            PHAsset *asset = [PHAsset new];
            asset.localIdentifier = [NSString stringWithFormat:@"%lu", (unsigned long)index];
            asset.creationDate = [NSDate dateWithTimeIntervalSince1970:123];
            asset.mediaType = PHAssetMediaTypeImage;
            if (index == 5)
                asset.mediaSubtypes = PHAssetMediaSubtypePhotoLive;
            return asset;
        },
        @"fixture@example.com", @"fixture", nil,
        ^(NSDictionary *state) {
            done = state;
        }));
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    assert(done);
    return done;
}
int main(void) {
    @autoreleasepool {
        NSDictionary *result = Run();
        assert(Queued == 60 && Written == 61 && [result[@"queued"] intValue] == 60 &&
               [result[@"failed"] intValue] == 0);
        IncludeUnreadable = YES;
        result = Run();
        assert(Queued == 119 && [result[@"queued"] intValue] == 59 &&
               [result[@"failed"] intValue] == 1 && [result[@"remaining"] intValue] == 0);
        assert([result[@"failureCodes"][@"export_failed"] intValue] == 1);
        IncludeUnreadable = NO;
        dispatch_group_t group = dispatch_group_create();
        for (NSUInteger i = 0; i < 60; i++)
            dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    PHAsset *asset = [PHAsset new];
                    asset.mediaType = PHAssetMediaTypeImage;
                    asset.localIdentifier = @"native";
                    NSURL *directory = [NSURL
                        fileURLWithPath:[NSTemporaryDirectory()
                                            stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                            isDirectory:YES];
                    assert([NSFileManager.defaultManager createDirectoryAtURL:directory
                                                  withIntermediateDirectories:YES
                                                                   attributes:nil
                                                                        error:nil]);
                    NSArray *files = GSExportAsset(asset, directory, nil);
                    assert(files.count == 1);
                    assert([[NSData dataWithContentsOfURL:files[0]] isEqual:OriginalBytes(NO)]);
                    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
                }
            });
        assert(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) ==
               0);
        assert(atomic_load(&PeakExports) == 1);
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            PHAssetResource *raw =
                Resource(PHAssetResourceTypePhoto, @"original.DNG", @"com.adobe.raw-image");
            PHAssetResource *jpeg =
                Resource(PHAssetResourceTypeAlternatePhoto, @"original.JPG", @"public.jpeg");
            PHAssetResource *edited =
                Resource(PHAssetResourceTypeFullSizePhoto, @"edited.HEIC", @"public.heic");
            PHAssetResource *movie = Resource(PHAssetResourceTypePairedVideo, @"original.MOV",
                                              @"com.apple.quicktime-movie");
            PHAssetResource *editedMovie = Resource(PHAssetResourceTypeFullSizePairedVideo,
                                                    @"edited.MOV", @"com.apple.quicktime-movie");
            CheckRendition(
                @[ Resource(PHAssetResourceTypePhoto, @"original.HEIC", @"public.heic") ],
                PHAssetMediaTypeImage, NO, @[ @"original.HEIC" ]);
            NSString *rawExtension =
                [UTType typeWithIdentifier:@"com.adobe.raw-image"].preferredFilenameExtension;
            assert(rawExtension.length &&
                   [rawExtension caseInsensitiveCompare:@"JPG"] != NSOrderedSame);
            CheckRendition(
                @[ raw, jpeg ], PHAssetMediaTypeImage, NO,
                @[ @"original.JPG", ExpectedFilename(raw.originalFilename, rawExtension) ]);
            CheckRendition(
                @[ jpeg, raw ], PHAssetMediaTypeImage, NO,
                @[ @"original.JPG", ExpectedFilename(raw.originalFilename, rawExtension) ]);
            CheckRendition(
                @[ raw, jpeg, edited ], PHAssetMediaTypeImage, NO,
                @[ @"original.heic", ExpectedFilename(raw.originalFilename, rawExtension) ]);
            raw.unreadable = YES;
            CheckRendition(@[ raw, jpeg ], PHAssetMediaTypeImage, NO, nil);
            raw.unreadable = NO;
            CheckRendition(@[ raw ], PHAssetMediaTypeImage, NO, @[ @"original.DNG" ]);
            CheckRendition(@[ jpeg, edited ], PHAssetMediaTypeImage, NO, @[ @"original.heic" ]);
            CheckRendition(@[ jpeg, movie, editedMovie, edited ], PHAssetMediaTypeImage, YES,
                           @[ @"original.heic", @"original.MOV" ]);
            CheckRendition(@[ jpeg, movie, edited ], PHAssetMediaTypeImage, YES, nil);
            CheckRendition(
                @[
                    Resource(PHAssetResourceTypePhoto, @"IMG_0001.JPG", @"com.adobe.raw-image"),
                    Resource(PHAssetResourceTypeAlternatePhoto, @"IMG_0001.JPG", @"public.jpeg")
                ],
                PHAssetMediaTypeImage, NO,
                @[ @"IMG_0001.JPG", ExpectedFilename(@"IMG_0001.JPG", rawExtension) ]);
            CheckRendition(
                @[
                    Resource(PHAssetResourceTypePhoto, nil, @"public.jpeg"),
                    Resource(PHAssetResourceTypeFullSizePhoto, @"FullSizeRender.heic",
                             @"public.heic")
                ],
                PHAssetMediaTypeImage, NO, @[ @"FullSizeRender.heic" ]);
            CheckRendition(
                @[
                    Resource(PHAssetResourceTypeVideo, @"original.MOV",
                             @"com.apple.quicktime-movie"),
                    Resource(PHAssetResourceTypeFullSizeVideo, @"edited.MOV",
                             @"com.apple.quicktime-movie")
                ],
                PHAssetMediaTypeVideo, NO, @[ @"original.MOV" ]);
        });
        assert(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) ==
               0);
        NSLog(@"PASS 60 HEIC/HEIF originals, Live Photo resources, exact IPC bytes/timestamp, "
              @"unreadable original isolation and bounded concurrent native exports");
    }
}
