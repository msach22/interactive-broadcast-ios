//
//  EventViewController.m
//  IB-ios
//
//  Created by Andrea Phillips on 30/09/2015.
//  Copyright (c) 2015 Andrea Phillips. All rights reserved.
//

#import <OpenTok/OpenTok.h>
#import "SIOSocket.h"

#import "OTKTextChatComponent.h"
#import "IBApi.h"

#import "EventViewController.h"

#import "SVProgressHUD.h"
#import "DotSpinnerViewController.h"

#import "OTDefaultAudioDevice.h"
#import "OTKAnalytics.h"

#import "EventView.h"
#import "IBDateFormatter.h"
#import "AppUtil.h"
#import "UIColor+AppAdditions.h"
#import "UIView+Category.h"
#import "UIImageView+Category.h"
#import "PerformSelectorWithDebounce.h"

#import <Reachability/Reachability.h>

@interface EventViewController () <OTSessionDelegate, OTSubscriberKitDelegate, OTPublisherDelegate, OTKTextChatDelegate,OTSubscriberKitNetworkStatsDelegate>

@property (nonatomic) NSMutableDictionary *user;
@property (nonatomic) NSMutableDictionary *eventData;
@property (nonatomic) NSMutableDictionary *connectionData;

@property (nonatomic) NSString *apikey;
@property (nonatomic) NSString *userName;
@property (nonatomic) BOOL isCeleb;
@property (nonatomic) BOOL isHost;
@property (nonatomic) NSMutableDictionary *errors;

@property (nonatomic) NSString *connectionQuality;

@property (nonatomic) NSMutableDictionary *instanceData;

@property (nonatomic) OTSession* session;
@property (nonatomic) OTSession* producerSession;
@property (nonatomic) OTPublisher* publisher;

@property (nonatomic) NSMutableDictionary *subscribers;
@property (nonatomic) OTSubscriber* producerSubscriber;
@property (nonatomic) OTSubscriber* privateProducerSubscriber;
@property (nonatomic) OTSubscriber* selfSubscriber;

@property (nonatomic) id<OTVideoCapture> cameraCapture;

@property (nonatomic) OTStream* celebrityStream;
@property (nonatomic) OTStream* hostStream;
@property (nonatomic) OTStream* fanStream;
@property (nonatomic) OTStream* producerStream;
@property (nonatomic) OTStream* privateProducerStream;

@property (nonatomic) OTConnection* producerConnection;

@property (nonatomic) OTKTextChatComponent *textChat;
@property (nonatomic) OTKAnalytics *logging;
@property (nonatomic) SIOSocket *signalingSocket;

@property (nonatomic) NSMutableDictionary* videoViews;
@property (nonatomic) CGFloat chatYPosition;

//Network Testing
@property (nonatomic) double prevVideoTimestamp;
@property (nonatomic) double prevVideoBytes;
@property (nonatomic) double prevAudioTimestamp;
@property (nonatomic) double prevAudioBytes;
@property (nonatomic) uint64_t prevVideoPacketsLost;
@property (nonatomic) uint64_t prevVideoPacketsRcvd;
@property (nonatomic) uint64_t prevAudioPacketsLost;
@property (nonatomic) uint64_t prevAudioPacketsRcvd;
@property (nonatomic) long video_bw;
@property (nonatomic) long audio_bw;
@property (nonatomic) double video_pl_ratio;
@property (nonatomic) double audio_pl_ratio;
@property (nonatomic) NSString *frameRate;
@property (nonatomic) NSString *resolution;

@property (nonatomic) EventView *eventView;
@property (nonatomic) BOOL isBackstage;
@property (nonatomic) BOOL isOnstage;
@property (nonatomic) BOOL shouldResendProducerSignal;
@property (nonatomic) BOOL inCallWithProducer;
@property (nonatomic) BOOL isLive;
@property (nonatomic) BOOL isFan;
@property (nonatomic) BOOL stopGoingLive;
@property (nonatomic) CGFloat unreadCount;

// Reachability
@property (nonatomic) Reachability *internetReachability;
@end

@implementation EventViewController


static NSString* const kTextChatType = @"chatMessage";

- (instancetype)initEventWithData:(NSMutableDictionary *)aEventData
                   connectionData:(NSMutableDictionary *)aConnectionData
                             user:(NSMutableDictionary *)aUser {
    
    if (self = [super initWithNibName:@"EventViewController" bundle:[NSBundle bundleForClass:[self class]]]) {
        
        OTDefaultAudioDevice *defaultAudioDevice = [[OTDefaultAudioDevice alloc] init];
        [OTAudioDeviceManager setAudioDevice:defaultAudioDevice];
        
        _instanceData = [aConnectionData mutableCopy];
        _eventData = [aEventData mutableCopy];
        _userName = aUser[@"name"] ? aUser[@"name"] : aUser[@"type"];
        _user = aUser;
        _isCeleb = [aUser[@"type"] isEqualToString:@"celebrity"];
        _isHost = [aUser[@"type"] isEqualToString:@"host"];
    
        
        _subscribers = [[NSMutableDictionary alloc]initWithCapacity:3];
        
        _isFan = !_isCeleb && !_isHost;
        
        //observers
        [self.eventData  addObserver:self
                          forKeyPath:@"status"
                             options:(NSKeyValueObservingOptionNew |
                                      NSKeyValueObservingOptionOld)
                             context:NULL];
        
        _internetReachability = [Reachability reachabilityForInternetConnection];
        [_internetReachability startNotifier];
    }
    return self;
}

-(void)viewDidLoad {
    
    [super viewDidLoad];
    self.eventView = (EventView *)self.view;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
    
    if (self.internetReachability.currentReachabilityStatus != NotReachable) {
        [self createEventToken];
    }
}

- (void)reachabilityChanged:(NSNotification *)notification {
    Reachability *reachability = [notification object];
    switch (reachability.currentReachabilityStatus) {
        case NotReachable:
            break;
        case ReachableViaWWAN:
        case ReachableViaWiFi:{
            
            if (!self.connectionData) {
                [self createEventToken];
            }
            break;
        }
    }
}

