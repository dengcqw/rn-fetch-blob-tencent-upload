//
//  RNFetchBlobNetwork.m
//  RNFetchBlob
//
//  Created by wkh237 on 2016/6/6.
//  Copyright © 2016 wkh237. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "RNFetchBlobNetwork.h"

#import "RNFetchBlob.h"
#import "RNFetchBlobConst.h"
#import "RNFetchBlobProgress.h"

#import "TXUGCPublishListener.h"
#import "TXUGCPublish.h"

#if __has_include(<React/RCTAssert.h>)
#import <React/RCTRootView.h>
#import <React/RCTLog.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTBridge.h>
#else
#import "RCTRootView.h"
#import "RCTLog.h"
#import "RCTEventDispatcher.h"
#import "RCTBridge.h"
#endif

////////////////////////////////////////
//
//  HTTP request handler
//
////////////////////////////////////////

NSMapTable * expirationTable;

__attribute__((constructor))
static void initialize_tables() {
    if (expirationTable == nil) {
        expirationTable = [[NSMapTable alloc] init];
    }
}


@interface STVideoUploadDelegate : NSObject <TXVideoPublishListener>
@property (nonatomic, strong) TXUGCPublish *videoPublish;

@property (nonatomic, strong) id retainself;
@property (nullable, nonatomic) NSString * taskId;
@property (nonatomic) long long expectedBytes;
@property (nonatomic) long long receivedBytes;
@property (nonatomic) BOOL isServerPush;
@property (nullable, nonatomic) NSMutableData * respData;
@property (nullable, strong, nonatomic) RCTResponseSenderBlock callback;
@property (nullable, nonatomic) RCTBridge * bridge;
@property (nullable, nonatomic) NSDictionary * options;
@property (nullable, nonatomic) NSError * error;
@property (nullable, nonatomic) RNFetchBlobProgress *progressConfig;
@property (nullable, nonatomic) RNFetchBlobProgress *uploadProgressConfig;
@property (nullable, nonatomic, weak) NSURLSessionDataTask *task;
@end


@implementation RNFetchBlobNetwork


- (id)init {
    self = [super init];
    if (self) {
        self.requestsTable = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableWeakMemory];
        
        self.taskQueue = [[NSOperationQueue alloc] init];
        self.taskQueue.qualityOfService = NSQualityOfServiceUtility;
        self.taskQueue.maxConcurrentOperationCount = 10;
        self.rebindProgressDict = [NSMutableDictionary dictionary];
        self.rebindUploadProgressDict = [NSMutableDictionary dictionary];
    }
    
    return self;
}

+ (RNFetchBlobNetwork* _Nullable)sharedInstance {
    static id _sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    
    return _sharedInstance;
}

- (void) sendRequest:(__weak NSDictionary  * _Nullable )options
       contentLength:(long) contentLength
              bridge:(RCTBridge * _Nullable)bridgeRef
              taskId:(NSString * _Nullable)taskId
         withRequest:(__weak NSURLRequest * _Nullable)req
            callback:(_Nullable RCTResponseSenderBlock) callback
{
    RNFetchBlobRequest *request = [[RNFetchBlobRequest alloc] init];
    [request sendRequest:options
           contentLength:contentLength
                  bridge:bridgeRef
                  taskId:taskId
             withRequest:req
      taskOperationQueue:self.taskQueue
                callback:callback];
    
    @synchronized([RNFetchBlobNetwork class]) {
        [self.requestsTable setObject:request forKey:taskId];
        [self checkProgressConfig];
    }
}

- (void)uploadVideo:(NSDictionary *)dict
                  taskId:(NSString *)taskId
              bridge:(RCTBridge * _Nullable)bridgeRef
           callback:(RCTResponseSenderBlock)callback {
    STVideoUploadDelegate *request = [[STVideoUploadDelegate alloc] init];
    request.retainself = request;
    request.callback = callback;
    request.taskId = taskId;
    request.bridge = bridgeRef;
    
    NSString * fileURL = [dict[@"fileURL"] stringByRemovingPercentEncoding];
    TXPublishParam *publishParam = [[TXPublishParam alloc] init];
    publishParam.signature  = dict[@"sign"];
    publishParam.videoPath  = fileURL;
    [request.videoPublish publishVideo:publishParam];
    @synchronized([RNFetchBlobNetwork class]) {
        [self.requestsTable setObject:(RNFetchBlobRequest*)request forKey:taskId];
        [self checkProgressConfig];
    }
}

