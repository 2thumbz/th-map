import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_nav_app/navigation/route_visualization.dart';

void main() {
  test('buildRouteArrowMarkers returns empty for short path', () {
    final markers = buildRouteArrowMarkers(
      points: const [LatLng(37.0, 127.0)],
      spacingMeters: 45,
      maxMarkers: 120,
    );
    expect(markers, isEmpty);
  });

  test('buildRouteArrowMarkers respects maxMarkers', () {
    final points = <LatLng>[];
    for (int i = 0; i < 200; i++) {
      points.add(LatLng(37.0 + i * 0.0001, 127.0 + i * 0.0001));
    }

    final markers = buildRouteArrowMarkers(
      points: points,
      spacingMeters: 5,
      maxMarkers: 8,
    );

    expect(markers.length, lessThanOrEqualTo(8));
  });
}
