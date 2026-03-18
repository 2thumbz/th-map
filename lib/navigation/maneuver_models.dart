enum ManeuverType { left, right, uTurn }

class ManeuverInfo {
  final int nodeIndex;
  final ManeuverType type;
  final String roadName;

  ManeuverInfo({
    required this.nodeIndex,
    required this.type,
    required this.roadName,
  });
}
