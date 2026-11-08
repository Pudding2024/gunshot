#import "../Shared/GSLocalization.h"
#import "GSExporter.h"
#import "../Shared/IPCProtocol.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static PHAssetResource *GSPreferredResource(NSArray<PHAssetResource *> *resources,
                                            NSArray<NSNumber *> *types) {
    PHAssetResource *raw = nil;
    for (NSNumber *type in types)
        for (PHAssetResource *resource in resources) {
            if (resource.type != type.integerValue)
                continue;
            UTType *format = [UTType typeWithIdentifier:resource.uniformTypeIdentifier];
            if ([format conformsToType:UTTypeRAWImage]) {
                if (!raw)
                    raw = resource;
            } else
                return resource;
        }
    return raw; // Preserve RAW when no rendered/JPEG companion exists.
}
static PHAssetResource *GSOriginalResourceFor(PHAssetResource *resource,
                                              NSArray<PHAssetResource *> *resources) {
    NSArray<NSNumber *> *types = nil;
    switch (resource.type) {
    case PHAssetResourceTypeFullSizePhoto:
        types = @[ @(PHAssetResourceTypePhoto), @(PHAssetResourceTypeAlternatePhoto) ];
        break;
    case PHAssetResourceTypeFullSizeVideo:
        types = @[ @(PHAssetResourceTypeVideo) ];
        break;
    case PHAssetResourceTypeFullSizePairedVideo:
        types = @[ @(PHAssetResourceTypePairedVideo) ];
        break;
    default:
        return resource;
    }
    return GSPreferredResource(resources, types) ?: resource;
}
static NSString *GSExportFilename(PHAssetResource *resource,
                                  NSArray<PHAssetResource *> *resources) {
    PHAssetResource *original = GSOriginalResourceFor(resource, resources);
    NSString *originalName = original.originalFilename.lastPathComponent;
    NSString *selectedName = resource.originalFilename.lastPathComponent;
    if (!originalName.length)
        return selectedName;
    NSString *basename = originalName.stringByDeletingPathExtension;
    NSString *originalExtension = originalName.pathExtension;
    NSString *extension = originalExtension;
    UTType *format = [UTType typeWithIdentifier:resource.uniformTypeIdentifier];
    NSString *preferredExtension = format.preferredFilenameExtension;
    UTType *originalFormat = [UTType typeWithFilenameExtension:originalExtension];
    if (![originalFormat.identifier isEqualToString:resource.uniformTypeIdentifier])
        extension = preferredExtension;
    if (!extension.length)
        extension = selectedName.pathExtension;
    return extension.length ? [basename stringByAppendingPathExtension:extension] : basename;
}
static NSArray<NSURL *> *GSWriteCurrentResources(PHAsset *asset, NSURL *directory,
                                                 NSError **error) {
    NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
    NSMutableArray *chosen = [NSMutableArray array];
    PHAssetResource *primary = GSPreferredResource(
        resources, asset.mediaType == PHAssetMediaTypeVideo
                       ? @[ @(PHAssetResourceTypeFullSizeVideo), @(PHAssetResourceTypeVideo) ]
                       : @[
                             @(PHAssetResourceTypeFullSizePhoto), @(PHAssetResourceTypePhoto),
                             @(PHAssetResourceTypeAlternatePhoto)
                         ]);
    if (primary)
        [chosen addObject:primary];
    if (primary && asset.mediaType == PHAssetMediaTypeImage &&
        !(asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) &&
        ![[UTType typeWithIdentifier:primary.uniformTypeIdentifier]
            conformsToType:UTTypeRAWImage]) {
        // Keep the current rendered image and its untouched RAW companion.
        for (PHAssetResource *resource in resources)
            if (resource != primary &&
                (resource.type == PHAssetResourceTypePhoto ||
                 resource.type == PHAssetResourceTypeAlternatePhoto) &&
                [[UTType typeWithIdentifier:resource.uniformTypeIdentifier]
                    conformsToType:UTTypeRAWImage]) {
                [chosen addObject:resource];
                break;
            }
    }
    if (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) {
        // Edited components must belong to the same rendition. Never pair an
        // edited still with the unedited movie or silently upload the original.
        PHAssetResource *movie =
            GSPreferredResource(resources, primary.type == PHAssetResourceTypeFullSizePhoto
                                               ? @[ @(PHAssetResourceTypeFullSizePairedVideo) ]
                                               : @[ @(PHAssetResourceTypePairedVideo) ]);
        if (movie)
            [chosen addObject:movie];
    }
    if (!chosen.count ||
        ((asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) && chosen.count != 2)) {
        if (error)
            *error = [NSError errorWithDomain:@"Gunshot"
                                         code:2
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             GSL(@"Original media resources are unavailable.")
                                     }];
        return nil;
    }
    NSMutableArray *files = [NSMutableArray array];
    for (PHAssetResource *r in chosen) {
        NSString *filename = GSExportFilename(r, resources);
        if (!filename.length) {
            if (error)
                *error =
                    [NSError errorWithDomain:@"Gunshot"
                                        code:2
                                    userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            GSL(@"Original media resources are unavailable.")
                                    }];
            return nil;
        }
        NSURL *url = [directory URLByAppendingPathComponent:filename];
        if ([NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            if (error)
                *error = [NSError
                    errorWithDomain:@"Gunshot"
                               code:3
                           userInfo:@{
                               NSLocalizedDescriptionKey : GSL(@"Duplicate media filename.")
                           }];
            return nil;
        }
        PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
        options.networkAccessAllowed = YES;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSError *exportError = nil;
        [PHAssetResourceManager.defaultManager writeDataForAssetResource:r
                                                                  toFile:url
                                                                 options:options
                                                       completionHandler:^(NSError *e) {
                                                           exportError = e;
                                                           dispatch_semaphore_signal(done);
                                                       }];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        if (exportError) {
            if (error)
                *error = exportError;
            return nil;
        }
        [files addObject:url];
    }
    return files;
}
NSArray<NSURL *> *GSExportAsset(PHAsset *asset, NSURL *directory, NSError **error) {
    // Native backup may schedule many assets simultaneously. Keep PhotoKit/cloud
    // resource preparation bounded across native, album, picker and share routes;
    // this does not change the queue's network upload concurrency.
    NSCAssert(!NSThread.isMainThread, @"Export originals on a worker");
    static dispatch_queue_t exports;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exports =
            dispatch_queue_create("dev.tqmane.gunshot.original-export", DISPATCH_QUEUE_SERIAL);
    });
    __block NSArray *files = nil;
    __block NSError *failure = nil;
    dispatch_sync(exports, ^{
        @autoreleasepool {
            files = GSWriteCurrentResources(asset, directory, &failure);
        }
    });
    if (error)
        *error = failure;
    return files;
}
NSString *GSImportFiles(NSArray<NSURL *> *files, NSString *account, NSString *quality, NSDate *date,
                        NSError **error) {
    NSMutableArray *resources = [NSMutableArray array];
    for (NSURL *u in files) {
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:u.path
                                                                             error:error];
        if (!attrs || ![attrs[NSFileType] isEqual:NSFileTypeRegular])
            return nil;
        [resources addObject:@{@"name" : u.lastPathComponent, @"size" : attrs[NSFileSize]}];
    }
    NSDictionary *begin = GSRequest(
        @{
            @"op" : @"begin",
            @"account" : account ?: @"",
            @"quality" : quality ?: @"original",
            @"timestamp" : @((long long)(date ?: NSDate.date).timeIntervalSince1970),
            @"resources" : resources
        },
        error);
    NSString *identifier = begin[@"id"];
    if (!identifier)
        return nil;
    BOOL success = NO;
    // Retain failures before each chunk's autorelease pool drains. Writing the
    // caller's autoreleasing out parameter inside that pool leaves a dangling
    // NSError during ARC writeback in the native backup worker (#70).
    NSError *failure = nil;
    @try {
        for (NSUInteger i = 0; i < files.count; i++) {
            NSFileHandle *f = [NSFileHandle fileHandleForReadingAtPath:files[i].path];
            if (!f)
                return nil;
            @try {
                unsigned long long offset = 0;
                while (YES) {
                    @autoreleasepool {
                        NSData *chunk = [f readDataUpToLength:32768 error:&failure];
                        if (!chunk)
                            return nil;
                        if (!chunk.length)
                            break;
                        if (!GSRequest(
                                @{
                                    @"op" : @"append",
                                    @"id" : identifier,
                                    @"index" : @(i),
                                    @"offset" : @(offset),
                                    @"data" : [chunk base64EncodedStringWithOptions:0]
                                },
                                &failure))
                            return nil;
                        offset += chunk.length;
                    }
                }
            } @finally {
                [f closeAndReturnError:nil];
            }
        }
        NSDictionary *sealed = GSRequest(@{@"op" : @"seal", @"id" : identifier}, &failure);
        success = sealed != nil;
        return sealed[@"id"];
    } @finally {
        if (error)
            *error = failure;
        if (!success)
            GSRequest(@{@"op" : @"cancel", @"id" : identifier}, nil);
    }
}
