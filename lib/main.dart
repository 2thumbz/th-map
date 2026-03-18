import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core/app_log.dart';
import 'database_helper.dart';
import 'navigation/maneuver_models.dart';
import 'navigation/maneuver_utils.dart';
import 'navigation/nav_engine.dart';
import 'navigation/navigation_math.dart';
import 'navigation/route_visualization.dart';
import 'postgresql_helper.dart';
import 'place_search_helper.dart';
import 'widgets/maneuver_guidance_card.dart';
import 'widgets/navigation_bottom_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite는 데스크톱에서 FFI 초기화가 필요하다.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyLocalNavApp());
}

// --- 3. UI 및 메인 로직 ---
class MyLocalNavApp extends StatelessWidget {
  const MyLocalNavApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const LocalNavScreen(),
    );
  }
}

class LocalNavScreen extends StatefulWidget {
  const LocalNavScreen({super.key});
  @override
  State<LocalNavScreen> createState() => _LocalNavScreenState();
}

// 앱의 핵심 상태/로직을 관리한다.
// - 데이터 소스(SQLite/PostgreSQL) 선택 및 로드
// - GPS 위치 추적/권한 처리
// - 경로 계산, 이탈 감지 재탐색, 내비게이션 UI 갱신
class _LocalNavScreenState extends State<LocalNavScreen> {
  // 경로 이탈 재탐색 정책
  // - 현재 위치가 경로에서 threshold(m) 이상 벗어난 상태가
  //   consecutiveHits 회 연속 감지되면 재탐색 후보로 판단한다.
  static const double _rerouteOffPathThresholdMeters = 20;
  static const int _rerouteOffPathConsecutiveHits = 2;
  static const double _rerouteCandidateRadiusMeters = 80;
  static const int _rerouteCandidateLimit = 6;
  static const double _rerouteHeadingToleranceDegrees = 100;
  static const double _maneuverHandoffDistanceMeters = 12;
  static const Duration _navigationMapRestoreDelay = Duration(seconds: 5);
  static const double _routeArrowSpacingMeters = 45;
  static const int _maxRouteArrowMarkers = 120;

  // 런타임 설정(dart-define)
  static const bool _enableBackend = bool.fromEnvironment(
    'ENABLE_BACKEND',
    defaultValue: false,
  );
  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const bool _offlineMapTiles = bool.fromEnvironment(
    'OFFLINE_MAP_TILES',
    defaultValue: true,
  );
  static const double _speedStartThresholdKmh = 4.0;
  static const double _speedStopThresholdKmh = 2.5;
  static const double _stationaryNoiseSpeedCeilingKmh = 6.0;
  static const double _stationaryNoiseMoveThresholdMeters = 3.5;
  static const int _stationaryNoiseConsecutiveHits = 2;

  // 과천 디테크타워 기준 시작점 (필요 시 좌표 미세 조정 가능)
  static const LatLng _gwacheonDTechTower = LatLng(37.4019, 126.9882);

  // 외부 의존성/헬퍼
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late PostgresqlHelper? _pgHelper;
  final PlaceSearchHelper _placeSearchHelper = PlaceSearchHelper();

  // 지도/경로/주행 상태
  Map<int, Node> _nodes = {};
  List<Link> _links = [];
  List<Node> _currentPath = [];
  final MapController _mapController = MapController();
  LatLng _currentLocation = _gwacheonDTechTower;
  double _mapZoom = 15;
  double _navigationFollowZoom = 17;
  double _preNavigationZoom = 15;
  double _mapRotation = 0;
  double _carHeadingDeg = 0;
  bool _isNavigating = false;
  bool _isNavigationMapFollowPaused = false;
  Timer? _timer;
  Timer? _networkTimer;
  Timer? _navigationMapRestoreTimer;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<Position>? _passivePositionSubscription;
  int _pathIndex = 0;
  double _interpolationProgress = 0.0; // 노드 간 보간 진행률 (0.0~1.0)
  bool _isLoading = true;
  bool _isLocating = false;
  bool _usePostgreSQL = false;

  Node? _currentNode; // 현재 위치의 노드
  Node? _destinationNode; // 목적지 노드
  List<NodeSearchSuggestion> _searchResults = [];
  Map<int, double?> _etaMinutesByNode = {};
  Map<int, double> _linearKmByNode = {};
  List<ManeuverInfo> _maneuvers = [];
  ManeuverInfo? _nextManeuver;
  double _totalDistance = 0;
  double _currentSpeedKmh = 0;
  bool _isVehicleMoving = false;
  int _stationaryNoiseHitCount = 0;
  String _roadSequence = '';
  bool _hasInternet = true;
  bool _hasOfflineTileAssets = false;
  int? _offlineTileMinZoom;
  int? _offlineTileMaxZoom;
  bool _hasGpsFix = false;

  final TextEditingController _searchController = TextEditingController();

