import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studyapp/common/book_name.dart';
import 'package:studyapp/common/word.dart';
import 'package:studyapp/services/bookmarks/bookmark_model.dart';
import 'package:studyapp/services/reading_session/rs_manager.dart';
import 'package:studyapp/theme.dart' show darkPickerColors, lightPickerColors;
import 'package:studyapp/ui/common/resource_ui_helper.dart';
import 'package:studyapp/services/settings/user_settings.dart';
import 'package:studyapp/ui/home/panel_area/common/infinite_scroll_view.dart';
import 'package:studyapp/ui/home/common/scroll_sync_controller.dart';
import 'package:studyapp/ui/home/panel_area/hebrew_greek_panel/chapter_manager.dart';
import 'package:studyapp/ui/home/panel_area/hebrew_greek_panel/text.dart';
import 'package:studyapp/ui/home/verse_selection_dialog/verse_selection_dialog.dart';
import 'package:studyapp/ui/home/word_details_dialog/word_details_dialog.dart';

class VerseNumberTapNotification extends Notification {
  final int bookId;
  final int chapter;
  final int verse;

  const VerseNumberTapNotification({
    required this.bookId,
    required this.chapter,
    required this.verse,
  });
}

/// Manages fetching data and alerts for a single chapter.
class HebrewGreekChapter extends StatefulWidget {
  const HebrewGreekChapter({
    super.key,
    required this.bookId,
    required this.chapter,
    required this.fontSize,
    required this.verseLayout,
    required this.readingModeEnabled,
    this.syncController,
    this.onReadingCheckboxGuideRectChanged,
    this.onReadingCheckboxGuideCompleted,
  });

  final int bookId;
  final int chapter;
  final double fontSize;
  final VerseLayout verseLayout;
  final bool readingModeEnabled;
  final ScrollSyncController? syncController;
  final ValueChanged<Rect?>? onReadingCheckboxGuideRectChanged;
  final VoidCallback? onReadingCheckboxGuideCompleted;

  @override
  State<HebrewGreekChapter> createState() => HebrewGreekChapterState();
}

