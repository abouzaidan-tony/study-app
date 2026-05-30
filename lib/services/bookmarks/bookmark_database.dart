import 'package:studyapp/services/bookmarks/bookmark_model.dart';
import 'package:studyapp/services/common/abstract_database.dart';

class BookmarksDatabase extends AbstractDatabase {
  static const _databaseName = 'bookmarks';
  static const _databaseVersion = 1;

  @override
  String getDatabaseName() {
    return _databaseName;
  }

  @override
  int getDatabaseVersion() {
    return _databaseVersion;
  }

  @override
  Future<void> restoreBackupJson(String content) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> buildBackupPayload() {
    throw UnimplementedError();
  }

  Future<Bookmark> insertDailyLog(Bookmark bookmark) async {
    final id = await database.insert(
      'bookmark',
      bookmark.toMap()..remove('id'),
    );
    return bookmark.copyWith(id: id);
  }

  Future<int> deleteBookmark(int id) async {
    return await database.delete('bookmark', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bookmark>> getBookmarksFor(int bookId, int chapter) async {
    final result = await database.query(
      'bookmark',
      where: 'book_id = ? and chapter = ?',
      whereArgs: [bookId, chapter],
      orderBy: "from_verse",
    );

    return result.map((e) => Bookmark.fromMap(e)).toList();
  }
}
