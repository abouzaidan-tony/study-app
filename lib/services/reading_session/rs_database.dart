import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gbt/services/common/abstract_database.dart';
import 'package:gbt/services/reading_session/rs_model.dart';

class ReadingSessionBackupInfo {
  const ReadingSessionBackupInfo({
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

class ReadingSessionDatabase extends AbstractDatabase {
  static const _databaseName = 'reading_session';
  static const _databaseVersion = 3;
  static const _backupFormatVersion = 2;

  @override
  String getDatabaseName() {
    return _databaseName;
  }

  @override
  int getDatabaseVersion() {
    return _databaseVersion;
  }

  @override
  Future<Map<String, Object?>> buildBackupPayload() async {
    return {
      'format_version': _backupFormatVersion,
      'created_at': DateTime.now().toIso8601String(),
      'tables': {
        'reading_plan': await database.query('reading_plan', orderBy: 'id'),
        'reading_plan_book': await database.query(
          'reading_plan_book',
          orderBy: 'id',
        ),
        'rs_daily_log': await database.query('rs_daily_log', orderBy: 'id'),
        'rs_log': await database.query('rs_log', orderBy: 'id'),
        'rs_stats': await database.query('rs_stats', orderBy: 'id'),
        'rs_book_progress': await database.query(
          'rs_book_progress',
          orderBy: 'id',
        ),
      },
    };
  }

  @override
  Future<void> restoreBackupJson(String content) async {
    await init();
    final raw = jsonDecode(content);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup file.');
    }

    final tables = raw['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('Backup is missing table data.');
    }

    final version = raw['format_version'];
    if (version is! int) {
      throw const FormatException('Backup is missing version data.');
    }

    if (version == 1) {
      await restoreBackupJson1(tables);
    } else {
      await restoreBackupJson2(tables);
    }
  }

  Future<void> restoreBackupJson1(Map<String, dynamic> tables) async {
    final dailyLogRows = parseBackupRows(tables['rs_daily_log']);
    final logRows = parseBackupRows(tables['rs_log']);
    final statsRows = parseBackupRows(tables['rs_stats']);
    final bookProgressRows = parseBackupRows(tables['rs_book_progress']);

    final file = 'assets/schemas/reading_session_data.sql';
    final sql = await rootBundle.loadString(file);

    await database.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('rs_log');
      batch.delete('rs_daily_log');
      batch.delete('rs_stats');
      batch.delete('rs_book_progress');
      batch.delete('reading_plan_book');
      batch.delete('reading_plan');

      await executeSqlBatch(batch, sql);

      for (final row in dailyLogRows) {
        row['reading_plan_id'] = 1;
        batch.insert('rs_daily_log', row);
      }
      for (final row in logRows) {
        row['reading_plan_id'] = 1;
        batch.insert('rs_log', row);
      }
      for (final row in statsRows) {
        row['reading_plan_id'] = 1;
        batch.insert('rs_stats', row);
      }
      for (final row in bookProgressRows) {
        row['reading_plan_id'] = 1;
        row['verses_read'] ??= 0;
        batch.insert('rs_book_progress', row);
      }

      await batch.commit(noResult: true);
    });
  }

