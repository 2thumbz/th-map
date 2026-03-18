import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

double normalizeAngle(double value) {
  return ((value + 540) % 360) - 180;
}

double calculateBearing(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180.0;
  final lat2 = to.latitude * math.pi / 180.0;
  final deltaLon = (to.longitude - from.longitude) * math.pi / 180.0;

  final y = math.sin(deltaLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
  final bearing = math.atan2(y, x) * 180.0 / math.pi;
  return (bearing + 360.0) % 360.0;
}

double bearingDifferenceDegrees(double a, double b) {
  return normalizeAngle(a - b).abs();
}

LatLng interpolateLatLng(LatLng a, LatLng b, double t) {
  return LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );
}
