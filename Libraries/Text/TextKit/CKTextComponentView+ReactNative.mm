//
//  CKTextComponentView+ReactNative.m
//  RCTText
//
//  Created by Oliver Rickard on 7/5/15.
//  Copyright © 2015 Facebook. All rights reserved.
//

#import "CKTextComponentView+ReactNative.h"

#import <objc/runtime.h>

#import "CKTextKitRenderer+Positioning.h"
#import "RCTShadowText.h"

static NSString *const kCKTextComponentViewReactTagKey = @"CKTextComonentViewReactTagKey";

@implementation CKTextComponentView (ReactNative)

- (NSNumber *)reactTag
{
  return objc_getAssociatedObject(self, (__bridge const void *)(kCKTextComponentViewReactTagKey));
}

- (void)setReactTag:(NSNumber *)reactTag
{
  objc_setAssociatedObject(self, (__bridge const void *)(kCKTextComponentViewReactTagKey), reactTag, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSNumber *)reactTagAtPoint:(CGPoint)point
{
  NSNumber *reactTag = self.reactTag;
  
  NSUInteger characterIndex = [self.renderer nearestTextIndexAtPosition:point];
  NSAttributedString *attributedString = self.renderer.attributes.attributedString;

  if (attributedString.length > 0 && characterIndex < attributedString.length - 1) {
    [self.renderer.attributes.attributedString attribute:RCTReactTagAttributeName atIndex:characterIndex effectiveRange:NULL];
  }
  return reactTag;
}

@end
