import 'dart:io';

import 'package:geojson/geojson.dart';
import 'package:geopoint/geopoint.dart';
import 'package:stream_transform/stream_transform.dart';

class Geofencing {
  List<GeoJsonFeature> features;

  Geofencing(this.features);

  /// Public factory
  static Future<Geofencing> fromFile(File file) async {
    final features = await featuresFromGeoJsonFile(file);
    final geofencing = Geofencing(features.collection);
    return geofencing;
  }

  /// Public factory
  static Future<Geofencing> fromString(String str) async {
    final features = await featuresFromGeoJson(str);
    final geofencing = Geofencing(features.collection);
    return geofencing;
  }

  Future<List<GeoJsonFeature>> contains(GeoPoint point) async {
    print("checking points against geo json");

    final geoJsonPoint = GeoJsonPoint(geoPoint: point);

    return await Stream.fromIterable(this.features)
        .asyncWhere((e) async => (await GeoJson()
                .geofencePolygon(polygon: e.geometry, points: [geoJsonPoint]))
            .isNotEmpty)
        .toList();
  }
}
