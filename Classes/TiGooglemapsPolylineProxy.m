/**
 * Ti.GoogleMaps
 * Copyright (c) 2015-present by Hans Knöchel. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiGooglemapsPolylineProxy.h"

@implementation TiGooglemapsPolylineProxy

- (GMSPolyline *)polyline
{
  if (_polyline == nil) {
    _polyline = [GMSPolyline new];
    _polyline.tappable = YES;
  }

  return _polyline;
}

- (void)setPoints:(id)points
{
  ENSURE_UI_THREAD(setPoints, points);

  [self replaceValue:points forKey:@"points" notification:NO];

  GMSMutablePath *path = [GMSMutablePath path];

  if (points != nil) {
    // Handle string paths
    if ([points isKindOfClass:[NSString class]]) {
      path = [GMSMutablePath pathFromEncodedPath:points];
    // Handle array paths
    } else {
      if ([points count] < 2) {
        NSLog(@"[WARN] Ti.GoogleMaps: You need to specify at least 2 points to create a polygon.");
        return;
      }

      for (id point in points) {
        if ([point isKindOfClass:[NSDictionary class]]) {
          CLLocationDegrees latitude = [TiUtils doubleValue:[point valueForKey:@"latitude"]];
          CLLocationDegrees longitude = [TiUtils doubleValue:[point valueForKey:@"longitude"]];

          [path addLatitude:latitude longitude:longitude];
        } else if ([point isKindOfClass:[NSArray class]]) {
          CLLocationDegrees latitude = [TiUtils doubleValue:[point objectAtIndex:1]];
          CLLocationDegrees longitude = [TiUtils doubleValue:[point objectAtIndex:0]];

          [path addLatitude:latitude longitude:longitude];
        }
      }
    }
  }

  [[self polyline] setPath:path];
}

- (void)setDotsImage:(id)dotsImage
{
  ENSURE_UI_THREAD(setDotsImage, dotsImage);

  if (dotsImage == nil) {
    [[self polyline] setSpans:@[]];
    return;
  }

  GMSStrokeStyle *strokeStyle = [[GMSStrokeStyle alloc] init];
  GMSTextureStyle *stampStyle = [[GMSTextureStyle alloc] initWithImage:[TiUtils image:dotsImage proxy:self]];
  strokeStyle.stampStyle = stampStyle;

  [[self polyline] setSpans:@[[GMSStyleSpan spanWithStyle:strokeStyle]]];

  [self replaceValue:dotsImage forKey:@"dotsImage" notification:NO];
}

- (void)setTappable:(id)value
{
  ENSURE_UI_THREAD(setTappable, value);
  ENSURE_TYPE(value, NSNumber);

  [[self polyline] setTappable:[TiUtils boolValue:value]];
  [self replaceValue:value forKey:@"tappable" notification:NO];
}

- (void)setStrokeColor:(id)value
{
  ENSURE_UI_THREAD(setStrokeColor, value);

  [[self polyline] setStrokeColor:[[TiUtils colorValue:value] _color]];
  [self replaceValue:value forKey:@"strokeColor" notification:NO];
}

- (void)setStrokeWidth:(id)value
{
  ENSURE_UI_THREAD(setStrokeWidth, value);

  [[self polyline] setStrokeWidth:[TiUtils floatValue:value def:1]];
  [self replaceValue:value forKey:@"strokeWidth" notification:NO];
}

- (void)setGeodesic:(id)value
{
  ENSURE_UI_THREAD(setGeodesic, value);

  [[self polyline] setGeodesic:[TiUtils boolValue:value def:NO]];
  [self replaceValue:value forKey:@"geodesic" notification:NO];
}

- (void)setTitle:(id)value
{
  ENSURE_UI_THREAD(setTitle, value);
  ENSURE_TYPE(value, NSString);

  [[self polyline] setTitle:[TiUtils stringValue:value]];
  [self replaceValue:value forKey:@"title" notification:NO];
}

- (void)setZIndex:(id)value
{
  ENSURE_UI_THREAD(setZIndex, value);
  ENSURE_TYPE(value, NSNumber);
  
  [[self polyline] setZIndex:[TiUtils intValue:value]];
  [self replaceValue:value forKey:@"zIndex" notification:NO];
}

- (void)setUserData:(id)value
{
  ENSURE_UI_THREAD(setUserData, value);
  ENSURE_TYPE(value, NSDictionary);
  
  [[self polyline] setUserData:value];
  [self replaceValue:value forKey:@"userData" notification:NO];
}

- (void)setStrokeGradient:(id)value
{
  ENSURE_UI_THREAD(setStrokeGradient, value);
  ENSURE_TYPE(value, NSDictionary);

  UIColor *fromColor = [TiUtils colorValue:value[@"from"]].color;
  UIColor *toColor = [TiUtils colorValue:value[@"to"]].color;

  GMSStrokeStyle *gradient = [GMSStrokeStyle gradientFromColor:fromColor toColor:toColor];
  [[self polyline] setSpans:@[[GMSStyleSpan spanWithStyle:gradient]]];

  [self replaceValue:value forKey:@"spans" notification:NO];
}

@end
