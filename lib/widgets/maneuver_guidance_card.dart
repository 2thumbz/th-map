import 'package:flutter/material.dart';

import '../navigation/maneuver_models.dart';
import '../navigation/maneuver_utils.dart';

class ManeuverGuidanceCard extends StatelessWidget {
  final ManeuverInfo? nextManeuver;
  final double distanceToManeuverMeters;
  final double remainingDistanceMeters;

  const ManeuverGuidanceCard({
    super.key,
    required this.nextManeuver,
    required this.distanceToManeuverMeters,
    required this.remainingDistanceMeters,
  });

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)}km';
    }
    return '${meters.toStringAsFixed(0)}m';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = nextManeuver != null
        ? '${distanceToManeuverMeters.toStringAsFixed(0)}m 후 ${nextManeuver!.roadName}'
        : '목적지까지 ${_formatDistance(remainingDistanceMeters)}';

    return Card(
      color: Colors.green.shade700,
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              nextManeuver != null
                  ? maneuverIcon(nextManeuver!.type)
                  : Icons.flag,
              color: Colors.white,
              size: 42,
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nextManeuver != null
                      ? maneuverLabel(nextManeuver!.type)
                      : '목적지 안내',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 30,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
