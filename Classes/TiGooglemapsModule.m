/**
 * Ti.GoogleMaps
 * Copyright (c) 2015-present by Hans Knöchel. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiGooglemapsModule.h"
#import "TiBase.h"
#import "TiGMSHTTPClient.h"
#import "TiGooglemapsClusterItemProxy.h"
#import "TiHost.h"
#import "TiUtils.h"
#import <GoogleMaps/GoogleMaps.h>

@implementation TiGooglemapsModule

#pragma mark Internal

- (id)moduleGUID
{
  return @"81fe0326-e874-4843-b902-51bbd46f9283";
}

- (NSString *)moduleId
{
  return @"ti.googlemaps";
}

#pragma Public APIs

- (void)setAPIKey:(NSString *)apiKey
{
  ENSURE_TYPE(apiKey, NSString);

  _apiKey = [TiUtils stringValue:apiKey];
  [GMSServices provideAPIKey:_apiKey];
}

- (void)enableMetalRenderer:(id)unused
{
  DEPRECATED_REMOVED(@"enableMetalRenderer", @"10.0.0", @"10.0.0");
}

- (NSString *)openSourceLicenseInfo
{
  __block NSString *openSourceLicenseInfo;

  TiThreadPerformOnMainThread(^{
    openSourceLicenseInfo = [GMSServices openSourceLicenseInfo];
  },
      YES);

  return openSourceLicenseInfo;
}

- (NSString *)version
{
  __block NSString *version;

  TiThreadPerformOnMainThread(^{
    version = [GMSServices SDKVersion];
  },
      YES);

  return version;
}

- (void)reverseGeocoder:(NSArray *)args
{
  ENSURE_UI_THREAD(reverseGeocoder, args);
  ENSURE_ARG_COUNT(args, 3);

  KrollCallback *callback;
  NSNumber *latitude;
  NSNumber *longitude;

  ENSURE_ARG_AT_INDEX(latitude, args, 0, NSNumber);
  ENSURE_ARG_AT_INDEX(longitude, args, 1, NSNumber);
  ENSURE_ARG_AT_INDEX(callback, args, 2, KrollCallback);

  [[GMSGeocoder geocoder] reverseGeocodeCoordinate:CLLocationCoordinate2DMake(latitude.doubleValue, longitude.doubleValue)
                                 completionHandler:^(GMSReverseGeocodeResponse *response, NSError *error) {
                                   NSMutableDictionary *propertiesDict = [NSMutableDictionary dictionaryWithDictionary:@{
                                     @"firstPlace" : NULL_IF_NIL([self dictionaryFromAddress:response.firstResult]),
                                     @"places" : [self arrayFromAddresses:response.results]
                                   }];

                                   if (!response.results || response.results.count == 0) {
                                     [propertiesDict setValue:@"No places found" forKey:@"error"];
                                     [propertiesDict setValue:@(1) forKey:@"code"];
                                     [propertiesDict setValue:@(NO) forKey:@"success"];
                                   } else {
                                     [propertiesDict setValue:@(0) forKey:@"code"];
                                     [propertiesDict setValue:@(YES) forKey:@"success"];
                                   }

                                   NSArray *invocationArray = [[NSArray alloc] initWithObjects:&propertiesDict count:1];

                                   [callback call:invocationArray thisObject:self];
                                 }];
}

- (void)getDirections:(NSArray *)args
{
  NSDictionary *params = [args objectAtIndex:0];

  id successCallback = [params objectForKey:@"success"];
  id errorCallback = [params objectForKey:@"error"];
  id origin = [params objectForKey:@"origin"];
  id destination = [params objectForKey:@"destination"];
  id waypoints = [params objectForKey:@"waypoints"];

  ENSURE_TYPE(successCallback, KrollCallback);
  ENSURE_TYPE(errorCallback, KrollCallback);
  ENSURE_TYPE(origin, NSString);
  ENSURE_TYPE(destination, NSString);
  ENSURE_TYPE_OR_NIL(waypoints, NSArray);

  TiGMSHTTPClient *httpClient = [[TiGMSHTTPClient alloc] initWithApiKey:_apiKey];

  NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:@{
    @"origin" : origin,
    @"destination" : destination,
  }];

  if (waypoints) {
    [options setObject:[TiGMSHTTPClient formattedWaypointsFromArray:waypoints] forKey:@"waypoints"];
  }

  [httpClient loadWithRequestPath:@"directions/json"
                       andOptions:options
                completionHandler:^(NSDictionary *json, NSError *error) {
                  if (error) {
                    NSDictionary *errorObject = [TiUtils dictionaryWithCode:1 message:[error localizedDescription]];
                    NSArray *invocationArray = [[NSArray alloc] initWithObjects:&errorObject count:1];

                    TiThreadPerformOnMainThread(^{
                      [errorCallback call:invocationArray thisObject:self];
                    },
                        NO);

                    return;
                  }

                  TiThreadPerformOnMainThread(^{
                    NSArray *invocationArray = [[NSArray alloc] initWithObjects:&json count:1];
                    [successCallback call:invocationArray thisObject:self];
                  },
                      NO);
                }];
}

- (NSNumber *)geometryContainsLocation:(id)args
{
  ENSURE_SINGLE_ARG(args, NSDictionary);
  
  NSDictionary<NSString *, NSNumber *> *location = args[@"location"];
  NSArray<NSArray<NSNumber *> *> *jsPath = args[@"path"];

  CLLocationDegrees latitude = [TiUtils doubleValue:@"latitude" properties:location];
  CLLocationDegrees longitude = [TiUtils doubleValue:@"longitude" properties:location];

  GMSMutablePath *path = [[GMSMutablePath alloc] init];

  [jsPath enumerateObjectsUsingBlock:^(NSArray<NSNumber *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    CLLocationDegrees _latitude = obj[0].doubleValue;
    CLLocationDegrees _longitude = obj[1].doubleValue;

    [path addCoordinate:CLLocationCoordinate2DMake(_latitude, _longitude)];
  }];

  return @(GMSGeometryContainsLocation(CLLocationCoordinate2DMake(latitude, longitude), path, YES));
}

- (NSNumber *)geometryDistanceBetweenPoints:(id)locations
{
  ENSURE_ARG_COUNT(locations, 2);

  NSDictionary *location1 = locations[0];
  NSDictionary *location2 = locations[1];

  CLLocationDegrees latitude1 = [TiUtils doubleValue:@"latitude" properties:location1];
  CLLocationDegrees longitude1 = [TiUtils doubleValue:@"longitude" properties:location1];

  CLLocationDegrees latitude2 = [TiUtils doubleValue:@"latitude" properties:location2];
  CLLocationDegrees longitude2 = [TiUtils doubleValue:@"longitude" properties:location2];

  return @(GMSGeometryDistance(CLLocationCoordinate2DMake(latitude1, longitude1), CLLocationCoordinate2DMake(latitude2, longitude2)));
}

- (TiGooglemapsClusterItemProxy *)createClusterItem:(NSArray *)args
{
  NSDictionary *params = [args objectAtIndex:0];

  id latitude = [params objectForKey:@"latitude"];
  ENSURE_TYPE(latitude, NSNumber);

  id longitude = [params objectForKey:@"longitude"];
  ENSURE_TYPE(longitude, NSNumber);

  id title = [params objectForKey:@"title"];
  ENSURE_TYPE_OR_NIL(title, NSString);

  id subtitle = [params objectForKey:@"subtitle"];
  ENSURE_TYPE_OR_NIL(subtitle, NSString);

  id icon = [params objectForKey:@"icon"];

  id userData = [params objectForKey:@"userData"];
  ENSURE_TYPE_OR_NIL(userData, NSDictionary);

  return [[TiGooglemapsClusterItemProxy alloc] _initWithPageContext:[self pageContext]
                                                        andPosition:CLLocationCoordinate2DMake([TiUtils doubleValue:latitude], [TiUtils doubleValue:longitude])
                                                              title:title
                                                           subtitle:subtitle
                                                               icon:icon
                                                           userData:userData];
}

- (NSArray *)decodePolylinePoints:(NSArray *)args
{
  NSString *polylinePoints = [args objectAtIndex:0];

  GMSPath *path = [GMSPath pathFromEncodedPath:polylinePoints];
  NSMutableArray *coordinates = [NSMutableArray arrayWithCapacity:path.count];

  for (NSUInteger i = 0; i < path.count; i++) {
    CLLocationCoordinate2D location = [path coordinateAtIndex:i];
    [coordinates addObject:@{ @"latitude" : @(location.latitude),
      @"longitude" : @(location.longitude) }];
  }

  return coordinates;
}

#pragma mark Utilities

- (NSDictionary *_Nullable)dictionaryFromAddress:(GMSAddress *)address
{
  if (!address) {
    return nil;
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];

  if (address.coordinate.latitude && address.coordinate.longitude) {
    [result setObject:@(address.coordinate.latitude) forKey:@"latitude"];
    [result setObject:@(address.coordinate.longitude) forKey:@"longitude"];
  }

  if (address.thoroughfare) {
    [result setObject:address.thoroughfare forKey:@"thoroughfare"];
  }

  if (address.locality) {
    [result setObject:address.locality forKey:@"locality"];
  }

  if (address.subLocality) {
    [result setObject:address.subLocality forKey:@"subLocality"];
  }

  if (address.administrativeArea) {
    [result setObject:address.administrativeArea forKey:@"administrativeArea"];
  }

  if (address.postalCode) {
    [result setObject:address.postalCode forKey:@"postalCode"];
  }

  if (address.country) {
    [result setObject:address.country forKey:@"country"];
  }

  if (address.lines) {
    [result setObject:address.lines forKey:@"lines"];
  }

  return result;
}

- (NSArray *)arrayFromAddresses:(NSArray<GMSAddress *> *)addresses
{
  if (!addresses) {
    return @[];
  }

  NSMutableArray *result = [NSMutableArray arrayWithCapacity:[addresses count]];

  for (GMSAddress *address in addresses) {
    [result addObject:[self dictionaryFromAddress:address]];
  }

  return result;
}

#pragma mark Constants

MAKE_SYSTEM_PROP(MAP_TYPE_HYBRID, kGMSTypeHybrid);
MAKE_SYSTEM_PROP(MAP_TYPE_NONE, kGMSTypeNone);
MAKE_SYSTEM_PROP(MAP_TYPE_NORMAL, kGMSTypeNormal);
MAKE_SYSTEM_PROP(MAP_TYPE_SATELLITE, kGMSTypeSatellite);
MAKE_SYSTEM_PROP(MAP_TYPE_TERRAIN, kGMSTypeTerrain);

MAKE_SYSTEM_PROP(APPEAR_ANIMATION_NONE, kGMSMarkerAnimationNone);
MAKE_SYSTEM_PROP(APPEAR_ANIMATION_POP, kGMSMarkerAnimationPop);
MAKE_SYSTEM_PROP(APPEAR_ANIMATION_FADE, kGMSMarkerAnimationFadeIn);

MAKE_SYSTEM_PROP(PADDING_ADJUSTMENT_BEHAVIOR_ALWAYS, kGMSMapViewPaddingAdjustmentBehaviorAlways);
MAKE_SYSTEM_PROP(PADDING_ADJUSTMENT_BEHAVIOR_AUTOMATIC, kGMSMapViewPaddingAdjustmentBehaviorAutomatic);
MAKE_SYSTEM_PROP(PADDING_ADJUSTMENT_BEHAVIOR_NEVER, kGMSMapViewPaddingAdjustmentBehaviorNever);

@end