  DateTime? _lastPathRecalcAt;
  int _offPathHitCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_detectOfflineTileAssets());
    unawaited(_checkInternetConnectivity());
    _networkTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_checkInternetConnectivity()),
    );
    _loadData();
  }

  bool get _useOfflineTilesNow =>
      _hasOfflineTileAssets && (_offlineMapTiles || !_hasInternet);

  int? _extractOfflineTileZoom(String assetPath) {
    final fileName = assetPath.split('/').last;
    final match = RegExp(
      r'^(\d+)_\d+_\d+\.(?:png|jpg|webp)$',
    ).firstMatch(fileName);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  // 에셋에 오프라인 타일이 포함되어 있는지 검사한다.
  Future<void> _detectOfflineTileAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final tileAssets = manifest
          .listAssets()
          .where(
            (key) =>
                key.startsWith('assets/tiles/') &&
                (key.endsWith('.png') ||
                    key.endsWith('.jpg') ||
                    key.endsWith('.webp')),
          )
          .toList();
      final hasTiles = tileAssets.isNotEmpty;

      int? minZoom;
      int? maxZoom;
      for (final asset in tileAssets) {
        final z = _extractOfflineTileZoom(asset);
        if (z == null) continue;
        minZoom = minZoom == null ? z : math.min(minZoom, z);
        maxZoom = maxZoom == null ? z : math.max(maxZoom, z);
      }

      if (!mounted) return;
      setState(() {
        _hasOfflineTileAssets = hasTiles;
        _offlineTileMinZoom = minZoom;
        _offlineTileMaxZoom = maxZoom;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasOfflineTileAssets = false;
        _offlineTileMinZoom = null;
        _offlineTileMaxZoom = null;
      });
    }
  }

  Future<void> _checkInternetConnectivity() async {
    bool hasInternet;
    try {
      final result = await InternetAddress.lookup(
        'tile.openstreetmap.org',
      ).timeout(const Duration(seconds: 2));
      hasInternet = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      hasInternet = false;
    }

    if (!mounted || hasInternet == _hasInternet) return;
    setState(() {
      _hasInternet = hasInternet;
    });
  }

  void _followLocationOnMap() {
    if (_isNavigating && _isNavigationMapFollowPaused) return;

    final targetZoom = _isNavigating ? _navigationFollowZoom : _mapZoom;
    _mapZoom = targetZoom;
    _mapController.move(_currentLocation, targetZoom);
    _mapController.rotate(_mapRotation);
  }

  void _scheduleNavigationMapRestore() {
    if (!_isNavigating) return;

    _navigationMapRestoreTimer?.cancel();
    _isNavigationMapFollowPaused = true;
    _navigationMapRestoreTimer = Timer(_navigationMapRestoreDelay, () {
      if (!mounted || !_isNavigating) return;
      setState(() {
        _isNavigationMapFollowPaused = false;
        _mapZoom = _navigationFollowZoom;
      });
      _followLocationOnMap();
    });
  }

  void _moveMapTo(LatLng target, {double? zoom}) {
    if (zoom != null) {
      _mapZoom = zoom;
    }
    _mapController.move(target, _mapZoom);
  }

  LatLng? _parseLatLngInput(String query) {
    final cleaned = query.trim().replaceAll(' ', '');
    final parts = cleaned.split(',');
    if (parts.length != 2) return null;

    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    return LatLng(lat, lng);
  }

  double _normalizeAngle(double value) {
    return ((value + 540) % 360) - 180;
  }

  // 경로 노드 열을 기반으로 좌/우회전/유턴 포인트를 추론한다.
  void _buildManeuversFromPath() {
    final result = <ManeuverInfo>[];
    if (_currentPath.length < 3) {
      _maneuvers = result;
      _nextManeuver = null;
      return;
    }

    for (int i = 0; i < _currentPath.length - 2; i++) {
      final first = _currentPath[i].location;
      final middle = _currentPath[i + 1].location;
      final last = _currentPath[i + 2].location;

      final inBearing = calculateBearing(first, middle);
      final outBearing = calculateBearing(middle, last);
      final delta = _normalizeAngle(outBearing - inBearing);
      final maneuverType = classifyTurn(delta);
      if (maneuverType == null) continue;

      final nextLink = _links.firstWhereOrNull(
        (l) =>
            l.startNode == _currentPath[i + 1].id &&
            l.endNode == _currentPath[i + 2].id,
      );

      result.add(
        ManeuverInfo(
          nodeIndex: i + 1,
          type: maneuverType,
          roadName: nextLink?.roadName ?? '다음 도로',
        ),
      );
    }

    _maneuvers = result;
    _updateNextManeuver();
  }

  // 현재 진행 인덱스 기준으로 가장 가까운 다음 안내를 선택한다.
  void _updateNextManeuver() {
    if (_currentPath.isEmpty || _maneuvers.isEmpty) {
      _nextManeuver = null;
      return;
    }
    final projection = _isNavigating
        ? _projectLocationOntoCurrentPath(_currentLocation)
        : null;
    final currentIndex =
        projection?.segmentIndex ??
        (_pathIndex - 1).clamp(0, _currentPath.length - 1);

    for (final maneuver in _maneuvers) {
      if (maneuver.nodeIndex > currentIndex) {
        _nextManeuver = maneuver;
        return;
      }

      if (projection != null && maneuver.nodeIndex == currentIndex) {
        final maneuverNode = _currentPath[maneuver.nodeIndex].location;
        final distanceToNode = const Distance().as(
          LengthUnit.Meter,
          _currentLocation,
          maneuverNode,
        );
        if (distanceToNode <= _maneuverHandoffDistanceMeters) {
          _nextManeuver = maneuver;
          return;
        }
      }
    }

    _nextManeuver = null;
  }

  // 다음 회전 안내 노드까지의 누적 거리를 계산한다.
  double _distanceToManeuverMeters() {
    if (_nextManeuver == null || _currentPath.isEmpty) return 0;
    final projection = _isNavigating
        ? _projectLocationOntoCurrentPath(_currentLocation)
        : null;
    final currentIndex =
        projection?.segmentIndex ??
        (_pathIndex - 1).clamp(0, _currentPath.length - 1);
    final targetIndex = _nextManeuver!.nodeIndex;
    if (targetIndex < currentIndex) return 0;

    if (targetIndex == currentIndex) {
      return 0;
    }

    final distance = const Distance();
    double meters = 0;
    if (projection != null) {
      final projected = interpolateLatLng(
        _currentPath[currentIndex].location,
        _currentPath[currentIndex + 1].location,
        projection.t,
      );
      meters += distance.as(
        LengthUnit.Meter,
        projected,
        _currentPath[currentIndex + 1].location,
      );
    }
    for (
      int i = currentIndex + (projection != null ? 1 : 0);
      i < targetIndex;
      i++
    ) {
      meters += distance.as(
        LengthUnit.Meter,
        _currentPath[i].location,
        _currentPath[i + 1].location,
      );
    }
    return meters;
  }

  // 백엔드 URL 결정 순서:
  // 1) API_BASE_URL dart-define
  // 2) 플랫폼 기본값(안드로이드 에뮬레이터/로컬호스트)
  String _resolveApiBaseUrl() {
    final envUrl = _apiBaseUrlFromEnv.trim();
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    return Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://localhost:3000';
  }

  // 로컬 DB가 비어 있으면 자동 복구를 시도한 뒤 데이터를 다시 읽는다.
  Future<(Map<int, Node>, List<Link>)> _loadLocalDataWithRepair() async {
    var nodes = await _dbHelper.getAllNodes();
    var links = await _dbHelper.getAllLinks();

    if (nodes.isEmpty || links.isEmpty) {
      await _dbHelper.repairDatabaseIfEmpty();
      nodes = await _dbHelper.getAllNodes();
      links = await _dbHelper.getAllLinks();
    }

    return (nodes, links);
  }

  // 앱 시작 시 데이터 소스를 초기화한다.
  // - 기본: SQLite 오프라인 모드
  // - 옵션: PostgreSQL 연결 시도 후 실패하면 SQLite로 폴백
  Future<void> _loadData() async {
    try {
      if (!_enableBackend) {
        final (nodes, links) = await _loadLocalDataWithRepair();

        setState(() {
          _nodes = nodes;
          _links = links;
          _usePostgreSQL = false;
          _currentLocation = _gwacheonDTechTower;
          _currentNode = _findNearestNodeLocal(_gwacheonDTechTower);
          _isLoading = false;
        });

        appLog('오프라인 모드(SQLite)로 데이터 로드');

        // 데이터 로드 후 GPS 현재 위치 자동 조회
        unawaited(_syncCurrentLocationToNearestNode(showMessage: false));
        unawaited(_startPassiveGpsTracking());
        return;
      }

      // PostgreSQL 연동 먼저 시도
      final apiBaseUrl = _resolveApiBaseUrl();

      _pgHelper = PostgresqlHelper(baseUrl: apiBaseUrl);

      try {
        await _pgHelper?.connect();
        final pgNodes = await _pgHelper?.getAllNodes();
        final pgLinks = await _pgHelper?.getAllLinks();

        if (pgNodes != null && pgLinks != null && pgNodes.isNotEmpty) {
          Node? nearestToDefault;
          if (_pgHelper != null) {
            nearestToDefault = await _pgHelper!.findNearestNode(
              _gwacheonDTechTower,
            );
          }

          setState(() {
            _nodes = pgNodes;
            _links = pgLinks;
            _usePostgreSQL = true;
            _currentLocation = _gwacheonDTechTower;
            _currentNode =
                nearestToDefault ?? _findNearestNodeLocal(_gwacheonDTechTower);
          });
          appLog('PostgreSQL 데이터 로드 성공');
        } else {
          throw Exception('PostgreSQL 데이터가 비어있습니다.');
        }
      } catch (e) {
        appLog('PostgreSQL 연결 실패, 로컬 DB 사용: $e');

        // 실패 시 로컬 DB fallback
        final (nodes, links) = await _loadLocalDataWithRepair();

        setState(() {
          _nodes = nodes;
          _links = links;
          _usePostgreSQL = false;
          _currentLocation = _gwacheonDTechTower;
          _currentNode = _findNearestNodeLocal(_gwacheonDTechTower);
        });
      }

      setState(() => _isLoading = false);
      unawaited(_startPassiveGpsTracking());
    } catch (e) {
      appLog('데이터 로드 오류: $e');
      setState(() => _isLoading = false);
    }
  }

  // GPS 포지션을 UI 상태에 반영하고, 가장 가까운 그래프 노드를 업데이트한다.
  Future<void> _updateCurrentLocationFromPosition(Position pos) async {
    final gpsLocation = LatLng(pos.latitude, pos.longitude);
    Node? nearestNode;
    if (_usePostgreSQL && _pgHelper != null) {
      nearestNode = await _pgHelper!.findNearestNode(gpsLocation);
    }
    nearestNode ??= _findNearestNodeLocal(gpsLocation);

    if (!mounted) return;
    setState(() {
      _currentLocation = gpsLocation;
      _hasGpsFix = true;
      if (nearestNode != null) {
        _currentNode = nearestNode;
      }
    });
    _followLocationOnMap();
  }

  // 내비게이션 비활성 상태에서 저전력 수동 위치 추적을 유지한다.
  Future<void> _startPassiveGpsTracking() async {
    final canUseLocation = await _ensureLocationAccess(showMessage: true);
    if (!canUseLocation) return;

    _passivePositionSubscription?.cancel();
    _passivePositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 3,
          ),
        ).listen(
          (position) async {
            if (!mounted || _isNavigating) return;
            await _updateCurrentLocationFromPosition(position);
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _hasGpsFix = false;
            });
          },
        );
  }

  // 로컬 노드 집합에서 가장 가까운 노드를 선형 탐색으로 찾는다.
  Node? _findNearestNodeLocal(LatLng location) {
    if (_nodes.isEmpty) return null;
    final distance = const Distance();
    Node? nearest;
    double minMeters = double.infinity;

    for (final node in _nodes.values) {
      final meters = distance.as(LengthUnit.Meter, location, node.location);
      if (meters < minMeters) {
        minMeters = meters;
        nearest = node;
      }
    }
    return nearest;
  }

  // 현재 위치 버튼 처리:
  // - 권한 확인
  // - 현재/마지막 위치 조회
  // - 지도 이동 및 필요 시 경로 재계산
  Future<void> _syncCurrentLocationToNearestNode({
    bool showMessage = true,
  }) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      final canUseLocation = await _ensureLocationAccess(
        showMessage: showMessage,
      );
      if (!canUseLocation) {
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
          ),
        ).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (mounted) {
          setState(() {
            _hasGpsFix = false;
          });
        }
        if (showMessage && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS 위치를 확인하지 못했습니다. 실외에서 다시 시도해 주세요.'),
            ),
          );
        }
        return;
      }

      await _updateCurrentLocationFromPosition(pos);

      final nearestNode = _currentNode;
      final gpsLocation = _currentLocation;

      // 현재 위치 버튼을 누르면 지도를 현재 위치로 즉시 이동한다.
      _moveMapTo(gpsLocation, zoom: math.max(_mapZoom, 17));

      if (_destinationNode != null && _currentNode != null) {
        _calculatePath();
      }

      if (showMessage && mounted && nearestNode != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('현재 위치 기준 시작 노드: ${nearestNode.id}')),
        );
      }
    } catch (e) {
      if (showMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('현재 위치 조회 실패: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  // 위치 서비스/권한 검증 공통 함수
  Future<bool> _ensureLocationAccess({bool showMessage = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('위치 서비스가 꺼져 있습니다.')));
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (showMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('위치 권한이 필요합니다.')));
      }
      return false;
    }

    return true;
  }

  // 과도한 재탐색을 막기 위한 쿨다운 게이트
  bool _canRecalculatePathNow() {
    final now = DateTime.now();
    if (_lastPathRecalcAt == null ||
        now.difference(_lastPathRecalcAt!) >= const Duration(seconds: 3)) {
      _lastPathRecalcAt = now;
      return true;
    }
    return false;
  }

  ({double distanceMeters, double t}) _distanceAndTPointToSegmentMeters(
    LatLng p,
    LatLng a,
    LatLng b,
  ) {
    final refLatRad = ((a.latitude + b.latitude) * 0.5) * math.pi / 180.0;
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(refLatRad);

    final ax = a.longitude * metersPerDegLng;
    final ay = a.latitude * metersPerDegLat;
    final bx = b.longitude * metersPerDegLng;
    final by = b.latitude * metersPerDegLat;
    final px = p.longitude * metersPerDegLng;
    final py = p.latitude * metersPerDegLat;

    final abx = bx - ax;
    final aby = by - ay;
    final abLenSq = abx * abx + aby * aby;
    if (abLenSq <= 1e-6) {
      final dx = px - ax;
      final dy = py - ay;
      return (distanceMeters: math.sqrt(dx * dx + dy * dy), t: 0.0);
    }

    final apx = px - ax;
    final apy = py - ay;
    final t = ((apx * abx + apy * aby) / abLenSq).clamp(0.0, 1.0);
    final cx = ax + abx * t;
    final cy = ay + aby * t;
    final dx = px - cx;
    final dy = py - cy;
    return (distanceMeters: math.sqrt(dx * dx + dy * dy), t: t);
  }

  // 경위도 평면 근사 기반 점-선분 최소거리 계산(미터)
  double _distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    return _distanceAndTPointToSegmentMeters(p, a, b).distanceMeters;
  }

  ({int segmentIndex, double t})? _projectLocationOntoCurrentPath(
    LatLng location,
  ) {
    if (_currentPath.length < 2) return null;

    int bestSegmentIndex = 0;
    double bestDistance = double.infinity;
    double bestT = 0.0;

    for (int i = 0; i < _currentPath.length - 1; i++) {
      final info = _distanceAndTPointToSegmentMeters(
        location,
        _currentPath[i].location,
        _currentPath[i + 1].location,
      );
      if (info.distanceMeters < bestDistance) {
        bestDistance = info.distanceMeters;
        bestSegmentIndex = i;
        bestT = info.t;
      }
    }

    return (segmentIndex: bestSegmentIndex, t: bestT);
  }

  // 현재 경로 polyline 전체에 대한 최소 이격거리(미터)
  double _minDistanceToCurrentPathMeters(LatLng location) {
    if (_currentPath.length < 2) return double.infinity;

    double minMeters = double.infinity;
    for (int i = 0; i < _currentPath.length - 1; i++) {
      final meters = _distancePointToSegmentMeters(
        location,
        _currentPath[i].location,
        _currentPath[i + 1].location,
      );
      if (meters < minMeters) {
        minMeters = meters;
      }
    }
    return minMeters;
  }

  // 거리 기반 이탈 재탐색 조건:
  // - 경로와의 최소거리 임계 초과
  // - 연속 감지 횟수 충족
  // - 쿨다운 충족
  bool _shouldRecalculateByOffPath(LatLng location) {
    if (_destinationNode == null || _currentPath.length < 2) return false;

    final offPathMeters = _minDistanceToCurrentPathMeters(location);
    if (offPathMeters >= _rerouteOffPathThresholdMeters) {
      _offPathHitCount += 1;
    } else {
      _offPathHitCount = 0;
    }

    if (_offPathHitCount < _rerouteOffPathConsecutiveHits) {
      return false;
    }
    return _canRecalculatePathNow();
  }

  Node? _selectRerouteStartNode(LatLng location, double heading) {
    if (_destinationNode == null || _nodes.isEmpty) {
      return _findNearestNodeLocal(location);
    }

    final distance = const Distance();
    final candidates = _nodes.values
        .map(
          (node) => (
            node: node,
            distanceMeters: distance.as(
              LengthUnit.Meter,
              location,
              node.location,
            ),
          ),
        )
        .where(
          (candidate) =>
              candidate.distanceMeters <= _rerouteCandidateRadiusMeters,
        )
        .sorted((a, b) => a.distanceMeters.compareTo(b.distanceMeters))
        .take(_rerouteCandidateLimit)
        .toList();

    if (candidates.isEmpty) {
      return _findNearestNodeLocal(location);
    }

    final engine = NavEngine(_nodes, _links);
    Node? bestNode;
    double bestScore = double.infinity;

    for (final candidate in candidates) {
      final path = engine.findShortestPath(
        candidate.node.id,
        _destinationNode!.id,
      );
      if (path.length < 2) continue;

      final firstBearing = calculateBearing(path[0].location, path[1].location);
      final headingDiff = bearingDifferenceDegrees(heading, firstBearing);
      if (headingDiff > _rerouteHeadingToleranceDegrees) continue;

      final score = candidate.distanceMeters + headingDiff * 0.35;
      if (score < bestScore) {
        bestScore = score;
        bestNode = candidate.node;
      }
    }

    return bestNode ?? candidates.first.node;
  }

  // 현재 위치를 기준으로 앞으로 남은 경로만 반환한다.
  // 내비게이션 중이 아닐 때는 전체 경로를 그대로 반환한다.
  List<LatLng> _remainingPathPointsFromLocation(LatLng location) {
    if (_currentPath.length < 2) {
      return _currentPath.map((n) => n.location).toList();
    }
    if (!_isNavigating) {
      return _currentPath.map((n) => n.location).toList();
    }

    int bestSegmentIndex = 0;
    double bestDistance = double.infinity;
    double bestT = 0.0;

    for (int i = 0; i < _currentPath.length - 1; i++) {
      final info = _distanceAndTPointToSegmentMeters(
        location,
        _currentPath[i].location,
        _currentPath[i + 1].location,
      );
      if (info.distanceMeters < bestDistance) {
        bestDistance = info.distanceMeters;
        bestSegmentIndex = i;
        bestT = info.t;
      }
    }

    final remaining = <LatLng>[
      interpolateLatLng(
        _currentPath[bestSegmentIndex].location,
        _currentPath[bestSegmentIndex + 1].location,
        bestT,
      ),
    ];

    for (int i = bestSegmentIndex + 1; i < _currentPath.length; i++) {
      remaining.add(_currentPath[i].location);
    }
    return remaining;
  }

  // 현재 위치를 기준으로 경로 상 남은 누적 거리(미터)
  double _remainingDistanceMetersFromLocation(LatLng location) {
    if (_currentPath.length < 2) return _totalDistance;
    if (!_isNavigating) return _totalDistance;

    final projection = _projectLocationOntoCurrentPath(location);
    if (projection == null) return _totalDistance;
    final bestSegmentIndex = projection.segmentIndex;

    final distance = const Distance();
    final projected = interpolateLatLng(
      _currentPath[bestSegmentIndex].location,
      _currentPath[bestSegmentIndex + 1].location,
      projection.t,
    );

    double remainingMeters = distance.as(
      LengthUnit.Meter,
      projected,
      _currentPath[bestSegmentIndex + 1].location,
    );

    for (int i = bestSegmentIndex + 1; i < _currentPath.length - 1; i++) {
      remainingMeters += distance.as(
        LengthUnit.Meter,
        _currentPath[i].location,
        _currentPath[i + 1].location,
      );
    }
    return remainingMeters;
  }

  // 현재 속도 기반 남은 시간(분) 추정.
  // GPS 속도가 너무 낮거나 불안정하면 기본 추정 속도(10km/h)를 사용한다.
  double _remainingEtaMinutesFromDistance(double remainingMeters) {
    final effectiveSpeedKmh = _currentSpeedKmh >= 5 ? _currentSpeedKmh : 10.0;
    final metersPerMinute = effectiveSpeedKmh * 1000 / 60;
    if (metersPerMinute <= 0) return 0;
    return remainingMeters / metersPerMinute;
  }

  // GPS 정차 노이즈(약 1~3km/h)를 줄이기 위한 히스테리시스 필터.
  double _normalizeGpsSpeedKmh(double rawSpeedKmh, double movedMeters) {
    final clamped = rawSpeedKmh.clamp(0, 160).toDouble();

    final looksStationaryNoise =
        clamped <= _stationaryNoiseSpeedCeilingKmh &&
        movedMeters <= _stationaryNoiseMoveThresholdMeters;
    if (looksStationaryNoise) {
      _stationaryNoiseHitCount += 1;
    } else {
      _stationaryNoiseHitCount = 0;
    }

    if (_stationaryNoiseHitCount >= _stationaryNoiseConsecutiveHits) {
      _isVehicleMoving = false;
      return 0;
    }

    if (_isVehicleMoving) {
      if (clamped <= _speedStopThresholdKmh && movedMeters < 4.0) {
        _isVehicleMoving = false;
        return 0;
      }
      return clamped;
    }

    if (clamped >= _speedStartThresholdKmh ||
        (clamped >= _speedStopThresholdKmh && movedMeters >= 8.0)) {
      _isVehicleMoving = true;
      return clamped;
    }

    return 0;
  }

  // GPS 불가 시 폴백되는 시뮬레이션 주행(디버깅/데모 용도)
  void _startSimulatedNavigation() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_pathIndex < _currentPath.length - 1) {
        setState(() {
          // 보간 진행률 업데이트 (0.1씩 증가하면 1초에 완료)
          _interpolationProgress += 0.1;

          if (_interpolationProgress >= 1.0) {
            // 다음 노드로 이동
            _pathIndex++;
            _interpolationProgress = 0.0;
            _currentNode = _currentPath[_pathIndex];
            _updateNextManeuver();

            if (_pathIndex >= _currentPath.length - 1) {
              // 마지막 노드 도착
              _currentLocation = _currentPath[_pathIndex].location;
              _currentSpeedKmh = 0;
              return;
            }
          }

          // 현재 노드와 다음 노드 사이를 선형 보간
          final currentNode = _currentPath[_pathIndex];
          final nextNode = _currentPath[_pathIndex + 1];

          final lat =
              currentNode.location.latitude +
              (nextNode.location.latitude - currentNode.location.latitude) *
                  _interpolationProgress;
          final lng =
              currentNode.location.longitude +
              (nextNode.location.longitude - currentNode.location.longitude) *
                  _interpolationProgress;

          _currentLocation = LatLng(lat, lng);

          // 이동 방향 계산 및 속도 업데이트
          final heading = calculateBearing(
            currentNode.location,
            nextNode.location,
          );
          _mapRotation = -heading;
          _carHeadingDeg = heading;

          // 속도 계산 (노드 간 거리 / 예상 시간 1초)
          if (_interpolationProgress < 0.2) {
            final distance = const Distance().as(
              LengthUnit.Meter,
              currentNode.location,
              nextNode.location,
            );
            _currentSpeedKmh = (distance * 3.6).clamp(0, 80).toDouble();
          }
        });
        _followLocationOnMap();
      } else {
        // 네비게이션 종료
        timer.cancel();
        setState(() {
          _isNavigating = false;
          _currentSpeedKmh = 0;
          _isVehicleMoving = false;
          _stationaryNoiseHitCount = 0;
          _nextManeuver = null;
        });
      }
    });
  }

  // 실제 GPS 기반 주행 루프
  // - 위치/헤딩/속도 갱신
  // - 노드 변경 또는 경로 이탈 시 재탐색
  // - 목적지 근접 시 자동 종료
  Future<void> _startGpsNavigation() async {
    final canUseLocation = await _ensureLocationAccess(showMessage: true);
    if (!canUseLocation) {
      return;
    }

    await _syncCurrentLocationToNearestNode(showMessage: false);

    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 3,
          ),
        ).listen(
          (position) async {
            if (!mounted || !_isNavigating) return;

            final gpsLocation = LatLng(position.latitude, position.longitude);
            final previousLocation = _currentLocation;

            Node? nearestNode;
            if (_usePostgreSQL && _pgHelper != null) {
              nearestNode = await _pgHelper!.findNearestNode(gpsLocation);
            }
            nearestNode ??= _findNearestNodeLocal(gpsLocation);

            final movedMeters = const Distance().as(
              LengthUnit.Meter,
              previousLocation,
              gpsLocation,
            );

            double heading = _carHeadingDeg;
            if (position.heading >= 0) {
              heading = position.heading;
            } else if (movedMeters > 1.5) {
              heading = calculateBearing(previousLocation, gpsLocation);
            }

            final speedKmh = position.speed >= 0
                ? position.speed * 3.6
                : _currentSpeedKmh;
            final normalizedSpeedKmh = _normalizeGpsSpeedKmh(
              speedKmh,
              movedMeters,
            );

            final shouldRecalculate = _shouldRecalculateByOffPath(gpsLocation);
            final rerouteStartNode = shouldRecalculate
                ? _selectRerouteStartNode(gpsLocation, heading)
                : null;

            setState(() {
              _currentLocation = gpsLocation;
              _mapRotation = -heading;
              _carHeadingDeg = heading;
              _currentSpeedKmh = normalizedSpeedKmh;
              if (rerouteStartNode != null) {
                _currentNode = rerouteStartNode;
              } else if (nearestNode != null) {
                _currentNode = nearestNode;
              }
              _updateNextManeuver();
            });

            if (shouldRecalculate) {
              _calculatePath();
            }

            _followLocationOnMap();

            if (_destinationNode != null) {
              final remainMeters = const Distance().as(
                LengthUnit.Meter,
                gpsLocation,
                _destinationNode!.location,
              );

              if (remainMeters <= 20) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('목적지에 도착했습니다.')));
                }
                _stopNavigation();
              }
            }
          },
          onError: (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('GPS 추적 오류로 시뮬레이션 모드로 전환합니다: $error')),
              );
            }
            _positionSubscription?.cancel();
            _startSimulatedNavigation();
          },
        );
  }

  // 노드 검색(ID/백엔드 제안)
  Future<void> _searchDestination(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _etaMinutesByNode = {};
        _linearKmByNode = {};
      });
      return;
    }

    try {
      List<NodeSearchSuggestion> results = [];

      if (_usePostgreSQL && _pgHelper != null) {
        results = await _pgHelper!.searchNodeSuggestions(query);
      } else {
        final q = query.trim().toLowerCase();
        if (q.isNotEmpty) {
          results = _nodes.values
              .where((node) {
                final idMatch = node.id.toString().contains(q);
                final name = node.name?.toLowerCase() ?? '';
                final nameMatch = name.contains(q);
                return idMatch || nameMatch;
              })
              .map((node) {
                final name = node.name?.trim();
                final label = (name != null && name.isNotEmpty)
                    ? '$name (노드 ${node.id})'
                    : '노드 ${node.id}';
                final nameLower = (node.name ?? '').toLowerCase();
                final score = nameLower == q
                    ? 100.0
                    : nameLower.startsWith(q)
                    ? 90.0
                    : nameLower.contains(q)
                    ? 75.0
                    : node.id.toString() == q
                    ? 85.0
                    : 60.0;

                return NodeSearchSuggestion(
                  node: node,
                  label: label,
                  score: score,
                );
              })
              .toList();
          results.sort((a, b) => b.score.compareTo(a.score));
        }
      }

      final etaMap = <int, double?>{};
      final linearMap = <int, double>{};
      for (final suggestion in results.take(8)) {
        etaMap[suggestion.node.id] = _estimateMinutesToNode(suggestion.node);
        linearMap[suggestion.node.id] = _estimateLinearKmToNode(
          suggestion.node,
        );
      }

      setState(() {
        _searchResults = results;
        _etaMinutesByNode = etaMap;
        _linearKmByNode = linearMap;
      });
    } catch (e) {
      appLog('검색 실패: $e');
    }
  }

  // 현재 노드 기준 네트워크 경로 거리로 ETA를 추정한다.
  double? _estimateMinutesToNode(Node destination) {
    if (_currentNode == null) return null;
    final engine = NavEngine(_nodes, _links);
    final pathInfo = engine.getPathInfo(_currentNode!.id, destination.id);
    final path = pathInfo['path'] as List<Node>;
    if (path.length < 2) return null;
    final meters = pathInfo['distance'] as double;
    const assumedKmh = 35.0;
    final minutes = meters / (assumedKmh * 1000 / 60);
    return minutes;
  }

  // 현재 좌표와 목적지 좌표의 직선 거리(km)
  double _estimateLinearKmToNode(Node destination) {
    const distance = Distance();
    final meters = distance(_currentLocation, destination.location);
    return meters / 1000.0;
  }

  // 통합 검색 처리:
  // - lat,lng 직접 입력
  // - 지명 검색(Kakao)
  // - 노드 검색
  Future<void> _submitSearch([String? value]) async {
    final query = (value ?? _searchController.text).trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _etaMinutesByNode = {};
        _linearKmByNode = {};
      });
      return;
    }

    final latLngInput = _parseLatLngInput(query);
    if (latLngInput != null) {
      _moveMapTo(latLngInput, zoom: math.max(_mapZoom, 17));
      Node? nearest = _usePostgreSQL && _pgHelper != null
          ? await _pgHelper!.findNearestNode(latLngInput)
          : _findNearestNodeLocal(latLngInput);

      if (nearest != null) {
        _selectDestination(nearest);
      }
      return;
    }

    // Try real place-name search first, then map each result to the nearest graph node.
    final placeResults = await _placeSearchHelper.searchPlace(query, limit: 3);
    if (placeResults.isNotEmpty) {
      final suggestions = <NodeSearchSuggestion>[];
      final seenNodeIds = <int>{};

      for (int i = 0; i < placeResults.length; i++) {
        final place = placeResults[i];
        Node? nearest = _usePostgreSQL && _pgHelper != null
            ? await _pgHelper!.findNearestNode(place.location)
            : _findNearestNodeLocal(place.location);

        if (nearest == null) continue;
        if (seenNodeIds.contains(nearest.id)) continue;

        seenNodeIds.add(nearest.id);
        suggestions.add(
          NodeSearchSuggestion(
            node: nearest,
            label: place.displayName,
            score: 100 - i.toDouble(),
          ),
        );
      }

      if (suggestions.isNotEmpty) {
        final etaMap = <int, double?>{};
        final linearMap = <int, double>{};
        for (final suggestion in suggestions.take(8)) {
          etaMap[suggestion.node.id] = _estimateMinutesToNode(suggestion.node);
          linearMap[suggestion.node.id] = _estimateLinearKmToNode(
            suggestion.node,
          );
        }

        setState(() {
          _searchResults = suggestions;
          _etaMinutesByNode = etaMap;
          _linearKmByNode = linearMap;
        });

        _moveMapTo(placeResults.first.location, zoom: math.max(_mapZoom, 17));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '지명 검색 결과 ${suggestions.length}건입니다. 목록에서 선택해 주세요.',
              ),
            ),
          );
        }
        return;
      }
    }

    await _searchDestination(query);

    if (_searchResults.isNotEmpty) {
      _moveMapTo(
        _searchResults.first.node.location,
        zoom: math.max(_mapZoom, 17),
      );
      if (_searchResults.length == 1) {
        _selectDestination(_searchResults.first.node);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색 결과가 없습니다. 다른 키워드로 시도해 주세요.')),
      );
    }
  }

  // 지도 롱프레스 지점을 목적지 후보로 선택한다.
  Future<void> _setDestinationFromLongPress(LatLng pressedLocation) async {
    if (_isNavigating) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('안내 중에는 길게 클릭으로 목적지를 변경할 수 없습니다.')),
        );
      }
      return;
    }

    Node? nearest = _usePostgreSQL && _pgHelper != null
        ? await _pgHelper!.findNearestNode(pressedLocation)
        : _findNearestNodeLocal(pressedLocation);

    if (nearest == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택한 위치 근처에서 노드를 찾지 못했습니다.')),
        );
      }
      return;
    }

    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '길게 누른 위치를 목적지로 설정할까요?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('선택 노드: ${nearest.id}'),
                Text(
                  '좌표: ${pressedLocation.latitude.toStringAsFixed(5)}, '
                  '${pressedLocation.longitude.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('목적지 설정'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    _moveMapTo(pressedLocation, zoom: math.max(_mapZoom, 17));
    _selectDestination(nearest);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('길게 클릭한 지점 기준으로 목적지 노드 ${nearest.id}를 선택했습니다.')),
      );
    }
  }

  // 목적지 선택 후 경로/예상시간을 갱신한다.
  void _selectDestination(Node destination) {
    setState(() {
      _destinationNode = destination;
      _searchResults = [];
      _etaMinutesByNode = {};
      _linearKmByNode = {};
      _searchController.clear();
    });

    _calculatePath();

    if (_totalDistance > 0 && mounted) {
      const assumedKmh = 35.0;
      final minutes = _totalDistance / (assumedKmh * 1000 / 60);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('예상 소요시간: 약 ${minutes.toStringAsFixed(1)}분')),
      );
    }
  }

  // 현재 노드 -> 목적지 노드 최단경로를 계산한다.
  void _calculatePath() {
    if (_currentNode == null || _destinationNode == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('시작점과 목적지를 선택하세요')));
      return;
    }

    final engine = NavEngine(_nodes, _links);
    final pathInfo = engine.getPathInfo(_currentNode!.id, _destinationNode!.id);

    setState(() {
      _currentPath = pathInfo['path'] as List<Node>;
      _totalDistance = pathInfo['distance'] as double;
      _roadSequence = pathInfo['roads'] as String;
      _pathIndex = 0;
      _interpolationProgress = 0.0;
      _offPathHitCount = 0;
    });
    _buildManeuversFromPath();
  }

  // 내비게이션 시작:
  // - UI 상태 전환
  // - 지도 확대
  // - GPS 주행 시작
  void _startNavigation() {
    if (_currentPath.isEmpty) return;
    setState(() {
      _isNavigating = true;
      _currentSpeedKmh = 0;
      _isVehicleMoving = false;
      _stationaryNoiseHitCount = 0;
      _isNavigationMapFollowPaused = false;
    });

    _preNavigationZoom = _mapZoom;
    // zoom +2 는 체감 약 4배 확대다.
    _navigationFollowZoom = (_mapZoom + 2).clamp(3.0, 20.0);
    _mapZoom = _navigationFollowZoom;
    _followLocationOnMap();

    _pathIndex = 0;
    _interpolationProgress = 0.0;
    _updateNextManeuver();

    unawaited(WakelockPlus.enable());
    _startGpsNavigation();
  }

  void _clearRoutePreview() {
    _currentPath = [];
    _totalDistance = 0;
    _roadSequence = '';
    _pathIndex = 0;
    _interpolationProgress = 0.0;
    _maneuvers = [];
    _nextManeuver = null;
  }

  // 내비게이션 종료 및 상태 초기화
  void _stopNavigation() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _navigationMapRestoreTimer?.cancel();
    unawaited(WakelockPlus.disable());
    setState(() {
      _isNavigating = false;
      _currentSpeedKmh = 0;
      _isVehicleMoving = false;
      _stationaryNoiseHitCount = 0;
      _isNavigationMapFollowPaused = false;
      _mapRotation = 0;
      _carHeadingDeg = 0;
      _mapZoom = _preNavigationZoom;
      _offPathHitCount = 0;
      _clearRoutePreview();
    });
    _followLocationOnMap();
  }

  void _toggleNavigation() {
    if (_isNavigating) {
      _stopNavigation();
      return;
    }
    _startNavigation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _networkTimer?.cancel();
    _navigationMapRestoreTimer?.cancel();
    _positionSubscription?.cancel();
    _passivePositionSubscription?.cancel();
    unawaited(WakelockPlus.disable());
    _searchController.dispose();
    _pgHelper?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Local DB Navigation')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_nodes.isEmpty || _links.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Local DB Navigation')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              const Text(
                'DB 데이터를 불러오지 못했습니다.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '앱을 완전히 삭제 후 재설치하거나\n아래 버튼으로 DB를 초기화하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  setState(() => _isLoading = true);
                  await _dbHelper.repairDatabaseIfEmpty();
                  await _loadData();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('DB 초기화 후 재시도'),
              ),
            ],
          ),
        ),
      );
    }

    final renderedPathPoints = _remainingPathPointsFromLocation(
      _currentLocation,
    );
    final routeArrowMarkers = buildRouteArrowMarkers(
      points: renderedPathPoints,
      spacingMeters: _routeArrowSpacingMeters,
      maxMarkers: _maxRouteArrowMarkers,
    );
    final remainingDistanceMeters = _remainingDistanceMetersFromLocation(
      _currentLocation,
    );
    final remainingEtaMinutes = _remainingEtaMinutesFromDistance(
      remainingDistanceMeters,
    );
    final mediaQuery = MediaQuery.of(context);
    final bottomUiLift = mediaQuery.viewPadding.bottom + 12;

    return Scaffold(
      appBar: AppBar(title: const Text('경로 네비게이션'), elevation: 0),
      body: Stack(
        children: [
          // 1) 지도 레이어(타일/경로선/마커)
          // 지도
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: _mapZoom,
              initialRotation: _mapRotation,
              onPositionChanged: (position, hasGesture) {
                final nextZoom = position.zoom ?? _mapZoom;
                if (_isNavigating) {
                  if (hasGesture) {
                    setState(() {
                      _mapZoom = nextZoom;
                    });
                    _scheduleNavigationMapRestore();
                    return;
                  }

                  if (!_isNavigationMapFollowPaused) {
                    _mapZoom = _navigationFollowZoom;
                  }
                  return;
                }

                _mapZoom = nextZoom;
              },
              onLongPress: (_, point) {
                _setDestinationFromLongPress(point);
              },
            ),
            children: [
              if (_hasInternet)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.my_nav_app',
                  panBuffer: 2,
                ),
              if (_useOfflineTilesNow)
                TileLayer(
                  urlTemplate: 'assets/tiles/{z}_{x}_{y}.png',
                  tileProvider: AssetTileProvider(),
                  minNativeZoom: _offlineTileMinZoom ?? 1,
                  maxNativeZoom: _offlineTileMaxZoom ?? 22,
                  panBuffer: 2,
                ),
              // 경로 선 그리기
              PolylineLayer(
                polylines: [
                  if (renderedPathPoints.length >= 2)
                    Polyline(
                      points: renderedPathPoints,
                      color: const Color(0xFF0A5CAD),
                      strokeWidth: 12,
                    ),
                  if (renderedPathPoints.length >= 2)
                    Polyline(
                      points: renderedPathPoints,
                      color: const Color(0xFF25A7FF),
                      strokeWidth: 8,
                    ),
                ],
              ),
              if (routeArrowMarkers.isNotEmpty)
                MarkerLayer(markers: routeArrowMarkers),
              // 마커 (현재 위치, 목적지)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 44,
                    height: 44,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 280),
                      tween: Tween<double>(begin: 0, end: _carHeadingDeg),
                      builder: (context, angleDeg, child) {
                        // 차량 아이콘이 실제 이동 경로의 각도를 바라보도록 heading만 적용.
                        final combinedAngle = angleDeg * math.pi / 180;
                        return Transform.rotate(
                          angle: combinedAngle,
                          child: child,
                        );
                      },
                      child: Image.asset(
                        'assets/images/car_icon.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (_destinationNode != null)
                    Marker(
                      point: _destinationNode!.location,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),
          // 2) 오프라인 타일 누락 경고
          if (!_hasOfflineTileAssets)
            Positioned(
              top: 72,
              left: 10,
              right: 10,
              child: Card(
                color: Colors.orange.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    '오프라인 타일 파일이 없습니다. assets/tiles/{z}_{x}_{y}.png 형식으로 타일을 추가하세요.',
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                  ),
                ),
              ),
            ),
          // 3) 상단 검색 패널(내비 시작 전)
          // 상단 검색 패널 (안내 시작 시 숨김)
          if (!_isNavigating)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Card(
                elevation: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: _submitSearch,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '목적지 검색 (지명/ID/노드명 또는 lat,lng)',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchResults = [];
                                      _etaMinutesByNode = {};
                                      _linearKmByNode = {};
                                    });
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                onPressed: () => _submitSearch(),
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    // 검색 결과 목록
                    if (_searchResults.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final suggestion = _searchResults[index];
                            final node = suggestion.node;
                            final eta = _etaMinutesByNode[node.id];
                            final linearKm = _linearKmByNode[node.id];

                            return ListTile(
                              leading: const Icon(Icons.location_on),
                              title: Text(suggestion.label),
                              subtitle: Text(
                                '노드 ${node.id} • 약 ${eta?.toStringAsFixed(1) ?? '-'}분 • '
                                '직선 ${linearKm?.toStringAsFixed(2) ?? '-'}km • '
                                '${node.location.latitude.toStringAsFixed(4)}, ${node.location.longitude.toStringAsFixed(4)}',
                              ),
                              onTap: () {
                                _moveMapTo(
                                  node.location,
                                  zoom: math.max(_mapZoom, 17),
                                );
                                _selectDestination(node);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // 4) 상단 안내 카드
          // 다음 회전 정보가 없더라도(마지막 구간) 목적지까지 남은 거리를 계속 보여준다.
          if (_isNavigating &&
              (_nextManeuver != null || _destinationNode != null))
            Positioned(
              top: 10,
              right: 10,
              child: ManeuverGuidanceCard(
                nextManeuver: _nextManeuver,
                distanceToManeuverMeters: _distanceToManeuverMeters(),
                remainingDistanceMeters: remainingDistanceMeters,
              ),
            ),

          // 5) 실시간 속도 카드
          // 좌측 하단 속도 표시
          if (_isNavigating)
            Positioned(
              left: 12,
              bottom: 240 + bottomUiLift,
              child: Card(
                color: Colors.black87,
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '속도',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 6) 하단 제어 패널(내비 시작 전)
          if (!_isNavigating)
            Positioned(
              bottom: 10 + bottomUiLift,
              left: 10,
              right: 10,
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_destinationNode != null &&
                          _currentPath.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '출발: 노드 ${_currentNode?.id ?? '-'}  /  목적지: 노드 ${_destinationNode!.id}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (_totalDistance > 0)
                                    Text(
                                      '거리: ${_totalDistance.toStringAsFixed(0)}m',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (_roadSequence.isNotEmpty)
                                    Text(
                                      '경로: $_roadSequence',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLocating
                                ? null
                                : () => _syncCurrentLocationToNearestNode(),
                            icon: Icon(
                              _isLocating
                                  ? Icons.hourglass_top
                                  : Icons.my_location,
                            ),
                            label: Text(_isLocating ? '위치확인중' : '현재위치'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _currentPath.isEmpty
                                ? null
                                : _toggleNavigation,
                            icon: Icon(
                              _isNavigating ? Icons.stop : Icons.play_arrow,
                            ),
                            label: Text(_isNavigating ? '정지' : '시작'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_usePostgreSQL)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PostgreSQL 연결됨',
                            style: TextStyle(fontSize: 11, color: Colors.blue),
                          ),
                        ),
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _hasGpsFix
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _hasGpsFix
                              ? 'GPS 수신 중 (${_currentLocation.latitude.toStringAsFixed(5)}, ${_currentLocation.longitude.toStringAsFixed(5)})'
                              : 'GPS 미수신: 현재 기본 위치 또는 마지막 위치를 사용 중',
                          style: TextStyle(
                            fontSize: 11,
                            color: _hasGpsFix
                                ? Colors.green
                                : Colors.deepOrange,
                          ),
                        ),
                      ),
                      if (_useOfflineTilesNow)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _offlineMapTiles
                                ? '오프라인 지도 타일 사용 중'
                                : '네트워크 미연결: 오프라인 타일로 전환됨',
                            style: TextStyle(fontSize: 11, color: Colors.green),
                          ),
                        ),
                      if (!_hasOfflineTileAssets)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '오프라인 타일 미탑재: 현재 온라인 타일로 표시합니다.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // 7) 내비게이션 중 하단 미니 패널(남은 거리 + 정지)
          if (_isNavigating)
            Positioned(
              bottom: 10 + bottomUiLift,
              left: 10,
              right: 10,
              child: NavigationBottomPanel(
                remainingDistanceMeters: remainingDistanceMeters,
                remainingEtaMinutes: remainingEtaMinutes,
                onStop: _stopNavigation,
              ),
            ),
        ],
      ),
    );
  }
}
