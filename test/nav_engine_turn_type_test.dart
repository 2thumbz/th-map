import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_nav_app/database_helper.dart';
import 'package:my_nav_app/navigation/nav_engine.dart';

void main() {
  group('NavEngine TURN_TYPE routing', () {
    final nodes = <int, Node>{
      1: Node(1, const LatLng(37.0, 127.0)),
      2: Node(2, const LatLng(37.0, 127.001)),
      3: Node(3, const LatLng(37.0, 127.002)),
      4: Node(4, const LatLng(37.001, 127.0015)),
    };

    final links = <Link>[
      Link(12, 1, 2, 1, 'A'),
      Link(23, 2, 3, 1, 'B'),
      Link(24, 2, 4, 1, 'C'),
      Link(43, 4, 3, 1, 'D'),
    ];

    test('003(회전금지) 전이는 피해서 우회 경로를 선택한다', () {
      final turnInfos = <TurnInfo>[
        const TurnInfo(prevLinkId: 12, nextLinkId: 23, turnType: '003'),
      ];

      final engine = NavEngine(nodes, links, turnInfos: turnInfos);
      final path = engine.findShortestPath(1, 3);

      expect(path.map((n) => n.id).toList(), [1, 2, 4, 3]);
    });

    test('011(U-TURN)은 허용 코드로 간주한다', () {
      final turnInfos = <TurnInfo>[
        const TurnInfo(prevLinkId: 12, nextLinkId: 23, turnType: '011'),
      ];

      final engine = NavEngine(nodes, links, turnInfos: turnInfos);
      final path = engine.findShortestPath(1, 3);

      expect(path.map((n) => n.id).toList(), [1, 2, 3]);
    });
  });
}
