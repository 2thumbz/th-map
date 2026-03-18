import 'package:flutter/material.dart';

class NavigationBottomPanel extends StatelessWidget {
  final double remainingDistanceMeters;
  final double remainingEtaMinutes;
  final VoidCallback onStop;

  const NavigationBottomPanel({
    super.key,
    required this.remainingDistanceMeters,
    required this.remainingEtaMinutes,
    required this.onStop,
  });

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)}km';
    }
    return '${meters.toStringAsFixed(0)}m';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '남은 거리: ${_formatDistance(remainingDistanceMeters)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'ETA: 약 ${remainingEtaMinutes.toStringAsFixed(1)}분',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('정지'),
            ),
          ],
        ),
      ),
    );
  }
}
