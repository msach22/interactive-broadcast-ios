//
//  ViewController.m
//  IB-ios
//
//  Created by Andrea Phillips on 30/09/2015.
//  Copyright (c) 2015 Andrea Phillips. All rights reserved.
//

#import "ViewController.h"
#import "CustomEventsViewController.h"
#import <IBKit/IBKit.h>
#import <Crashlytics/Crashlytics.h>

static NSString * const instanceIdentifier = @"AAAA1";
static NSString * const backendBaseUrl = @"https://tokbox-ib-staging-tesla.herokuapp.com";
static NSString * const demoBackend = @"https://tokbox-ib-demos-tesla.herokuapp.com";
static NSString * const MLBBackend = @"https://spotlight-tesla-mlb.herokuapp.com";
static NSString * const mlbpass = @"spotlight-mlb-210216";

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIButton *celebrityButton;
@property (weak, nonatomic) IBOutlet UIButton *hostButton;
@property (weak, nonatomic) IBOutlet UIButton *fanButton;
@property (weak, nonatomic) IBOutlet UIButton *mlbFanButton;
@property (weak, nonatomic) IBOutlet UIButton *fanCustomEventsButton;
@property (weak, nonatomic) IBOutlet UIButton *celebrityCustomEventsButton;
@property (weak, nonatomic) IBOutlet UIButton *hostCustomEventsButton;
@property (weak, nonatomic) IBOutlet UITextField *adminIdField;
@property (weak, nonatomic) IBOutlet UISegmentedControl *enviromentPicker;


@property (nonatomic) NSDictionary *requestData;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [IBApi configureBackendURL:demoBackend];
    _requestData = @{
                     @(self.celebrityButton.hash): [IBUser userWithIBUserRole:IBUserRoleCelebrity name:@"Celebrity"],
                     @(self.hostButton.hash): [IBUser userWithIBUserRole:IBUserRoleHost name:@"Host"],
                     @(self.fanButton.hash): [IBUser userWithIBUserRole:IBUserRoleFan name:@"FanName"],
                     @(self.mlbFanButton.hash): [IBUser userWithIBUserRole:IBUserRoleFan name:@"FanName"],
                     @(self.fanCustomEventsButton.hash): [IBUser userWithIBUserRole:IBUserRoleFan name:@"Fan"],
                     @(self.celebrityCustomEventsButton.hash): [IBUser userWithIBUserRole:IBUserRoleCelebrity name:@"Celebrity"],
                     @(self.hostCustomEventsButton.hash): [IBUser userWithIBUserRole:IBUserRoleHost name:@"Host"]
                    };
}

- (IBAction)mlbEventButtonPressed:(UIButton *)sender {
    
    [IBApi configureBackendURL:MLBBackend];
    __weak ViewController *weakSelf = (ViewController *)self;
    [[IBApi sharedManager] getInstanceWithInstanceId:mlbpass
                                          completion:^(IBInstance *instance, NSError *error) {
                                              if (!error) {
                                                  NSMutableDictionary *instance_data = [NSMutableDictionary dictionaryWithDictionary:@{}];
                                                  instance_data[@"backend_base_url"] = MLBBackend;
                                  
                                                  dispatch_async(dispatch_get_main_queue(), ^(){
                                                      UIViewController *viewcontroller;
                                                      if(instance.events.count != 1){
                                                          viewcontroller = [[EventsViewController alloc] initWithInstance:instance user:weakSelf.requestData[@(sender.hash)]];
                                                      }
                                                      else {
                                                          viewcontroller = [[EventViewController alloc] initWithInstance:instance eventIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] user:weakSelf.requestData[@(sender.hash)]];
                                                      }
                                                      [weakSelf presentViewController:viewcontroller animated:YES completion:nil];
                                                  });
                                              }
                                          }];

}

- (IBAction)eventButtonPressed:(UIButton *)sender {

    if((sender != self.fanCustomEventsButton ) && (sender != self.hostCustomEventsButton) && (sender != self.celebrityCustomEventsButton)) {
        
        NSString * selectedEnviroment = self.enviromentPicker.selectedSegmentIndex == 0 ? backendBaseUrl : demoBackend;
        [IBApi configureBackendURL:selectedEnviroment];
        
        __weak ViewController *weakSelf = (ViewController *)self;
        [[IBApi sharedManager] getInstanceWithAdminId: self.adminIdField.text
                                           completion:^(IBInstance *instance, NSError *error) {
                             
                                               if (!error) {
                                                   
                                                   dispatch_async(dispatch_get_main_queue(), ^(){
                                       
                                                       UIViewController *viewcontroller;
                                                       if(instance.events.count != 1){
                                                           viewcontroller = [[EventsViewController alloc] initWithInstance:instance user:weakSelf.requestData[@(sender.hash)]];
                                                       }
                                                       else {
                                                           viewcontroller = [[EventViewController alloc] initWithInstance:instance eventIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] user:weakSelf.requestData[@(sender.hash)]];
                                                       }
                                       
                                                       [weakSelf presentViewController:viewcontroller animated:YES completion:nil];
                                                   });
                                               }
                                           }];
    }
    else {
        
        [self performSegueWithIdentifier:@"EventSegueIdentifier" sender:sender];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(UIButton *)sender {
    
    CustomEventsViewController *vc = [segue destinationViewController];
    
    if ([segue.identifier isEqualToString:@"EventSegueIdentifier"]) {
        vc.instance_id = instanceIdentifier;
        vc.user = self.requestData[@(sender.hash)];
    }
}

@end