- (void)createEventToken{
    
    [SVProgressHUD show];
    [IBApi creteEventToken:self.user[@"type"]
                  back_url:_instanceData[@"backend_base_url"]
                      data:self.eventData
                completion:^(NSMutableDictionary *resultData) {
                    [SVProgressHUD dismiss];
                    self.connectionData = resultData;
                    self.eventData = [self.connectionData[@"event"] mutableCopy];
                    [self statusChanged];
                    self.eventView.eventName.text = [NSString stringWithFormat:@"%@ (%@)", self.eventData[@"event_name"], [AppUtil convertToStatusString:self.eventData]];
                    [self startSession];
                }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _videoViews = [[NSMutableDictionary alloc] init];
    _videoViews[@"fan"] = self.eventView.FanViewHolder;
    _videoViews[@"celebrity"] = self.eventView.CelebrityViewHolder;
    _videoViews[@"host"] = self.eventView.HostViewHolder;
    [self performSelector:@selector(adjustChildrenWidth) withObject:nil afterDelay:1.0];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)startSession{
    _prevVideoTimestamp = 0;
    _prevVideoBytes = 0;
    _prevAudioTimestamp = 0;
    _prevAudioBytes = 0;
    _prevVideoPacketsLost = 0;
    _prevVideoPacketsRcvd = 0;
    _prevAudioPacketsLost = 0;
    _prevAudioPacketsRcvd = 0;
    _video_bw = 0;
    _audio_bw = 0;
    _video_pl_ratio = -1;
    _audio_pl_ratio = -1;
    
    
    NSNumber *api = self.connectionData[@"apiKey"];
    self.apikey = [NSString stringWithFormat:@"%@", api];
    
    _session = [[OTSession alloc] initWithApiKey:self.apikey
                                       sessionId:self.connectionData[@"sessionIdHost"]
                                        delegate:self];
    
    self.eventView.getInLineBtn.hidden = YES;
    [self statusChanged];
    [self doConnect];
    
    if(_isFan){
        [self connectFanSignaling];
    }
    
}
-(void)loadChat{
    OTSession *currentSession;
    
    if(_isBackstage){
        currentSession = _producerSession;
    }else{
        currentSession = _session;
    }
    
    _textChat = [[OTKTextChatComponent alloc] init];
    
    _textChat.delegate = self;
    
    [_textChat setMaxLength:1050];
    
    [_textChat setSenderId:currentSession.connection.connectionId alias:@"You"];
    
    _chatYPosition = self.eventView.statusBar.layer.frame.size.height + self.eventView.chatBar.layer.frame.size.height;
    
    CGRect r = self.view.bounds;
    r.origin.y += _chatYPosition;
    r.size.height -= _chatYPosition;
    (_textChat.view).frame = r;
    [self.eventView insertSubview:_textChat.view belowSubview:self.eventView.chatBar];
    
    if(!_isFan){
        self.eventView.chatBtn.hidden = NO;
    }
    
    self.textChat.view.hidden = YES;
    self.eventView.chatBar.hidden = YES;
    _unreadCount = 0;
}

-(void)connectFanSignaling{
    
    __weak EventViewController *weakSelf = self;
    [SIOSocket socketWithHost:_instanceData[@"signaling_url"] response: ^(SIOSocket *socket)
     {
         _signalingSocket = socket;
         _signalingSocket.onConnect = ^()
         {
             [weakSelf.signalingSocket emit:@"joinRoom" args:@[weakSelf.connectionData[@"sessionIdProducer"]]];
         };
     }];
}

///SESSION CONNECTIONS///

- (void)doConnect
{
    OTError *error = nil;
    [_session connectWithToken:self.connectionData[@"tokenHost"] error:&error];

    if (error) {
        NSLog(@"connect error");
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    }
}

- (void)inLineConnect
{
    
    OTError *error = nil;
    [self.eventView showLoader];
    
    self.eventView.getInLineBtn.hidden = YES;
    [_logging logEventAction:@"fan_connects_backstage" variation:@"attempt"];
    [_producerSession connectWithToken:self.connectionData[@"tokenProducer"] error:&error];
    
    if (error) {
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        [_logging logEventAction:@"fan_connects_backstage" variation:@"failed"];
    }
    
}

-(void)disconnectBackstage
{
    [self unpublishFrom:_producerSession];
    _isBackstage = NO;
    self.eventView.inLineHolder.hidden = YES;
    self.eventView.getInLineBtn.hidden = NO;
    _shouldResendProducerSignal = YES;
}

-(void)disconnectBackstageSession{
    OTError *error = nil;
    if(_producerSession){
        [_producerSession disconnect:&error];
    }
    if(error){
        [_logging logEventAction:@"fan_disconnects_backstage" variation:@"failed"];
    }
}

-(void)forceDisconnect
{
    [self cleanupPublisher];
    NSString *text = [NSString stringWithFormat: @"There already is a %@ using this session. If this is you please close all applications or browser sessions and try again.", _isCeleb ? @"celebrity" : @"host"];
    
    
    
    [self.eventView showNotification:text useColor:[UIColor SLBlueColor]];
    OTError *error = nil;
    
    [_session disconnect:&error];
    self.eventView.videoHolder.hidden = YES;
    if (error) {
        NSLog(@"%@", error);
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    }
}

#pragma mark - logging
- (void)addLogging {
    NSString *apiKey = self.apikey;
    NSString *sessionId = _session.sessionId;
    NSInteger partner = [apiKey integerValue];
    NSString* sourceId = [NSString stringWithFormat:@"%@-event-%@",[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"],self.eventData[@"id"]];
    
    _logging = [[OTKAnalytics alloc] initWithSessionId:sessionId connectionId:_session.connection.connectionId partnerId:partner clientVersion:@"ib-ios-1.0.1" source:sourceId];
    
    NSString *me = _isHost ? @"host" : _isCeleb ? @"celebrity" : @"fan";
    NSString *logtype = [NSString stringWithFormat:@"%@_connects_onstage",me];
    [_logging logEventAction:logtype variation:@"success"];
}

#pragma mark - publishers
- (void)doPublish{
    if(_isFan){
        //FAN
        if(_isBackstage){
            [self sendNewUserSignal];
            [self publishTo:_producerSession];
            
            //[self showVideoPreview];
            self.eventView.closeEvenBtn.hidden = YES;
            _publisher.publishAudio = NO;
            (_publisher.view).frame = CGRectMake(0, 0, self.eventView.inLineHolder.bounds.size.width, self.eventView.inLineHolder.bounds.size.height);
            [self.eventView stopLoader];
        }
        if(_isOnstage){
            [self publishTo:_session];
            self.eventView.statusLabel.text = @"\u2022 You are live";
            [self.eventView.FanViewHolder addSubview:_publisher.view];
            _publisher.view.frame = CGRectMake(0, 0, self.eventView.FanViewHolder.bounds.size.width, self.eventView.FanViewHolder.bounds.size.height);
            self.eventView.closeEvenBtn.hidden = YES;
            self.eventView.getInLineBtn.hidden = YES;
        }
    }else{
        if(self.isCeleb && !_stopGoingLive){
            [self publishTo:_session];
            [_videoViews[@"celebrity"] addSubview:_publisher.view];
            (_publisher.view).frame = CGRectMake(0, 0, self.eventView.CelebrityViewHolder.bounds.size.width, self.eventView.CelebrityViewHolder.bounds.size.height);
            self.eventView.closeEvenBtn.hidden = NO;
        }
        if(_isHost && !_stopGoingLive){
            [self publishTo:_session];
            [_videoViews[@"host"] addSubview:_publisher.view];
            self.eventView.closeEvenBtn.hidden = NO;
            (_publisher.view).frame = CGRectMake(0, 0, self.eventView.HostViewHolder.bounds.size.width, self.eventView.HostViewHolder.bounds.size.height);
        }
        if(_stopGoingLive){
            return [self forceDisconnect];
        }
    }
    
    [self adjustChildrenWidth];
}

-(void) publishTo:(OTSession *)session
{
    if(_publisher){
        NSLog(@"PUBLISHER EXISTED");
    }
    NSString *me = _isHost ? @"host" : _isCeleb ? @"celebrity" : @"fan";
    NSString *session_name = _session.sessionId == session.sessionId ? @"onstage" : @"backstage";
    NSString *logtype = [NSString stringWithFormat:@"%@_publishes_%@",me,session_name];

    [_logging logEventAction:logtype variation:@"attempt"];
    
    
    if(!_publisher){
        _publisher = [[OTPublisher alloc] initWithDelegate:self name:self.userName];
    }
    
    OTError *error = nil;
    [session publish:_publisher error:&error];
    
    if (error)
    {
        NSLog(@"%@", error);
        [self sendWarningSignal];
        
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        [_logging logEventAction:logtype variation:@"fail"];


    }else{
        [_logging logEventAction:logtype variation:@"success"];
    }
    
}

-(void)unpublishFrom:(OTSession *)session
{
    OTError *error = nil;
    [session unpublish:_publisher error:&error];
    
    NSString *me = _isHost ? @"host" : _isCeleb ? @"celebrity" : @"fan";
    NSString *session_name = _session.sessionId == session.sessionId ? @"onstage" : @"backstage";
    NSString *logtype = [NSString stringWithFormat:@"%@_unpublishes_%@",me,session_name];
    
    [_logging logEventAction:logtype variation:@"attempt"];
    
    if (error) {
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        [_logging logEventAction:logtype variation:@"fail"];
    }
}

-(void)cleanupPublisher{
    if(_publisher){
        
        if(_publisher.stream.connection.connectionId == _session.connection.connectionId){
            NSLog(@"cleanup publisher from onstage");
        }else{
            NSLog(@"cleanup publisher from backstage");
        }
        
        [_publisher.view removeFromSuperview];
        _publisher = nil;
    }
}

# pragma mark - OTPublisher delegate callbacks

- (void)publisher:(OTPublisherKit *)publisher
    streamCreated:(OTStream *)stream
{
    if(_isBackstage){
        NSLog(@"stream Created PUBLISHER BACK");
        _selfSubscriber = [[OTSubscriber alloc] initWithStream:stream delegate:self];
        
        _selfSubscriber.subscribeToAudio = NO;
        
        OTError *error = nil;
        [_producerSession subscribe: _selfSubscriber error:&error];
        if (error)
        {
            NSLog(@"subscribe self error");
        }
    }else{
        NSLog(@"stream Created PUBLISHER ONST");
        [self doSubscribe:stream];
    }
    [self performSelector:@selector(startNetworkTest) withObject:nil afterDelay:5.0];

    
}

- (void)publisher:(OTPublisherKit*)publisher
  streamDestroyed:(OTStream *)stream
{
    NSLog(@"stream DESTROYED PUBLISHER");
    
    if(!_publisher.stream && !stream.connection) return;
    
    NSString *me = _isHost ? @"host" : _isCeleb ? @"celebrity" : @"fan";
    
    
    NSString *connectingTo =[self getStreamData:stream.connection.data];
    OTSubscriber *_subscriber = _subscribers[connectingTo];
    if ([_subscriber.stream.streamId isEqualToString:stream.streamId])
    {
        NSLog(@"stream DESTROYED ONSTAGE %@", connectingTo);
        
        NSString *logtype = [NSString stringWithFormat:@"%@_unpublishes_onstage",me];
        [_logging logEventAction:logtype variation:@"success"];
        
        [self cleanupSubscriber:connectingTo];
    }
    if(_selfSubscriber){
        [_producerSession unsubscribe:_selfSubscriber error:nil];
        _selfSubscriber = nil;
        
        NSString *logtype = [NSString stringWithFormat:@"%@_unpublishes_backstage",me];
        [_logging logEventAction:logtype variation:@"success"];    }
    
        [self cleanupPublisher];
}

- (void)publisher:(OTPublisherKit*)publisher
 didFailWithError:(OTError*) error
{
    NSLog(@"publisher didFailWithError %@", error);
    [self.errors setObject:error forKey:@"publisherError"];
    [self sendWarningSignal];
    [self cleanupPublisher];
}




//Subscribers
- (void)doSubscribe:(OTStream*)stream
{
    
    NSString *connectingTo =[self getStreamData:stream.connection.data];
    
    if(stream.session.connection.connectionId != _producerSession.connection.connectionId && ![connectingTo isEqualToString:@"producer"]){
        OTSubscriber *subs = [[OTSubscriber alloc] initWithStream:stream delegate:self];
        subs.viewScaleBehavior = OTVideoViewScaleBehaviorFit;
        _subscribers[connectingTo] = subs;
        
        NSString *me = _isHost ? @"host" : _isCeleb ? @"celebrity" : @"fan";
        NSString *logtype = [NSString stringWithFormat:@"%@_subscribes_%@",me,connectingTo];
        [_logging logEventAction:logtype variation:@"attempt"];

        
        OTError *error = nil;
        [_session subscribe: _subscribers[connectingTo] error:&error];
        if (error)
        {
            [self.errors setObject:error forKey:connectingTo];
            [_logging logEventAction:logtype variation:@"fail"];
            [self sendWarningSignal];
            NSLog(@"subscriber didFailWithError %@", error);
        }
        subs = nil;
        
    }
    if(stream.session.connection.connectionId == _producerSession.connection.connectionId && [connectingTo isEqualToString:@"producer"]){
        _producerSubscriber = [[OTSubscriber alloc] initWithStream:stream delegate:self];
        
        OTError *error = nil;
        [_producerSession subscribe: _producerSubscriber error:&error];
        if (error)
        {
            [self.errors setObject:error forKey:@"producer_backstage"];
            NSLog(@"subscriber didFailWithError %@", error);
        }
        
    }
    if(stream.session.connection.connectionId == _session.connection.connectionId && [connectingTo isEqualToString:@"producer"]){
        _privateProducerSubscriber = [[OTSubscriber alloc] initWithStream:stream delegate:self];
        
        OTError *error = nil;
        [_session subscribe: _privateProducerSubscriber error:&error];
        if (error)
        {
            [self.errors setObject:error forKey:@"producer_onstage"];
            NSLog(@"subscriber didFailWithError %@", error);
        }
        
    }
}


- (void)cleanupSubscriber:(NSString*)type
{
    OTSubscriber *_subscriber = _subscribers[type];
    if(_subscriber){
        NSLog(@"SUBSCRIBER CLEANING UP");
        [_subscriber.view removeFromSuperview];
        [_subscribers removeObjectForKey:type];
        _subscriber = nil;
    }
    
    [self adjustChildrenWidth];
}



# pragma mark - OTSubscriber delegate callbacks

- (void)subscriberDidConnectToStream:(OTSubscriberKit*)subscriber
{
    
    _frameRate = @"30";
    _resolution = @"640x480";
    
    if(subscriber.session.connection.connectionId == _session.connection.connectionId && subscriber.stream != _privateProducerStream){
        
        NSLog(@"subscriberDidConnectToStream (%@)", subscriber.stream.connection.connectionId);
        
        UIView *holder;
        NSString *connectingTo =[self getStreamData:subscriber.stream.connection.data];
        OTSubscriber *_subscriber = _subscribers[connectingTo];
        
        NSString *me = _isHost ? @"host" : _isCeleb ? @"celebrity" : @"fan";
        NSString *logtype = [NSString stringWithFormat:@"%@_subscribes_%@",me,connectingTo];
        [_logging logEventAction:logtype variation:@"success"];
        
        assert(_subscriber == subscriber);
        
        holder = _videoViews[connectingTo];
        
        (_subscriber.view).frame = CGRectMake(0, 0, holder.bounds.size.width,holder.bounds.size.height);
        
        [holder addSubview:_subscriber.view];
        self.eventView.eventImage.hidden = YES;
        [self adjustChildrenWidth];
        
    }
    if(_publisher && _publisher.stream.connection.connectionId == subscriber.stream.connection.connectionId){
        subscriber.subscribeToAudio = NO;
    }
    
}

- (void)subscriber:(OTSubscriberKit*)subscriber
  didFailWithError:(OTError*)error
{
    NSLog(@"subscriber %@ didFailWithError %@",
          subscriber.stream.streamId,
          error);
    [self.errors setObject:error forKey:@"subscriberError"];
    [self sendWarningSignal];
}

- (void)subscriberVideoDisabled:(OTSubscriberKit*)subscriber
                         reason:(OTSubscriberVideoEventReason)reason
{
    NSString *feed = [self getStreamData:subscriber.stream.connection.data];
    [self showAvatarFor:feed];
}

- (void)subscriberVideoEnabled:(OTSubscriberKit*)subscriber
                        reason:(OTSubscriberVideoEventReason)reason
{
    NSString *feed = [self getStreamData:subscriber.stream.connection.data];
    [self hideAvatarFor:feed];
}

- (void) showAvatarFor:(NSString*)feed
{
    UIView *feedView = _videoViews[feed];
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImageView* avatar = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"avatar" inBundle:bundle compatibleWithTraitCollection:nil]];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    
    CGRect frame = feedView.frame;
    avatar.frame = CGRectMake(0, 0, frame.size.width,frame.size.height);
    
    [_videoViews[feed] addSubview:avatar];
}

- (void) hideAvatarFor:(NSString*)feed
{
    for(UIView* subview in [_videoViews[feed] subviews])
    {
        if([subview isKindOfClass:[UIImageView class]])
        {
            return [subview removeFromSuperview];
        }
    }
}

//Network Test

-(NSArray*)getVideoLimits:(NSString*)resolution framerate:(NSString*)framerate
{
    
    NSDictionary* videoLimits = @{
                                  @"1280x720-30": @[@(250),@(350),@(600),@(1000)],
                                  @"1280x720-15": @[@(150),@(250),@(350),@(800)],
                                  @"1280x720-7": @[@(120),@(150),@(250),@(600)],
                                  //VGA
                                  @"640x480-30": @[@(600),@(250),@(250),@(600),@(150),@(150),@(120)],
                                  @"640x480-15": @[@(400),@(200),@(150),@(200),@(120),@(120),@(75)],
                                  @"640x480-7": @[@(200),@(150),@(120),@(150),@(75),@(50),@(50)],
                                  //QVGA
                                  @"320x240-30": @[@(300),@(200),@(120),@(200),@(120),@(100)],
                                  @"320x240-15": @[@(200),@(150),@(120),@(150),@(120),@(100)],
                                  @"320x240-7": @[@(150),@(100),@(100),@(150),@(75),@(50)]
                                  };
    
    NSString* key = [NSString stringWithFormat:@"%@-%@",resolution,framerate];
    NSLog(@"%@",key);
    return videoLimits[key];
}
-(void)startNetworkTest{
    if(_isBackstage || _isOnstage){
        if(_hostStream && _hostStream.hasVideo && _isLive){
            OTSubscriber *test = _subscribers[@"host"];
            test.networkStatsDelegate = self;
        }else if(_celebrityStream && _celebrityStream.hasVideo && _isLive){
            OTSubscriber *test = _subscribers[@"celebrity"];
            test.networkStatsDelegate = self;
        }else if(_selfSubscriber){
            _selfSubscriber.networkStatsDelegate = self;
        }
    }
}

-(void)subscriber:(OTSubscriberKit*)subscriber
videoNetworkStatsUpdated:(OTSubscriberKitVideoNetworkStats*)stats
{
    //    if(subscriber.stream && subscriber.stream.videoDimensions.width){
    //        resolution = [NSString stringWithFormat:@"%.0fx%.0f",subscriber.stream.videoDimensions.width, subscriber.stream.videoDimensions.height];
    //    }
    
    /// TODO : check how to update the framerate
    
    if (_prevVideoTimestamp == 0)
    {
        _prevVideoTimestamp = stats.timestamp;
        _prevVideoBytes = stats.videoBytesReceived;
    }
    
    if (stats.timestamp - _prevVideoTimestamp >= 3000)
    {
        _video_bw = (8 * (stats.videoBytesReceived - _prevVideoBytes)) / ((stats.timestamp - _prevVideoTimestamp) / 1000ull);
        
        subscriber.delegate = nil;
        _prevVideoTimestamp = stats.timestamp;
        _prevVideoBytes = stats.videoBytesReceived;
        [self processStats:stats];
    }
}

- (void)processStats:(id)stats
{
    if ([stats isKindOfClass:[OTSubscriberKitVideoNetworkStats class]])
    {
        _video_pl_ratio = -1;
        OTSubscriberKitVideoNetworkStats *videoStats =
        (OTSubscriberKitVideoNetworkStats *) stats;
        if (_prevVideoPacketsRcvd != 0) {
            uint64_t pl = videoStats.videoPacketsLost - _prevVideoPacketsLost;
            uint64_t pr = videoStats.videoPacketsReceived - _prevVideoPacketsRcvd;
            uint64_t pt = pl + pr;
            if (pt > 0)
                _video_pl_ratio = (double) pl / (double) pt;
        }
        _prevVideoPacketsLost = videoStats.videoPacketsLost;
        _prevVideoPacketsRcvd = videoStats.videoPacketsReceived;
    }
    //[self checkQualityAndSendSignal];
    [self performSelector:@selector(checkQualityAndSendSignal) withDebounceDuration:15.0];
}

- (void)checkQualityAndSendSignal
{
    if(_publisher && _publisher.session){
        
        NSArray *aVideoLimits = [self getVideoLimits:_resolution framerate:_frameRate];
        if (!aVideoLimits) return;
        
        NSString *quality;
        
        if([_resolution isEqualToString:@"1280x720"]){
            if (_video_bw < [aVideoLimits[0] longValue]) {
                quality = @"Poor";
            } else if (_video_bw > [aVideoLimits[0] longValue] && _video_bw <= [aVideoLimits[1] longValue] && _video_pl_ratio < 0.1 ) {
                quality = @"Poor";
            } else if (_video_bw > [aVideoLimits[0] longValue] && _video_pl_ratio > 0.1 ) {
                quality = @"Poor";
            } else if (_video_bw > [aVideoLimits[1] longValue] && _video_bw <= [aVideoLimits[2] longValue] && _video_pl_ratio < 0.1 ) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[2] longValue] && _video_bw <= [aVideoLimits[3] longValue] && _video_pl_ratio > 0.02 && _video_pl_ratio < 0.1 ) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[2] longValue] && _video_bw <= [aVideoLimits[3] longValue] && _video_pl_ratio < 0.02 ) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[3] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Great";
            }
        }
        
        if([_resolution isEqualToString:@"640x480"]){
            if(_video_bw > [aVideoLimits[0] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Great";
            } else if (_video_bw > [aVideoLimits[1] longValue] && _video_bw <= [aVideoLimits[0] longValue] && _video_pl_ratio <0.02) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[2] longValue] && _video_bw <= [aVideoLimits[3] longValue] && _video_pl_ratio >0.02 && _video_pl_ratio < 0.1) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[4] longValue] && _video_bw <= [aVideoLimits[0] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Good";
            } else if (_video_pl_ratio > 0.1 && _video_bw > [aVideoLimits[5] longValue]) {
                quality = @"Poor";
            } else if (_video_bw >[aVideoLimits[6] longValue] && _video_bw <= [aVideoLimits[4] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Poor";
            } else if (_video_bw < [aVideoLimits[6] longValue] || _video_pl_ratio > 0.1) {
                quality = @"Poor";
            }
        }
        if([_resolution isEqualToString:@"320x240"]){
            if(_video_bw > [aVideoLimits[0] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Great";
            } else if (_video_bw > [aVideoLimits[1] longValue] && _video_bw <= [aVideoLimits[0] longValue] && _video_pl_ratio <0.02) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[2] longValue] && _video_bw <= [aVideoLimits[3] longValue] && _video_pl_ratio >0.02 && _video_pl_ratio < 0.1) {
                quality = @"Good";
            } else if (_video_bw > [aVideoLimits[4] longValue] && _video_bw <= [aVideoLimits[1] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Good";
            } else if (_video_pl_ratio > 0.1 && _video_bw >[aVideoLimits[4] longValue]) {
                quality = @"Poor";
            } else if (_video_bw >[aVideoLimits[5] longValue] && _video_bw <= [aVideoLimits[4] longValue] && _video_pl_ratio < 0.1) {
                quality = @"Poor";
            } else if (_video_bw < [aVideoLimits[5] longValue] || _video_pl_ratio > 0.1) {
                quality = @"Poor";
            }
        }
        
        self.connectionQuality = quality;
        
        
        NSDictionary *data = @{
                               @"type" : @"qualityUpdate",
                               @"data" :@{
                                       @"connectionId": _publisher.session.connection.connectionId,
                                       @"quality" : quality,
                                       },
                               };
        
        OTError* error = nil;
        
        NSString *stringified = [NSString stringWithFormat:@"%@", [self stringify:data]];
        [_producerSession signalWithType:@"qualityUpdate" string:stringified connection:_producerSubscriber.stream.connection error:&error];
        
        if (error) {
            NSLog(@"signal didFailWithError %@", error);
        } else {
            NSLog(@"quality update sent  %@",quality);
        }
        
        [self startNetworkTest];
    }
}
///end network test //


