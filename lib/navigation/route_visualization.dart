import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'navigation_math.dart';

List<Marker> buildRouteArrowMarkers({
  required List<LatLng> points,
  required double spacingMeters,
  required int maxMarkers,
}) {
  if (points.length < 2) return const [];

  final distance = const Distance();
  final markers = <Marker>[];
  double distanceUntilNextArrow = spacingMeters * 0.6;

  for (int i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    final segmentMeters = distance.as(LengthUnit.Meter, start, end);
    if (segmentMeters < 3) continue;

    double traversedMeters = 0;
    final bearingRad = (calculateBearing(start, end) - 90.0) * math.pi / 180.0;

    while (traversedMeters + distanceUntilNextArrow <= segmentMeters) {
      traversedMeters += distanceUntilNextArrow;
      final t = (traversedMeters / segmentMeters).clamp(0.0, 1.0);
      final point = interpolateLatLng(start, end, t);

      markers.add(
        Marker(
          point: point,
          width: 20,
          height: 20,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: bearingRad,
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (markers.length >= maxMarkers) {
        return markers;
      }

      distanceUntilNextArrow = spacingMeters;
    }

    distanceUntilNextArrow -= (segmentMeters - traversedMeters);
    if (distanceUntilNextArrow <= 0) {
      distanceUntilNextArrow = spacingMeters;
    }
  }

  return markers;
}
