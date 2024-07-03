/**
 * Ti.GoogleMaps
 * Copyright (c) 2015-present by Hans Knöchel. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiGooglemapsView.h"
#import "TiClusterIconGenerator.h"
#import "TiGooglemapsAnnotationProxy.h"
#import "TiGooglemapsCircleProxy.h"
#import "TiGooglemapsClusterItemProxy.h"
#import "TiGooglemapsConstants.h"
#import "TiGooglemapsPolygonProxy.h"
#import "TiGooglemapsPolylineProxy.h"
#import "TiGooglemapsViewProxy.h"
#import "TiPOIItem.h"

static NSString *const kGMUMyLocationKeyPath = @"myLocation";

@implementation TiGooglemapsView

- (void)dealloc
{
  [_mapView removeObserver:self forKeyPath:kGMUMyLocationKeyPath];
  _mapView.delegate = nil;
  _clusterRenderer.delegate = nil;
}

- (GMSMapView *)mapView
{
  if (_mapView == nil) {
    _centerAnnotationOnTap = YES;
    
    GMSMapViewOptions *options = [[GMSMapViewOptions alloc] init];
    options.frame = self.bounds;
    options.backgroundColor = [UIColor systemBackgroundColor];

    _mapView = [[GMSMapView alloc] initWithOptions:options];
    [_mapView setMapType:kGMSTypeNormal];
    [_mapView setDelegate:self];
    [_mapView setAutoresizingMask:UIViewAutoresizingNone];

    [_mapView addObserver:self
               forKeyPath:kGMUMyLocationKeyPath
                  options:NSKeyValueObservingOptionNew
                  context:nil];

    [self addSubview:_mapView];
  }

  return _mapView;
}

- (GMUClusterManager *)clusterManager
{
  if (_clusterManager == nil) {
    // Set up the cluster manager with default icon generator and renderer.
    id<GMUClusterAlgorithm> algorithm = [[GMUNonHierarchicalDistanceBasedAlgorithm alloc] init];

    TiClusterIconGenerator *iconGenerator = [self createIconGenerator];

    _clusterRenderer = [[TiClusterRenderer alloc] initWithMapView:_mapView clusterIconGenerator:iconGenerator];
    _clusterRenderer.delegate = self;

    _clusterManager = [[GMUClusterManager alloc] initWithMap:[self mapView] algorithm:algorithm renderer:_clusterRenderer];
    [_clusterManager setDelegate:self mapDelegate:self];
  }

  return _clusterManager;
}

- (void)renderer:(id<GMUClusterRenderer>)renderer willRenderMarker:(GMSMarker *)marker
{
  if ([[marker userData] isKindOfClass:[TiPOIItem class]]) {
    TiPOIItem *item = (TiPOIItem *)[marker userData];

    // Note: All native props are nullable, so we don't need to check against nil here

    // TODO: Add more property mappings here
    [marker setTitle:item.title];
    [marker setSnippet:item.subtitle];
    [marker setIcon:item.icon];
  }
}

- (TiClusterIconGenerator *)createIconGenerator
{
  id clusterRanges = [[self proxy] valueForKey:@"clusterRanges"];
  id clusterBackgrounds = [[self proxy] valueForKey:@"clusterBackgrounds"];

  if (clusterRanges && clusterBackgrounds) {
    NSMutableArray *backgrounds = [NSMutableArray array];

    for (id background in clusterBackgrounds) {
      ENSURE_TYPE(background, NSString);
      UIImage *clusterBackground = [TiUtils image:background proxy:self.proxy];

      if (!clusterBackground) {
        NSLog(@"[ERROR] Cluster background-file (%@) cannot be found, skipping ...");
        continue;
      }

      [backgrounds addObject:clusterBackground];
    }

    return [[TiClusterIconGenerator alloc] initWithBuckets:clusterRanges backgroundImages:backgrounds];
  } else if (clusterRanges) {
    return [[TiClusterIconGenerator alloc] initWithBuckets:clusterRanges];
  }

  return [[TiClusterIconGenerator alloc] init];
}

- (TiGooglemapsViewProxy *)mapViewProxy
{
  return (TiGooglemapsViewProxy *)[self proxy];
}

- (void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
  [TiUtils setView:_mapView positionRect:bounds];
  [super frameSizeChanged:frame bounds:bounds];
}

#pragma mark Cluster Delegates

- (BOOL)clusterManager:(GMUClusterManager *)clusterManager didTapCluster:(id<GMUCluster>)cluster
{
  if ([[self proxy] _hasListeners:@"clusterclick"]) {
    [[self proxy] fireEvent:@"clusterclick"
                 withObject:@{
                   @"latitude" : @(cluster.position.latitude),
                   @"longitude" : @(cluster.position.longitude),
                   @"count" : @(cluster.count),
                   @"clusterItems" : [self arrayFromClusterItems:cluster.items]
                 }];
  }

  GMSCameraPosition *newCamera = [GMSCameraPosition cameraWithTarget:cluster.position zoom:_mapView.camera.zoom + 1];
  [_mapView moveCamera:[GMSCameraUpdate setCamera:newCamera]];

  return YES;
}

- (BOOL)clusterManager:(GMUClusterManager *)clusterManager didTapClusterItem:(id<GMUClusterItem>)clusterItem
{
  if ([[self proxy] _hasListeners:@"clusteritemclick"]) {
    [[self proxy] fireEvent:@"clusteritemclick"
                 withObject:@{
                   @"latitude" : @(clusterItem.position.latitude),
                   @"longitude" : @(clusterItem.position.longitude),
                   @"title" : [(TiPOIItem *)clusterItem title] ?: [NSNull null],
                   @"subtitle" : [(TiPOIItem *)clusterItem subtitle] ?: [NSNull null],
                   @"userData" : [(TiPOIItem *)clusterItem userData] ?: [NSNull null]
                 }];
  }

  return YES;
}

#pragma mark Map View Delegates

- (void)mapView:(GMSMapView *)mapView willMove:(BOOL)gesture
{
  if ([[self proxy] _hasListeners:@"regionwillchange"]) {
    [[self proxy] fireEvent:@"regionwillchange"
                 withObject:@{
                   @"map" : [self proxy],
                   @"latitude" : @(mapView.camera.target.latitude),
                   @"longitude" : @(mapView.camera.target.longitude),
                   @"gesture" : @(gesture)
                 }];
  }
}

- (void)mapView:(GMSMapView *)mapView didChangeCameraPosition:(GMSCameraPosition *)position
{
  if ([[self proxy] _hasListeners:@"regionchanged"]) {
    NSMutableDictionary *updatedRegion = [NSMutableDictionary dictionaryWithDictionary:@{
      @"latitude" : @(position.target.latitude),
      @"longitude" : @(position.target.longitude),
      @"zoom" : @(position.zoom),
      @"bearing" : @(position.bearing),
      @"viewingAngle" : @(position.viewingAngle)
    }];

    [(TiGooglemapsViewProxy *)[self proxy] replaceValue:updatedRegion forKey:@"region" notification:NO];

    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:updatedRegion];
    [event setObject:[self proxy] forKey:@"map"];

    [[self proxy] fireEvent:@"regionchanged" withObject:event];
  }
}

- (void)mapView:(GMSMapView *)mapView idleAtCameraPosition:(GMSCameraPosition *)position
{
  if ([[self proxy] _hasListeners:@"idle"]) {
    [[self proxy] fireEvent:@"idle" withObject:[self dictionaryFromCameraPosition:position]];
  }
}

- (void)mapView:(GMSMapView *)mapView didTapAtCoordinate:(CLLocationCoordinate2D)coordinate
{
  if ([[self proxy] _hasListeners:@"mapclick"]) {
    [[self proxy] fireEvent:@"mapclick"
                 withObject:@{
                   @"map" : [self proxy],
                   @"latitude" : @(coordinate.latitude),
                   @"longitude" : @(coordinate.longitude)
                 }];
  }
}

- (void)mapView:(GMSMapView *)mapView didLongPressAtCoordinate:(CLLocationCoordinate2D)coordinate
{
  if ([[self proxy] _hasListeners:@"longclick"]) {
    [[self proxy] fireEvent:@"longclick"
                 withObject:@{
                   @"map" : [self proxy],
                   @"latitude" : @(coordinate.latitude),
                   @"longitude" : @(coordinate.longitude)
                 }];
  }
}

- (BOOL)mapView:(GMSMapView *)mapView didTapMarker:(GMSMarker *)marker
{
  if ([[self proxy] _hasListeners:@"click"]) {
    [[self proxy] fireEvent:@"click"
                 withObject:@{
                   @"clicksource" : @"pin",
                   @"annotation" : [self dictionaryFromMarker:marker],
                   @"map" : [self proxy],
                   @"latitude" : @(marker.position.latitude),
                   @"longitude" : @(marker.position.longitude)
                 }];
  }

  return _centerAnnotationOnTap;
}

- (void)mapView:(GMSMapView *)mapView didTapInfoWindowOfMarker:(GMSMarker *)marker
{
  if ([[self proxy] _hasListeners:@"click"]) {
    [[self proxy] fireEvent:@"click"
                 withObject:@{
                   @"clicksource" : @"infoWindow",
                   @"annotation" : [self dictionaryFromMarker:marker],
                   @"map" : [self proxy],
                   @"latitude" : @(marker.position.latitude),
                   @"longitude" : @(marker.position.longitude)
                 }];
  }
}

- (void)mapView:(GMSMapView *)mapView didTapOverlay:(GMSOverlay *)overlay
{
  if ([[self proxy] _hasListeners:@"overlayclick"]) {
    [[self proxy] fireEvent:@"overlayclick"
                 withObject:@{
                   @"overlay" : [self overlayProxyFromOverlay:overlay]
                 }];
  }
  if ([[self proxy] _hasListeners:@"click"]) {
    [[self proxy] fireEvent:@"click"
                 withObject:@{
                   @"clicksource" : [self overlayTypeFromOverlay:overlay],
                   @"map" : [self proxy],
                   @"overlay" : [self overlayProxyFromOverlay:overlay]
                 }];
  }
}

- (void)mapView:(GMSMapView *)mapView didTapPOIWithPlaceID:(NSString *)placeID name:(NSString *)name location:(CLLocationCoordinate2D)location
{
  if ([[self proxy] _hasListeners:@"poiclick"]) {
    NSDictionary *event = @{
      @"placeID" : placeID,
      @"name": name,
      @"latitude" : @(location.latitude),
      @"longitude" : @(location.longitude)
    };
    [[self proxy] fireEvent:@"poiclick" withObject:event];
  }
}

- (void)mapView:(GMSMapView *)mapView didBeginDraggingMarker:(GMSMarker *)marker
{
  if ([[self proxy] _hasListeners:@"dragstart"]) {
    NSDictionary *event = @{
      @"annotation" : [self dictionaryFromMarker:marker]
    };
    [[self proxy] fireEvent:@"dragstart" withObject:event];
  }
}

- (void)mapView:(GMSMapView *)mapView didEndDraggingMarker:(GMSMarker *)marker
{
  if ([[self proxy] _hasListeners:@"dragend"]) {
    NSDictionary *event = @{
      @"annotation" : [self dictionaryFromMarker:marker]
    };
    [[self proxy] fireEvent:@"dragend" withObject:event];
  }
}

- (void)mapView:(GMSMapView *)mapView didDragMarker:(GMSMarker *)marker
{
  if ([[self proxy] _hasListeners:@"dragmove"]) {
    NSDictionary *event = @{
      @"annotation" : [self dictionaryFromMarker:marker]
    };
    [[self proxy] fireEvent:@"dragmove" withObject:event];
  }
}

- (UIView *)mapView:(GMSMapView *)mapView markerInfoWindow:(GMSMarker *)marker
{
  TiGooglemapsAnnotationProxy *annotation = nil;

  for (TiGooglemapsAnnotationProxy *proxy in [[(TiGooglemapsViewProxy *)[self proxy] markers] mutableCopy]) {
    if ([[[[proxy marker] userData] objectForKey:@"uuid"] isEqualToString:[[marker userData] objectForKey:@"uuid"]]) {
      annotation = proxy;
    }
  }

  if (!annotation || !annotation.infoWindow) {
    return nil;
  }
  
  [annotation rememberSelf];

  return [[annotation infoWindow] view];
}

- (BOOL)didTapMyLocationButtonForMapView:(GMSMapView *)mapView
{
  if ([[self proxy] _hasListeners:@"locationclick"]) {
    NSDictionary *event = @{
      @"map" : [self proxy]
    };
    [[self proxy] fireEvent:@"locationclick" withObject:event];
  }

  return NO;
}

- (void)mapViewDidFinishTileRendering:(GMSMapView *)mapView
{
  if ([[self proxy] _hasListeners:@"complete"]) {
    [[self proxy] fireEvent:@"complete"];
  }
  if ([[self proxy] _hasListeners:@"ready"]) {
    [[self proxy] fireEvent:@"ready"];
  }
}

#pragma mark Helper

- (NSDictionary *)dictionaryFromCameraPosition:(GMSCameraPosition *)position
{
  if (position == nil) {
    return @{};
  }

  return @{
    @"latitude" : @(position.target.latitude),
    @"longitude" : @(position.target.longitude),
    @"zoom" : @(position.zoom),
    @"viewingAngle" : @(position.viewingAngle),
    @"bearing" : @([position bearing])
  };
}

- (NSDictionary *)dictionaryFromCoordinate:(CLLocationCoordinate2D)coordinate
{
  return @{
    @"latitude" : @(coordinate.latitude),
    @"longitude" : @(coordinate.longitude)
  };
}

- (NSDictionary *)dictionaryFromMarker:(GMSMarker *)marker
{
  if (!marker) {
    return @{};
  }

  return @{
    @"latitude" : @(marker.position.latitude),
    @"longitude" : @(marker.position.longitude),
    @"userData" : marker.userData ?: [NSNull null],
    @"title" : marker.title ?: [NSNull null],
    @"subtitle" : marker.snippet ?: [NSNull null]
  };
}

- (void)setCenterAnnotationOnTap_:(id)value
{
  _centerAnnotationOnTap = [TiUtils boolValue:value];
}

- (id)overlayTypeFromOverlay:(GMSOverlay *)overlay
{
  ENSURE_UI_THREAD(overlayTypeFromOverlay, overlay);

  if ([overlay isKindOfClass:[GMSPolygon class]]) {
    return @(TiGooglemapsOverlayTypePolygon);
  } else if ([overlay isKindOfClass:[GMSPolyline class]]) {
    return @(TiGooglemapsOverlayTypePolyline);
  } else if ([overlay isKindOfClass:[GMSCircle class]]) {
    return @(TiGooglemapsOverlayTypeCircle);
  }

  NSLog(@"[ERROR] Unknown overlay provided: %@", [overlay class])

      return @(TiGooglemapsOverlayTypeUnknown);
}

- (id)overlayProxyFromOverlay:(GMSOverlay *)overlay
{
  for (TiProxy *overlayProxy in [[self mapViewProxy] overlays]) {
    // Check for polygons
    if ([overlay isKindOfClass:[GMSPolygon class]] && [overlayProxy isKindOfClass:[TiGooglemapsPolygonProxy class]]) {
      if ([(TiGooglemapsPolygonProxy *)overlayProxy polygon] == overlay) {
        return (TiGooglemapsPolygonProxy *)overlayProxy;
      }

      // Check for polylines
    } else if ([overlay isKindOfClass:[GMSPolyline class]] && [overlayProxy isKindOfClass:[TiGooglemapsPolylineProxy class]]) {
      if ([(TiGooglemapsPolylineProxy *)overlayProxy polyline] == overlay) {
        return (TiGooglemapsPolylineProxy *)overlayProxy;
      }

      // Check for circles
    } else if ([overlay isKindOfClass:[GMSCircle class]] && [overlayProxy isKindOfClass:[TiGooglemapsCircleProxy class]]) {
      if ([(TiGooglemapsCircleProxy *)overlayProxy circle] == overlay) {
        return (TiGooglemapsCircleProxy *)overlayProxy;
      }
    }
  }

  return [NSNull null];
}

- (NSArray *)arrayFromClusterItems:(NSArray<id<GMUClusterItem>> *)clusterItems
{
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:clusterItems.count];

  for (id<GMUClusterItem> clusterItem in clusterItems) {
    [result addObject:[[TiGooglemapsClusterItemProxy alloc] _initWithPageContext:[[self proxy] pageContext]
                                                                     andPosition:clusterItem.position
                                                                           title:[(TiPOIItem *)clusterItem title]
                                                                        subtitle:[(TiPOIItem *)clusterItem subtitle]
                                                                            icon:[(TiPOIItem *)clusterItem icon]
                                                                        userData:[(TiPOIItem *)clusterItem userData]]];
  }

  return result;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
  CLLocation *myLocation = _mapView.myLocation;

  if (myLocation != nil) {
    [[self proxy] fireEvent:@"myLocationUpdate" withObject:@{ @"latitude": @(myLocation.coordinate.latitude), @"longitude": @(myLocation.coordinate.longitude) }];
  }
}

#pragma mark Constants

MAKE_SYSTEM_PROP(OVERLAY_TYPE_POLYGON, TiGooglemapsOverlayTypePolygon);
MAKE_SYSTEM_PROP(OVERLAY_TYPE_POLYLINE, TiGooglemapsOverlayTypePolyline);
MAKE_SYSTEM_PROP(OVERLAY_TYPE_CIRCLE, TiGooglemapsOverlayTypeCircle);

@end