# pragma mark - OTSession delegate callbacks

- (void)sessionDidConnect:(OTSession*)session
{
    
    if(_isFan){
        if(session.sessionId == _session.sessionId){
            NSLog(@"sessionDidConnect to Onstage");
            (self.eventView.statusLabel).text = @"";
            self.eventView.closeEvenBtn.hidden = NO;
            [self addLogging];
        }
        if(session.sessionId == _producerSession.sessionId){
            NSLog(@"sessionDidConnect to Backstage");
            _isBackstage = YES;
            self.eventView.closeEvenBtn.hidden = YES;
            self.eventView.leaveLineBtn.hidden = NO;
            self.eventView.getInLineBtn.hidden = YES;
            [self doPublish];
            [self loadChat];
            [_logging logEventAction:@"fan_connects_backstage" variation:@"success"];
        }
    }else{
        [self.eventView showLoader];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if(_stopGoingLive){
                [self forceDisconnect];
            }else{
                [self loadChat];
                [self addLogging];
                _isOnstage = YES;
                [self doPublish];
            }
            [self.eventView stopLoader];
        });
        
    }
}

- (void)sessionDidDisconnect:(OTSession*)session
{
    NSString* alertMessage =
    [NSString stringWithFormat:@"Session disconnected: (%@)", session.sessionId];
    NSLog(@"sessionDidDisconnect (%@)", alertMessage);
    if(session == _producerSession){
        _isBackstage = NO;
        self.eventView.inLineHolder.hidden = YES;
        self.eventView.getInLineBtn.hidden = NO;
        _shouldResendProducerSignal = YES;
        [self cleanupPublisher];
        self.eventView.leaveLineBtn.hidden = YES;
        [self.eventView hideNotification];
    }else{
        self.eventView.getInLineBtn.hidden = YES;
        _session = nil;
    }
}


