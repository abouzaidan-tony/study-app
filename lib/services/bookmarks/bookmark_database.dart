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

  Future<Bookmark> insertBookmark(Bookmark bookmark) async {
    final id = await database.insert(
      'bookmark',
      bookmark.toMap()..remove('id'),
    );
    return bookmark.copyWith(id: id);
  }

  Future<int> deleteBookmark(int id) async {
    return await database.delete('bookmark', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteBookmarkByReference(
    int bookId,
    int chapter,
    int verse,
  ) async {
    return await database.delete(
      'bookmark',
      where: 'book_id = ? and chapter = ? and verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
  }

  Future<List<Bookmark>> getBookmarksFor(int bookId, int chapter) async {
    final result = await database.query(
      'bookmark',
      where: 'book_id = ? and chapter = ?',
      whereArgs: [bookId, chapter],
      orderBy: "verse",
    );

    return result.map((e) => Bookmark.fromMap(e)).toList();
  }

  Future<List<Bookmark>> getBookmarks() async {
    final result = await database.query('bookmark', orderBy: "date desc");

    return result.map((e) => Bookmark.fromMap(e)).toList();
  }

  Future<Highlight> insertHighlight(Highlight highlight) async {
    final id = await database.insert(
      'highlight',
      highlight.toMap()..remove('id'),
    );
    return highlight.copyWith(id: id);
  }

  Future<int> deleteHighlight(int id) async {
    return await database.delete('highlight', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Highlight>> getHighlightsFor(int bookId, int chapter) async {
    final result = await database.query(
      'highlight',
      where: 'book_id = ? and chapter = ?',
      whereArgs: [bookId, chapter],
      orderBy: "from_word",
    );

    return result.map((e) => Highlight.fromMap(e)).toList();
  }

  Future<List<Highlight>> getHighlights() async {
    final result = await database.query('highlights', orderBy: "date desc");

    return result.map((e) => Highlight.fromMap(e)).toList();
  }
}
