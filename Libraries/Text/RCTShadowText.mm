/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTShadowText.h"

#import "RCTConvert.h"
#import "RCTLog.h"
#import "RCTShadowRawText.h"
#import "RCTSparseArray.h"
#import "RCTText.h"
#import "RCTUtils.h"
#import "CKTextKitRendererCache.h"
#import "CKTextComponentView.h"
#import "CKTextKitRenderer.h"

NSString *const RCTIsHighlightedAttributeName = @"IsHighlightedAttributeName";
NSString *const RCTReactTagAttributeName = @"ReactTagAttributeName";

@implementation RCTShadowText
{
  NSTextStorage *_cachedTextStorage;
  CGFloat _cachedTextStorageWidth;
  NSAttributedString *_cachedAttributedString;
  CGFloat _effectiveLetterSpacing;
}

static CK::TextKit::Renderer::Cache *sharedRendererCache()
{
  // This cache is sized arbitrarily
  static CK::TextKit::Renderer::Cache *__rendererCache (new CK::TextKit::Renderer::Cache("CKTextKitRendererCache", 500, 0.2));
  return __rendererCache;
}

static CKTextKitRenderer *rendererForAttributes(const CKTextKitAttributes &attributes, CGSize constrainedSize)
{
  CK::TextKit::Renderer::Cache *cache = sharedRendererCache();
  const CK::TextKit::Renderer::Key key {
    attributes,
    constrainedSize
  };
  
  CKTextKitRenderer *renderer = cache->objectForKey(key);
  
  if (!renderer) {
    renderer =
    [[CKTextKitRenderer alloc]
     initWithTextKitAttributes:attributes
     constrainedSize:constrainedSize];
    cache->cacheObject(key, renderer, 1);
  }
  
  return renderer;
}

static css_dim_t RCTMeasure(void *context, float width)
{
  RCTShadowText *shadowText = (__bridge RCTShadowText *)context;
  CKTextKitRenderer *renderer = [shadowText rendererForSize:{ .width = width, .height = CGFLOAT_MAX }];
  CGSize computedSize = renderer.size;

  css_dim_t result;
  result.dimensions[CSS_WIDTH] = RCTCeilPixelValue(computedSize.width);
  if (shadowText->_effectiveLetterSpacing < 0) {
    result.dimensions[CSS_WIDTH] -= shadowText->_effectiveLetterSpacing;
  }
  result.dimensions[CSS_HEIGHT] = RCTCeilPixelValue(computedSize.height);
  return result;
}

- (instancetype)init
{
  if ((self = [super init])) {
    _fontSize = NAN;
    _letterSpacing = NAN;
    _isHighlighted = NO;
  }
  return self;
}

- (NSString *)description
{
  NSString *superDescription = super.description;
  return [[superDescription substringToIndex:superDescription.length - 1] stringByAppendingFormat:@"; text: %@>", [self attributedString].string];
}

- (NSDictionary *)processUpdatedProperties:(NSMutableSet *)applierBlocks
                          parentProperties:(NSDictionary *)parentProperties
{
  parentProperties = [super processUpdatedProperties:applierBlocks
                                    parentProperties:parentProperties];
  
  CKTextKitRenderer *renderer = [self rendererForSize:self.frame.size];
  [applierBlocks addObject:^(RCTSparseArray *viewRegistry) {
    CKTextComponentView *view = viewRegistry[self.reactTag];
    view.renderer = renderer;
  }];

  return parentProperties;
}

- (void)applyLayoutNode:(css_node_t *)node
      viewsWithNewFrame:(NSMutableSet *)viewsWithNewFrame
       absolutePosition:(CGPoint)absolutePosition
{
  [super applyLayoutNode:node viewsWithNewFrame:viewsWithNewFrame absolutePosition:absolutePosition];
  [self dirtyPropagation];
}

- (const CKTextKitAttributes)attributes
{
  return {
    .attributedString = self.attributedString,
    .lineBreakMode = _numberOfLines > 0 ? NSLineBreakByTruncatingTail : NSLineBreakByClipping,
    .maximumNumberOfLines = _numberOfLines
  };
}

- (CKTextKitRenderer *)rendererForSize:(CGSize)constrainedSize
{
  return rendererForAttributes([self attributes], constrainedSize);
}

