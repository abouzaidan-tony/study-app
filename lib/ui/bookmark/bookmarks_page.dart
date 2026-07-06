import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:scripture/scripture.dart';
import 'package:studyapp/common/book_name.dart';
import 'package:studyapp/services/bookmarks/bookmark_model.dart';
import 'package:studyapp/ui/bookmark/bookmarks_page_manager.dart';
import 'package:studyapp/ui/home/home_manager.dart';

class BookmarksManagerPage extends StatefulWidget {
  BookmarksManagerPage({super.key, required this.homeManager});

  final HomeManager homeManager;
  final manager = BookmarksPageManager();

  @override
  State<BookmarksManagerPage> createState() => _BookmarksManagerPageState();
}

class _BookmarksManagerPageState extends State<BookmarksManagerPage> {
  @override
  void initState() {
    super.initState();
    widget.manager.init();
  }

  @override
  Widget build(BuildContext context) {
    //final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text("Bookmarks")),
      body: ValueListenableBuilder(
        valueListenable: widget.manager.booksmarksList,
        builder: (context, list, _) {
          return ListView(
            children: [
              ...list.map(
                (bi) => Card(
                  child: ListTile(
                    title: Text(formatBookmarkTitle(bi.bookmark)),
                    subtitle: Column(
                      children: [
                        Text(
                          bi.text,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'sbl',
                            fontSize: 22,
                          ),
                        ),

                        SizedBox.fromSize(size: Size.fromHeight(8)),

                        buildUsfm(bi.lines),
                      ],
                    ),

                    onTap: () {
                      widget.homeManager.onBookSelected(
                        context,
                        bi.bookmark.bookId,
                      );

                      widget.homeManager.onChapterSelected(bi.bookmark.chapter);

                      widget.homeManager.syncController.jumpToVerse(
                        bi.bookmark.bookId,
                        bi.bookmark.chapter,
                        bi.bookmark.verse,
                      );

                      Navigator.of(context).maybePop();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String formatBookmarkTitle(Bookmark bookmark) {
    final book = bookNameForId(context, bookmark.bookId);
    return "$book ${bookmark.chapter}:${bookmark.verse}";
  }

  Widget buildUsfm(List<UsfmLine> verseLines) {
    return IgnorePointer(
      child: UsfmWidget(
        verseLines: verseLines,
        selectionController: ScriptureSelectionController(),
        showHeadings: false,
        showVerseNumbers: false,
        footnoteMarkerStyle: null,
        styleBuilder: (format) {
          final baseStyle = UsfmParagraphStyle.usfmDefaults(
            format: format,
            baseStyle: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(fontSize: 20),
          );
          return baseStyle.copyWith(
            verseNumberStyle: baseStyle.textStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        },
      ),
    );
  }
}
