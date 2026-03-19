import 'package:collection/collection.dart';

import '../database_helper.dart';

class NavEngine {
  final Map<int, Node> nodes;
  final List<Link> links;
  final Map<int, Map<int, String>> _turnTypeByTransition;

  NavEngine(this.nodes, this.links, {List<TurnInfo> turnInfos = const []})
    : _turnTypeByTransition = _buildTurnTypeByTransition(turnInfos);

  static Map<int, Map<int, String>> _buildTurnTypeByTransition(
    List<TurnInfo> turnInfos,
  ) {
    final result = <int, Map<int, String>>{};
    for (final info in turnInfos) {
      if (!info.hasTransition) continue;
      result.putIfAbsent(
        info.prevLinkId!,
        () => <int, String>{},
      )[info.nextLinkId!] = info.turnType;
    }
    return result;
  }

  bool _isTurnTypeAllowed(String turnType) {
    switch (turnType) {
      case '002': // 버스만회전
      case '003': // 회전금지
      case '101': // 좌회전금지
      case '102': // 직진금지
      case '103': // 우회전금지
        return false;
      case '001': // 비보호회전
      case '011': // U-TURN
      case '012': // P-TURN
      default:
        return true;
    }
  }

  bool _isTransitionAllowed(int? prevLinkId, int nextLinkId) {
    if (prevLinkId == null) return true;
    final nextMap = _turnTypeByTransition[prevLinkId];
    if (nextMap == null) return true;
    final turnType = nextMap[nextLinkId];
    if (turnType == null) return true;
    return _isTurnTypeAllowed(turnType);
  }

  List<Node> findShortestPath(int startId, int endId) {
    final distances = <_PathState, double>{};
    final previous = <_PathState, _PathState?>{};
    final pq = PriorityQueue<_PathStateCost>(
      (a, b) => a.cost.compareTo(b.cost),
    );

    final startState = _PathState(startId, null);
    distances[startState] = 0;
    previous[startState] = null;
    pq.add(_PathStateCost(startState, 0));

    _PathState? bestEndState;

    while (pq.isNotEmpty) {
      final currentItem = pq.removeFirst();
      final currentState = currentItem.state;
      final currentCost = currentItem.cost;

      if (currentCost > (distances[currentState] ?? double.infinity)) {
        continue;
      }
      if (currentState.nodeId == endId) {
        bestEndState = currentState;
        break;
      }

      final neighbors = links.where((l) => l.startNode == currentState.nodeId);
      for (var link in neighbors) {
        if (!_isTransitionAllowed(currentState.prevLinkId, link.id)) {
          continue;
        }

        final newState = _PathState(link.endNode, link.id);
        final newDist = currentCost + link.weight;
        if (newDist < (distances[newState] ?? double.infinity)) {
          distances[newState] = newDist;
          previous[newState] = currentState;
          pq.add(_PathStateCost(newState, newDist));
        }
      }
    }

    if (bestEndState == null) {
      return [];
    }

    final path = <Node>[];
    _PathState? step = bestEndState;
    while (step != null) {
      final node = nodes[step.nodeId];
      if (node != null) {
        path.insert(0, node);
      }
      step = previous[step];
    }

    return path;
  }

  Map<String, dynamic> getPathInfo(int startId, int endId) {
    final path = findShortestPath(startId, endId);
    if (path.length < 2) {
      return {'path': path, 'distance': 0.0, 'roads': ''};
    }

    double totalDistance = 0;
    String roadSequence = '';

    for (int i = 0; i < path.length - 1; i++) {
      final link = links.firstWhereOrNull(
        (l) => l.startNode == path[i].id && l.endNode == path[i + 1].id,
      );
      if (link != null) {
        totalDistance += link.weight;
        if (roadSequence.isNotEmpty) roadSequence += ' -> ';
        roadSequence += link.roadName;
      }
    }

    return {'path': path, 'distance': totalDistance, 'roads': roadSequence};
  }
}

class _PathState {
  final int nodeId;
  final int? prevLinkId;

  const _PathState(this.nodeId, this.prevLinkId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _PathState &&
        other.nodeId == nodeId &&
        other.prevLinkId == prevLinkId;
  }

  @override
  int get hashCode => Object.hash(nodeId, prevLinkId);
}

class _PathStateCost {
  final _PathState state;
  final double cost;

  const _PathStateCost(this.state, this.cost);
}