- (NSTextStorage *)deprecated_buildTextStorageForWidth:(CGFloat)width
{
  UIEdgeInsets padding = self.paddingAsInsets;
  width -= (padding.left + padding.right);

  if (_cachedTextStorage && width == _cachedTextStorageWidth) {
    return _cachedTextStorage;
  }

  NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];

  NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self.attributedString];
  [textStorage addLayoutManager:layoutManager];

  NSTextContainer *textContainer = [[NSTextContainer alloc] init];
  textContainer.lineFragmentPadding = 0.0;
  textContainer.lineBreakMode = _numberOfLines > 0 ? NSLineBreakByTruncatingTail : NSLineBreakByClipping;
  textContainer.maximumNumberOfLines = _numberOfLines;
  textContainer.size = (CGSize){isnan(width) ? CGFLOAT_MAX : width, CGFLOAT_MAX};

  [layoutManager addTextContainer:textContainer];
  [layoutManager ensureLayoutForTextContainer:textContainer];

  _cachedTextStorageWidth = width;
  _cachedTextStorage = textStorage;

  return textStorage;
}

- (void)dirtyText
{
  [super dirtyText];
  _cachedTextStorage = nil;
}

- (void)recomputeText
{
  [self attributedString];
  [self setTextComputed];
  [self dirtyPropagation];
}

- (NSAttributedString *)attributedString
{
  return [self _attributedStringWithFontFamily:nil
                                      fontSize:nil
                                    fontWeight:nil
                                     fontStyle:nil
                                 letterSpacing:nil
                            useBackgroundColor:NO];
}

- (NSAttributedString *)_attributedStringWithFontFamily:(NSString *)fontFamily
                                               fontSize:(NSNumber *)fontSize
                                             fontWeight:(NSString *)fontWeight
                                              fontStyle:(NSString *)fontStyle
                                          letterSpacing:(NSNumber *)letterSpacing
                                     useBackgroundColor:(BOOL)useBackgroundColor
{
  if (![self isTextDirty] && _cachedAttributedString) {
    return _cachedAttributedString;
  }

  if (_fontSize && !isnan(_fontSize)) {
    fontSize = @(_fontSize);
  }
  if (_fontWeight) {
    fontWeight = _fontWeight;
  }
  if (_fontStyle) {
    fontStyle = _fontStyle;
  }
  if (_fontFamily) {
    fontFamily = _fontFamily;
  }
  if (!isnan(_letterSpacing)) {
    letterSpacing = @(_letterSpacing);
  }

  _effectiveLetterSpacing = letterSpacing.doubleValue;

  NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
  for (RCTShadowView *child in [self reactSubviews]) {
    if ([child isKindOfClass:[RCTShadowText class]]) {
      RCTShadowText *shadowText = (RCTShadowText *)child;
      [attributedString appendAttributedString:[shadowText _attributedStringWithFontFamily:fontFamily fontSize:fontSize fontWeight:fontWeight fontStyle:fontStyle letterSpacing:letterSpacing useBackgroundColor:YES]];
    } else if ([child isKindOfClass:[RCTShadowRawText class]]) {
      RCTShadowRawText *shadowRawText = (RCTShadowRawText *)child;
      [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:[shadowRawText text] ?: @""]];
    } else {
      RCTLogError(@"<Text> can't have any children except <Text> or raw strings");
    }

    [child setTextComputed];
  }

  if (_color) {
    [self _addAttribute:NSForegroundColorAttributeName withValue:_color toAttributedString:attributedString];
  }
  if (_isHighlighted) {
    [self _addAttribute:RCTIsHighlightedAttributeName withValue:@YES toAttributedString:attributedString];
  }
  if (useBackgroundColor && self.backgroundColor) {
    [self _addAttribute:NSBackgroundColorAttributeName withValue:self.backgroundColor toAttributedString:attributedString];
  }

  UIFont *font = [RCTConvert UIFont:nil withFamily:fontFamily size:fontSize weight:fontWeight style:fontStyle];
  [self _addAttribute:NSFontAttributeName withValue:font toAttributedString:attributedString];
  [self _addAttribute:NSKernAttributeName withValue:letterSpacing toAttributedString:attributedString];
  [self _addAttribute:RCTReactTagAttributeName withValue:self.reactTag toAttributedString:attributedString];
  [self _setParagraphStyleOnAttributedString:attributedString];

  // create a non-mutable attributedString for use by the Text system which avoids copies down the line
  _cachedAttributedString = [[NSAttributedString alloc] initWithAttributedString:attributedString];
  [self dirtyLayout];

  return _cachedAttributedString;
}

