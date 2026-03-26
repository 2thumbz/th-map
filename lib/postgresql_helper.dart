import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'core/app_log.dart';
import 'database_helper.dart';

class NodeSearchSuggestion {
  final Node node;
  final String label;
  final double score;

  NodeSearchSuggestion({
    required this.node,
    required this.label,
    required this.score,
  });
}

class PostgresqlHelper {
  final String baseUrl;
  late http.Client _httpClient;

  PostgresqlHelper({
    required this.baseUrl, // 예: http://localhost:3000
  }) {
    _httpClient = http.Client();
  }

  // 데이터베이스 연결 (REST API의 경우 불필요하지만 인터페이스 호환성 유지)
  Future<void> connect() async {
    try {
      // 헬스 체크
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        appLog('REST API 서버 연결 성공');
      }
    } catch (e) {
      appLog('REST API 서버 연결 실패: $e');
      rethrow;
    }
  }

  // 데이터베이스 연결 해제
  Future<void> disconnect() async {
    _httpClient.close();
  }

  // 모든 노드 조회
  Future<Map<int, Node>> getAllNodes() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/api/nodes'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final Map<int, Node> nodes = {};

        for (var item in data) {
          final id = item['id'] as int;
          final latitude = (item['latitude'] as num).toDouble();
          final longitude = (item['longitude'] as num).toDouble();
          final name = item['name']?.toString();
          nodes[id] = Node(id, LatLng(latitude, longitude), name: name);
        }
        return nodes;
      } else {
        throw Exception('노드 로드 실패: ${response.statusCode}');
      }
    } catch (e) {
      appLog('노드 조회 실패: $e');
      rethrow;
    }
  }

  // 모든 링크 조회
  Future<List<Link>> getAllLinks() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/api/links'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Link> links = [];

        for (var item in data) {
          final id = item['id'] as int;
          final startNode = item['start_node'] as int;
          final endNode = item['end_node'] as int;
          final weight = (item['weight'] as num).toDouble();
          final roadName = item['road_name'] as String;
          links.add(Link(id, startNode, endNode, weight, roadName));
        }
        return links;
      } else {
        throw Exception('링크 로드 실패: ${response.statusCode}');
      }
    } catch (e) {
      appLog('링크 조회 실패: $e');
      rethrow;
    }
  }

  // 회전 제약 전이 정보 조회
  Future<List<TurnInfo>> getAllTurnInfos() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/api/turninfos'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map(
              (item) => TurnInfo.fromMap(item as Map<String, dynamic>),
            )
            .where((item) => item.turnType.isNotEmpty && item.hasTransition)
            .toList();
      }

      throw Exception('회전정보 로드 실패: ${response.statusCode}');
    } catch (e) {
      appLog('회전정보 조회 실패: $e');
      return [];
    }
  }

  // 노드 검색 (이름이나 ID로)
  Future<List<Node>> searchNodes(String query) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/nodes/search',
      ).replace(queryParameters: {'q': query});
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Node> nodes = [];

        for (var item in data) {
          final id = item['id'] as int;
          final latitude = (item['latitude'] as num).toDouble();
          final longitude = (item['longitude'] as num).toDouble();
          final name = item['name']?.toString();
          nodes.add(Node(id, LatLng(latitude, longitude), name: name));
        }
        return nodes;
      } else {
        return [];
      }
    } catch (e) {
      appLog('노드 검색 실패: $e');
      return [];
    }
  }

  double _scoreSuggestion(String query, String label, int id) {
    final q = query.toLowerCase().trim();
    final l = label.toLowerCase();
    final idStr = id.toString();

    if (q.isEmpty) return 0;
    if (l == q || idStr == q) return 100;
    if (l.startsWith(q)) return 85;
    if (l.contains(q)) return 70;
    if (idStr.contains(q)) return 60;

    int shared = 0;
    for (final ch in q.split('')) {
      if (l.contains(ch) || idStr.contains(ch)) {
        shared++;
      }
    }
    return math.min(50, shared * 8).toDouble();
  }

  // 추천 검색 결과 (이름 + 좌표 + 정렬 점수)
  Future<List<NodeSearchSuggestion>> searchNodeSuggestions(String query) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/nodes/search',
      ).replace(queryParameters: {'q': query});
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final List<dynamic> data = jsonDecode(response.body);
      final suggestions = <NodeSearchSuggestion>[];

      for (var item in data) {
        final id = item['id'] as int;
        final label = (item['name'] ?? '노드 $id').toString();
        final latitude = (item['latitude'] as num).toDouble();
        final longitude = (item['longitude'] as num).toDouble();
        final node = Node(id, LatLng(latitude, longitude), name: label);

        suggestions.add(
          NodeSearchSuggestion(
            node: node,
            label: label,
            score: _scoreSuggestion(query, label, id),
          ),
        );
      }

      suggestions.sort((a, b) => b.score.compareTo(a.score));
      return suggestions;
    } catch (e) {
      appLog('추천 검색 실패: $e');
      return [];
    }
  }

  // 위치 기반 가장 가까운 노드 찾기
  Future<Node?> findNearestNode(LatLng location) async {
    try {
      final uri = Uri.parse('$baseUrl/api/nodes/nearest').replace(
        queryParameters: {
          'lat': location.latitude.toString(),
          'lng': location.longitude.toString(),
        },
      );
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final id = data['id'] as int;
        final latitude = (data['latitude'] as num).toDouble();
        final longitude = (data['longitude'] as num).toDouble();
        final name = data['name']?.toString();
        return Node(id, LatLng(latitude, longitude), name: name);
      } else {
        return null;
      }
    } catch (e) {
      appLog('가장 가까운 노드 찾기 실패: $e');
      return null;
    }
  }

  // 노드 추가
  Future<void> insertNode(Node node) async {
    try {
      await _httpClient
          .post(
            Uri.parse('$baseUrl/api/nodes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': node.id,
              'latitude': node.location.latitude,
              'longitude': node.location.longitude,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      appLog('노드 추가 실패: $e');
    }
  }

  // 링크 추가
  Future<void> insertLink(Link link) async {
    try {
      await _httpClient
          .post(
            Uri.parse('$baseUrl/api/links'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': link.id,
              'start_node': link.startNode,
              'end_node': link.endNode,
              'weight': link.weight,
              'road_name': link.roadName,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      appLog('링크 추가 실패: $e');
    }
  }
}