- (void)session:(OTSession*)mySession
  streamCreated:(OTStream *)stream
{
    NSLog(@"session streamCreated (%@)", stream.streamId);
    if(mySession.connection.connectionId != _producerSession.connection.connectionId){
        
        if([stream.connection.data isEqualToString:@"usertype=producer"]){
            _privateProducerStream = stream;
            
        }else{
            if([stream.connection.data isEqualToString:@"usertype=host"]){
                _hostStream = stream;
                if(self.isHost){
                    _stopGoingLive = YES;
                }
            }
            
            if([stream.connection.data isEqualToString:@"usertype=celebrity"]){
                _celebrityStream = stream;
                if(self.isCeleb){
                    _stopGoingLive = YES;
                }
            }
            
            if([stream.connection.data isEqualToString:@"usertype=fan"]){
                _fanStream = stream;
            }
            
            
            if(_isLive || _isCeleb || _isHost){
                [self doSubscribe:stream];
            }
        }
        
        
        
        
    }else{
        if([stream.connection.data isEqualToString:@"usertype=producer"]){
            _producerStream = stream;
            if(_producerSession.connection){
                _shouldResendProducerSignal = YES;
            }
        }
        
    }
    
    
    
}

- (void)session:(OTSession*)session
streamDestroyed:(OTStream *)stream
{
    NSLog(@"session streamDestroyed (%@)", stream.streamId);
    NSLog(@"disconnectin from stream (%@)", stream.connection.data);
    
    NSString *type = [self getStreamData:stream.connection.data];
    if([type isEqualToString:@"producer"]){
        if(session.connection.connectionId == _producerSession.connection.connectionId){
            _producerStream = nil;
        }else{
            _privateProducerStream = nil;
        }
    }else{
        if(session.connection.connectionId == _session.connection.connectionId){
            
            if([type isEqualToString:@"host"]){
                _hostStream = nil;
            }
            
            if([type isEqualToString:@"celebrity"]){
                _celebrityStream = nil;
            }
            
            if([type isEqualToString:@"fan"]){
                _fanStream = nil;
            }
            [self cleanupSubscriber:type];
        }
    }
    
}


