import 'package:flutter/material.dart';
import 'package:studyapp/app_state.dart';
import 'package:studyapp/common/word.dart';
import 'package:studyapp/services/bible/bible_service.dart';
import 'package:studyapp/services/bookmarks/bookmark_database.dart';
import 'package:studyapp/services/bookmarks/bookmark_model.dart';
import 'package:studyapp/services/download/cancel_token.dart';
import 'package:studyapp/services/gloss/gloss_service.dart';
import 'package:studyapp/services/hebrew_greek/database.dart';
import 'package:studyapp/services/reading_session/rs_manager.dart';
import 'package:studyapp/services/service_locator.dart';
import 'package:studyapp/services/settings/user_settings.dart';

class HighlightDetail {
  Highlight highlight;
  bool isDelete;
  bool isActive;
  bool isChanged;
  bool defaultColor;

  HighlightDetail({
    required this.highlight,
    this.isDelete = false,
    this.isActive = false,
    this.isChanged = false,
    this.defaultColor = true,
  });

  HighlightDetail copyWith({
    Highlight? highlight,
    bool? isDelete,
    bool? isActive,
    bool? isChanged,
    bool? defaultColor,
  }) {
    return HighlightDetail(
      highlight: highlight ?? this.highlight,
      isDelete: isDelete ?? this.isDelete,
      isActive: isActive ?? this.isActive,
      isChanged: isChanged ?? this.isChanged,
      defaultColor: defaultColor ?? this.defaultColor,
    );
  }

  @override
  String toString() {
    return 'HighlightDetail(highlight: $highlight, isDelete: $isDelete, isActive: $isActive, isChanged: $isChanged)';
  }
}

class HebrewGreekChapterManager {
  final _hebrewGreekDb = getIt<HebrewGreekDatabase>();
  final _glossService = getIt<GlossService>();
  final _bibleService = getIt<BibleService>();
  final _settings = getIt<UserSettings>();
  final _rsmanager = getIt<ReadingSessionManager>();
  final _bookmarkDb = getIt<BookmarksDatabase>();

  final textNotifier = _SafeValueNotifier<List<HebrewGreekWord>>([]);
  final verseCheckboxNotifier = VerseCheckboxNotifier();
  final bookmarkedVerses = _SafeValueNotifier<Set<int>>({});
  final highlightedWords = _SafeValueNotifier<List<HighlightDetail>>([]);
  final highlighModeEnabled = ValueNotifier<bool>(false);
  final temporaryHighlightIdx = ValueNotifier<int?>(null);

  int? activeHighlightAnchorWordId;
  bool _disposed = false;
  int _chapterLoadToken = 0;
  int _readVersesLoadToken = 0;

  List<HighlightDetail> _dbHighlightedWords = [];
  List<HighlightDetail> get dbHighlightedWords => _dbHighlightedWords;

  Future<void> loadChapterData(int bookId, int chapter) async {
    final token = ++_chapterLoadToken;
    if (_disposed) return;
    textNotifier.value = [];
    final words = await _hebrewGreekDb.getChapter(bookId, chapter);
    if (_disposed || token != _chapterLoadToken) return;
    textNotifier.value = words;
  }

  Future<void> loadReadVerses(int bookId, int chapter) async {
    final token = ++_readVersesLoadToken;
    if (_disposed) return;
    verseCheckboxNotifier.clear();
    final versesRead = await _rsmanager.getVersesReadForChapter(
      bookId,
      chapter,
    );
    if (_disposed || token != _readVersesLoadToken) return;
    verseCheckboxNotifier.setVersesRead(versesRead);
  }

  Future<void> loadBookmarkedVerses(int bookId, int chapter) async {
    if (_disposed) return;
    final bookmarks = await _bookmarkDb.getBookmarksFor(bookId, chapter);
    Set<int> bookmarkVerses = {};
    for (Bookmark b in bookmarks) {
      bookmarkVerses.add(b.verse);
    }
    if (_disposed) return;
    bookmarkedVerses.value = bookmarkVerses;
  }

