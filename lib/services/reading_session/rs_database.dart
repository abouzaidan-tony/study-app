import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:studyapp/services/common/abstract_database.dart';
import 'package:studyapp/services/reading_session/rs_model.dart';

class ReadingSessionDatabase extends AbstractDatabase {
  static const _databaseName = 'reading_session';
  static const _databaseVersion = 2;
  static const _backupFormatVersion = 1;

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

    final dailyLogRows = parseBackupRows(tables['rs_daily_log']);
    final logRows = parseBackupRows(tables['rs_log']);
    final statsRows = parseBackupRows(tables['rs_stats']);
    final bookProgressRows = parseBackupRows(tables['rs_book_progress']);

    await database.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('rs_log');
      batch.delete('rs_stats');
      batch.delete('rs_book_progress');
      batch.delete('rs_daily_log');

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
        batch.insert('rs_book_progress', row);
      }

      await batch.commit(noResult: true);
    });
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

  Future<RsStats?> findStatsByTypeAndDate(
    RsStatsType type,
    DateTime date,
  ) async {
    final result = await database.query(
      'rs_stats',
      where: 'type = ? AND date(stats_date) = date(?)',
      whereArgs: [type.value, date.toIso8601String()],
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

  Future<List<RsBookProgress>> getAllBookProgress() async {
    final result = await database.query('rs_book_progress', orderBy: "book_id");

    return result.map((e) => RsBookProgress.fromMap(e)).toList();
  }

  Future<int> countVersesReadForChapter(int bookId, int chapter) async {
    final result = await database.rawQuery(
      'SELECT COUNT(distinct verse) AS count FROM rs_log where book_id = ? and chapter = ?',
      [bookId, chapter],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;

    return count;
  }

  Future<Map<int, int>> getVersesReadForChapter(int bookId, int chapter) async {
    final result = await database.rawQuery(
      'SELECT verse, count(*) count FROM rs_log where book_id = ? and chapter = ? group by verse',
      [bookId, chapter],
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
  ) async {
    final result = await database.query(
      'rs_stats',
      where: 'type = ? AND date(stats_date) between date(?) and date(?)',
      whereArgs: [
        type.value,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
    );

    return result.map((e) => RsStats.fromMap(e)).toList();
  }

  Future<List<RsDailyLog>> getSessionsForDate(DateTime date) async {
    final result = await database.query(
      'rs_daily_log',
      where: 'date(rs_date) = date(?)',
      whereArgs: [date.toIso8601String()],
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

  Future<int> getVersesReadToday(DateTime date) async {
    final result = await database.rawQuery(
      'SELECT SUM(verses) FROM rs_daily_log where date(rs_date) = date(?) and end_time is not null',
      [date.toIso8601String()],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;

    return count;
  }

  Future<int> getTotalSecondsReadToday(DateTime date) async {
    final result = await database.rawQuery(
      "SELECT SUM(strftime('%s', end_time) - strftime('%s', start_time)) AS count "
      'FROM rs_daily_log '
      'WHERE date(rs_date) = date(?) AND end_time IS NOT NULL',
      [date.toIso8601String()],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;

    return count;
  }
}
