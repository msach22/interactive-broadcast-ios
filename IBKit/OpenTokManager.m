//
//  OpenTokManager.m
//  IBDemo
//
//  Created by Xi Huang on 5/29/16.
//  Copyright © 2016 Tokbox, Inc. All rights reserved.
//

#import "OpenTokManager.h"
#import "JSON.h"
#import "SIOSocket.h"
#import <SVProgressHUD/SVProgressHUD.h>

@interface OpenTokManager()
@property (nonatomic) SIOSocket *socket;
@end

@implementation OpenTokManager

- (instancetype)init {
    if (self = [super init]) {
        _subscribers = [[NSMutableDictionary alloc]initWithCapacity:3];
    }
    return self;
}

- (void)connectWithTokenHost:(NSString *)tokenHost {
    OTError *error = nil;
    [self.session connectWithToken:tokenHost error:&error];
    
    if (error) {
        NSLog(@"connectWithTokenHost error: %@", error);
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    }
}
- (void)muteOnstageSession:(BOOL)mute {
    for(NSString *subscriber in self.subscribers){
        OTSubscriber *sub = self.subscribers[subscriber];
        sub.subscribeToAudio = !mute;
    }
}

- (void)dealloc {
    [self.socket close];
}

#pragma subscriber
- (void)cleanupSubscriber:(NSString*)type
{
    OTSubscriber *_subscriber = _subscribers[type];
    if(_subscriber){
        NSLog(@"SUBSCRIBER CLEANING UP");
        [_subscriber.view removeFromSuperview];
        [_subscribers removeObjectForKey:type];
        _subscriber = nil;
    }
    
}

#pragma session
-(NSError*)disconnectBackstageSession {
    OTError *error = nil;
    if(_producerSession){
        [_producerSession disconnect:&error];
    }
    if(error){
        return error;
    }
    return nil;
}

#pragma mark - OpenTok Signaling
- (NSError *)sendWarningSignal {
    if (self.producerSession.sessionConnectionStatus != OTSessionConnectionStatusConnected) {
        return [NSError errorWithDomain:@"OpenTokManagerDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"sendNewUserSignalWithName: producerSession has not connected"}];
    }

    
    NSDictionary *data = @{
                           @"type" : @"warning",
                           @"data" :@{
                                   @"connected": @(YES),
                                   @"subscribing":@(_errors.count == 0 ? NO : YES),
                                   @"connectionId": _publisher && _publisher.stream ? _publisher.stream.connection.connectionId : @"",
                                   },
                           };
    
    OTError* error = nil;
    [_producerSession signalWithType:@"warning" string:[JSON stringify:data] connection:_publisher.stream.connection error:&error];
    
    if (error) {
        return [NSError errorWithDomain:@"OpenTokManagerDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"sendWarningSignal: unable to send warning signal"}];
    }
    return nil;
    
    
}

#pragma mark - SIOSocket Signaling
- (void)connectFanToSocketWithURL:(NSString *)url
                        sessionId:(NSString *)sessionId {
    
    __weak OpenTokManager *weakSelf = self;
    [SIOSocket socketWithHost:url response:^(SIOSocket *socket){
        weakSelf.socket = socket;
        weakSelf.socket.onConnect = ^(){
            
            [weakSelf.socket emit:@"joinRoom" args:@[sessionId]];
        };
    }];
}

- (NSError *)sendNewUserSignalWithName:(NSString *)username {
    
    if (self.producerSession.sessionConnectionStatus != OTSessionConnectionStatusConnected) {
        return [NSError errorWithDomain:@"OpenTokManagerDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"sendNewUserSignalWithName: producerSession has not connected"}];
    }
    
    if (!username) {
        return [NSError errorWithDomain:@"OpenTokManagerDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"sendNewUserSignalWithName: Misses username"}];
    }
    
    NSLog(@"sending new user signal");
    NSDictionary *data = @{
                           @"type":@"newFan",
                           @"user":
                               @{
                                   @"username": username,
                                   @"quality":@"",
                                   @"user_id": [[[UIDevice currentDevice] identifierForVendor] UUIDString],
                                   @"mobile":@(YES),
                                   @"os":@"iOS",
                                   @"device":[[UIDevice currentDevice] model]
                                },
                           @"chat":
                               @{
                                   @"chatting" : @"false",
                                   @"messages" : @"[]"
                                }
                           };
    
    OTError* error = nil;
    [self.producerSession signalWithType:@"newFan" string:[JSON stringify:data] connection:nil error:&error];
    if (error) {
        NSLog(@"%@", error);
    }
    return error;
}

- (NSError *)sendScreenShotSignalWithFormattedString:(NSString *)formattedString {
    
    if (!self.publisher.session.connection) {
        return [NSError errorWithDomain:@"OpenTokManagerDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"sendScreenShotWithFormattedString: pubisher has not published"}];
    }
    
    if (self.producerSession.sessionConnectionStatus != OTSessionConnectionStatusConnected) {
        return [NSError errorWithDomain:@"OpenTokManagerDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"sendNewUserSignalWithName: producerSession has not connected"}];
    }
    
    [self.socket emit:@"mySnapshot" args:@[
                                           @{
                                               @"connectionId": self.publisher.session.connection.connectionId,
                                               @"sessionId" : self.producerSession.sessionId,
                                               @"snapshot": formattedString
                                            }
                                        ]];
    
    return nil;
}

- (NSError*)updateQualitySignal:(NSString*)quality
{
    NSDictionary *data = @{
                           @"type" : @"qualityUpdate",
                           @"data" :@{
                                   @"connectionId":_publisher.session.connection.connectionId,
                                   @"quality" : quality,
                                   },
                           };
    
    OTError* error = nil;
    NSString *parsedString = [JSON stringify:data];
    [_producerSession signalWithType:@"qualityUpdate" string:parsedString connection:_producerSubscriber.stream.connection error:&error];
    
    if (error) {
        NSLog(@"signal didFailWithError %@", error);
        return error;
    }
    
    return nil;
}

@end