  Future<void> loadHighlightedWords(int bookId, int chapter) async {
    if (_disposed) return;
    final highlights = await _bookmarkDb.getHighlightsFor(bookId, chapter);
    List<HighlightDetail> highlightedWordsList = [];
    for (Highlight b in highlights) {
      highlightedWordsList.add(
        HighlightDetail(highlight: b, defaultColor: false),
      );
    }
    if (_disposed) return;
    _dbHighlightedWords = highlightedWordsList;
    highlightedWords.value = highlightedWordsList;
  }

  Future<void> saveHighlights(List<HighlightDetail> highlights) async {
    if (_disposed) return;

    final savedHighlights = <HighlightDetail>[];
    for (final detail in highlights) {
      if (detail.isDelete) {
        final id = detail.highlight.id;
        if (id != null) {
          await _bookmarkDb.deleteHighlight(id);
        }
        continue;
      }

      var highlight = detail.highlight;
      if (highlight.id == null) {
        highlight = await _bookmarkDb.insertHighlight(highlight);
      } else if (detail.isChanged) {
        await _bookmarkDb.updateHighlight(highlight);
      }

      savedHighlights.add(
        detail.copyWith(
          highlight: highlight,
          isChanged: false,
          defaultColor: false,
        ),
      );
    }

    if (_disposed) return;
    _dbHighlightedWords = List<HighlightDetail>.from(savedHighlights);
    highlightedWords.value = savedHighlights;
  }

  Future<void> deleteHighlight(int existingHighlightId) async {
    if (_disposed) return;
    await _bookmarkDb.deleteHighlight(existingHighlightId);
  }

  Future<void> markVerseAsRead(int bookId, int chapter, int verse) async {
    if (_disposed) return;
    await _rsmanager.markVerseAsRead(bookId, chapter, verse);
    if (_disposed) return;
    final versesRead = await _rsmanager.getVersesReadForChapter(
      bookId,
      chapter,
    );
    if (_disposed) return;
    verseCheckboxNotifier.setVersesRead(versesRead, changedVerse: verse);
  }

  Future<void> resetVerseProgress(int bookId, int chapter, int verse) async {
    if (_disposed) return;
    await _rsmanager.resetReadingCountForVerse(bookId, chapter, verse);
    if (_disposed) return;
    final versesRead = await _rsmanager.getVersesReadForChapter(
      bookId,
      chapter,
    );
    if (_disposed) return;
    verseCheckboxNotifier.setVersesRead(versesRead, changedVerse: verse);
  }

  bool isRtl(int bookId) {
    const malachi = 39;
    return bookId <= malachi;
  }

  Future<String?> getPopupTextForId(
    Locale uiLocale,
    int wordId,
    void Function(Locale)? onGlossDownloadNeeded,
  ) async {
    return _glossService.glossForId(
      locale: uiLocale,
      wordId: wordId,
      onDatabaseMissing: onGlossDownloadNeeded,
    );
  }

  // Called from the UI when user agrees to download.
  Future<void> downloadResources(
    Locale locale, {
    required ValueNotifier<double> progressNotifier,
    required CancelToken cancelToken,
  }) async {
    // Reuse the exact same logic as SettingsManager
    // 1. Determine tasks
    final needGloss = !await _glossService.glossesExists(locale);
    final needBible = !await _bibleService.bibleExists(locale);

    int tasksToRun = (needGloss ? 1 : 0) + (needBible ? 1 : 0);
    int tasksCompleted = 0;

    void updateProgress(double fileProgress) {
      if (tasksToRun == 0) {
        progressNotifier.value = 1.0;
        return;
      }
      final overall =
          (tasksCompleted / tasksToRun) + (fileProgress / tasksToRun);
      progressNotifier.value = overall;
    }

    // 2. Glosses
    if (needGloss) {
      if (cancelToken.isCancelled) return;
      await _glossService.downloadGlosses(
        locale,
        cancelToken: cancelToken,
        onProgress: updateProgress,
      );
      tasksCompleted++;
    }

    // 3. Bible
    if (needBible) {
      if (cancelToken.isCancelled) return;
      updateProgress(0.0);
      await _bibleService.downloadBible(
        locale,
        cancelToken: cancelToken,
        onProgress: updateProgress,
      );
      tasksCompleted++;
    }

    progressNotifier.value = 1.0;
  }