- (void)  session:(OTSession *)session
connectionCreated:(OTConnection *)connection
{
    NSLog(@"session connectionCreated (%@)", connection.connectionId);
}


- (void) session:(OTSession*)session
didFailWithError:(OTError*)error
{
    NSLog(@"didFailWithError: (%@)", error);
    [self.errors setObject:error forKey:@"sessionError"];
    [self sendWarningSignal];
    
}


#pragma mark - session signal handler

- (void)session:(OTSession*)session receivedSignalType:(NSString*)type fromConnection:(OTConnection*)connection withString:(NSString*)string {
    NSDictionary* messageData;
    
    if(string){
        messageData = [self parseJSON:string];
    }
    
    NSLog(@"session did receiveSignalType: (%@)", type);
    
    if([type isEqualToString:@"startEvent"]){
        self.eventData[@"status"] = @"P";
        self.eventView.eventName.text = [NSString stringWithFormat:@"%@ (%@)",  self.eventData[@"event_name"], [AppUtil convertToStatusString:self.eventData]];
        _shouldResendProducerSignal = YES;
        [self statusChanged];
    }
    if([type isEqualToString:@"openChat"]){
        //self.chatBtn.hidden = NO;
        _producerConnection = connection;
    }
    if([type isEqualToString:@"closeChat"]){
        if(_isFan){
            [self hideChatBox];
            self.eventView.chatBtn.hidden = YES;
        }
        
    }
    if([type isEqualToString:@"muteAudio"]){
        [messageData[@"mute"] isEqualToString:@"on"] ? [_publisher setPublishAudio: NO] : [_publisher setPublishAudio: YES];
    }
    
    if([type isEqualToString:@"videoOnOff"]){
        [messageData[@"video"] isEqualToString:@"on"] ? [_publisher setPublishVideo: YES] : [_publisher setPublishVideo: NO];
    }
    if([type isEqualToString:@"newBackstageFan"]){
        if(!_isFan){
            [self.eventView showNotification:@"A new FAN has been moved to backstage" useColor:[UIColor SLBlueColor]];
            [self.eventView performSelector:@selector(hideNotification) withObject:nil afterDelay:10.0];
        }
    }
    if([type isEqualToString:@"joinBackstage"]){
        self.eventView.statusLabel.text = @"BACKSTAGE";
        _publisher.publishAudio = YES;
        [self.eventView showVideoPreviewWithPublisher:self.publisher];
        [self.eventView showNotification:@"Going Backstage.You are sharing video." useColor:[UIColor SLBlueColor]];
    }
    
    if([type isEqualToString:@"newFanAck"]){
        _shouldResendProducerSignal = NO;
        [self performSelector:@selector(captureAndSendScreenshot) withObject:nil afterDelay:2.0];
    }
    if([type isEqualToString:@"producerLeaving"]){
        _shouldResendProducerSignal = YES;
    }
    if([type isEqualToString:@"resendNewFanSignal"]){
        
        if(_shouldResendProducerSignal){
            [self sendNewUserSignal];
        }
        
    }
    
    if([type isEqualToString:@"joinProducer"]){
        [self doSubscribe:_producerStream];
        _inCallWithProducer = YES;
        _publisher.publishAudio = YES;
        [self muteOnstageSession:YES];
        [self.eventView showNotification:@"YOU ARE NOW IN CALL WITH PRODUCER" useColor:[UIColor SLBlueColor]];
        [self.eventView showVideoPreviewWithPublisher:self.publisher];
    }
    if([type isEqualToString:@"privateCall"]){
        if(_isOnstage || _isBackstage){
            if ([messageData[@"callWith"] isEqualToString: _publisher.stream.connection.connectionId ]) {
                [self doSubscribe:_privateProducerStream];
                _inCallWithProducer = YES;
                [self muteOnstageSession:YES];
                [self.eventView showNotification:@"YOU ARE NOW IN PRIVATE CALL WITH PRODUCER" useColor:[UIColor SLBlueColor]];
                if(_isFan && _isBackstage){
                    [self.eventView showVideoPreviewWithPublisher:self.publisher];
                }
            }else{
                [self muteOnstageSession:YES];
                [self.eventView showNotification:@"OTHER PARTICIPANTS ARE IN A PRIVATE CALL. THEY MAY NOT BE ABLE TO HEAR YOU." useColor:[UIColor SLBlueColor]];
            }
        }
        
    }
    
    if([type isEqualToString:@"endPrivateCall"]){
        if(_isBackstage || _isOnstage){
            if(_inCallWithProducer){
                OTError *error = nil;
                [_session unsubscribe: _privateProducerSubscriber error:&error];
                _inCallWithProducer = NO;
                [self muteOnstageSession:NO];
                if(_isFan && _isBackstage){
                    [self.eventView hideVideoPreview];
                }
            }else{
                NSLog(@"I CAN HEAR AGAIN");
                [self muteOnstageSession:NO];
            }
            [self.eventView hideNotification];
        }
    }
    
    if([type isEqualToString:@"disconnectProducer"]){
        if(!_isOnstage){
            OTError *error = nil;
            [_producerSession unsubscribe: _producerSubscriber error:&error];
            _producerSubscriber = nil;
            _inCallWithProducer = NO;
            self.eventView.getInLineBtn.hidden = NO;
            _publisher.publishAudio = NO;
            [self muteOnstageSession:NO];
            [self.eventView hideNotification];
            [self.eventView hideVideoPreview];
        }
    }
    
    if([type isEqualToString:@"disconnectBackstage"]){
        self.eventView.leaveLineBtn.hidden = NO;
        self.eventView.statusLabel.text = @"IN LINE";
        _publisher.publishAudio = NO;
        [self.eventView hideNotification];
        [self.eventView hideVideoPreview];
    }
    if([type isEqualToString:@"goLive"]){
        self.eventData[@"status"] = @"L";
        self.eventView.eventName.text = [NSString stringWithFormat:@"%@ (%@)",  self.eventData[@"event_name"], [AppUtil convertToStatusString:self.eventData]];
        if(!_isLive){
            [self goLive];
        }
        [self statusChanged];
        self.eventView.eventImage.hidden = YES;
        
    }
    if([type isEqualToString:@"joinHost"]){
        
        [self disconnectBackstage];
        
        _isOnstage = YES;
        
        self.eventView.statusLabel.text = @"\u2022 You are live";
        self.eventView.statusLabel.hidden = NO;
        self.eventView.leaveLineBtn.hidden = YES;
        self.eventView.getInLineBtn.hidden = YES;
        [self hideChatBox];
        [self.eventView hideNotification];
        self.eventView.chatBtn.hidden = YES;
        
        if(![self.eventData[@"status"] isEqualToString:@"L"] && !_isLive){
            [self goLive];
        }
        [self.eventView hideVideoPreview];
        [DotSpinnerViewController show];
    }
    
    if ([type isEqualToString:@"joinHostNow"]) {
        
        // TODO: remove spinner
        [DotSpinnerViewController dismiss];
        [self doPublish];
    }
    
    if([type isEqualToString:@"finishEvent"]){
        self.eventData[@"status"] = @"C";
        self.eventView.eventName.text = [NSString stringWithFormat:@"%@ (%@)",  self.eventData[@"event_name"],  [AppUtil convertToStatusString:self.eventData]];
        self.eventView.statusLabel.hidden = YES;
        self.eventView.chatBtn.hidden = YES;
        [self statusChanged];
    }
    
    if([type isEqualToString:@"disconnect"]){
        
        self.eventView.statusLabel.hidden = YES;
        self.eventView.chatBtn.hidden = YES;
        self.eventView.closeEvenBtn.hidden = NO;
        [self hideChatBox];
        _isOnstage = NO;
        
        if(_publisher){
            [self unpublishFrom:_session];
        }
        [self disconnectBackstageSession];
        
        [self.eventView showNotification:@"Thank you for participating, you are no longer sharing video/voice. You can continue to watch the session at your leisure." useColor:[UIColor SLBlueColor]];
        [self.eventView performSelector:@selector(hideNotification) withObject:nil afterDelay:5.0];
        
    }
    
    if([type isEqualToString:@"chatMessage"]){
        if (![connection.connectionId isEqualToString:session.connection.connectionId]) {
            self.eventView.chatBtn.hidden = NO;
            _producerConnection = connection;
            NSDictionary *userInfo = [self parseJSON:string];
            OTKChatMessage *msg = [[OTKChatMessage alloc]init];
            msg.senderAlias = [self getStreamData:connection.data];
            msg.senderId = connection.connectionId;
            msg.text = userInfo[@"message"][@"message"];
            _unreadCount ++;
            [_textChat addMessage:msg];
            [self.eventView.chatBtn setTitle:[[NSNumber numberWithFloat:_unreadCount] stringValue] forState:UIControlStateNormal];
            
        }
        
        
        
    }
}

