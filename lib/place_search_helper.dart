import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceSearchResult {
  final String displayName;
  final LatLng location;

  PlaceSearchResult({
    required this.displayName,
    required this.location,
  });
}

class PlaceSearchHelper {
  static const String _endpoint =
      'https://dapi.kakao.com/v2/local/search/keyword.json';
  static const String _apiKey = String.fromEnvironment('KAKAO_REST_API_KEY');

  Future<List<PlaceSearchResult>> searchPlace(String query, {int limit = 5}) async {
    if (query.trim().isEmpty) return [];
    if (_apiKey.isEmpty) return [];

    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'query': query,
        'size': '$limit',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'KakaoAK $_apiKey',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return [];
      final documents = decoded['documents'];
      if (documents is! List) return [];

      final results = <PlaceSearchResult>[];
      for (final item in documents) {
        if (item is! Map<String, dynamic>) continue;

        final latRaw = item['y']?.toString();
        final lonRaw = item['x']?.toString();
        final placeName = (item['place_name'] ?? '').toString();
        final roadAddress = (item['road_address_name'] ?? '').toString();
        final address = (item['address_name'] ?? '').toString();
        final displayName = placeName.isNotEmpty
            ? placeName
            : (roadAddress.isNotEmpty ? roadAddress : address);
        if (latRaw == null || lonRaw == null || displayName.isEmpty) continue;

        final lat = double.tryParse(latRaw);
        final lon = double.tryParse(lonRaw);
        if (lat == null || lon == null) continue;

        results.add(
          PlaceSearchResult(
            displayName: displayName,
            location: LatLng(lat, lon),
          ),
        );
      }

      return results;
    } catch (_) {
      return [];
    }
  }
}