  // Called from the UI when user wants to use English instead of downloading.
  Future<void> setLanguageToEnglish(Locale originalLocale) async {
    await _settings.setLocale('en');
    getIt<AppState>().init();
  }

  String getVerseText(int verse) {
    if (_disposed) return '';
    final words = textNotifier.value;
    final verseWords = words
        .where((w) => (w.id ~/ 100) % 1000 == verse)
        .toList();

    if (verseWords.isEmpty) return '';

    final buffer = StringBuffer();
    // Maqaph (Hebrew hyphen) indicates words should be connected without space.
    const maqaph = '־';

    for (int i = 0; i < verseWords.length; i++) {
      final text = verseWords[i].text;
      buffer.write(text);

      // Add space if it's not the last word and doesn't end with a maqaph
      if (i < verseWords.length - 1 && !text.endsWith(maqaph)) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  Future<void> createBookmark(int bookId, int chapter, int verse) async {
    Set<int> bookmarks = Set.of(bookmarkedVerses.value);
    bookmarks.add(verse);

    Bookmark b = Bookmark(
      date: DateTime.now(),
      bookId: bookId,
      chapter: chapter,
      verse: verse,
    );
    await _bookmarkDb.insertBookmark(b);

    bookmarkedVerses.value = bookmarks;
  }

  Future<void> deleteBookmark(int bookId, int chapter, int verse) async {
    Set<int> bookmarks = Set.of(bookmarkedVerses.value);
    bookmarks.remove(verse);

    await _bookmarkDb.deleteBookmarkByReference(bookId, chapter, verse);

    bookmarkedVerses.value = bookmarks;
  }

  Future<String> getText(int fromWordId, int toWordId) async {
    if (_disposed) return '';

    List<HebrewGreekWord> words = await _hebrewGreekDb.wordsForBound(
      fromWordId,
      toWordId,
    );

    if (words.isEmpty) return '';

    final buffer = StringBuffer();
    const maqaph = '־';

    for (int i = 0; i < words.length; i++) {
      final text = words[i].text;
      buffer.write(text);

      if (i < words.length - 1 && !text.endsWith(maqaph)) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  void dispose() {
    _disposed = true;
    _chapterLoadToken++;
    _readVersesLoadToken++;
    textNotifier.dispose();
    verseCheckboxNotifier.dispose();
    bookmarkedVerses.dispose();
    highlightedWords.dispose();
    highlighModeEnabled.dispose();
    temporaryHighlightIdx.dispose();
  }
}

class VerseCheckboxNotifier extends ChangeNotifier {
  Map<int, int> _value = const {};
  int? _changedVerse;
  bool _resetAll = true;
  int _revision = 0;
  bool _disposed = false;

  Map<int, int> get value => _value;
  int? get changedVerse => _changedVerse;
  bool get resetAll => _resetAll;
  int get revision => _revision;

  void setVersesRead(Map<int, int> versesRead, {int? changedVerse}) {
    if (_disposed) return;
    _value = Map<int, int>.unmodifiable(versesRead);
    _changedVerse = changedVerse;
    _resetAll = changedVerse == null;
    _revision++;
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _value = const {};
    _changedVerse = null;
    _resetAll = true;
    _revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _SafeValueNotifier<T> extends ValueNotifier<T> {
  _SafeValueNotifier(super.value);

  bool _disposed = false;

  @override
  set value(T newValue) {
    if (_disposed) return;
    super.value = newValue;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