- (void)sendWarningSignal
{
    
    [self.eventView showNotification:@"You are experiencing network connectivity issues. Please try closing the application and coming back to the event" useColor:[UIColor SLRedColor]];
    [self.eventView performSelector:@selector(hideNotification) withObject:nil afterDelay:10.0];
    
    if(!_producerSession.connection) return;
    
    BOOL subscribing =  self.errors.count == 0 ? NO : YES;
    
    NSDictionary *data = @{
                           @"type" : @"warning",
                           @"data" :@{
                                   @"connected": @(YES),
                                   @"subscribing":@(subscribing),
                                   @"connectionId": _publisher && _publisher.stream ? _publisher.stream.connection.connectionId : @"",
                                   },
                           };
    
    OTError* error = nil;
    
    NSString *stringified = [NSString stringWithFormat:@"%@", [self stringify:data]];
    [_producerSession signalWithType:@"warning" string:stringified connection:_publisher.stream.connection error:&error];
    
    if (error) {
        NSLog(@"signal error %@", error);
    } else {
        NSLog(@"signal sent of type Warning");
    }
    
    
}

- (void)sendNewUserSignal
{
    NSLog(@"sending new user signal");
    
    if(!self.connectionQuality){
        self.connectionQuality = @"";
    }
    
    NSDictionary *data = @{
                           @"type" : @"newFan",
                           @"user" :@{
                                   @"username": self.userName,
                                   @"quality":self.connectionQuality,
                                   @"user_id": [[[UIDevice currentDevice] identifierForVendor] UUIDString],
                                   @"mobile":@(YES),
                                   @"os":@"iOS",
                                   @"device":[[UIDevice currentDevice] model]
                                   },
                           @"chat" : @{
                                   @"chatting" : @"false",
                                   @"messages" : @"[]"
                                   }
                           };
    
    OTError* error = nil;
    
    NSString *stringified = [NSString stringWithFormat:@"%@", [self stringify:data]];
    [_producerSession signalWithType:@"newFan" string:stringified connection:nil error:&error];
    
    if (error) {
        NSLog(@"signal error %@", error);
    } else {
        NSLog(@"signal sent of type newFan");
    }
    
}

