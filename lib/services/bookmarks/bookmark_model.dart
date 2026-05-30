class Bookmark {
  final int? id;
  final DateTime date;
  final int bookId;
  final int chapter;
  final int fromVerse;
  final int toVerse;

  Bookmark({
    this.id,
    required this.date,
    required this.bookId,
    required this.chapter,
    required this.fromVerse,
    required this.toVerse,
  });

  static const _undefined = Object();

  Bookmark copyWith({
    Object? id = _undefined,
    DateTime? date,
    int? bookId,
    int? chapter,
    int? fromVerse,
    int? toVerse,
  }) {
    return Bookmark(
      id: id == _undefined ? this.id : id as int?,
      date: date ?? this.date,
      bookId: bookId ?? this.bookId,
      chapter: chapter ?? this.chapter,
      fromVerse: fromVerse ?? this.fromVerse,
      toVerse: toVerse ?? this.toVerse,
    );
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'],
      date: DateTime.parse(map['date']),
      bookId: map['book_id'],
      chapter: map['chapter'],
      fromVerse: map['from_verse'],
      toVerse: map['to_verse'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'book_id': bookId,
      'chapter': chapter,
      'from_verse': fromVerse,
      'to_verse': toVerse,
    };
  }
}