- (void)_addAttribute:(NSString *)attribute withValue:(id)attributeValue toAttributedString:(NSMutableAttributedString *)attributedString
{
  [attributedString enumerateAttribute:attribute inRange:NSMakeRange(0, [attributedString length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
    if (!value && attributeValue) {
      [attributedString addAttribute:attribute value:attributeValue range:range];
    }
  }];
}

/*
 * LineHeight works the same way line-height works in the web: if children and self have
 * varying lineHeights, we simply take the max.
 */
- (void)_setParagraphStyleOnAttributedString:(NSMutableAttributedString *)attributedString
{
  // check if we have lineHeight set on self
  __block BOOL hasParagraphStyle = NO;
  if (_lineHeight || _textAlign) {
    hasParagraphStyle = YES;
  }

  if (!_lineHeight) {
    self.lineHeight = 0.0;
  }

  // check for lineHeight on each of our children, update the max as we go (in self.lineHeight)
  [attributedString enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0, [attributedString length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
    if (value) {
      NSParagraphStyle *paragraphStyle = (NSParagraphStyle *)value;
      if ([paragraphStyle maximumLineHeight] > _lineHeight) {
        self.lineHeight = [paragraphStyle maximumLineHeight];
      }
      hasParagraphStyle = YES;
    }
  }];

  self.textAlign = (NSTextAlignment)(_textAlign ?: NSTextAlignmentNatural);
  self.writingDirection = (NSWritingDirection)(_writingDirection ?: NSWritingDirectionNatural);

  // if we found anything, set it :D
  if (hasParagraphStyle) {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = _textAlign;
    paragraphStyle.baseWritingDirection = _writingDirection;
    paragraphStyle.minimumLineHeight = _lineHeight;
    paragraphStyle.maximumLineHeight = _lineHeight;
    [attributedString addAttribute:NSParagraphStyleAttributeName
                             value:paragraphStyle
                             range:(NSRange){0, attributedString.length}];
  }
}

- (void)fillCSSNode:(css_node_t *)node
{
  [super fillCSSNode:node];
  node->measure = RCTMeasure;
  node->children_count = 0;
}

- (void)insertReactSubview:(RCTShadowView *)subview atIndex:(NSInteger)atIndex
{
  [super insertReactSubview:subview atIndex:atIndex];
  [self cssNode]->children_count = 0;
}

- (void)removeReactSubview:(RCTShadowView *)subview
{
  [super removeReactSubview:subview];
  [self cssNode]->children_count = 0;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
  super.backgroundColor = backgroundColor;
  [self dirtyText];
}

#define RCT_TEXT_PROPERTY(setProp, ivar, type) \
- (void)set##setProp:(type)value;              \
{                                              \
  ivar = value;                                \
  [self dirtyText];                            \
}

RCT_TEXT_PROPERTY(Color, _color, UIColor *)
RCT_TEXT_PROPERTY(FontFamily, _fontFamily, NSString *)
RCT_TEXT_PROPERTY(FontSize, _fontSize, CGFloat)
RCT_TEXT_PROPERTY(FontWeight, _fontWeight, NSString *)
RCT_TEXT_PROPERTY(FontStyle, _fontStyle, NSString *)
RCT_TEXT_PROPERTY(IsHighlighted, _isHighlighted, BOOL)
RCT_TEXT_PROPERTY(LetterSpacing, _letterSpacing, CGFloat)
RCT_TEXT_PROPERTY(LineHeight, _lineHeight, CGFloat)
RCT_TEXT_PROPERTY(NumberOfLines, _numberOfLines, NSUInteger)
RCT_TEXT_PROPERTY(ShadowOffset, _shadowOffset, CGSize)
RCT_TEXT_PROPERTY(TextAlign, _textAlign, NSTextAlignment)
RCT_TEXT_PROPERTY(WritingDirection, _writingDirection, NSWritingDirection)

@end