- (void)captureAndSendScreenshot{

    if (_publisher.view) {
        UIImage *screenshot = [self.publisher.view captureViewImage];
        
        NSData *imageData = UIImageJPEGRepresentation(screenshot, 0.3);
        NSString *encodedString = [imageData base64EncodedStringWithOptions:0 ];
        NSString *formated = [NSString stringWithFormat:@"data:image/png;base64,%@",encodedString];
        
        [_signalingSocket emit:@"mySnapshot" args:@[@{
                                                       @"connectionId": _publisher.session.connection.connectionId,
                                                       @"sessionId" : _producerSession.sessionId,
                                                       @"snapshot": formated
                                                       }]];
    }
}

#pragma mark - status observer
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    
    if ([keyPath isEqual:@"status"]) {
        [self statusChanged];
    }
}

-(void) statusChanged{
    if([self.eventData[@"status"] isEqualToString:@"N"]){
        if(!_isFan){
            self.eventView.eventImage.hidden = YES;
        }else{
            self.eventView.eventImage.hidden = NO;
            [self.eventView.eventImage loadImageWithUrl:[NSString stringWithFormat:@"%@%@", _instanceData[@"frontend_url"], self.eventData[@"event_image"]]];
            self.eventView.getInLineBtn.hidden = YES;
        }
    };
    if([self.eventData[@"status"] isEqualToString:@"P"]){
        if(!_isFan){
            self.eventView.eventImage.hidden = YES;
        }else{
            self.eventView.eventImage.hidden = NO;
            [self.eventView.eventImage loadImageWithUrl:[NSString stringWithFormat:@"%@%@", _instanceData[@"frontend_url"], self.eventData[@"event_image"]]];
            self.eventView.getInLineBtn.hidden = NO;
        }
        
    };
    if([self.eventData[@"status"] isEqualToString:@"L"]){
        [self.eventView.eventImage loadImageWithUrl:[NSString stringWithFormat:@"%@%@", _instanceData[@"frontend_url"], self.eventData[@"event_image"]]];
        
        if (_subscribers.count > 0) {
            self.eventView.eventImage.hidden = YES;
        }else{
            self.eventView.eventImage.hidden = NO;
        }
        if(!_isCeleb && !_isHost && !_isBackstage && !_isOnstage){
            self.eventView.getInLineBtn.hidden = NO;
        }
        _isLive = YES;
    };
    if([self.eventData[@"status"] isEqualToString:@"C"]){
        if(self.eventData[@"event_image_end"]){
            [self.eventView.eventImage loadImageWithUrl:[NSString stringWithFormat:@"%@%@", _instanceData[@"frontend_url"], self.eventData[@"event_image_end"]]];
        }
        //Event Closed, disconect fan and show image
        self.eventView.eventImage.hidden = NO;
        self.eventView.getInLineBtn.hidden = YES;
        self.eventView.leaveLineBtn.hidden = YES;
        
        OTError *error = nil;
        
        [_session disconnect:&error];
        if(_isBackstage){
            [self disconnectBackstageSession];
        }
        if (error) {
            NSLog(@"error: (%@)", error);
            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        }
        [self cleanupPublisher];
        self.eventView.closeEvenBtn.hidden = NO;
        
    };
    
};

