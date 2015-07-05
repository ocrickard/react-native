//
//  CKTextComponentView+ReactNative.h
//  RCTText
//
//  Created by Oliver Rickard on 7/5/15.
//  Copyright © 2015 Facebook. All rights reserved.
//

#import "CKTextComponentView.h"

@interface CKTextComponentView (ReactNative)

@property (nonatomic, copy) NSNumber *reactTag;

- (NSNumber *)reactTagAtPoint:(CGPoint)point;

@end
