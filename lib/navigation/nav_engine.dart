import 'package:collection/collection.dart';

import '../database_helper.dart';

class NavEngine {
  final Map<int, Node> nodes;
  final List<Link> links;

  NavEngine(this.nodes, this.links);

  List<Node> findShortestPath(int startId, int endId) {
    var distances = <int, double>{};
    var previous = <int, int?>{};
    var pq = PriorityQueue<MapEntry<int, double>>(
      (a, b) => a.value.compareTo(b.value),
    );

    for (var id in nodes.keys) {
      distances[id] = double.infinity;
    }
    distances[startId] = 0;
    pq.add(MapEntry(startId, 0));

    while (pq.isNotEmpty) {
      var current = pq.removeFirst().key;
      if (current == endId) break;

      var neighbors = links.where((l) => l.startNode == current);
      for (var link in neighbors) {
        double newDist = distances[current]! + link.weight;
        if (newDist < distances[link.endNode]!) {
          distances[link.endNode] = newDist;
          previous[link.endNode] = current;
          pq.add(MapEntry(link.endNode, newDist));
        }
      }
    }

    List<Node> path = [];
    int? step = endId;
    while (step != null) {
      path.insert(0, nodes[step]!);
      step = previous[step];
    }
    return path;
  }

  Map<String, dynamic> getPathInfo(int startId, int endId) {
    final path = findShortestPath(startId, endId);
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
