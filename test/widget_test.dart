import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:my_nav_app/database_helper.dart';
import 'package:my_nav_app/navigation/nav_engine.dart';

void main() {
  test('NavEngine returns shortest path from start to destination', () {
    final nodes = <int, Node>{
      1: Node(1, const LatLng(37.4017, 126.9767)),
      2: Node(2, const LatLng(37.4050, 126.9800)),
      3: Node(3, const LatLng(37.4100, 126.9850)),
      4: Node(4, const LatLng(37.4150, 126.9900)),
    };

    final links = <Link>[
      Link(101, 1, 2, 500, 'Road A'),
      Link(102, 2, 3, 600, 'Road B'),
      Link(103, 3, 4, 700, 'Road C'),
      Link(104, 1, 4, 5000, 'Long Detour'),
    ];

    final engine = NavEngine(nodes, links);
    final path = engine.findShortestPath(1, 4);

    expect(path.map((n) => n.id).toList(), [1, 2, 3, 4]);
  });
}
