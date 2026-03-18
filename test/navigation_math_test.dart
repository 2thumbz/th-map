import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_nav_app/navigation/navigation_math.dart';

void main() {
  test('calculateBearing returns east around 90 degrees', () {
    const from = LatLng(37.0, 127.0);
    const to = LatLng(37.0, 127.01);

    final bearing = calculateBearing(from, to);
    expect(bearing, greaterThan(80));
    expect(bearing, lessThan(100));
  });

  test('interpolateLatLng returns midpoint when t=0.5', () {
    const a = LatLng(37.0, 127.0);
    const b = LatLng(38.0, 128.0);

    final mid = interpolateLatLng(a, b, 0.5);
    expect(mid.latitude, closeTo(37.5, 1e-9));
    expect(mid.longitude, closeTo(127.5, 1e-9));
  });

  test('bearingDifferenceDegrees handles wrap-around', () {
    final diff = bearingDifferenceDegrees(350, 10);
    expect(diff, closeTo(20, 1e-9));
  });
}
