import 'package:flutter/material.dart';

import 'maneuver_models.dart';

ManeuverType? classifyTurn(double delta) {
  final absDelta = delta.abs();
  if (absDelta < 25) return null;
  if (absDelta > 150) return ManeuverType.uTurn;
  return delta > 0 ? ManeuverType.right : ManeuverType.left;
}

String maneuverLabel(ManeuverType type) {
  switch (type) {
    case ManeuverType.left:
      return '좌회전';
    case ManeuverType.right:
      return '우회전';
    case ManeuverType.uTurn:
      return '유턴';
  }
}

IconData maneuverIcon(ManeuverType type) {
  switch (type) {
    case ManeuverType.left:
      return Icons.turn_left;
    case ManeuverType.right:
      return Icons.turn_right;
    case ManeuverType.uTurn:
      return Icons.u_turn_left;
  }
}