- (void) checkProgressConfig {
    //reconfig progress
    [self.rebindProgressDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RNFetchBlobProgress * _Nonnull config, BOOL * _Nonnull stop) {
        [self enableProgressReport:key config:config];
    }];
    [self.rebindProgressDict removeAllObjects];
    
    //reconfig uploadProgress
    [self.rebindUploadProgressDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RNFetchBlobProgress * _Nonnull config, BOOL * _Nonnull stop) {
        [self enableUploadProgress:key config:config];
    }];
    [self.rebindUploadProgressDict removeAllObjects];
}

- (void) enableProgressReport:(NSString *) taskId config:(RNFetchBlobProgress *)config
{
    if (config) {
        @synchronized ([RNFetchBlobNetwork class]) {
            if (![self.requestsTable objectForKey:taskId]) {
                [self.rebindProgressDict setValue:config forKey:taskId];
            } else {
                [self.requestsTable objectForKey:taskId].progressConfig = config;
            }
        }
    }
}

- (void) enableUploadProgress:(NSString *) taskId config:(RNFetchBlobProgress *)config
{
    if (config) {
        @synchronized ([RNFetchBlobNetwork class]) {
            if (![self.requestsTable objectForKey:taskId]) {
                [self.rebindUploadProgressDict setValue:config forKey:taskId];
            } else {
                [self.requestsTable objectForKey:taskId].uploadProgressConfig = config;
            }
        }
    }
}

- (void) cancelRequest:(NSString *)taskId
{
    NSURLSessionDataTask * task;
    STVideoUploadDelegate * videoUpload;
    
    @synchronized ([RNFetchBlobNetwork class]) {
        RNFetchBlobRequest *req = [self.requestsTable objectForKey:taskId];
        if ([req isKindOfClass:[STVideoUploadDelegate class]]) {
            videoUpload = (STVideoUploadDelegate *)req;
        } else {
            task = req.task;
        }
    }
    
    if (task && task.state == NSURLSessionTaskStateRunning) {
        [task cancel];
    }
    
    if (videoUpload) {
        [videoUpload.videoPublish canclePublish];
        videoUpload.retainself = nil;
    }
}

// removing case from headers
+ (NSMutableDictionary *) normalizeHeaders:(NSDictionary *)headers
{
    NSMutableDictionary * mheaders = [[NSMutableDictionary alloc]init];
    for (NSString * key in headers) {
        [mheaders setValue:[headers valueForKey:key] forKey:[key lowercaseString]];
    }
    
    return mheaders;
}

// #115 Invoke fetch.expire event on those expired requests so that the expired event can be handled
+ (void) emitExpiredTasks
{
    @synchronized ([RNFetchBlobNetwork class]){
        NSEnumerator * emu =  [expirationTable keyEnumerator];
        NSString * key;
        
        while ((key = [emu nextObject]))
        {
            RCTBridge * bridge = [RNFetchBlob getRCTBridge];
            id args = @{ @"taskId": key };
            [bridge.eventDispatcher sendDeviceEventWithName:EVENT_EXPIRE body:args];
            
        }
        
        // clear expired task entries
        [expirationTable removeAllObjects];
        expirationTable = [[NSMapTable alloc] init];
    }
}

@end

@implementation STVideoUploadDelegate

- (void)dealloc
{
    NSLog(@"STVideoUploadDelegate dealloc");
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _videoPublish = [[TXUGCPublish alloc] initWithUserID:@"1304755944"];
    _videoPublish.delegate = self;
  }
  return self;
}

- (void)onPublishProgress:(NSInteger)uploadBytes totalBytes:(NSInteger)totalBytes {
  NSLog(@"onPublishProgress [%ld/%ld]", uploadBytes, totalBytes);
  NSString *percent = [NSString stringWithFormat:@"%0.0f", (uploadBytes * 1.0)/totalBytes * 100];
    
  NSNumber * now = [NSNumber numberWithFloat:((float)uploadBytes/(float)totalBytes)];

  if ([self.uploadProgressConfig shouldReport:now]) {
        [self.bridge.eventDispatcher
         sendDeviceEventWithName:EVENT_PROGRESS_UPLOAD
         body:@{
                @"taskId": self.taskId,
                @"written": [NSString stringWithFormat:@"%ld", (long) uploadBytes],
                @"total": [NSString stringWithFormat:@"%ld", (long) totalBytes],
                @"percent": percent
                }
         ];
    }
}

- (void)onPublishComplete:(TXPublishResult*)result {
  NSLog(@"onPublishComplete [%d/%@]", result.retCode, result.retCode == 0? result.videoURL: result.descMsg);
    if (result.retCode == 0) {
      self.callback(@[@{@"videoURL": result.videoURL, @"videoId": result.videoId }, [NSNull null]]);
    } else {
      self.callback(@[[NSNull null], result.descMsg]);
    }
    self.retainself = nil;
}

@end