class HebrewGreekChapterState extends State<HebrewGreekChapter>
    with VerseScrollable {
  final manager = HebrewGreekChapterManager();

  final _textController = HebrewGreekTextController();

  // GlobalKey to track the HebrewGreekText widget's position relative to the HebrewGreekChapter
  final _hebrewGreekTextKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    manager.loadChapterData(widget.bookId, widget.chapter);

    if (widget.readingModeEnabled) {
      manager.loadReadVerses(widget.bookId, widget.chapter);
    }

    manager.loadBookmarkedVerses(widget.bookId, widget.chapter);
    manager.loadHighlightedWords(widget.bookId, widget.chapter);

    _textController.setSpotlightUpdatedCalllback(
      _reportReadingCheckboxGuideRect,
    );
  }

  @override
  void didUpdateWidget(covariant HebrewGreekChapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If Flutter reuses this widget for a new chapter, fetch the new chapter's data.
    if (widget.bookId != oldWidget.bookId ||
        widget.chapter != oldWidget.chapter) {
      manager.loadChapterData(widget.bookId, widget.chapter);

      if (widget.readingModeEnabled) {
        manager.loadReadVerses(widget.bookId, widget.chapter);
      }

      manager.loadBookmarkedVerses(widget.bookId, widget.chapter);
      manager.loadHighlightedWords(widget.bookId, widget.chapter);
    } else if (widget.readingModeEnabled && !oldWidget.readingModeEnabled) {
      manager.loadReadVerses(widget.bookId, widget.chapter);
    }
  }

  @override
  void dispose() {
    manager.dispose();
    super.dispose();
  }

  @override
  double? getOffsetForVerse(int verseNumber) {
    // If Verse 1 is requested, return 0.0 to show the Chapter Header (Title).
    if (verseNumber == 1) {
      return 0.0;
    }

    final textLocalRect = _textController.getVerseRect(verseNumber);
    if (textLocalRect == null) return null;

    // Calculate the offset relative to the Chapter widget (context)
    // We need to add the height of the Header (Text + SizedBoxes)
    final textRenderBox =
        _hebrewGreekTextKey.currentContext?.findRenderObject() as RenderBox?;
    final chapterRenderBox = context.findRenderObject() as RenderBox?;

    if (textRenderBox != null && chapterRenderBox != null) {
      // Find where the Text widget starts inside the Chapter widget
      final textTopLeftInChapter = textRenderBox.localToGlobal(
        Offset.zero,
        ancestor: chapterRenderBox,
      );

      // Add that starting Y to the verse's local Y
      return textTopLeftInChapter.dy + textLocalRect.top;
    }

    // Fallback (if layout isn't ready, though it usually is when calling this)
    return textLocalRect.top;
  }

  @override
  int? getVerseForOffset(double yOffset) {
    // Convert the Chapter Y offset back to Text widget local Y
    final textRenderBox =
        _hebrewGreekTextKey.currentContext?.findRenderObject() as RenderBox?;
    final chapterRenderBox = context.findRenderObject() as RenderBox?;

    if (textRenderBox != null && chapterRenderBox != null) {
      final textTopLeftInChapter = textRenderBox.localToGlobal(
        Offset.zero,
        ancestor: chapterRenderBox,
      );

      // Subtract the header height to get "y" relative to the Text widget
      final localY = yOffset - textTopLeftInChapter.dy;

      return _textController.getVerseForOffset(localY);
    }

    return _textController.getVerseForOffset(yOffset);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        manager.verseCheckboxNotifier,
        manager.bookmarkedVerses,
        manager.highlightedWords,
        manager.highlighModeEnabled,
        manager.temporaryHighlightIdx,
      ]),
      builder: (context, child) {
        final checkedVerses = manager.verseCheckboxNotifier.value;
        final changedVerse = manager.verseCheckboxNotifier.changedVerse;
        final resetCheckedVerses = manager.verseCheckboxNotifier.resetAll;
        final checkedVersesRevision = manager.verseCheckboxNotifier.revision;
        final bookmarkedVerses = manager.bookmarkedVerses.value;
        final highlightedWords = manager.highlightedWords.value;

        return ValueListenableBuilder<List<HebrewGreekWord>>(
          valueListenable: manager.textNotifier,
          builder: (context, words, child) {
            if (words.isEmpty) return const SizedBox();

            return ValueListenableBuilder<VerseHighlight?>(
              valueListenable:
                  widget.syncController?.highlightNotifier ??
                  ValueNotifier(null),
              builder: (context, highlightInfo, _) {
                int? verseToHighlight;
                if (highlightInfo != null &&
                    highlightInfo.bookId == widget.bookId &&
                    highlightInfo.chapter == widget.chapter) {
                  verseToHighlight = highlightInfo.verse;
                }

                //always show first verse only (basic logic)
                final spotlightVerse =
                    widget.onReadingCheckboxGuideRectChanged != null ? 1 : null;

                return Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        '${bookNameForId(context, widget.bookId)} ${widget.chapter}',
                        style: TextStyle(fontSize: 30),
                      ),
                      const SizedBox(height: 10),
                      HebrewGreekText(
                        key: _hebrewGreekTextKey,
                        words: words,
                        verseLayout: widget.verseLayout,
                        readingModeEnabled: widget.readingModeEnabled,
                        checkedVerses: checkedVerses,
                        changedCheckedVerse: changedVerse,
                        resetCheckedVerses: resetCheckedVerses,
                        checkedVersesRevision: checkedVersesRevision,
                        spotlightVerse: spotlightVerse,
                        bookmarkedVerses: bookmarkedVerses,
                        highlightedWords: highlightedWords,
                        highlightModeEnabled: manager.highlighModeEnabled.value,
                        highlightSelectionAnchorWordId:
                            manager.activeHighlightAnchorWordId,
                        onHighlightSelectionStarted:
                            _onHighlightSelectionStarted,
                        onHighlightSelectionChanged:
                            _onHighlightSelectionChanged,
                        onHighlightSelectionCompleted:
                            _onHighlightSelectionCompleted,
                        onHighlightSelectionCanceled:
                            _onHighlightSelectionCanceled,
                        onHighlightColorSelected: _onHighightColorSelected,
                        onHighlightSelectionCopy: _onHighightCopy,
                        highlightPickerColors:
                            Theme.of(context).brightness == Brightness.dark
                            ? darkPickerColors
                            : lightPickerColors,
                        controller: _textController,
                        textDirection: manager.isRtl(widget.bookId)
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        textStyle: TextStyle(fontSize: widget.fontSize),
                        verseNumberStyle: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: widget.fontSize * 0.7,
                        ),
                        onVerseNumberTap: (verse) {
                          VerseNumberTapNotification(
                            bookId: widget.bookId,
                            chapter: widget.chapter,
                            verse: verse,
                          ).dispatch(context);
                        },
                        onVerseCheckboxTap: (verse) async {
                          if (widget.onReadingCheckboxGuideCompleted != null) {
                            widget.onReadingCheckboxGuideCompleted!.call();
                            return;
                          }

                          int count = checkedVerses[verse] ?? 0;
                          if (count < ReadingSessionManager.maximumReadCount) {
                            await manager.markVerseAsRead(
                              widget.bookId,
                              widget.chapter,
                              verse,
                            );
                          } else {
                            await manager.resetVerseProgress(
                              widget.bookId,
                              widget.chapter,
                              verse,
                            );
                          }
                        },
                        onVerseNumberLongPress: (verse) {
                          final isBookmarked = bookmarkedVerses.contains(verse);
                          _showVerseSelectionDialog(verse, isBookmarked);
                        },
                        popupBackgroundColor: Theme.of(
                          context,
                        ).colorScheme.inverseSurface,
                        popupTextStyle: TextStyle(
                          fontFamily: 'sbl',
                          fontSize: widget.fontSize * 0.7,
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                        popupWordProvider: (wordId) {
                          final locale = Localizations.localeOf(context);
                          return manager.getPopupTextForId(
                            locale,
                            wordId,
                            (locale) => _handleMissingResources(locale),
                          );
                        },
                        onPopupShown: _ensurePopupIsVisible,
                        onWordLongPress: _showWordDetails,
                        highlightedVerse: verseToHighlight,
                        highlightColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.25),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _ensurePopupIsVisible(Rect globalPopupRect) {
    // 1. Calculate the safe area top (Status Bar + App Bar + small padding)
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double safeTopPadding = statusBarHeight + kToolbarHeight + 16.0;

    final topY = globalPopupRect.top;

    // 2. If the top of the popup is underneath the App Bar
    if (topY < safeTopPadding) {
      final double scrollAdjustment = safeTopPadding - topY;
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) {
        return;
      }
      final position = scrollable.position;

      // Push the screen DOWN by decreasing the offset
      final targetOffset = position.pixels - scrollAdjustment;
      final clampedOffset = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if (position.pixels != clampedOffset) {
        position.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _reportReadingCheckboxGuideRect(Rect? localRect) {
    if (!mounted ||
        !widget.readingModeEnabled ||
        localRect == null ||
        widget.onReadingCheckboxGuideRectChanged == null) {
      return;
    }

    final textRenderBox =
        _hebrewGreekTextKey.currentContext?.findRenderObject() as RenderBox?;

    if (textRenderBox == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final globalTopLeft = textRenderBox.localToGlobal(localRect.topLeft);
      widget.onReadingCheckboxGuideRectChanged?.call(
        globalTopLeft & localRect.size,
      );
    });
  }

  Future<void> _handleMissingResources(Locale locale) async {
    // Use the shared helper logic
    final success = await ResourceUIHelper.ensureResources(context, locale);

    if (!success && mounted) {
      // If they clicked "Cancel" or download failed,
      // tell the manager to stop trying to load localized glosses
      // for this session so they aren't prompted on every single tap.
      manager.setLanguageToEnglish(locale);
    } else if (success && mounted) {
      // Refresh the UI so the words show the newly downloaded glosses
      setState(() {});
    }
  }

  Future<void> _showWordDetails(int wordId) async {
    int? existingHighlightIdx;

    for (int i = 0; i < manager.highlightedWords.value.length; i++) {
      Highlight h = manager.highlightedWords.value[i].highlight;
      if (wordId >= h.fromWord && wordId <= h.toWord) {
        existingHighlightIdx = i;
        break;
      }
    }

    await showDialog(
      context: context,
      builder: (context) => WordDetailsDialog(
        wordId: wordId,
        isRtl: manager.isRtl(widget.bookId),
        onHighlightClick: _onHighlightClick,
        existingHighlightIdx: existingHighlightIdx,
      ),
    );
  }

  Future<void> _showVerseSelectionDialog(int verse, bool isBookmarked) async {
    final text = manager.getVerseText(verse);
    if (text.isEmpty) return;

    await showDialog(
      context: context,
      builder: (context) => VerseSelectionDialog(
        bookId: widget.bookId,
        chapter: widget.chapter,
        verse: verse,
        text: text,
        onBookmarkCreated: !isBookmarked ? _createBookmark : null,
        onBookmarkRemoved: isBookmarked ? _deleteBookmark : null,
      ),
    );
  }

  void _createBookmark(int verse) {
    manager.createBookmark(widget.bookId, widget.chapter, verse);
  }

  void _deleteBookmark(int verse) {
    manager.deleteBookmark(widget.bookId, widget.chapter, verse);
  }

  void _onHighlightSelectionStarted(int fromWordId, int toWordId) async {
    final highlights = _setActiveHighlightRange(
      fromWordId,
      toWordId,
      createIfMissing: true,
    );

    manager.highlighModeEnabled.value = true;
    manager.activeHighlightAnchorWordId = fromWordId;

    await manager.saveHighlights(highlights);
  }

  Future<void> _onHighlightClick(int wordId, int? existingHighlightIdx) async {
    if (existingHighlightIdx != null) {
      List<HighlightDetail> highlights = List.of(
        manager.highlightedWords.value,
      );
      Highlight h = highlights[existingHighlightIdx].highlight;
      highlights.removeAt(existingHighlightIdx);
      if (h.id != null) {
        await manager.deleteHighlight(h.id!);
      }
      manager.highlightedWords.value = highlights;
      return;
    }
  }

  void _onHighlightSelectionChanged(int fromWordId, int toWordId) {
    _setActiveHighlightRange(fromWordId, toWordId);
  }

  Future<void> _onHighlightSelectionCompleted(
    int fromWordId,
    int toWordId,
  ) async {
    final highlights = _setActiveHighlightRange(
      fromWordId,
      toWordId,
      isActive: false,
    );
    _finishHighlightSelection();
    await manager.saveHighlights(highlights);
  }

  void _onHighlightSelectionCanceled(bool isDelete) {
    final highlights = List.of(manager.highlightedWords.value);

    int activeIndex = -1;

    if (isDelete) {
      activeIndex = highlights.indexWhere(
        (detail) => detail.isActive && !detail.isDelete,
      );
    }

    if (activeIndex != -1 && isDelete) {
      highlights[activeIndex].isActive = false;

      final highlight = highlights[activeIndex].highlight;

      if (highlight.id != null) {
        manager.deleteHighlight(highlight.id!);
        highlights.removeAt(activeIndex);
      }
    }

    manager.highlightedWords.value = highlights;
    _finishHighlightSelection();
  }

  void _finishHighlightSelection() {
    manager.highlighModeEnabled.value = false;
    manager.temporaryHighlightIdx.value = null;
    manager.activeHighlightAnchorWordId = null;
  }

  void _onHighightColorSelected(int colorIdx) {
    final highlights = List.of(manager.highlightedWords.value);

    final activeIndex = highlights.indexWhere(
      (detail) => detail.isActive && !detail.isDelete,
    );

    if (activeIndex == -1) return;

    highlights[activeIndex].highlight = highlights[activeIndex].highlight
        .copyWith(colorIdx: colorIdx);
    highlights[activeIndex].defaultColor = false;

    manager.highlightedWords.value = highlights;
  }

  void _onHighightCopy() async {
    if (!mounted) return;

    final highlights = List.of(manager.highlightedWords.value);

    final activeIndex = highlights.indexWhere(
      (detail) => detail.isActive && !detail.isDelete,
    );

    if (activeIndex == -1) return;

    HighlightDetail hd = highlights[activeIndex];

    String text = await manager.getText(
      hd.highlight.fromWord,
      hd.highlight.toWord,
    );

    await Clipboard.setData(ClipboardData(text: text));
  }

  List<HighlightDetail> _setActiveHighlightRange(
    int fromWordId,
    int toWordId, {
    bool createIfMissing = false,
    bool isActive = true,
  }) {
    final fromWord = min(fromWordId, toWordId);
    final toWord = max(fromWordId, toWordId);
    final highlights = List.of(manager.highlightedWords.value);

    if (createIfMissing) {
      //this is a new highlight, try to check if its within an existing highlight
      for (final detail in highlights) {
        if (detail.isDelete) continue;
        if (detail.highlight.fromWord > fromWord) break;

        if (detail.highlight.toWord >= toWord) {
          //this is a valid highligh
          detail.isActive = true;
          detail.defaultColor = false;
          manager.highlightedWords.value = highlights;
          return highlights;
        }
      }
    }

    final activeIndex = highlights.indexWhere(
      (detail) => detail.isActive && !detail.isDelete,
    );
    late final HighlightDetail activeDetail;

    if (activeIndex == -1) {
      if (!createIfMissing) return highlights;

      activeDetail = HighlightDetail(
        highlight: Highlight(
          date: DateTime.now(),
          bookId: widget.bookId,
          chapter: widget.chapter,
          fromWord: fromWord,
          toWord: toWord,
          colorIdx: 0,
        ),
        isActive: isActive,
        isChanged: true,
      );
      highlights.add(activeDetail);
    } else {
      activeDetail = highlights[activeIndex];
      activeDetail.highlight = activeDetail.highlight.copyWith(
        fromWord: fromWord,
        toWord: toWord,
      );
      activeDetail.isChanged = true;
    }

    highlights.sort(_sortHighlights);
    mergeHighlights(highlights);

    if (!activeDetail.isDelete) {
      activeDetail.isActive = isActive;
    }

    manager.highlightedWords.value = highlights;
    return highlights;
  }

  int _sortHighlights(HighlightDetail x, HighlightDetail y) {
    return x.highlight.fromWord.compareTo(y.highlight.fromWord);
  }

  void mergeHighlights(List<HighlightDetail> list) {
    if (list.isEmpty) {
      return;
    }

    HighlightDetail active = list[0];
    active.isDelete = false;

    for (int i = 1; i < list.length; i++) {
      HighlightDetail cur = list[i];

      cur.isDelete = false;

      if (cur.highlight.fromWord <= active.highlight.toWord) {
        HighlightDetail main, other;

        if (cur.isActive) {
          main = cur;
          other = active;
        } else {
          main = active;
          other = cur;
        }

        Highlight highlight = main.highlight.copyWith(
          fromWord: min(main.highlight.fromWord, other.highlight.fromWord),
          toWord: max(main.highlight.toWord, other.highlight.toWord),
          colorIdx: main.defaultColor
              ? other.highlight.colorIdx
              : main.highlight.colorIdx,
        );

        main.isChanged = true;
        other.isDelete = true;
        main.highlight = highlight;
        active = main;
      } else {
        active = cur;
      }
    }
  }
}