  Future<void> restoreBackupJson2(Map<String, dynamic> tables) async {
    final readingPlanRows = parseBackupRows(tables['reading_plan']);
    final readingPlanBookRows = parseBackupRows(tables['reading_plan_book']);
    final dailyLogRows = parseBackupRows(tables['rs_daily_log']);
    final logRows = parseBackupRows(tables['rs_log']);
    final statsRows = parseBackupRows(tables['rs_stats']);
    final bookProgressRows = parseBackupRows(tables['rs_book_progress']);

    await database.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('rs_log');
      batch.delete('rs_daily_log');
      batch.delete('rs_stats');
      batch.delete('rs_book_progress');
      batch.delete('reading_plan_book');
      batch.delete('reading_plan');

      for (final row in readingPlanRows) {
        batch.insert('reading_plan', row);
      }
      for (final row in readingPlanBookRows) {
        batch.insert('reading_plan_book', row);
      }
      for (final row in dailyLogRows) {
        batch.insert('rs_daily_log', row);
      }
      for (final row in logRows) {
        batch.insert('rs_log', row);
      }
      for (final row in statsRows) {
        batch.insert('rs_stats', row);
      }
      for (final row in bookProgressRows) {
        row['verses_read'] ??= 0;
        batch.insert('rs_book_progress', row);
      }

      await batch.commit(noResult: true);
    });
  }

  /* READING PLAN */
  Future<List<ReadingPlan>> _getReadingPlans() async {
    final result = await database.query(
      'reading_plan',
      orderBy: "is_bookmarked desc, created_at desc",
    );

    return result.map((e) => ReadingPlan.fromMap(e)).toList();
  }

  Future<void> updateReadingPlan(ReadingPlan readingPlan) async {
    await database.update(
      'reading_plan',
      readingPlan.toMap(),
      where: 'id = ?',
      whereArgs: [readingPlan.id],
    );
  }

  Future<List<ReadingPlanDetails>> getReadingPlans() async {
    List<ReadingPlan> plans = await _getReadingPlans();

    List<ReadingPlanDetails> planDetails = [];
    for (ReadingPlan p in plans) {
      List<ReadingPlanBook> books = await getReadingPlanBooks(p.id!);
      planDetails.add(ReadingPlanDetails(p, books));
    }

    return planDetails;
  }

  Future<List<ReadingPlanBook>> getReadingPlanBooks(int readingPlanId) async {
    final result = await database.query(
      'reading_plan_book',
      where: 'reading_plan_id = ?',
      whereArgs: [readingPlanId],
      orderBy: "ord",
    );

    return result.map((e) => ReadingPlanBook.fromMap(e)).toList();
  }

  Future<ReadingPlan> insertReadingPlan(ReadingPlan plan) async {
    final id = await database.insert(
      'reading_plan',
      plan.toMap()..remove('id'),
    );
    return plan.copyWith(id: id);
  }

  Future<void> insertReadingPlanBooks(List<ReadingPlanBook> books) async {
    for (ReadingPlanBook b in books) {
      await database.insert('reading_plan_book', b.toMap()..remove('id'));
    }
  }

  Future<void> deleteReadingPlanBooks(int readingPlanId) async {
    await database.delete(
      'reading_plan_book',
      where: 'reading_plan_id = ?',
      whereArgs: [readingPlanId],
    );
  }

  void updateReadingPlanBooks(List<ReadingPlanBook> books) async {
    for (ReadingPlanBook b in books) {
      await database.update(
        'reading_plan_book',
        b.toMap(),
        where: 'id = ?',
        whereArgs: [b.id],
      );
    }
  }

  /* RS DAILY LOG */
  Future<RsDailyLog> insertDailyLog(RsDailyLog log) async {
    final id = await database.insert('rs_daily_log', log.toMap()..remove('id'));
    return log.copyWith(id: id);
  }

  Future<int> updateDailyLog(RsDailyLog log) async {
    return await database.update(
      'rs_daily_log',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<int> deleteDailyLog(int id) async {
    return await database.delete(
      'rs_daily_log',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /* RS LOG */
  Future<RsLog> insertLog(RsLog log) async {
    final id = await database.insert('rs_log', log.toMap()..remove('id'));
    return log.copyWith(id: id);
  }

  Future<int> updateLog(RsLog log) async {
    return await database.update(
      'rs_log',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<int> deleteLog(int id) async {
    return await database.delete('rs_log', where: 'id = ?', whereArgs: [id]);
  }

  /* RS STATS */
  Future<RsStats> insertStats(RsStats stats) async {
    final id = await database.insert('rs_stats', stats.toMap()..remove('id'));
    return stats.copyWith(id: id);
  }

  Future<int> updateStats(RsStats stats) async {
    return await database.update(
      'rs_stats',
      stats.toMap(),
      where: 'id = ?',
      whereArgs: [stats.id],
    );
  }

  Future<int> deleteStats(int id) async {
    return await database.delete('rs_stats', where: 'id = ?', whereArgs: [id]);
  }

  Future<RsStats?> findStatsByTypeAndDateForPlan(
    RsStatsType type,
    DateTime date,
    int readingPlanId,
  ) async {
    final result = await database.query(
      'rs_stats',
      where: 'type = ? AND date(stats_date) = date(?) AND reading_plan_id = ?',
      whereArgs: [type.value, date.toIso8601String(), readingPlanId],
    );

    if (result.isEmpty) return null;

    return RsStats.fromMap(result.first);
  }

  /* RS BOOK PROGRESS */
  Future<RsBookProgress> insertBookProgresss(
    RsBookProgress bookProgress,
  ) async {
    final id = await database.insert(
      'rs_book_progress',
      bookProgress.toMap()..remove('id'),
    );
    return bookProgress.copyWith(id: id);
  }

  Future<int> updateBookProgress(RsBookProgress bookProgress) async {
    return await database.update(
      'rs_book_progress',
      bookProgress.toMap(),
      where: 'id = ?',
      whereArgs: [bookProgress.id],
    );
  }

  Future<int> deleteBookProgress(int id) async {
    return await database.delete(
      'rs_book_progress',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<RsBookProgress>> getAllBookProgress(int readingPlanId) async {
    final result = await database.query(
      'rs_book_progress',
      where: 'reading_plan_id = ?',
      whereArgs: [readingPlanId],
      orderBy: "book_id",
    );

    return result.map((e) => RsBookProgress.fromMap(e)).toList();
  }

  Future<int> countVersesReadForChapter(
    int readingPlanId,
    int bookId,
    int chapter,
  ) async {
    final result = await database.rawQuery(
      'SELECT COUNT(distinct verse) AS count FROM rs_log where book_id = ? and chapter = ? and reading_plan_id = ?',
      [bookId, chapter, readingPlanId],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;

    return count;
  }

  Future<Map<int, int>> getVersesReadForChapter(
    int readingPlanId,
    int bookId,
    int chapter,
  ) async {
    final result = await database.rawQuery(
      'SELECT verse, count(*) count FROM rs_log where book_id = ? and chapter = ? and reading_plan_id = ? group by verse',
      [bookId, chapter, readingPlanId],
    );

    if (result.isEmpty) return {};

    Map<int, int> res = {};
    for (final row in result) {
      final verse = row['verse'] as int?;
      final count = row['count'] as int?;

      if (verse == null || count == null) {
        continue;
      }

      res[verse] = count;
    }

    return res;
  }

  Future<List<RsStats>> getRsStatsForType(
    RsStatsType type,
    DateTime startDate,
    DateTime endDate,
    int readingPlanId,
  ) async {
    final result = await database.query(
      'rs_stats',
      where:
          'type = ? AND date(stats_date) between date(?) and date(?) AND reading_plan_id = ?',
      whereArgs: [
        type.value,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
        readingPlanId,
      ],
      orderBy: "stats_date asc",
    );

    return result.map((e) => RsStats.fromMap(e)).toList();
  }

  Future<List<RsDailyLog>> getSessionsForDate(
    DateTime date,
    int readingPlanId,
  ) async {
    final result = await database.query(
      'rs_daily_log',
      where: 'date(rs_date) = date(?) AND reading_plan_id = ?',
      whereArgs: [date.toIso8601String(), readingPlanId],
      orderBy: "start_time",
    );

    return result.map((e) => RsDailyLog.fromMap(e)).toList();
  }

  Future<List<RsLog>> getRsLogForDailyLog(int rsDailyLogId) async {
    final result = await database.query(
      'rs_log',
      where: 'rs_daily_log_id = ?',
      whereArgs: [rsDailyLogId],
      orderBy: "book_id, chapter, verse",
    );

    return result.map((e) => RsLog.fromMap(e)).toList();
  }

  Future<List<RsLog>> getRsLogForDailyLogAndVerse(
    int rsDailyLogId,
    int bookId,
    int chapter,
    int verse,
  ) async {
    final result = await database.query(
      'rs_log',
      where:
          'rs_daily_log_id = ? and book_id = ? and chapter = ? and verse = ?',
      whereArgs: [rsDailyLogId, bookId, chapter, verse],
      orderBy: "book_id, chapter, verse",
    );

    return result.map((e) => RsLog.fromMap(e)).toList();
  }

  Future<int> getVersesReadToday(int readingPlanId, DateTime date) async {
    final result = await database.rawQuery(
      'SELECT SUM(verses) FROM rs_daily_log where date(rs_date) = date(?) and end_time is not null and reading_plan_id = ?',
      [date.toIso8601String(), readingPlanId],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;

    return count;
  }

  Future<int> getTotalSecondsReadToday(int readingPlanId, DateTime date) async {
    final result = await database.rawQuery(
      "SELECT SUM(strftime('%s', end_time) - strftime('%s', start_time)) AS count "
      'FROM rs_daily_log '
      'WHERE date(rs_date) = date(?) AND end_time IS NOT NULL and reading_plan_id = ?',
      [date.toIso8601String(), readingPlanId],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;

    return count;
  }
}
