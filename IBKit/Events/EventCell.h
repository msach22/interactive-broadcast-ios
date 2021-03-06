//
//  EventCell.h
//  IBDemo
//
//  Created by Xi Huang on 5/25/16.
//  Copyright © 2016 Tokbox, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "IBEvent.h"
#import "IBUser.h"

@interface EventCell : UICollectionViewCell

@property (weak, nonatomic) IBOutlet UIButton *eventButton;
- (void)updateCellWithEvent:(IBEvent *)event
                       user:(IBUser *)user;

@end