-(void)goLive{
    NSLog(@"Event changed status to LIVE");
    _isLive = YES;
    if(_hostStream && !_subscribers[@"host"]){
        [self doSubscribe:_hostStream];
    }
    if(_celebrityStream && !_subscribers[@"celebrity"]){
        [self doSubscribe:_celebrityStream];
    }
    if(_fanStream && !_subscribers[@"fan"]){
        [self doSubscribe:_fanStream];
    }
}


#pragma mark - OTChat
- (void)keyboardWillShow:(NSNotification*)aNotification
{
    NSDictionary* info = aNotification.userInfo;
    CGSize kbSize = [info[UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    double duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    _chatYPosition = 106 - _textChat.view.bounds.size.height ;
    [UIView animateWithDuration:duration animations:^{
        CGRect r = self.view.bounds;
        r.origin.y += _chatYPosition;
        r.size.height -= _chatYPosition + kbSize.height;
        _textChat.view.frame = r;
    }];
}

- (void)keyboardWillHide:(NSNotification*)aNotification
{
    NSDictionary* info = aNotification.userInfo;
    double duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    _chatYPosition = self.eventView.statusBar.layer.frame.size.height + self.eventView.chatBar.layer.frame.size.height;
    
    [UIView animateWithDuration:duration animations:^{
        
        CGRect r = self.view.bounds;
        r.origin.y += _chatYPosition;
        r.size.height -= _chatYPosition;
        _textChat.view.frame = r;
    }];
}

- (BOOL)onMessageReadyToSend:(OTKChatMessage *)message {
    OTError *error = nil;
    OTSession *currentSession;
    currentSession = _producerSession;
    
    NSDictionary *user_message = @{@"message": message.text};
    NSDictionary *userInfo = @{@"message": user_message};
    
    [currentSession signalWithType:kTextChatType string:[self stringify:userInfo] connection: _producerConnection error:&error];
    if (error) {
        return NO;
    }
    return YES;
}


#pragma mark - Utils
- (void) adjustChildrenWidth{
    CGFloat c = 0;
    CGFloat new_width = 1;
    CGFloat new_height = self.eventView.internalHolder.bounds.size.height;
    if(_subscribers.count == 0){
        self.eventView.eventImage.hidden = NO;
    }
    else{
        self.eventView.eventImage.hidden = YES;
        new_width = CGRectGetWidth([UIScreen mainScreen].bounds) / _subscribers.count;
    }
    
    NSArray *viewNames = @[@"host",@"celebrity",@"fan"];
    
    for(NSString *viewName in viewNames){
        if(_subscribers[viewName]){
            [_videoViews[viewName] setHidden:NO];
            OTSubscriber *temp = _subscribers[viewName];
            
            [_videoViews[viewName] setFrame:CGRectMake((c*new_width), 0, new_width, new_height)];
            temp.view.frame = CGRectMake(0, 0, new_width,new_height);
            c++;
            
        }else{
            [_videoViews[viewName] setHidden:YES];
            [_videoViews[viewName] setFrame:CGRectMake(0, 0, 5,new_height)];
        }
        
    }
}

-(NSString*)getStreamData:(NSString*)data {
    return [data stringByReplacingOccurrencesOfString:@"usertype=" withString:@""];
}

-(NSDictionary*)parseJSON:(NSString*)string{
    NSString *toParse = [[NSString alloc] initWithString:string];
    NSError *errorDictionary = nil;
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:[toParse dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&errorDictionary];
    return dictionary;
}

-(NSString*)stringify:(NSDictionary*)data{
    NSError *err;
    NSData *jsonData = [NSJSONSerialization  dataWithJSONObject:data options:0 error:&err];
    NSString *string = [[NSString alloc] initWithData:jsonData   encoding:NSUTF8StringEncoding];
    return string;
}

#pragma mark - fan Actions
- (IBAction)chatNow:(id)sender {
    [UIView animateWithDuration:0.5 animations:^() {
        [self showChatBox];
        _unreadCount = 0;
        [self.eventView.chatBtn setTitle:@"" forState:UIControlStateNormal];
    }];
}

- (IBAction)closeChat:(id)sender {
    [UIView animateWithDuration:0.5 animations:^() {
        [self hideChatBox];
        if(!_isFan){
            self.eventView.chatBtn.hidden = NO;
        }
    }];
}

- (IBAction)getInLineClick:(id)sender {
    self.userName = self.userName;
    _producerSession = [[OTSession alloc] initWithApiKey:self.apikey
                                               sessionId:self.connectionData[@"sessionIdProducer"]
                                                delegate:self];
    [self inLineConnect];
}

- (IBAction)leaveLine:(id)sender {
    self.eventView.leaveLineBtn.hidden = YES;
    self.eventView.chatBtn.hidden = YES;
    self.eventView.closeEvenBtn.hidden = NO;
    [self disconnectBackstage];
    [self disconnectBackstageSession];
    self.eventView.statusLabel.text = @"";
    self.eventView.getInLineBtn.hidden = NO;
    
}

-(void)muteOnstageSession:(BOOL)mute {
    for(NSString *_subscriber in _subscribers){
        OTSubscriber *sub = _subscribers[_subscriber];
        sub.subscribeToAudio = !mute;
    }
}

//UI

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

-(void)showChatBox{
    self.eventView.chatBtn.hidden = YES;
    self.textChat.view.hidden = NO;
    self.eventView.chatBar.hidden = NO;
}

-(void)hideChatBox{
    self.textChat.view.hidden = YES;
    self.eventView.chatBar.hidden = YES;
}

-(IBAction)dismissInlineTxt:(id)sender {
    [self.eventView hideVideoPreview];
}

//GO BACK

- (IBAction)goBack:(id)sender {

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
        
        OTError *error = nil;
        if(_producerSession){
            [self disconnectBackstageSession];
        }
        if(_session){
            [_session disconnect:&error];
        }
        
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                [SVProgressHUD showErrorWithStatus:error.localizedDescription];
            });
        }
    });
    
    [self dismissViewControllerAnimated:NO completion:nil];
}

#pragma mark - orientation
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

@end