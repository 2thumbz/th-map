import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:latlong2/latlong.dart';

import 'core/app_log.dart';

class Node {
  final int id;
  final LatLng location;
  final String? name;

  Node(this.id, this.location, {this.name});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (name != null) 'name': name,
      'latitude': location.latitude,
      'longitude': location.longitude,
    };
  }

  factory Node.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'] ?? map['ID'] ?? map['node_id'] ?? map['NODE_ID'];
    final rawLat =
        map['latitude'] ??
        map['LATITUDE'] ??
        map['node_lat'] ??
        map['NODE_LAT'];
    final rawLng =
        map['longitude'] ??
        map['LONGITUDE'] ??
        map['node_lng'] ??
        map['NODE_LNG'];
    final rawName =
        map['name'] ?? map['NAME'] ?? map['node_name'] ?? map['NODE_NAME'];

    final parsedName = rawName?.toString().trim();

    return Node(
      int.parse(rawId.toString()),
      LatLng((rawLat as num).toDouble(), (rawLng as num).toDouble()),
      name: parsedName == null || parsedName.isEmpty ? null : parsedName,
    );
  }
}

class Link {
  final int id;
  final int startNode;
  final int endNode;
  final double weight;
  final String roadName;

  Link(this.id, this.startNode, this.endNode, this.weight, this.roadName);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_node': startNode,
      'end_node': endNode,
      'weight': weight,
      'road_name': roadName,
    };
  }

  factory Link.fromMap(Map<String, dynamic> map) {
    return Link(
      map['id'],
      map['start_node'],
      map['end_node'],
      map['weight'].toDouble(),
      map['road_name'],
    );
  }
}

class DatabaseHelper {
  static const String _nodeName = 'nodes';
  static const String _linkName = 'links';
  static const String _bundledDatabaseAsset = 'assets/db/nav_database.db';
  static Database? _database;

  // 번들 DB의 논리적 버전. export 스크립트의 PRAGMA user_version 과 맞춰야 한다.
  static const int _bundledDataVersion = 2;
  // 유효 데이터로 간주할 최소 노드 수 (4개 더미 노드는 스킵)
  static const int _minRequiredNodes = 100;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'nav_database.db');

    await _copyBundledDatabaseIfNeeded(path);

    // version 파라미터를 지정하지 않으면 sqflite가 user_version=0 인 번들 DB에 대해
    // onCreate를 호출하지 않으므로 "table already exists" 오류를 피할 수 있다.
    // 테이블/인덱스가 없을 경우에만 _ensureSchema 로 생성한다.
    try {
      final db = await openDatabase(path);
      await _ensureSchema(db);
      return db;
    } catch (e) {
      appLog('DB 열기 실패, 재생성: $e');
      await deleteDatabase(path);
      final db = await openDatabase(path);
      await _ensureSchema(db);
      await _insertDefaultData(db);
      return db;
    }
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_nodeName (
        id INTEGER PRIMARY KEY,
        name TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL
      )
    ''');
    try {
      await db.execute('ALTER TABLE $_nodeName ADD COLUMN name TEXT');
    } catch (_) {
      // 이미 name 컬럼이 있으면 무시한다.
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_linkName (
        id INTEGER PRIMARY KEY,
        start_node INTEGER NOT NULL,
        end_node INTEGER NOT NULL,
        weight REAL NOT NULL,
        road_name TEXT NOT NULL,
        FOREIGN KEY(start_node) REFERENCES $_nodeName(id),
        FOREIGN KEY(end_node) REFERENCES $_nodeName(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_nodes_name ON $_nodeName(name)',
    );
  }

  Future<void> _copyBundledDatabaseIfNeeded(String dbFilePath) async {
    final file = File(dbFilePath);

    bool needsCopy = !await file.exists();

    if (!needsCopy) {
      // 파일이 있어도 user_version이 낮거나 노드가 _minRequiredNodes 미만이면 재복사
      try {
        final existing = await openDatabase(dbFilePath);
        final localVersion = await existing.getVersion();
        final nodeCount =
            Sqflite.firstIntValue(
              await existing.rawQuery('SELECT COUNT(*) FROM nodes'),
            ) ??
            0;
        await existing.close();
        if (localVersion < _bundledDataVersion ||
            nodeCount < _minRequiredNodes) {
          needsCopy = true;
          appLog('로컬 DB 구버전/데이터부족(v$localVersion, $nodeCount개), 번들로 교체');
        }
      } catch (_) {
        needsCopy = true;
      }
    }

    if (!needsCopy) return;

    try {
      final byteData = await rootBundle.load(_bundledDatabaseAsset);
      await file.parent.create(recursive: true);

      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      await file.writeAsBytes(bytes, flush: true);
      appLog('번들 SQLite DB 복사 완료: $_bundledDatabaseAsset');
    } catch (e) {
      // 에셋 DB가 없는 경우 기존 onCreate 경로로 자동 fallback 된다.
      appLog('번들 SQLite DB 미사용(기본 DB 생성): $e');
    }
  }

  Future<bool> _hasRequiredData(Database db) async {
    try {
      final nodeCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_nodeName'),
          ) ??
          0;
      final linkCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_linkName'),
          ) ??
          0;
      return nodeCount >= _minRequiredNodes && linkCount > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> repairDatabaseIfEmpty() async {
    final db = await database;
    if (await _hasRequiredData(db)) {
      return;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'nav_database.db');

    try {
      await db.close();
    } catch (_) {
      // ignore close error and continue recovery
    }

    _database = null;
    await deleteDatabase(path);
    _database = await _initDatabase();

    final repaired = await _hasRequiredData(await database);
    if (!repaired) {
      await resetDatabase();
    }
  }

  Future<void> _insertDefaultData(Database db) async {
    final defaultNodes = [
      Node(1, const LatLng(37.4017, 126.9767)), // 인덕원
      Node(2, const LatLng(37.4050, 126.9800)),
      Node(3, const LatLng(37.4100, 126.9850)),
      Node(4, const LatLng(37.4150, 126.9900)), // 목적지
    ];

    final defaultLinks = [
      Link(101, 1, 2, 500, "인덕원로"),
      Link(102, 2, 3, 600, "관악대로"),
      Link(103, 3, 4, 700, "중앙로"),
    ];

    for (var node in defaultNodes) {
      await db.insert(
        _nodeName,
        node.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (var link in defaultLinks) {
      await db.insert(
        _linkName,
        link.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // 모든 노드 조회
  Future<Map<int, Node>> getAllNodes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_nodeName);
    return {for (var item in maps) item['id']: Node.fromMap(item)};
  }

  // 모든 링크 조회
  Future<List<Link>> getAllLinks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_linkName);
    return [for (var item in maps) Link.fromMap(item)];
  }

  // 노드 추가
  Future<int> insertNode(Node node) async {
    final db = await database;
    return db.insert(
      _nodeName,
      node.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 링크 추가
  Future<int> insertLink(Link link) async {
    final db = await database;
    return db.insert(
      _linkName,
      link.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 노드 삭제
  Future<int> deleteNode(int id) async {
    final db = await database;
    return db.delete(_nodeName, where: 'id = ?', whereArgs: [id]);
  }

  // 링크 삭제
  Future<int> deleteLink(int id) async {
    final db = await database;
    return db.delete(_linkName, where: 'id = ?', whereArgs: [id]);
  }

  // DB 초기화 (모든 데이터 삭제 후 재생성)
  Future<void> resetDatabase() async {
    final db = await database;
    await db.delete(_linkName);
    await db.delete(_nodeName);
    await _insertDefaultData(db);
  }
}
