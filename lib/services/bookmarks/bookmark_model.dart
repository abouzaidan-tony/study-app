class Bookmark {
  final int? id;
  final DateTime date;
  final int bookId;
  final int chapter;
  final int verse;

  Bookmark({
    this.id,
    required this.date,
    required this.bookId,
    required this.chapter,
    required this.verse,
  });

  static const _undefined = Object();

  Bookmark copyWith({
    Object? id = _undefined,
    DateTime? date,
    int? bookId,
    int? chapter,
    int? verse,
  }) {
    return Bookmark(
      id: id == _undefined ? this.id : id as int?,
      date: date ?? this.date,
      bookId: bookId ?? this.bookId,
      chapter: chapter ?? this.chapter,
      verse: verse ?? this.verse,
    );
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'],
      date: DateTime.parse(map['date']),
      bookId: map['book_id'],
      chapter: map['chapter'],
      verse: map['verse'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'book_id': bookId,
      'chapter': chapter,
      'verse': verse,
    };
  }
}

class Highlight {
  final int? id;
  final DateTime date;
  final int bookId;
  final int chapter;
  final int fromWord;
  final int toWord;

  Highlight({
    this.id,
    required this.date,
    required this.bookId,
    required this.chapter,
    required this.fromWord,
    required this.toWord,
  });

  static const _undefined = Object();

  Highlight copyWith({
    Object? id = _undefined,
    DateTime? date,
    int? bookId,
    int? chapter,
    int? fromWord,
    int? toWord,
  }) {
    return Highlight(
      id: id == _undefined ? this.id : id as int?,
      date: date ?? this.date,
      bookId: bookId ?? this.bookId,
      chapter: chapter ?? this.chapter,
      fromWord: fromWord ?? this.fromWord,
      toWord: toWord ?? this.toWord,
    );
  }

  factory Highlight.fromMap(Map<String, dynamic> map) {
    return Highlight(
      id: map['id'],
      date: DateTime.parse(map['date']),
      bookId: map['book_id'],
      chapter: map['chapter'],
      fromWord: map['from_word'],
      toWord: map['to_word'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'book_id': bookId,
      'chapter': chapter,
      'from_word': fromWord,
      'to_word': toWord,
    };
  }
}
