import 'package:flutter/material.dart';
import 'package:studyapp/common/reference.dart';
import 'package:studyapp/common/word.dart';
import 'package:studyapp/services/bookmarks/bookmark_database.dart';
import 'package:studyapp/services/bookmarks/bookmark_model.dart';
import 'package:studyapp/services/hebrew_greek/database.dart';
import 'package:studyapp/services/service_locator.dart';

class BookmarkInformation {
  Bookmark bookmark;
  String text;

  BookmarkInformation({required this.bookmark, required this.text});
}

class BookmarksPageManager {
  final _bookmarksDb = getIt<BookmarksDatabase>();
  final _hebrewGreekDb = getIt<HebrewGreekDatabase>();

  final booksmarksList = ValueNotifier<List<BookmarkInformation>>([]);

  Future<void> init() async {
    List<Bookmark> bookmarks = await _bookmarksDb.getBookmarks();
    List<BookmarkInformation> result = List.empty(growable: true);

    for (Bookmark b in bookmarks) {
      String text = await getVerseText(b.bookId, b.chapter, b.verse);
      result.add(BookmarkInformation(bookmark: b, text: text));
    }

    booksmarksList.value = result;
  }

  Future<String> getVerseText(int bookId, int chapter, int verse) async {
    final ref = Reference(bookId: bookId, chapter: chapter, verse: verse);
    List<HebrewGreekWord> words = await _hebrewGreekDb.wordsForVerse(ref);

    String result = "";
    for (HebrewGreekWord word in words) {
      result += "${word.text} ";
    }

    return result;
  }
}
