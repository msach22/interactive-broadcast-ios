//
//  ViewController.m
//  spotlightIos
//
//  Created by Andrea Phillips on 30/09/2015.
//  Copyright (c) 2015 Andrea Phillips. All rights reserved.
//

#import "ViewController.h"
#import "MainSpotlightControllerViewController.h"

@interface ViewController ()
@property (strong, nonatomic) IBOutlet UIButton *SingleInstanceButton;
@property (strong, nonatomic) IBOutlet UIButton *SingleInstanceHost;
@property (strong, nonatomic) IBOutlet UIButton *SingleInstanceFan;
@property (strong, nonatomic) IBOutlet UITextField *nameTextField;

@property MainSpotlightControllerViewController  *spotlightController;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)openSingleInstance:(id)sender {
    self.instance_id = @"AAAA1";
    NSMutableDictionary *user =[NSMutableDictionary
                                dictionaryWithDictionary:@{
                                @"type":@"celebrity",
                                @"name":@"Celebridad",
                                @"id":@1234,
                                  }];
    
    [self presentController:user];
}

- (IBAction)singleInstanceAsHost:(id)sender {
    
    self.instance_id = @"AAAA1";
    NSMutableDictionary *user =[NSMutableDictionary
                                dictionaryWithDictionary:@{
                                                           @"type":@"host",
                                                           @"name":@"HOST NAME",
                                                           @"id":@1235,
                                                           }];
    
    [self presentController:user];

    
}
- (IBAction)singleInstanceAsFan:(id)sender {
    
    
    self.instance_id = @"AAAA1";
    NSMutableDictionary *user =[NSMutableDictionary
                                dictionaryWithDictionary:@{
                                                           @"type":@"fan",
                                                           @"name":@"FanName",
                                                           }];
    [self presentController:user];

}



- (IBAction)openMultipleInstance:(id)sender {
    self.instance_id = @"AAAA1";
    NSMutableDictionary *user =[NSMutableDictionary
                                dictionaryWithDictionary:@{
                                                           @"type":@"fan",
                                                           @"name":@"Fan",
                                                           }];
    [self presentController:user];

}
- (IBAction)multipleAsHost:(id)sender {
    self.instance_id = @"AAAA1";
    NSMutableDictionary *user =[NSMutableDictionary
                                dictionaryWithDictionary:@{
                                                           @"type":@"host",
                                                           @"name":@"Host",
                                                           }];
    [self presentController:user];
}
- (IBAction)multipleAsCeleb:(id)sender {
    self.instance_id = @"AAAA1";
    NSMutableDictionary *user =[NSMutableDictionary
                                dictionaryWithDictionary:@{
                                                           @"type":@"celebrity",
                                                           @"name":@"Celebrity",
                                                           }];
    [self presentController:user];
}

///SELF IMPLEMENTED MULTIPLE EVENTS VIEW
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    if ([segue.identifier isEqualToString:@"GoToMultipleEvents"]) {
        ViewController *vc = [segue destinationViewController];
        NSString* instance_id = @"AAAA1";
        NSMutableDictionary *user =[NSMutableDictionary
                                    dictionaryWithDictionary:@{
                                                               @"type":@"fan",
                                                               @"name":@"Fan",
                                                               }];
        vc.instance_id = instance_id;
        vc.backend_base_url= @"https://chatshow-tesla.herokuapp.com";
        vc.user = user;
    }
}


-(void) presentController:(NSMutableDictionary*)userOptions{
    if(![self.nameTextField.text isEqualToString:@"" ]){
        userOptions[@"name"] = self.nameTextField.text;
    }
    NSString *stagingBackend = @"https://chatshow-tesla.herokuapp.com";
    NSString *demoBackend = @"https://chatshow-tesla-prod.herokuapp.com";
    NSString *MLBBackend = @"https://spotlight-tesla-mlb.herokuapp.com";
    self.spotlightController = [[MainSpotlightControllerViewController alloc] initWithData:@"spotlight-mlb-210216" backend_base_url:MLBBackend user:userOptions];
    [self presentViewController:self.spotlightController animated:NO completion:nil];
}

@end
