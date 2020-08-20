import 'dart:io';

import 'package:geopoint/geopoint.dart';
import 'package:paris_masque/geofencing.dart';
import 'package:test/test.dart';

Future<bool> testFunc(GeoPoint point, Matcher want) async {
  final file = new File(
      'assets/data/coronavirus-port-du-masque-obligatoire-lieux-places-et-marches.geojson');

  return (await (await Geofencing.fromFile(file)).contains(point)).isNotEmpty;
}

void main() {
  group('Geofencing.contains', () {
    test('Parc Monceau to be false', () async {
      final point =
          GeoPoint(latitude: 48.87933059613624, longitude: 2.309075931979237);
      final want = isFalse;

      final got = await testFunc(point, isFalse);
      expect(got, want);
    });

    test('Louvre to be true', () async {
      final point = GeoPoint(latitude: 48.8606492757, longitude: 2.33751296997);
      final want = isTrue;

      final got = await testFunc(point, isFalse);
      expect(got, want);
    });

    test('Les Quais to be true', () async {
      final point =
          GeoPoint(latitude: 48.85434401169192, longitude: 2.3542727155285093);
      final want = isTrue;

      final got = await testFunc(point, isFalse);
      expect(got, want);
    });

    test('Pont Neuf to be true', () async {
      final point = GeoPoint(latitude: 48.85705, longitude: 2.3413252);
      final want = isTrue;

      final got = await testFunc(point, isFalse);
      expect(got, want);
    });

    test('Pont Cardinet to be false', () async {
      final point = GeoPoint(latitude: 48.8876011, longitude: 2.3141667);
      final want = isFalse;

      final got = await testFunc(point, isFalse);
      expect(got, want);
    });

    test('Champs-Élysées - Clemenceau to be false', () async {
      final point = GeoPoint(latitude: 48.8675367, longitude: 2.3133083);
      final want = isFalse;

      final got = await testFunc(point, isFalse);
      expect(got, want);
    });
  });
}
