import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseBackupInfo {
  const DatabaseBackupInfo({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final DateTime modifiedAt;
  final int sizeBytes;
}

abstract class AbstractDatabase {
  static const _backupDirectoryName = 'backups';

  @protected
  late Database database;
  Future<void>? _initFuture;

  String getDatabaseName();
  int getDatabaseVersion();

  Future<void> init() async {
    if (_initFuture != null) {
      return _initFuture;
    }

    _initFuture = _initDatabase("${getDatabaseName()}.db");
    try {
      await _initFuture;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
    return _initFuture;
  }

  Future<void> resetDatabase() async {
    final path = await getDatabasesPath();
    final dbPath = '$path/${getDatabaseName()}.db';

    await deleteDatabase(dbPath);
  }

  Future<void> _initDatabase(String path) async {
    database = await openDatabase(
      path,
      version: getDatabaseVersion(),
      onCreate: (db, version) async {
        log("Creating reading session database");
        String sql = await rootBundle.loadString(
          'assets/schemas/${getDatabaseName()}.sql',
        );
        await _executeSqlBatch(db, sql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        log(
          "Upgrading ${getDatabaseName()} database from $oldVersion to $newVersion",
        );
        for (int v = oldVersion + 1; v <= newVersion; v++) {
          final file = 'assets/schemas/${getDatabaseName()}_$v.sql';
          final sql = await rootBundle.loadString(file);
          await _executeSqlBatch(db, sql);
        }
      },
    );
  }

  Future<void> _executeSqlBatch(Database db, String sql) async {
    final statements = sql
        .split(RegExp(r';\s*\n'))
        .where((s) => s.trim().isNotEmpty);

    final batch = db.batch();

    for (final statement in statements) {
      batch.execute(statement);
    }

    await batch.commit(noResult: true);
  }

  Future<String> createBackup() async {
    await init();
    final backupDir = await _getBackupDirectory();
    await backupDir.create(recursive: true);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = join(
      backupDir.path,
      '${getDatabaseName()}_$timestamp.json',
    );

    return writeBackupToPath(backupPath);
  }

  Future<String> writeBackupToPath(String backupPath) async {
    await init();
    final file = File(backupPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await buildBackupBytes(), flush: true);
    return file.path;
  }

  Future<Uint8List> buildBackupBytes() async {
    await init();
    final payload = await buildBackupPayload();
    final encoded = utf8.encode(jsonEncode(payload));
    return Uint8List.fromList(encoded);
  }

  Future<Map<String, Object?>> buildBackupPayload();

  Future<List<DatabaseBackupInfo>> listBackups() async {
    await init();
    final backupDir = await _getBackupDirectory();
    if (!await backupDir.exists()) {
      return [];
    }

    final files = await backupDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final backups = <DatabaseBackupInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      backups.add(
        DatabaseBackupInfo(
          path: file.path,
          name: basename(file.path),
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }

    backups.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return backups;
  }

  Future<void> restoreBackup(String backupPath) async {
    await init();
    final file = File(backupPath);
    await restoreBackupJson(await file.readAsString());
  }

  Future<void> restoreBackupBytes(Uint8List bytes) async {
    await init();
    await restoreBackupJson(utf8.decode(bytes));
  }

  Future<void> restoreBackupJson(String content);

  @protected
  List<Map<String, Object?>> parseBackupRows(Object? rows) {
    if (rows is! List) {
      throw const FormatException('Backup table payload is invalid.');
    }

    return rows.map((row) {
      if (row is! Map) {
        throw const FormatException('Backup row payload is invalid.');
      }
      return Map<String, Object?>.from(row);
    }).toList();
  }

  Future<Directory> _getBackupDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    return Directory(join(docDir.path, _backupDirectoryName));
  }

  void dispose() {
    database.close();
  }
}
