import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gbt/l10n/app_localizations.dart';
import 'package:gbt/common/word.dart';
import 'package:gbt/services/bookmarks/bookmark_model.dart';
import 'package:gbt/services/settings/user_settings.dart';
import 'package:gbt/ui/common/sparkle_icon.dart';
import 'package:gbt/ui/common/word_popup.dart';
import 'package:gbt/ui/home/panel_area/hebrew_greek_panel/chapter_manager.dart';

export 'package:gbt/ui/common/word_popup.dart' show WordPopup;

/// A function that is called when a word is long-pressed.
///
/// The function can be asynchronous to allow waiting for user
/// interaction (e.g., closing a dialog).
typedef AsyncWordActionCallback = Future<void> Function(String wordId);

/// A callback for a highlighted word range.
typedef WordRangeCallback =
    void Function(WordRenderer fromWord, WordRenderer toWord);

/// A function that returns the popup content for a given word ID.
///
/// The lookup can be asynchronous (e.g., from a database or network).
/// If the function's Future resolves to null, or to a popup with an
/// empty text, no popup will be shown for that word.
typedef AsyncPopupWordProvider = Future<WordPopup?> Function(String wordId);

/// A callback to find a verse number at a specific Y offset
typedef VerseAtOffsetCallback = int? Function(double y);

class _LineMetrics {
  final double top;
  final double bottom;

  // The verse to show if this line is visible
  final int labelVerse;

  //the minimum verse number on a given line
  final int lowestVerseOnLine;
  //the maximum verse number on a given line
  final int highestVerseOnLine;

  _LineMetrics(
    this.top,
    this.bottom,
    this.labelVerse,
    this.lowestVerseOnLine,
    this.highestVerseOnLine,
  );
}

/// A way for the outside world (such as scroll controllers) to obtain the
/// internal layout metrics of [HebrewGreekText].
class HebrewGreekTextController {
  final Map<int, Rect> _verseRects = {};
  VerseAtOffsetCallback? _verseAtOffsetCallback;
  ValueChanged<Rect?>? _spotlightSetCallback;

  /// Updates the controller with the latest verse rectangles.
  ///
  /// This is intended to be called by the RenderHebrewGreekText object.
  void _updateVerseRects(Map<int, Rect> rects) {
    _verseRects.clear();
    _verseRects.addAll(rects);
  }

  /// Registers the callback from the RenderObject
  void _registerVerseFinder(VerseAtOffsetCallback callback) {
    _verseAtOffsetCallback = callback;
  }

  void setSpotlightUpdatedCalllback(ValueChanged<Rect?> callback) {
    _spotlightSetCallback = callback;
  }

  /// Retrieves the [Rect] for a given verse number.
  ///
  /// The [Rect] contains the position and size of the verse number
  /// relative to the top-left corner of the HebrewGreekText widget.
  /// Returns null if the verse number is not found.
  Rect? getVerseRect(int verseNumber) {
    return _verseRects[verseNumber];
  }

  int? getVerseForOffset(double y) {
    if (_verseAtOffsetCallback != null) {
      return _verseAtOffsetCallback!(y);
    }
    return 1;
  }
}

//class to group words by verse
class VerseLayoutBlock {
  final int verse;
  final List<HebrewGreekWord> words;
  VerseLayoutBlock(this.verse, this.words);
}

class WordRenderer {
  HebrewGreekWord word;
  TextPainter painter;
  Rect? rect;
  WordRenderer({required this.word, required this.painter});

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WordRenderer &&
            runtimeType == other.runtimeType &&
            word.id == other.word.id;
  }

  @override
  int get hashCode => word.id.hashCode;
}

class VerseRenderer {
  final int verse;
  int readingCount;
  Rect? verseNumberRect;
  Rect? readingCheckboxRect;
  Rect? bookmarkIconRect;
  TextPainter verseNumberPainter;
  TextPainter? verseReadingCountPainter;
  TextPainter? bookmarkIconPainter;
  Size? checkboxSize;
  List<WordRenderer> words;
  List<(Rect, int)> highlightRects;
  int? activeHighlightStartIdx;
  int? activeHighlightEndIdx;

  VerseRenderer(this.verse, this.verseNumberPainter)
    : words = [],
      highlightRects = [],
      readingCount = 0;
}

class CustomPopupButton {
  final TextPainter textPainter;
  final VoidCallback? callback;

  CustomPopupButton(this.textPainter, this.callback);
}

/// A widget that renders Hebrew and Greek text with custom layout and styling.
///
/// This widget takes a list of [HebrewGreekWord] objects and renders them according
/// to the specified [textDirection] and [textStyle]. It handles proper text layout and
/// styling for both Hebrew and Greek text.
///
/// Example:
///
/// HebrewGreekText(
///   words: [HebrewGreekWord(...)],
///   textDirection: TextDirection.rtl,
///   style: TextStyle(fontSize: 18),
/// )
///
class HebrewGreekText extends LeafRenderObjectWidget {
  const HebrewGreekText({
    super.key,
    required this.words,
    this.controller,
    this.textDirection = TextDirection.ltr,
    this.textStyle,
    this.verseNumberStyle,
    this.popupWordProvider,
    this.popupBackgroundColor,
    this.popupTextStyle,
    this.onPopupShown,
    this.onWordLongPress,
    this.onVerseNumberTap,
    this.onVerseCheckboxTap,
    this.onVerseNumberLongPress,
    this.flashColor,
    this.flashedWordId,
    this.highlightedVerse,
    this.highlightColor,
    required this.verseLayout,
    required this.readingModeEnabled,
    this.checkedVerses,
    this.changedCheckedVerse,
    this.resetCheckedVerses = false,
    this.checkedVersesRevision = 0,
    this.spotlightVerse,
    this.bookmarkedVerses = const {},
    this.highlightedWords = const [],
    this.highlightModeEnabled = false,
    this.highlightSelectionAnchorWordId,
    this.onHighlightSelectionStarted,
    this.onHighlightSelectionChanged,
    this.onHighlightSelectionCompleted,
    this.onHighlightSelectionCanceled,
    this.onHighlightSelectionCopy,
    this.onHighlightColorSelected,
    required this.highlightPickerColors,
  });

  /// The words that will rendered in the text layout
  final List<HebrewGreekWord> words;

  /// A controller to programmatically interact with the text layout,
  /// for example, to scroll to a specific verse.
  final HebrewGreekTextController? controller;

  /// RTL for Hebrew and LTR for Greek
  final TextDirection textDirection;

  /// The style of the rendered text
  final TextStyle? textStyle;

  /// The style of the rendered verse numbers
  final TextStyle? verseNumberStyle;

  /// An async function that provides the content of the popup when a word
  /// is tapped.
  final AsyncPopupWordProvider? popupWordProvider;

  /// The background color of the popup. Defaults to a dark grey.
  final Color? popupBackgroundColor;

  /// The text style for the text inside the popup. Defaults to white text.
  final TextStyle? popupTextStyle;

  /// A callback that is invoked when a popup is about to be shown.
  /// It provides the global [Rect] of the popup, allowing for actions
  /// like scrolling to ensure visibility.
  final ValueChanged<Rect>? onPopupShown;

  /// A callback that is invoked when a word is long-pressed.
  final AsyncWordActionCallback? onWordLongPress;

  /// Callback when a verse number is tapped
  final ValueChanged<int>? onVerseNumberTap;

  /// Callback when a verse checkbox is tapped
  final ValueChanged<int>? onVerseCheckboxTap;

  /// Callback when a verse number is long pressed
  final ValueChanged<int>? onVerseNumberLongPress;

  /// The color of the flash effect.
  ///
  /// Defaults to the same color as [verseNumberStyle].
  final Color? flashColor;

  /// The word ID to flash highlight.
  final String? flashedWordId;

  /// The verse number to highlight
  final int? highlightedVerse;

  /// The background color to use for a highlighted verse
  final Color? highlightColor;

  /// The verse layout to use for the text
  final VerseLayout verseLayout;

  // Specifies if reading mode is enabled ot not
  final bool readingModeEnabled;

  /// Indicates if the verse has been read or not
  /// a filled checkbox will appear
  final Map<int, int>? checkedVerses;
  final int? changedCheckedVerse;
  final bool resetCheckedVerses;
  final int checkedVersesRevision;
  final int? spotlightVerse;
  final Set<int> bookmarkedVerses;
  final List<HighlightDetail> highlightedWords;
  final bool highlightModeEnabled;
  final WordRenderer? highlightSelectionAnchorWordId;
  final WordRangeCallback? onHighlightSelectionStarted;
  final WordRangeCallback? onHighlightSelectionChanged;
  final WordRangeCallback? onHighlightSelectionCompleted;
  final ValueChanged<bool>? onHighlightSelectionCanceled;
  final VoidCallback? onHighlightSelectionCopy;
  final List<Color> highlightPickerColors;
  final ValueChanged<int>? onHighlightColorSelected;

  @override
  RenderHebrewGreekText createRenderObject(BuildContext context) {
    final defaultTextStyle = DefaultTextStyle.of(context);
    var effectiveTextStyle = textStyle;
    if (textStyle == null || textStyle!.inherit) {
      effectiveTextStyle = defaultTextStyle.style.merge(textStyle);
    }
    var effectiveVerseNumberStyle = verseNumberStyle;
    if (verseNumberStyle == null || verseNumberStyle!.inherit) {
      effectiveVerseNumberStyle = effectiveTextStyle!.merge(verseNumberStyle);
    }
    final effectivePopupTextStyle = defaultTextStyle.style.merge(
      popupTextStyle,
    );

    final popupHighlightTextStyle = TextStyle(
      fontSize: 20,
      color: Theme.of(context).colorScheme.onInverseSurface,
    );

    return RenderHebrewGreekText(
      words: words,
      controller: controller,
      textDirection: textDirection,
      style: effectiveTextStyle!,
      verseNumberStyle: effectiveVerseNumberStyle,
      popupWordProvider: popupWordProvider,
      popupBackgroundColor: popupBackgroundColor ?? Color(0xFF000000),
      popupTextStyle: effectivePopupTextStyle,
      popupHighlightTextStyle: popupHighlightTextStyle,
      highlightSelectionClearLabel: AppLocalizations.of(
        context,
      )!.highlightSelectionClear,
      highlightSelectionCopyLabel: AppLocalizations.of(
        context,
      )!.highlightSelectionCopy,
      onPopupShown: onPopupShown,
      onWordLongPress: onWordLongPress,
      onVerseNumberTap: onVerseNumberTap,
      onVerseCheckboxTap: onVerseCheckboxTap,
      onVerseNumberLongPress: onVerseNumberLongPress,
      verseLayout: verseLayout,
      readingModeEnabled: readingModeEnabled,
      checkedVerses: checkedVerses,
      changedCheckedVerse: changedCheckedVerse,
      resetCheckedVerses: resetCheckedVerses,
      checkedVersesRevision: checkedVersesRevision,
      spotlightVerse: spotlightVerse,
      bookmarkedVerses: bookmarkedVerses,
      highlightedWords: highlightedWords,
      highlightModeEnabled: highlightModeEnabled,
      highlightSelectionAnchorWordId: highlightSelectionAnchorWordId,
      onHighlightSelectionStarted: onHighlightSelectionStarted,
      onHighlightSelectionChanged: onHighlightSelectionChanged,
      onHighlightSelectionCompleted: onHighlightSelectionCompleted,
      onHighlightSelectionCanceled: onHighlightSelectionCanceled,
      onHighlightSelectionCopy: onHighlightSelectionCopy,
      highlightPickerColors: highlightPickerColors,
      onHighlightColorSelected: onHighlightColorSelected,
      flashColor:
          flashColor ??
          effectiveVerseNumberStyle?.color?.withValues(alpha: 0.4) ??
          const Color(0xFFFFFFFF),
      flashedWordId: flashedWordId,
      highlightedVerse: highlightedVerse,
      highlightColor:
          highlightColor ??
          effectiveVerseNumberStyle?.color?.withValues(alpha: 0.4) ??
          const Color(0xFFFFFFFF),
      primaryColor: Theme.of(context).colorScheme.primary,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHebrewGreekText renderObject,
  ) {
    final defaultTextStyle = DefaultTextStyle.of(context);
    var effectiveTextStyle = textStyle;
    if (textStyle == null || textStyle!.inherit) {
      effectiveTextStyle = defaultTextStyle.style.merge(textStyle);
    }
    var effectiveVerseNumberStyle = verseNumberStyle;
    if (verseNumberStyle == null || verseNumberStyle!.inherit) {
      effectiveVerseNumberStyle = effectiveTextStyle!.merge(verseNumberStyle);
    }
    final effectivePopupTextStyle = const TextStyle(
      fontSize: 20,
      color: Color(0xFFFFFFFF),
    ).merge(popupTextStyle);

    final popupHighlightTextStyle = TextStyle(
      fontSize: 20,
      color: Theme.of(context).colorScheme.onInverseSurface,
    );

    renderObject
      ..words = words
      ..controller = controller
      ..textDirection = textDirection
      ..textStyle = effectiveTextStyle!
      ..verseNumberStyle = effectiveVerseNumberStyle
      ..popupWordProvider = popupWordProvider
      ..popupBackgroundColor = popupBackgroundColor ?? Color(0xFF000000)
      ..popupTextStyle = effectivePopupTextStyle
      ..popupHighlightTextStyle = popupHighlightTextStyle
      ..highlightSelectionClearLabel = AppLocalizations.of(
        context,
      )!.highlightSelectionClear
      ..highlightSelectionCopyLabel = AppLocalizations.of(
        context,
      )!.highlightSelectionCopy
      ..onPopupShown = onPopupShown
      ..onWordLongPress = onWordLongPress
      ..onVerseNumberTap = onVerseNumberTap
      ..onVerseCheckboxTap = onVerseCheckboxTap
      ..onVerseNumberLongPress = onVerseNumberLongPress
      ..verseLayout = verseLayout
      ..updateCheckedVerses(
        checkedVerses,
        changedVerse: changedCheckedVerse,
        resetAll: resetCheckedVerses,
        revision: checkedVersesRevision,
      )
      ..spotlightVerse = spotlightVerse
      ..bookmarkedVerses = bookmarkedVerses
      ..highlightedWords = highlightedWords
      ..highlightModeEnabled = highlightModeEnabled
      ..highlightSelectionAnchorWordId = highlightSelectionAnchorWordId
      ..onHighlightSelectionStarted = onHighlightSelectionStarted
      ..onHighlightSelectionChanged = onHighlightSelectionChanged
      ..onHighlightSelectionCompleted = onHighlightSelectionCompleted
      ..onHighlightSelectionCanceled = onHighlightSelectionCanceled
      ..onHighlightSelectionCopy = onHighlightSelectionCopy
      ..onHighlightColorSelected = onHighlightColorSelected
      ..highlightPickerColors = highlightPickerColors
      ..readingModeEnabled = readingModeEnabled
      ..flashColor =
          flashColor ??
          effectiveVerseNumberStyle?.color?.withValues(alpha: 0.4) ??
          const Color(0xFFFFFFFF)
      ..flashedWordId = flashedWordId
      ..highlightedVerse = highlightedVerse
      ..highlightColor =
          highlightColor ??
          effectiveVerseNumberStyle?.color?.withValues(alpha: 0.4) ??
          const Color(0xFFFFFFFF)
      ..primaryColor = Theme.of(context).colorScheme.primary;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<List<HebrewGreekWord>>('words', words));
    properties.add(
      DiagnosticsProperty<HebrewGreekTextController>('controller', controller),
    );
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
    properties.add(DiagnosticsProperty<TextStyle>('textStyle', textStyle));
    properties.add(
      DiagnosticsProperty<TextStyle>('verseNumberStyle', verseNumberStyle),
    );
    properties.add(
      ObjectFlagProperty<AsyncPopupWordProvider>.has(
        'popupWordProvider',
        popupWordProvider,
      ),
    );
    properties.add(ColorProperty('popupBackgroundColor', popupBackgroundColor));
    properties.add(
      DiagnosticsProperty<TextStyle>('popupTextStyle', popupTextStyle),
    );
    properties.add(
      ObjectFlagProperty<ValueChanged<Rect>>.has('onPopupShown', onPopupShown),
    );
    properties.add(
      ObjectFlagProperty<AsyncWordActionCallback>.has(
        'onWordLongPress',
        onWordLongPress,
      ),
    );
    properties.add(
      ObjectFlagProperty<ValueChanged<int>>.has(
        'onVerseNumberTap',
        onVerseNumberTap,
      ),
    );
    properties.add(
      ObjectFlagProperty<ValueChanged<int>>.has(
        'onVerseNumberLongPress',
        onVerseNumberLongPress,
      ),
    );
    properties.add(ColorProperty('flashColor', flashColor));
    properties.add(StringProperty('flashedWordId', flashedWordId));
    properties.add(IntProperty('highlightedVerse', highlightedVerse));
    properties.add(ColorProperty('highlightColor', highlightColor));
  }
}

class RenderHebrewGreekText extends RenderBox {
  static const maqaph = '־';

  RenderHebrewGreekText({
    required List<HebrewGreekWord> words,
    HebrewGreekTextController? controller,
    required TextDirection textDirection,
    required TextStyle style,
    required TextStyle? verseNumberStyle,
    AsyncPopupWordProvider? popupWordProvider,
    required Color popupBackgroundColor,
    required TextStyle popupTextStyle,
    required TextStyle popupHighlightTextStyle,
    required String highlightSelectionClearLabel,
    required String highlightSelectionCopyLabel,
    ValueChanged<Rect>? onPopupShown,
    AsyncWordActionCallback? onWordLongPress,
    ValueChanged<int>? onVerseNumberTap,
    ValueChanged<int>? onVerseNumberLongPress,
    ValueChanged<int>? onVerseCheckboxTap,
    required Color flashColor,
    String? flashedWordId,
    int? highlightedVerse,
    Color? highlightColor,
    required VerseLayout verseLayout,
    required bool readingModeEnabled,
    Map<int, int>? checkedVerses,
    int? changedCheckedVerse,
    bool resetCheckedVerses = false,
    int checkedVersesRevision = 0,
    int? spotlightVerse,
    required Set<int> bookmarkedVerses,
    required List<HighlightDetail> highlightedWords,
    required bool highlightModeEnabled,
    WordRenderer? highlightSelectionAnchorWordId,
    WordRangeCallback? onHighlightSelectionStarted,
    WordRangeCallback? onHighlightSelectionChanged,
    WordRangeCallback? onHighlightSelectionCompleted,
    ValueChanged<bool>? onHighlightSelectionCanceled,
    VoidCallback? onHighlightSelectionCopy,
    required List<Color> highlightPickerColors,
    ValueChanged<int>? onHighlightColorSelected,
    required Color primaryColor,
  }) : _words = words,
       _verses = _buildBlocks(words),
       _controller = controller,
       _textDirection = textDirection,
       _textStyle = style,
       _verseNumberStyle = verseNumberStyle,
       _popupWordProvider = popupWordProvider,
       _popupBackgroundColor = popupBackgroundColor,
       _popupTextStyle = popupTextStyle,
       _popupHighlightTextStyle = popupHighlightTextStyle,
       _highlightSelectionClearLabel = highlightSelectionClearLabel,
       _highlightSelectionCopyLabel = highlightSelectionCopyLabel,
       _onPopupShown = onPopupShown,
       _onWordLongPress = onWordLongPress,
       _onVerseNumberTap = onVerseNumberTap,
       _onVerseCheckboxTap = onVerseCheckboxTap,
       _onVerseNumberLongPress = onVerseNumberLongPress,
       _flashColor = flashColor,
       _flashedWordId = flashedWordId,
       _highlightedVerse = highlightedVerse,
       _highlightColor = highlightColor,
       _verseLayout = verseLayout,
       _readingModeEnabled = readingModeEnabled,
       _bookmarkedVerses = bookmarkedVerses,
       _highlightedWords = highlightedWords,
       _highlightModeEnabled = highlightModeEnabled,
       _highlightSelectionAnchorWordId = highlightSelectionAnchorWordId,
       _onHighlightSelectionStarted = onHighlightSelectionStarted,
       _onHighlightSelectionChanged = onHighlightSelectionChanged,
       _onHighlightSelectionCompleted = onHighlightSelectionCompleted,
       _onHighlightSelectionCanceled = onHighlightSelectionCanceled,
       _onHighlightSelectionCopy = onHighlightSelectionCopy,
       _highlightPickerColors = highlightPickerColors,
       _onHighlightColorSelected = onHighlightColorSelected,
       _checkedVerses = checkedVerses == null
           ? null
           : Map<int, int>.unmodifiable(checkedVerses),
       _checkedVersesRevision = checkedVersesRevision,
       _spotlightVerse = spotlightVerse,
       _primaryColor = primaryColor {
    _updatePainters();
    _tapRecognizer = TapGestureRecognizer()..onTapUp = _handleTapUp;
    _doubleTapRecognizer = DoubleTapGestureRecognizer()
      ..onDoubleTapDown = _handleDoubleTapDown;
    _longPressRecognizer = LongPressGestureRecognizer()
      ..onLongPressStart = _handleLongPressStart;
    _panRecognizer = PanGestureRecognizer()
      ..onStart = _handlePanStart
      ..onUpdate = _handlePanUpdate
      ..onEnd = _handlePanEnd
      ..onCancel = _handlePanCancel;
    _controller?._registerVerseFinder(_findVerseAtOffset);
  }
  Color _primaryColor;

  Color get primaryColor => _primaryColor;
  set primaryColor(Color value) {
    if (_primaryColor == value) return;
    _primaryColor = value;
    markNeedsPaint();
  }

  // Cached Paint objects
  final Paint _flashPaint = Paint();
  final Paint _highlightPaint = Paint();
  final Paint _bgPaint = Paint();

  String? _tappedWordId;
  String? _popupText;
  bool _popupIsAi = false;
  TextDirection _popupTextDirection = TextDirection.ltr;
  TextPainter? _popupPainter;
  Timer? _popupDismissTimer;
  late final TapGestureRecognizer _tapRecognizer;
  late final DoubleTapGestureRecognizer _doubleTapRecognizer;
  late final LongPressGestureRecognizer _longPressRecognizer;
  late final PanGestureRecognizer _panRecognizer;
  final List<CustomPopupButton> _customButtonsPainters = [];
  bool _isUpdatingHighlightSelection = false;
  final List<_LineMetrics> _lineMetrics = [];
  VerseLayout _verseLayout;
  bool _readingModeEnabled;
  Map<int, int>? _checkedVerses;
  int _checkedVersesRevision;
  int? _spotlightVerse;

  static List<VerseLayoutBlock> _buildBlocks(List<HebrewGreekWord> words) {
    final blocks = <VerseLayoutBlock>[];
    int? currentVerse;
    List<HebrewGreekWord> currentWords = [];

    for (final w in words) {
      final verse = w.reference.verse;

      if (currentVerse == null || currentVerse != verse) {
        if (blocks.isNotEmpty && blocks.last.words.isEmpty) {
          blocks.removeLast();
        }

        currentWords = [];

        currentVerse = verse;

        blocks.add(VerseLayoutBlock(currentVerse, currentWords));
      }

      currentWords.add(w);
    }

    if (blocks.isNotEmpty && blocks.last.words.isEmpty) {
      blocks.removeLast();
    }

    return blocks;
  }

  static void _updateHighlightBlocks(
    List<VerseRenderer> verseRenderer,
    List<HighlightDetail> highlightedWords,
    bool isLtr,
  ) {
    double? top, left;
    double? bottom, right;

    int? highlightStart;
    int? highlightStartVerse;
    int? highlightEnd;
    int? highlightEndVerse;
    int highlightVerseColor = 0;
    int highlightIdx = 0;

    while (highlightIdx < highlightedWords.length) {
      if (highlightedWords[highlightIdx].isDelete) {
        highlightIdx++;
      } else {
        break;
      }
    }

    if (highlightIdx < highlightedWords.length) {
      Highlight h = highlightedWords[highlightIdx].highlight;
      highlightStart = h.fromWord;
      highlightEnd = h.toWord;
      highlightStartVerse = (highlightStart ~/ 100) % 1000;
      highlightEndVerse = (highlightEnd ~/ 100) % 1000;
      highlightVerseColor = h.colorIdx;
    }

    for (int i = 0; i < verseRenderer.length; i++) {
      VerseRenderer verse = verseRenderer[i];
      verse.highlightRects.clear();
      verse.activeHighlightStartIdx = null;
      verse.activeHighlightEndIdx = null;

      for (int j = 0; j < verse.words.length; j++) {
        HebrewGreekWord word = verse.words[j].word;

        int wid = int.parse(word.id);

        if (highlightStart != null &&
            highlightEnd != null &&
            highlightStart <= wid &&
            wid <= highlightEnd) {
          if (highlightedWords[highlightIdx].isActive &&
              verse.activeHighlightStartIdx == null &&
              verse.verse == highlightStartVerse) {
            verse.activeHighlightStartIdx = verse.highlightRects.length;
          }

          if (highlightedWords[highlightIdx].isActive &&
              verse.verse == highlightEndVerse) {
            verse.activeHighlightEndIdx = verse.highlightRects.length;
          }

          bool isNewLine =
              j > 0 &&
              verse.words[j].rect!.topLeft.dy >
                  verse.words[j - 1].rect!.topLeft.dy +
                      verse.words[j - 1].rect!.height / 2;

          //new line started, add save previous line
          if (isNewLine || top == null) {
            if (top != null) {
              verse.highlightRects.add((
                Rect.fromLTRB(left!, top, right!, bottom!),
                highlightVerseColor,
              ));
            }

            Rect r = verse.words[j].rect!;

            top = r.top;
            if (isLtr) {
              left = r.left;
            } else {
              right = r.right;
            }
          }

          bottom = verse.words[j].rect!.bottom;
          if (isLtr) {
            right = verse.words[j].rect!.right;
          } else {
            left = verse.words[j].rect!.left;
          }

          //check if we move to the next highlight
          if (wid == highlightEnd) {
            verse.highlightRects.add((
              Rect.fromLTRB(left!, top, right!, bottom),
              highlightVerseColor,
            ));

            highlightIdx++;
            top = null;
          }

          while (highlightIdx < highlightedWords.length) {
            if (highlightedWords[highlightIdx].isDelete) {
              highlightIdx++;
            } else {
              break;
            }
          }

          if (highlightIdx < highlightedWords.length) {
            Highlight h = highlightedWords[highlightIdx].highlight;
            highlightStart = h.fromWord;
            highlightEnd = h.toWord;
            highlightStartVerse = (highlightStart ~/ 100) % 1000;
            highlightEndVerse = (highlightEnd ~/ 100) % 1000;
            highlightVerseColor = h.colorIdx;
          } else {
            highlightStart = null;
            highlightEnd = null;
          }
        }
      }

      if (top != null) {
        if (highlightedWords.isNotEmpty &&
            highlightedWords.last.isActive &&
            verse.verse == highlightEndVerse) {
          verse.activeHighlightEndIdx = verse.highlightRects.length;
        }

        verse.highlightRects.add((
          Rect.fromLTRB(left!, top, right!, bottom!),
          highlightVerseColor,
        ));
        top = null;
      }
    }
  }

  late List<VerseLayoutBlock> _verses;
  List<HebrewGreekWord> _words;
  List<HebrewGreekWord> get words => _words;

  set words(List<HebrewGreekWord> value) {
    if (_words == value) return;
    _words = value;
    _verses = _buildBlocks(_words);
    _needsResetVersesRenderers = true;
    _needsTextPaintersUpdate = true;
    markNeedsLayout();
  }

  List<VerseLayoutBlock> get verses => _verses;
  VerseLayout get verseLayout => _verseLayout;
  Map<int, int>? get checkedVerses => _checkedVerses;

  set verseLayout(VerseLayout value) {
    if (_verseLayout == value) return;
    _verseLayout = value;
    _needsTextPaintersUpdate = true;
    markNeedsLayout();
  }

  set checkedVerses(Map<int, int>? value) {
    updateCheckedVerses(
      value,
      resetAll: true,
      revision: _checkedVersesRevision + 1,
    );
  }

  void updateCheckedVerses(
    Map<int, int>? value, {
    int? changedVerse,
    bool resetAll = false,
    required int revision,
  }) {
    if (revision == _checkedVersesRevision) return;

    _checkedVerses = value == null ? null : Map<int, int>.unmodifiable(value);
    _checkedVersesRevision = revision;

    if (resetAll) {
      _checkboxesNeedFullUpdate = true;
      _checkboxesToUpdate.clear();
    } else if (changedVerse != null) {
      _checkboxesToUpdate.add(changedVerse);
    } else {
      return;
    }

    _needsCheckboxesUpdate = true;
    _updateCheckboxPainters();
  }

  set readingModeEnabled(bool value) {
    if (_readingModeEnabled == value) return;
    _readingModeEnabled = value;
    _needsCheckboxesUpdate = true;
    _checkboxesNeedFullUpdate = true;
    _updateCheckboxPainters();
  }

  set spotlightVerse(int? value) {
    if (_spotlightVerse == value) return;
    _spotlightVerse = value;
  }

  HebrewGreekTextController? _controller;
  HebrewGreekTextController? get controller => _controller;
  set controller(HebrewGreekTextController? value) {
    if (_controller == value) return;
    _controller = value;
    _controller?._registerVerseFinder(_findVerseAtOffset);
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _needsTextPaintersUpdate = true;
    markNeedsLayout();
  }

  TextStyle _textStyle;
  TextStyle get textStyle => _textStyle;
  set textStyle(TextStyle value) {
    if (_textStyle == value) return;
    _textStyle = value;
    _needsTextPaintersUpdate = true;
    _needsCheckboxesUpdate = true;
    _checkboxesNeedFullUpdate = true;
    markNeedsLayout();
  }

  TextStyle? _verseNumberStyle;
  TextStyle? get verseNumberStyle => _verseNumberStyle;
  set verseNumberStyle(TextStyle? value) {
    if (_verseNumberStyle == value) return;
    _verseNumberStyle = value;
    _needsTextPaintersUpdate = true;
    markNeedsLayout();
  }

  AsyncPopupWordProvider? _popupWordProvider;
  AsyncPopupWordProvider? get popupWordProvider => _popupWordProvider;
  set popupWordProvider(AsyncPopupWordProvider? value) {
    if (_popupWordProvider == value) return;
    _popupWordProvider = value;
    if (value == null && _tappedWordId != null) {
      _dismissPopup();
    }
  }

  Color _popupBackgroundColor;
  Color get popupBackgroundColor => _popupBackgroundColor;
  set popupBackgroundColor(Color value) {
    if (_popupBackgroundColor == value) return;
    _popupBackgroundColor = value;
    if (_tappedWordId != null) {
      markNeedsPaint();
    }
  }

  List<Color> _highlightPickerColors;
  List<Color> get highlightPickerColors => _highlightPickerColors;
  set highlightPickerColors(List<Color> value) {
    if (_highlightPickerColors == value) return;
    _highlightPickerColors = value;
  }

  bool _colorPickerVisible = false;
  ValueChanged<int>? _onHighlightColorSelected;
  ValueChanged<int>? get onHighlightColorSelected => _onHighlightColorSelected;
  set onHighlightColorSelected(ValueChanged<int>? value) {
    if (_onHighlightColorSelected == value) return;
    _onHighlightColorSelected = value;
  }

  TextStyle _popupTextStyle;
  TextStyle get popupTextStyle => _popupTextStyle;
  set popupTextStyle(TextStyle value) {
    if (_popupTextStyle == value) return;
    _popupTextStyle = value;
    if (_tappedWordId != null) {
      _preparePopupPainter();
      markNeedsPaint();
    }
  }

  TextStyle _popupHighlightTextStyle;
  TextStyle get popupHighlightTextStyle => _popupHighlightTextStyle;
  set popupHighlightTextStyle(TextStyle value) {
    if (_popupHighlightTextStyle == value) return;
    _popupHighlightTextStyle = value;
    if (_tappedWordId != null) {
      _preparePopupPainter();
      markNeedsPaint();
    }
  }

  String _highlightSelectionClearLabel;
  set highlightSelectionClearLabel(String value) {
    _highlightSelectionClearLabel = value;
  }

  String _highlightSelectionCopyLabel;
  set highlightSelectionCopyLabel(String value) {
    _highlightSelectionCopyLabel = value;
  }

  void _preparePopupPainter() {
    if (_popupText == null || _popupText!.isEmpty) {
      _popupPainter = null;
      return;
    }
    _popupPainter = TextPainter(
      text: TextSpan(text: _popupText!, style: _popupTextStyle),
      textDirection: _popupTextDirection,
    )..layout();
  }

  ValueChanged<Rect>? _onPopupShown;
  ValueChanged<Rect>? get onPopupShown => _onPopupShown;
  set onPopupShown(ValueChanged<Rect>? value) {
    if (_onPopupShown == value) return;
    _onPopupShown = value;
  }

  AsyncWordActionCallback? _onWordLongPress;
  AsyncWordActionCallback? get onWordLongPress => _onWordLongPress;
  set onWordLongPress(AsyncWordActionCallback? value) {
    if (_onWordLongPress == value) return;
    _onWordLongPress = value;
  }

  ValueChanged<int>? _onVerseNumberTap;
  ValueChanged<int>? get onVerseNumberTap => _onVerseNumberTap;
  set onVerseNumberTap(ValueChanged<int>? value) {
    if (_onVerseNumberTap == value) return;
    _onVerseNumberTap = value;
  }

  ValueChanged<int>? _onVerseCheckboxTap;
  ValueChanged<int>? get onVerseCheckboxTap => _onVerseCheckboxTap;
  set onVerseCheckboxTap(ValueChanged<int>? value) {
    if (_onVerseCheckboxTap == value) return;
    _onVerseCheckboxTap = value;
  }

  ValueChanged<int>? _onVerseNumberLongPress;
  ValueChanged<int>? get onVerseNumberLongPress => _onVerseNumberLongPress;
  set onVerseNumberLongPress(ValueChanged<int>? value) {
    if (_onVerseNumberLongPress == value) return;
    _onVerseNumberLongPress = value;
  }

  Color _flashColor;
  Color get flashColor => _flashColor;
  set flashColor(Color value) {
    if (_flashColor == value) return;
    _flashColor = value;
    if (_flashedWordId != null) {
      markNeedsPaint();
    }
  }

  String? _flashedWordId;
  String? get flashedWordId => _flashedWordId;
  set flashedWordId(String? value) {
    if (_flashedWordId == value) return;
    _flashedWordId = value;
    markNeedsPaint();
  }

  int? _highlightedVerse;
  int? get highlightedVerse => _highlightedVerse;
  set highlightedVerse(int? value) {
    if (_highlightedVerse == value) return;
    _highlightedVerse = value;
    markNeedsPaint();
  }

  Color? _highlightColor;
  Color? get highlightColor => _highlightColor;
  set highlightColor(Color? value) {
    if (_highlightColor == value) return;
    _highlightColor = value;
    markNeedsPaint();
  }

  Set<int> _bookmarkedVerses;
  Set<int> get bookmarkedVerses => _bookmarkedVerses;
  set bookmarkedVerses(Set<int> verses) {
    if (setEquals(_bookmarkedVerses, verses)) return;
    _bookmarkedVerses = verses;
    _needsResetVersesRenderers = true;
    _needsTextPaintersUpdate = true;
    markNeedsLayout();
  }

  List<HighlightDetail> _highlightedWords;
  List<HighlightDetail> get highlightedWords => _highlightedWords;
  set highlightedWords(List<HighlightDetail> highlightedWords) {
    if (identical(_highlightedWords, highlightedWords)) return;
    _highlightedWords = highlightedWords;
    _updateHighlightBlocks(
      _verseRenderer,
      highlightedWords,
      _textDirection == TextDirection.ltr,
    );
    markNeedsPaint();
  }

  bool _highlightModeEnabled;
  bool get highlightModeEnabled => _highlightModeEnabled;
  set highlightModeEnabled(bool value) {
    if (_highlightModeEnabled == value) return;
    _highlightModeEnabled = value;
    if (!value) {
      _isUpdatingHighlightSelection = false;
    }
  }

  WordRenderer? _highlightSelectionAnchorWordId;
  WordRenderer? get highlightSelectionAnchorWordId =>
      _highlightSelectionAnchorWordId;
  set highlightSelectionAnchorWordId(WordRenderer? value) {
    if (_highlightSelectionAnchorWordId == value) return;
    _highlightSelectionAnchorWordId = value;
    _colorPickerVisible = (value != null); // show when anchor is set
    markNeedsPaint();
  }

  WordRangeCallback? _onHighlightSelectionStarted;
  WordRangeCallback? get onHighlightSelectionStarted =>
      _onHighlightSelectionStarted;
  set onHighlightSelectionStarted(WordRangeCallback? value) {
    if (_onHighlightSelectionStarted == value) return;
    _onHighlightSelectionStarted = value;
  }

  WordRangeCallback? _onHighlightSelectionChanged;
  WordRangeCallback? get onHighlightSelectionChanged =>
      _onHighlightSelectionChanged;
  set onHighlightSelectionChanged(WordRangeCallback? value) {
    if (_onHighlightSelectionChanged == value) return;
    _onHighlightSelectionChanged = value;
  }

  WordRangeCallback? _onHighlightSelectionCompleted;
  WordRangeCallback? get onHighlightSelectionCompleted =>
      _onHighlightSelectionCompleted;
  set onHighlightSelectionCompleted(WordRangeCallback? value) {
    if (_onHighlightSelectionCompleted == value) return;
    _onHighlightSelectionCompleted = value;
  }

  ValueChanged<bool>? _onHighlightSelectionCanceled;
  ValueChanged<bool>? get onHighlightSelectionCanceled =>
      _onHighlightSelectionCanceled;
  set onHighlightSelectionCanceled(ValueChanged<bool>? value) {
    if (_onHighlightSelectionCanceled == value) return;
    _onHighlightSelectionCanceled = value;
  }

  void _onHighlightSelectionCleared() {
    _onHighlightSelectionCanceled?.call(true);
  }

  VoidCallback? _onHighlightSelectionCopy;
  VoidCallback? get onHighlightSelectionCopy => _onHighlightSelectionCopy;
  set onHighlightSelectionCopy(VoidCallback? value) {
    if (_onHighlightSelectionCopy == value) return;
    _onHighlightSelectionCopy = value;
  }

  /// Clears all popup state and requests a repaint to make it disappear.
  void _dismissPopup() {
    _popupDismissTimer?.cancel();
    _popupDismissTimer = null;

    if (_tappedWordId == null) return;
    _tappedWordId = null;
    _popupText = null;
    _popupIsAi = false;
    _popupTextDirection = TextDirection.ltr;
    _popupPainter = null;
    markNeedsPaint();
  }

  // Cached layout data
  bool _needsTextPaintersUpdate = true;
  bool _needsCheckboxesUpdate = false;
  bool _needsResetVersesRenderers = false;
  bool _checkboxesNeedFullUpdate = false;
  final Set<int> _checkboxesToUpdate = {};

  late TextPainter _spacePainter;
  final List<VerseRenderer> _verseRenderer = [];

  final Map<int, int> _verseIndex = {};
  int _indexForVerse(int verse) => _verseIndex[verse] ?? -1;

  void _updatePainters({bool duringLayout = false}) {
    if (_needsTextPaintersUpdate || _needsResetVersesRenderers) {
      _spacePainter = TextPainter(
        text: TextSpan(text: ' ', style: _textStyle),
        textDirection: _textDirection,
      )..layout();

      if (_verseRenderer.isEmpty || _needsResetVersesRenderers) {
        _verseRenderer.clear();
        _initializeVerseRenderers();
      } else {
        _updateVerseRenderers();
      }

      _needsTextPaintersUpdate = false;
      _needsResetVersesRenderers = false;
    }

    if (_needsCheckboxesUpdate) {
      _updateCheckboxPainters(duringLayout: duringLayout);
    }
  }

  void _updateCheckboxPainters({bool duringLayout = false}) {
    if (!_needsCheckboxesUpdate) return;
    bool sizeChanged = false;

    if (!_readingModeEnabled) {
      for (final verseRenderer in _verseRenderer) {
        if (verseRenderer.readingCount != 0 ||
            verseRenderer.checkboxSize != null) {
          verseRenderer.readingCount = 0;
          verseRenderer.checkboxSize = null;
          verseRenderer.readingCheckboxRect = null;
          verseRenderer.verseReadingCountPainter = null;
          sizeChanged = true;
        }
      }
    } else {
      for (final verseRenderer in _verseRenderer) {
        final shouldUpdate =
            _checkboxesNeedFullUpdate ||
            _checkboxesToUpdate.contains(verseRenderer.verse);
        if (shouldUpdate) {
          final oldSize = verseRenderer.checkboxSize;
          final newSize = _setupCheckboxPainter(verseRenderer);
          if (oldSize != newSize) {
            sizeChanged = true;
          }
        }
      }
    }

    _needsCheckboxesUpdate = false;
    _checkboxesNeedFullUpdate = false;
    _checkboxesToUpdate.clear();

    if (duringLayout) {
      return;
    }

    if (sizeChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  void _initializeVerseRenderers() {
    _verseIndex.clear();
    //for each verse of the chapter
    for (final verse in verses) {
      final verseNumberPainter = TextPainter(
        text: TextSpan(text: '${verse.verse}', style: _verseNumberStyle),
        textDirection: _textDirection,
      )..layout();

      final verseRenderer = VerseRenderer(verse.verse, verseNumberPainter);

      _verseIndex[verse.verse] = _verseRenderer.length;
      _verseRenderer.add(verseRenderer);

      if (_bookmarkedVerses.contains(verse.verse)) {
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.bookmark.codePoint),
            style: _verseNumberStyle!.copyWith(
              fontFamily: Icons.bookmark.fontFamily,
              package: Icons.bookmark.fontPackage,
            ),
          ),
          textDirection: _textDirection,
        )..layout();

        verseRenderer.bookmarkIconPainter = painter;
      }

      //for each word of the verse
      for (final word in verse.words) {
        final wordPainter = TextPainter(
          text: TextSpan(text: word.text, style: _textStyle),
          textDirection: _textDirection,
        )..layout();

        final wordRenderer = WordRenderer(word: word, painter: wordPainter);

        verseRenderer.words.add(wordRenderer);
      }

      if (_readingModeEnabled) {
        _setupCheckboxPainter(verseRenderer);
      } else {
        verseRenderer.readingCheckboxRect = null;
        verseRenderer.verseReadingCountPainter = null;
      }
    }
  }

  Size _setupCheckboxPainter(VerseRenderer verseRenderer) {
    final readingCount = _checkedVerses?[verseRenderer.verse] ?? 0;
    final horizontalPadding = 8.0;
    final verticalPadding = 4.0;
    final badgeHeight = 0.4 * (_textStyle.fontSize ?? 48);

    verseRenderer.readingCount = readingCount;

    final countPainter = TextPainter(
      text: TextSpan(
        text: '$readingCount',
        style: _textStyle.copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w700,
          fontSize: (_textStyle.fontSize ?? 48) * 0.4,
        ),
      ),
      textDirection: _textDirection,
    )..layout();

    final height = math.max(
      badgeHeight,
      countPainter.height + verticalPadding * 2,
    );

    final width = math.max(countPainter.width + horizontalPadding * 2, height);

    verseRenderer.verseReadingCountPainter = countPainter;

    final newSize = Size(width, height);
    verseRenderer.checkboxSize = newSize;
    return newSize;
  }

  void _updateVerseRenderers() {
    //for each verse of the chapter
    for (final verseRenderer in _verseRenderer) {
      //for each word of the verse
      for (final word in verseRenderer.words) {
        word.painter.text = TextSpan(text: word.word.text, style: _textStyle);
        word.painter.layout();
      }

      verseRenderer.highlightRects.clear();
      verseRenderer.activeHighlightStartIdx = null;
      verseRenderer.activeHighlightEndIdx = null;

      verseRenderer.verseNumberPainter.text = TextSpan(
        text: '${verseRenderer.verse}',
        style: _verseNumberStyle,
      );

      verseRenderer.verseNumberPainter.layout();

      if (verseRenderer.bookmarkIconPainter != null) {
        verseRenderer.bookmarkIconPainter!.text = TextSpan(
          text: String.fromCharCode(Icons.bookmark.codePoint),
          style: _verseNumberStyle!.copyWith(
            fontFamily: Icons.bookmark.fontFamily,
            package: Icons.bookmark.fontPackage,
          ),
        );
        verseRenderer.bookmarkIconPainter!.layout();
      }
    }
  }

  _LineMetrics? _findLineAtOffset(double y) {
    if (_lineMetrics.isEmpty) return null;

    // Binary search to find the line containing 'y'
    int min = 0;
    int max = _lineMetrics.length - 1;
    _LineMetrics? match;
    int? closestPrevIndex;

    while (min <= max) {
      final mid = min + ((max - min) >> 1);
      final line = _lineMetrics[mid];

      if (y < line.top) {
        // Look before
        max = mid - 1;
      } else if (y > line.bottom) {
        // Look after
        min = mid + 1;
        closestPrevIndex = mid;
      } else {
        // Direct hit!
        match = line;
        break;
      }
    }

    if (match != null) {
      return match;
    }

    // Fallback: If we scrolled past everything (y > last line)
    // closestPrevIndex will point to the last line.
    if (closestPrevIndex != null) {
      return _lineMetrics[closestPrevIndex];
    }

    // Fallback: Top of screen (y < first line)
    return _lineMetrics.first;
  }

  int? _findVerseAtOffset(double y) {
    return _findLineAtOffset(y)?.labelVerse;
  }

  // Helper to finalize a line
  void _finalizeLine(
    double top,
    double bottom,
    List<({HebrewGreekWord word, bool isFirstInVerse})> lineWords,
  ) {
    if (lineWords.isEmpty) return;

    int? bestStartVerse;
    int? lowestVerseOnLine;
    int? highestVerseOnLine;

    for (final item in lineWords) {
      final verse = item.word.reference.verse;

      if (lowestVerseOnLine == null || verse < lowestVerseOnLine) {
        lowestVerseOnLine = verse;
      }
      if (highestVerseOnLine == null || verse > highestVerseOnLine) {
        highestVerseOnLine = verse;
      }
      if (item.isFirstInVerse) {
        if (bestStartVerse == null || verse < bestStartVerse) {
          bestStartVerse = verse;
        }
      }
    }

    // Priority: Start Verse > Lowest Visible
    final label = bestStartVerse ?? lowestVerseOnLine ?? 1;
    _lineMetrics.add(
      _LineMetrics(
        top,
        bottom,
        label,
        lowestVerseOnLine ?? 1,
        highestVerseOnLine ?? 1,
      ),
    );
    lineWords.clear();
  }

  Size _performLayout(BoxConstraints constraints) {
    if (_needsTextPaintersUpdate || _needsCheckboxesUpdate) {
      _updatePainters(duringLayout: true);
    }
    _lineMetrics.clear();

    double mainAxisOffset = 0.0;
    double crossAxisOffset = 0.0;
    double currentLineMaxHeight = 0.0;
    double maxLineWidth = 0.0;
    double effectiveSpaceWidth = 0.0;

    final double availableWidth = constraints.maxWidth;
    final double spaceWidth = _spacePainter.width;
    final isLtr = _textDirection == TextDirection.ltr;

    // Temporary storage for calculating verse priority on the current line
    final List<({HebrewGreekWord word, bool isFirstInVerse})> currentLineWords =
        [];

    mainAxisOffset = isLtr ? 0.0 : availableWidth;

    final Map<int, Rect> verseRectsMap = {};
    Rect? spotlightRect;

    double? top, left;
    double? bottom, right;

    int? highlightStart;
    int? highlightStartVerse;
    int? highlightEnd;
    int? highlightEndVerse;
    int highlightIdx = 0;

    while (highlightIdx < highlightedWords.length) {
      if (highlightedWords[highlightIdx].isDelete) {
        highlightIdx++;
      } else {
        break;
      }
    }

    if (highlightIdx < highlightedWords.length) {
      Highlight h = highlightedWords[highlightIdx].highlight;
      highlightStart = h.fromWord;
      highlightEnd = h.toWord;
      highlightStartVerse = (highlightStart ~/ 100) % 1000;
      highlightEndVerse = (highlightEnd ~/ 100) % 1000;
    }

    for (int i = 0; i < _verseRenderer.length; i++) {
      VerseRenderer verse = _verseRenderer[i];
      verse.highlightRects.clear();

      for (int j = 0; j < verse.words.length; j++) {
        HebrewGreekWord word = verse.words[j].word;
        (
          mainAxisOffset,
          crossAxisOffset,
          currentLineMaxHeight,
          effectiveSpaceWidth,
        ) = _performWordLayout(
          verse,
          verse.words[j],
          mainAxisOffset,
          crossAxisOffset,
          spaceWidth,
          isLtr,
          availableWidth,
          currentLineMaxHeight,
          currentLineWords,
          j == 0 ? verse.verseNumberPainter : null,
          j == 0 ? verse.verseReadingCountPainter : null,
          j == 0 ? verse.bookmarkIconPainter : null,
          j == 0 ? verse.checkboxSize : null,
        );

        int wid = int.parse(word.id);

        if (highlightStart != null &&
            highlightEnd != null &&
            highlightStart <= wid &&
            wid <= highlightEnd) {
          if (highlightedWords[highlightIdx].isActive &&
              verse.activeHighlightStartIdx == null &&
              verse.verse == highlightStartVerse) {
            verse.activeHighlightStartIdx = verse.highlightRects.length;
          }

          if (highlightedWords[highlightIdx].isActive &&
              verse.verse == highlightEndVerse) {
            verse.activeHighlightEndIdx = verse.highlightRects.length;
          }

          //new line started, add save previous line
          if (currentLineWords.length == 1 || top == null) {
            if (top != null) {
              verse.highlightRects.add((
                Rect.fromLTRB(left!, top, right!, bottom!),
                highlightedWords[highlightIdx].highlight.colorIdx,
              ));
            }

            Rect r = verse.words[j].rect!;

            top = r.top;
            if (isLtr) {
              left = r.left;
            } else {
              right = r.right;
            }
          }

          bottom = verse.words[j].rect!.bottom;
          if (isLtr) {
            right = verse.words[j].rect!.right;
          } else {
            left = verse.words[j].rect!.left;
          }

          //check if we move to the next highlight
          if (wid == highlightEnd) {
            verse.highlightRects.add((
              Rect.fromLTRB(left!, top, right!, bottom),
              highlightedWords[highlightIdx].highlight.colorIdx,
            ));
            highlightIdx++;
            top = null;
          }

          while (highlightIdx < highlightedWords.length) {
            if (highlightedWords[highlightIdx].isDelete) {
              highlightIdx++;
            } else {
              break;
            }
          }

          if (highlightIdx < highlightedWords.length) {
            Highlight h = highlightedWords[highlightIdx].highlight;
            highlightStart = h.fromWord;
            highlightEnd = h.toWord;
            highlightStartVerse = (highlightStart ~/ 100) % 1000;
            highlightEndVerse = (highlightEnd ~/ 100) % 1000;
          } else {
            highlightStart = null;
            highlightEnd = null;
          }
        }

        // Track the maximum width used.
        if (isLtr) {
          maxLineWidth = math.max(
            maxLineWidth,
            mainAxisOffset - effectiveSpaceWidth,
          );
        } else {
          maxLineWidth = math.max(
            maxLineWidth,
            availableWidth - (mainAxisOffset + effectiveSpaceWidth),
          );
        }
      }

      if (top != null) {
        if (highlightedWords.isNotEmpty &&
            highlightedWords.last.isActive &&
            verse.verse == highlightEndVerse) {
          verse.activeHighlightEndIdx = verse.highlightRects.length;
        }

        verse.highlightRects.add((
          Rect.fromLTRB(left!, top, right!, bottom!),
          highlightedWords.last.highlight.colorIdx,
        ));
        top = null;
      }

      if (_spotlightVerse != null &&
          _readingModeEnabled &&
          _spotlightVerse == verse.verse) {
        spotlightRect = verse.readingCheckboxRect!;
      }

      verseRectsMap[verse.verse] = verse.verseNumberRect!;
    }

    // Finalize the last line
    _finalizeLine(
      crossAxisOffset,
      crossAxisOffset + currentLineMaxHeight,
      currentLineWords,
    );

    controller?._updateVerseRects(verseRectsMap);

    if (spotlightRect != null) {
      controller?._spotlightSetCallback?.call(spotlightRect);
    }

    final double finalHeight = crossAxisOffset + currentLineMaxHeight;
    final double finalWidth = constraints.hasBoundedWidth
        ? availableWidth
        : maxLineWidth;

    return Size(finalWidth, finalHeight);
  }

  /// Main layout method for a single word (called for every word)
  (double, double, double, double) _performWordLayout(
    VerseRenderer verse,
    WordRenderer wordRenderer,
    double mainAxisOffset,
    double crossAxisOffset,
    double spaceWidth,
    bool isLtr,
    double availableWidth,
    double currentLineMaxHeight,
    List<({HebrewGreekWord word, bool isFirstInVerse})> currentLineWords,
    TextPainter? verseNumberPainter,
    TextPainter? countPainter,
    TextPainter? bookmarkPainter,
    Size? checkboxSize,
  ) {
    final wordPainter = wordRenderer.painter;
    final word = wordRenderer.word;
    final wordSize = wordPainter.size;
    final verseNumberSize = verseNumberPainter?.size ?? Size.zero;
    final bookmarkSize = bookmarkPainter?.size;
    final checkboxHeight = checkboxSize?.height ?? 0.0;

    final verseNumberUnitWidth = verseNumberPainter != null
        ? verseNumberPainter.size.width + spaceWidth
        : 0.0;

    final bookmarkUnitWidth = bookmarkPainter != null
        ? bookmarkPainter.size.width + spaceWidth
        : 0.0;

    final checkboxUnitWidth = checkboxSize != null
        ? checkboxSize.width + spaceWidth
        : 0.0;

    final totalUnitWidth =
        verseNumberUnitWidth +
        bookmarkUnitWidth +
        checkboxUnitWidth +
        wordSize.width;

    // Should this verse start on a new line?
    bool fitsOnLine = true;
    if (verseNumberPainter != null &&
        _verseLayout == VerseLayout.versePerLine) {
      fitsOnLine = false;
    } else if (isLtr) {
      fitsOnLine = mainAxisOffset + totalUnitWidth <= availableWidth;
    } else {
      fitsOnLine = mainAxisOffset - totalUnitWidth >= 0;
    }

    // Line wrap
    if (!fitsOnLine) {
      _finalizeLine(
        crossAxisOffset,
        crossAxisOffset + currentLineMaxHeight,
        currentLineWords,
      );
      crossAxisOffset += currentLineMaxHeight;
      currentLineMaxHeight = 0.0;
      mainAxisOffset = isLtr ? 0.0 : availableWidth;
    }

    // The verse number painter is only passed for the first word of a verse
    // (j == 0 in the verse loop), so its presence marks a verse start.
    currentLineWords.add((
      word: word,
      isFirstInVerse: verseNumberPainter != null,
    ));

    // Calculate max height for this line
    currentLineMaxHeight = math.max(
      currentLineMaxHeight,
      math.max(wordSize.height, verseNumberSize.height),
    );

    final bool endsWithMaqaph = word.text.endsWith(maqaph);
    final double effectiveSpaceWidth = endsWithMaqaph ? 0.0 : spaceWidth;

    final double offset = math.max(
      0,
      (currentLineMaxHeight - checkboxHeight) / 4,
    );

    // === LAYOUT BRANCH ===
    if (isLtr) {
      mainAxisOffset = _layoutLTR(
        verse,
        wordRenderer,
        mainAxisOffset,
        crossAxisOffset,
        offset,
        verseNumberPainter,
        checkboxSize,
        bookmarkSize,
        verseNumberSize,
        spaceWidth,
        effectiveSpaceWidth,
      );
    } else {
      mainAxisOffset = _layoutRTL(
        verse,
        wordRenderer,
        mainAxisOffset,
        crossAxisOffset,
        offset,
        verseNumberPainter,
        checkboxSize,
        bookmarkSize,
        verseNumberSize,
        spaceWidth,
        effectiveSpaceWidth,
      );
    }

    return (
      mainAxisOffset,
      crossAxisOffset,
      currentLineMaxHeight,
      effectiveSpaceWidth,
    );
  }

  double _layoutLTR(
    VerseRenderer verse,
    WordRenderer wordRenderer,
    double mainAxisOffset,
    double crossAxisOffset,
    double offset,
    TextPainter? verseNumberPainter,
    Size? checkboxSize,
    Size? bookmarkSize,
    Size verseNumberSize,
    double spaceWidth,
    double effectiveSpaceWidth,
  ) {
    // 1. Position verse reading checkbox if it exists
    if (checkboxSize != null) {
      final checkboxRect = Rect.fromLTWH(
        mainAxisOffset,
        crossAxisOffset + offset,
        checkboxSize.width,
        checkboxSize.height,
      );
      verse.readingCheckboxRect = checkboxRect;
      mainAxisOffset += checkboxSize.width + spaceWidth;
    }
    // 2. Position bookmark icon
    if (bookmarkSize != null) {
      final verseRect = Rect.fromLTWH(
        mainAxisOffset,
        crossAxisOffset,
        bookmarkSize.width,
        bookmarkSize.height,
      );
      verse.bookmarkIconRect = verseRect;
      mainAxisOffset += bookmarkSize.width + spaceWidth;
    }

    // 3. Position verse number if it exists
    if (verseNumberPainter != null) {
      final verseRect = Rect.fromLTWH(
        mainAxisOffset,
        crossAxisOffset,
        verseNumberSize.width,
        verseNumberSize.height,
      );
      verse.verseNumberRect = verseRect;
      mainAxisOffset += verseNumberSize.width + spaceWidth;
    }
    // 4. Position the word
    final wordRect = Rect.fromLTWH(
      mainAxisOffset,
      crossAxisOffset,
      wordRenderer.painter.size.width,
      wordRenderer.painter.size.height,
    );

    wordRenderer.rect = wordRect;
    mainAxisOffset += wordRenderer.painter.size.width + effectiveSpaceWidth;

    return mainAxisOffset;
  }

  double _layoutRTL(
    VerseRenderer verse,
    WordRenderer wordRenderer,
    double mainAxisOffset,
    double crossAxisOffset,
    double offset,
    TextPainter? verseNumberPainter,
    Size? checkboxSize,
    Size? bookmarkSize,
    Size verseNumberSize,
    double spaceWidth,
    double effectiveSpaceWidth,
  ) {
    // RTL
    // 1. Position verse reading checkbox if it exists
    if (checkboxSize != null) {
      // Move cursor left by the width of the number to find its top-left
      mainAxisOffset -= checkboxSize.width;
      final checkboxRect = Rect.fromLTWH(
        mainAxisOffset,
        crossAxisOffset + offset,
        checkboxSize.width,
        checkboxSize.height,
      );
      verse.readingCheckboxRect = checkboxRect;
      mainAxisOffset -= spaceWidth;
    }
    // 2. Position bookmark if exists
    if (bookmarkSize != null) {
      mainAxisOffset -= bookmarkSize.width;
      final checkboxRect = Rect.fromLTWH(
        mainAxisOffset,
        crossAxisOffset,
        bookmarkSize.width,
        bookmarkSize.height,
      );
      verse.bookmarkIconRect = checkboxRect;
      //mainAxisOffset -= spaceWidth;
    }
    // 3. Position verse number if it exists (at the rightmost available spot)
    if (verseNumberPainter != null) {
      // Move cursor left by the width of the number to find its top-left
      mainAxisOffset -= verseNumberSize.width;
      final verseRect = Rect.fromLTWH(
        mainAxisOffset,
        crossAxisOffset,
        verseNumberSize.width,
        verseNumberSize.height,
      );
      verse.verseNumberRect = verseRect;
      mainAxisOffset -= spaceWidth;
    }
    // 4. Position the word to the left of the verse number (or at the start)
    mainAxisOffset -= wordRenderer.painter.size.width;
    final wordRect = Rect.fromLTWH(
      mainAxisOffset,
      crossAxisOffset,
      wordRenderer.painter.size.width,
      wordRenderer.painter.size.height,
    );
    wordRenderer.rect = wordRect;
    // 4. Account for the space before the next element
    mainAxisOffset -= effectiveSpaceWidth;

    return mainAxisOffset;
  }

  @override
  void performLayout() {
    size = _performLayout(constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _performLayout(constraints);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (_needsTextPaintersUpdate || _needsCheckboxesUpdate) _updatePainters();
    if (_verseRenderer.isEmpty) return 0.0;

    double maxWidth = 0.0;

    for (int i = 0; i < _verseRenderer.length; i++) {
      for (int j = 0; j < _verseRenderer[i].words.length; j++) {
        final word = _verseRenderer[i].words[j];
        final wordPainter = word.painter;
        final versePainter = j == 0
            ? _verseRenderer[i].verseNumberPainter
            : null;
        final checkboxPainter = j == 0
            ? _verseRenderer[i].verseReadingCountPainter
            : null;

        double unitWidth = wordPainter.width;
        if (versePainter != null && _verseRenderer[i].readingCount > 0) {
          unitWidth += versePainter.width + _spacePainter.width;
        }

        if (checkboxPainter != null) {
          unitWidth += checkboxPainter.width + _spacePainter.width;
        }

        maxWidth = math.max(maxWidth, unitWidth);
      }
    }

    return maxWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (_needsTextPaintersUpdate || _needsCheckboxesUpdate) _updatePainters();
    if (_verseRenderer.isEmpty) return 0.0;

    double totalWidth = 0.0;
    for (VerseRenderer vr in _verseRenderer) {
      totalWidth += vr.verseNumberPainter.width + _spacePainter.width;

      if (vr.verseReadingCountPainter != null) {
        totalWidth += vr.verseReadingCountPainter!.width + _spacePainter.width;
      }

      if (vr.bookmarkIconPainter != null) {
        totalWidth += vr.bookmarkIconPainter!.width + _spacePainter.width;
      }

      // Sum of  words + inter-word spaces, skipping words that end with a maqaph.
      totalWidth += vr.words.fold(
        0.0,
        (sum, w) =>
            sum +
            w.painter.width +
            (w.word.text.endsWith(maqaph) ? 0 : _spacePainter.width),
      );
    }
    return totalWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return computeDryLayout(BoxConstraints.tightFor(width: width)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeDryLayout(BoxConstraints.tightFor(width: width)).height;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }

    _LineMetrics? verse = _findLineAtOffset(position.dy);

    if (verse == null) {
      return false;
    }

    final int lowestIndex = _indexForVerse(verse.lowestVerseOnLine);
    final int highestIndex = _indexForVerse(verse.highestVerseOnLine);

    for (
      int i = lowestIndex < 0 ? 0 : lowestIndex;
      i <= (highestIndex < 0 ? _verseRenderer.length - 1 : highestIndex) &&
          i < _verseRenderer.length;
      i++
    ) {
      VerseRenderer vr = _verseRenderer[i];

      // Check verse numbers first
      if (vr.verseNumberRect?.contains(position) ?? false) {
        result.add(VerseNumberHitTestEntry(this, vr.verse));
        return true;
      }

      // Check verse numbers first
      if (vr.bookmarkIconRect?.contains(position) ?? false) {
        result.add(VerseNumberHitTestEntry(this, vr.verse));
        return true;
      }

      // then check verse checkbox
      if (vr.readingCheckboxRect?.contains(position) ?? false) {
        result.add(VerseCheckboxHitTestEntry(this, vr.verse));
        return true;
      }

      // Then check words
      for (int j = 0; j < vr.words.length; j++) {
        if (vr.words[j].rect?.contains(position) ?? false) {
          result.add(HebrewGreekWordHitTestEntry(this, vr.words[j]));
          return true;
        }
      }
    }

    // If no specific word or verse number was hit, the tap was on the background.
    // Let the default behavior (from super.hitTest) add a generic BoxHitTestEntry.
    return super.hitTest(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, covariant HitTestEntry entry) {
    if (event is PointerDownEvent) {
      _tapRecognizer.addPointer(event);
      _longPressRecognizer.addPointer(event);
      _doubleTapRecognizer.addPointer(event);
      if (_highlightModeEnabled) {
        _panRecognizer.addPointer(event);
      }
    }
  }

  /// Performs a hit test at a given offset and returns the specific entry.
  HitTestEntry? _getHitTestEntryForOffset(Offset offset) {
    final result = BoxHitTestResult();
    // Use the existing hitTest method to populate the result
    if (hitTest(result, position: offset)) {
      // Return the most specific entry (which is added last)
      return result.path.last.target == this ? result.path.last : null;
    }
    return null;
  }

  /// This method is called by the [TapGestureRecognizer] only when a tap is confirmed.
  void _handleTapUp(TapUpDetails details) {
    // Use our helper to find out what was under the user's finger.
    final entry = _getHitTestEntryForOffset(details.localPosition);

    if (_colorPickerVisible) {
      final proceed = _colorPickerHitTest(details.localPosition);
      _colorPickerVisible = false;
      if (!proceed) return;
    }

    if (_highlightModeEnabled) {
      if (entry is HebrewGreekWordHitTestEntry) {
        _updateHighlightSelection(entry.wordRenderer, complete: true);
      } else {
        _onHighlightSelectionCanceled?.call(false);
      }
      _dismissPopup();
      return;
    }

    if (entry is VerseNumberHitTestEntry) {
      debugPrint('Tapped on verse number: ${entry.verseNumber}');
      _onVerseNumberTap?.call(entry.verseNumber);
      _dismissPopup();
      return;
    }

    if (entry is VerseCheckboxHitTestEntry) {
      debugPrint('Tapped on verse checkbox: ${entry.verseNumber}');
      _onVerseCheckboxTap?.call(entry.verseNumber);
      _dismissPopup();
      return;
    }

    if (_popupWordProvider == null) return;

    if (entry is HebrewGreekWordHitTestEntry) {
      _popupDismissTimer?.cancel();

      final tappedId = entry.wordId;
      final tappedWordRenderer = entry.wordRenderer;

      _tappedWordId = tappedId;
      _popupText = null;
      _popupPainter = null;
      markNeedsPaint(); // Hide any old popup immediately

      _popupWordProvider!(tappedId).then((popup) {
        if (_tappedWordId == tappedId) {
          if (popup != null && popup.text.isNotEmpty) {
            _popupText = popup.text;
            _popupIsAi = popup.isAiGenerated;
            _popupTextDirection = popup.textDirection;
            _preparePopupPainter();

            // Notify parent about the popup rect for potential scrolling.
            final tappedWordRect = tappedWordRenderer.rect;
            if (tappedWordRect != null) {
              final localPopupRect = _getPopupRect(tappedWordRect);
              final globalTopLeft = localToGlobal(localPopupRect.topLeft);
              final globalPopupRect = globalTopLeft & localPopupRect.size;
              onPopupShown?.call(globalPopupRect);
            }

            markNeedsPaint();
            _popupDismissTimer = Timer(
              const Duration(seconds: 3),
              _dismissPopup,
            );
          } else {
            _dismissPopup();
          }
        }
      });
    } else {
      // The tap was on the background of the widget,
      // not on a specific word or verse number.
      _dismissPopup();
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    // Use our helper to find out what was under the user's finger.
    final entry = _getHitTestEntryForOffset(details.localPosition);

    if (highlightModeEnabled) {
      _onHighlightSelectionCanceled?.call(false);
    }

    _dismissPopup();

    _customButtonsPainters.clear();

    if (entry is HebrewGreekWordHitTestEntry) {
      final anchorRect = entry.wordRenderer.rect;

      if (anchorRect != null) {
        final painter = TextPainter(
          text: TextSpan(
            text: _highlightSelectionClearLabel,
            style: _popupHighlightTextStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        _customButtonsPainters.add(
          CustomPopupButton(painter, _onHighlightSelectionCleared),
        );

        final painter2 = TextPainter(
          text: TextSpan(
            text: _highlightSelectionCopyLabel,
            style: _popupHighlightTextStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        _customButtonsPainters.add(
          CustomPopupButton(painter2, _onHighlightSelectionCopy),
        );

        final pickerRect = _getColorPickerRect(anchorRect);
        final globalTopLeft = localToGlobal(pickerRect.topLeft);
        final globalPopupRect = globalTopLeft & pickerRect.size;
        onPopupShown?.call(globalPopupRect);
      }

      _startHighlightSelection(entry.wordRenderer);
    }
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_highlightModeEnabled) return;
    final wordId = _getWordIdAtOffset(details.localPosition);
    if (wordId == null) return;
    _isUpdatingHighlightSelection = true;
    _updateHighlightSelection(wordId);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_highlightModeEnabled || !_isUpdatingHighlightSelection) return;
    final wordId = _getWordIdAtOffset(details.localPosition);
    if (wordId == null) return;
    _colorPickerVisible = false;
    _updateHighlightSelection(wordId);
    markNeedsPaint();
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_highlightModeEnabled || !_isUpdatingHighlightSelection) return;
    _isUpdatingHighlightSelection = false;
    final range = _highlightSelectionRange(_lastHighlightSelectionWordId);
    if (range == null) {
      _onHighlightSelectionCanceled?.call(true);
      return;
    }
    _onHighlightSelectionCompleted?.call(range.$1, range.$2);
  }

  void _handlePanCancel() {
    _isUpdatingHighlightSelection = false;
  }

  WordRenderer? _lastHighlightSelectionWordId;

  WordRenderer? _getWordIdAtOffset(Offset offset) {
    final entry = _getHitTestEntryForOffset(offset);
    return entry is HebrewGreekWordHitTestEntry ? entry.wordRenderer : null;
  }

  (WordRenderer, WordRenderer)? _highlightSelectionRange(WordRenderer? wordr) {
    final anchor = _highlightSelectionAnchorWordId;
    if (anchor == null || wordr == null) return null;
    return anchor.word.id.compareTo(wordr.word.id) <= 0
        ? (anchor, wordr)
        : (wordr, anchor);
  }

  void _startHighlightSelection(WordRenderer wordr) {
    _onHighlightSelectionStarted?.call(wordr, wordr);
  }

  void _updateHighlightSelection(WordRenderer word, {bool complete = false}) {
    _lastHighlightSelectionWordId = word;
    final range = _highlightSelectionRange(word);
    if (range == null) return;

    if (complete) {
      _onHighlightSelectionCompleted?.call(range.$1, range.$2);
    } else {
      _onHighlightSelectionChanged?.call(range.$1, range.$2);
    }
  }

  Rect _getPopupRect(Rect tappedWordRect) {
    final popupSize = _popupPainter!.size;
    final contentWidth = popupSize.width + _popupIconBlockWidth;

    // Center the popup horizontally above the tapped word.
    double popupContentX = tappedWordRect.center.dx - (contentWidth / 2);
    // Position it vertically above the tapped word.
    const double verticalMargin = 6.0;
    double popupContentY =
        tappedWordRect.top - popupSize.height - verticalMargin;

    // Adjust to stay within the render box's horizontal bounds.
    if (popupContentX < 0.0) {
      popupContentX = 0.0;
    }
    if (popupContentX + contentWidth > size.width) {
      popupContentX = size.width - contentWidth;
    }

    return Rect.fromLTWH(
      popupContentX - kPopupHorizontalPadding,
      popupContentY - kPopupVerticalPadding,
      contentWidth + kPopupHorizontalPadding * 2,
      popupSize.height + kPopupVerticalPadding * 2,
    );
  }

  /// This method is called by the [LongPressGestureRecognizer].
  Future<void> _handleLongPressStart(LongPressStartDetails details) async {
    if (_highlightModeEnabled) return;

    // Find out what was under the user's finger.
    final entry = _getHitTestEntryForOffset(details.localPosition);

    if (entry is VerseNumberHitTestEntry) {
      if (onVerseNumberLongPress != null) {
        onVerseNumberLongPress!(entry.verseNumber);
      }
      return;
    }

    if (onWordLongPress == null) return;
    if (entry is HebrewGreekWordHitTestEntry) {
      _dismissPopup();
      await onWordLongPress!(entry.wordId);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (verses.isEmpty) return;

    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    final isLtr = _textDirection == TextDirection.ltr;

    // --- 0. Paint audio highlight (Continuous Line Style) ---
    final int highlightedIndex = _highlightedVerse == null
        ? -1
        : _indexForVerse(_highlightedVerse!);

    if (highlightedIndex != -1 && _highlightColor != null) {
      _highlightPaint.color = _highlightColor!;
      final List<Rect> verseRects = [];

      VerseRenderer verse = _verseRenderer[highlightedIndex];

      // A. Collect Verse Number Rect
      verseRects.add(verse.verseNumberRect!);

      // B. Collect all Word Rects for this verse
      for (final word in verse.words) {
        verseRects.add(word.rect!);
      }

      if (verseRects.isNotEmpty) {
        // C. Sort rects: First by Top (Line), then by Left (Position)
        // This groups them so we can merge them easily.
        verseRects.sort((a, b) {
          final diffY = a.top - b.top;
          // If vertical difference is small, treat as same line
          if (diffY.abs() > 2.0) {
            return diffY.compareTo(0);
          }
          return a.left.compareTo(b.left);
        });

        // D. Merge rects on the same line
        final List<Rect> mergedLines = [];
        Rect? currentLineRect;

        for (final rect in verseRects) {
          if (currentLineRect == null) {
            currentLineRect = rect;
            continue;
          }

          // Check if 'rect' is on the same line as 'currentLineRect'
          if ((rect.top - currentLineRect.top).abs() < 5.0) {
            // Same line: Expand the current rect to include this new one.
            // This fills the gap between words.
            currentLineRect = currentLineRect.expandToInclude(rect);
          } else {
            // New line detected: Store the completed line and start a new one
            mergedLines.add(currentLineRect);
            currentLineRect = rect;
          }
        }
        // Add the last line
        if (currentLineRect != null) {
          mergedLines.add(currentLineRect);
        }

        // E. Paint the merged lines using a single Path
        final highlightPath = Path();

        for (final rect in mergedLines) {
          // Inflate slightly
          final displayRect = rect.inflate(4.0);
          final rrect = RRect.fromRectAndRadius(
            displayRect,
            const Radius.circular(4.0),
          );

          // Add to the path instead of drawing immediately
          highlightPath.addRRect(rrect);
        }

        // Draw the entire path once.
        // Overlapping areas within a single Path do not accumulate alpha.
        canvas.drawPath(highlightPath, _highlightPaint);
      }
    }
    // ---------------------------------------------------------

    // 2. Paint all the words
    final Rect visibleRect = canvas.getLocalClipBounds();
    final firstLine = _findLineAtOffset(visibleRect.top);
    final lastLine = _findLineAtOffset(visibleRect.bottom);

    final int startVerse = firstLine?.labelVerse ?? _verseRenderer.first.verse;
    final int endVerse =
        lastLine?.highestVerseOnLine ?? _verseRenderer.last.verse;
    final int startIndex = _indexForVerse(startVerse);
    final int endIndex = _indexForVerse(endVerse);

    for (
      int i = startIndex < 0 ? 0 : startIndex;
      i <= (endIndex < 0 ? _verseRenderer.length - 1 : endIndex) &&
          i < _verseRenderer.length;
      i++
    ) {
      final verse = _verseRenderer[i];

      //paint the checkbox for the reading session
      if (verse.verseReadingCountPainter != null) {
        _paintCheckboxes(canvas, verse);
      }

      if (verse.highlightRects.isNotEmpty) {
        for ((Rect, int) entry in verse.highlightRects) {
          Rect r = entry.$1;
          int idx = entry.$2;
          final paint = Paint()..color = highlightPickerColors[idx];

          final displayRect = r.inflate(-0.2);
          final rrect = RRect.fromRectAndRadius(
            displayRect,
            const Radius.circular(4.0),
          );

          canvas.drawRRect(rrect, paint);
        }

        int? startIdx, endIdx;
        if (isLtr) {
          startIdx = verse.activeHighlightStartIdx;
          endIdx = verse.activeHighlightEndIdx;
        } else {
          startIdx = verse.activeHighlightEndIdx;
          endIdx = verse.activeHighlightStartIdx;
        }

        if (startIdx != null && startIdx < verse.highlightRects.length) {
          int idx = verse.highlightRects[startIdx].$2;
          Color c = highlightPickerColors[idx].withAlpha(255);
          final handlePaint = Paint()..color = c;

          final startRect = verse.highlightRects[startIdx].$1;
          final startCenter = Offset(
            startRect.topLeft.dx,
            startRect.topLeft.dy + startRect.height / 2,
          );

          canvas.drawCircle(startCenter, startRect.height / 4, handlePaint);
        }

        if (endIdx != null && endIdx < verse.highlightRects.length) {
          int idx = verse.highlightRects[endIdx].$2;
          Color c = highlightPickerColors[idx].withAlpha(255);
          final handlePaint = Paint()..color = c;

          final endRect = verse.highlightRects[endIdx].$1;
          final endCenter = Offset(
            endRect.topRight.dx,
            endRect.topRight.dy + endRect.height / 2,
          );

          canvas.drawCircle(endCenter, endRect.height / 4, handlePaint);
        }
      }

      if (verse.bookmarkIconPainter != null) {
        verse.bookmarkIconPainter!.paint(
          canvas,
          verse.bookmarkIconRect!.topLeft,
        );
      }

      // 2.1 Paint the verse number
      verse.verseNumberPainter.paint(canvas, verse.verseNumberRect!.topLeft);

      // 2.2 Paint the verse words
      for (final word in verse.words) {
        if (word.rect == null) {
          continue;
        }

        final rect = word.rect!;

        // 2.2.1 Paint the flash effect (long press)
        if (_flashedWordId != null && _flashedWordId == word.word.id) {
          _flashPaint.color = _flashColor;
          final rrect = RRect.fromRectAndRadius(
            rect.inflate(2.0),
            const Radius.circular(4.0),
          );
          canvas.drawRRect(rrect, _flashPaint);
        }

        // 2.2.2 Paint the popup if a word is tapped AND its painter is ready
        if (_tappedWordId != null &&
            _popupPainter != null &&
            word.word.id == _tappedWordId) {
          _paintPopup(canvas, rect);
        }

        if (_highlightSelectionAnchorWordId != null &&
            word == _highlightSelectionAnchorWordId &&
            _colorPickerVisible) {
          _paintColorPicker(canvas, rect);
        }

        // 2.2.3 Paint the word
        word.painter.paint(canvas, word.rect!.topLeft);
      }
    }

    canvas.restore();
  }

  Rect _getColorPickerRect(Rect anchorWordRect) {
    int swatchCount = _highlightPickerColors.length;
    final double swatchDiameter = kPickerSwatchRadius * 2;

    final double customButtonsWidth = _customButtonsPainters.fold<double>(
      0,
      (sum, entry) => sum + entry.textPainter.size.width,
    );

    final double customButtonsMaxHeight = _customButtonsPainters.fold<double>(
      0,
      (max, entry) => math.max(max, entry.textPainter.size.width),
    );

    final double contentWidth =
        swatchCount * (swatchDiameter + kPickerSwatchSpacing) +
        (2 * _customButtonsPainters.length - 1) * kPickerSwatchSpacing +
        customButtonsWidth;

    final double totalWidth = contentWidth + kPickerPadding * 2;
    final double totalHeight = math.max(
      swatchDiameter + kPickerPadding * 2,
      customButtonsMaxHeight,
    );

    double left = anchorWordRect.center.dx - totalWidth / 2;
    double top = anchorWordRect.top - totalHeight - 8.0;

    left = left.clamp(0.0, size.width - totalWidth);

    return Rect.fromLTWH(left, top, totalWidth, totalHeight);
  }

  static const double kPickerSwatchRadius = 14.0;
  static const double kPickerSwatchSpacing = 10.0;
  static const double kPickerPadding = 10.0;
  static const double kPickerCornerRadius = 12.0;

  bool _colorPickerHitTest(Offset position) {
    if (!_colorPickerVisible || _highlightSelectionAnchorWordId == null) {
      return true;
    }
    final anchorRect = _highlightSelectionAnchorWordId?.rect;
    if (anchorRect == null) return true;

    final pickerRect = _getColorPickerRect(anchorRect);
    if (!pickerRect.contains(position)) return true;

    const double swatchDiameter = kPickerSwatchRadius * 2;
    double cx = pickerRect.left + kPickerPadding + kPickerSwatchRadius;
    final double cy = pickerRect.top + kPickerPadding + kPickerSwatchRadius;

    for (int i = 0; i < _highlightPickerColors.length; i++) {
      final center = Offset(cx, cy);
      if ((position - center).distance <= kPickerSwatchRadius + 4) {
        _onHighlightColorSelected?.call(i);
        return false;
      }
      cx += swatchDiameter + kPickerSwatchSpacing;
    }

    for (CustomPopupButton entry in _customButtonsPainters) {
      if (position.dx >= cx && position.dx <= cx + entry.textPainter.width) {
        entry.callback?.call();
        return false;
      }

      cx += entry.textPainter.width + kPickerSwatchSpacing;
    }

    return true;
  }

  void _paintColorPicker(Canvas canvas, Rect anchorWordRect) {
    final pickerRect = _getColorPickerRect(anchorWordRect);

    final bgPaint = Paint()..color = _popupBackgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pickerRect,
        const Radius.circular(kPickerCornerRadius),
      ),
      bgPaint,
    );

    const double swatchDiameter = kPickerSwatchRadius * 2;
    double cx = pickerRect.left + kPickerPadding + kPickerSwatchRadius;
    final double cy = pickerRect.top + kPickerPadding + kPickerSwatchRadius;

    // Draw color swatches
    for (final color in _highlightPickerColors) {
      final center = Offset(cx, cy);

      final swatchPaint = Paint()..color = color;
      canvas.drawCircle(center, kPickerSwatchRadius, swatchPaint);

      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, kPickerSwatchRadius, ringPaint);

      cx += swatchDiameter + kPickerSwatchSpacing;
    }

    cx -= swatchDiameter / 2;

    final separatorPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.0;

    for (CustomPopupButton entry in _customButtonsPainters) {
      canvas.drawLine(
        Offset(cx, pickerRect.top + 6.0),
        Offset(cx, pickerRect.bottom - 6.0),
        separatorPaint,
      );

      cx += kPickerSwatchSpacing;

      double textDy =
          pickerRect.top +
          (pickerRect.height - entry.textPainter.height) / 2 +
          2;

      entry.textPainter.paint(canvas, Offset(cx, textDy));

      cx += entry.textPainter.width + kPickerSwatchSpacing;
    }

    final anchorX = anchorWordRect.center.dx.clamp(
      pickerRect.left + kPickerCornerRadius,
      pickerRect.right - kPickerCornerRadius,
    );
    final caretPath = Path()
      ..moveTo(anchorX - 6, pickerRect.bottom)
      ..lineTo(anchorX + 6, pickerRect.bottom)
      ..lineTo(anchorX, pickerRect.bottom + 6)
      ..close();
    canvas.drawPath(caretPath, Paint()..color = _popupBackgroundColor);
  }

  void _paintCheckboxes(Canvas canvas, VerseRenderer verse) {
    final readingCount = verse.readingCount;
    final isChecked = readingCount > 0;
    final isHighlighted = _spotlightVerse == verse.verse;

    final rect = verse.readingCheckboxRect!;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final baseColor = _primaryColor;
    final uncheckedTop = baseColor.withValues(alpha: 0.3);
    final uncheckedBottom = baseColor.withValues(alpha: 0.1);

    final paint = Paint()
      ..shader = LinearGradient(
        colors: isChecked
            ? [
                baseColor.withValues(alpha: 0.9),
                baseColor.withValues(alpha: 0.6),
              ]
            : (isHighlighted
                  ? [
                      baseColor.withValues(alpha: 0.9),
                      baseColor.withValues(alpha: 0.2),
                    ]
                  : [uncheckedTop, uncheckedBottom]),
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);

    if (isHighlighted) {
      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(rrect.inflate(-1), paint);
    }

    if (isChecked) {
      final countPainter = verse.verseReadingCountPainter!;

      final textOffset = Offset(
        rect.left + (rect.width - countPainter.width) / 2,
        rect.top + (rect.height - countPainter.height) / 2,
      );
      countPainter.paint(canvas, textOffset);
    }
  }

  static const double kPopupVerticalPadding = 4.0;
  static const double kPopupHorizontalPadding = 8.0;

  double get _popupIconExtent => (_popupTextStyle.fontSize ?? 16.0) * 0.9;

  double get _popupIconGap => _popupIconExtent * 0.35;

  double get _popupIconBlockWidth =>
      _popupIsAi ? _popupIconExtent + _popupIconGap : 0.0;

  void _paintPopup(Canvas canvas, Rect tappedWordRect) {
    // Draw the background.
    const double kPopupCornerRadius = 8.0;
    final bgRect = _getPopupRect(tappedWordRect);
    _bgPaint.color = _popupBackgroundColor;
    final rrect = RRect.fromRectAndRadius(
      bgRect,
      const Radius.circular(kPopupCornerRadius),
    );
    canvas.drawRRect(rrect, _bgPaint);

    var textOffset = Offset(
      bgRect.left + kPopupHorizontalPadding,
      bgRect.top + kPopupVerticalPadding,
    );

    if (_popupIsAi) {
      final iconExtent = _popupIconExtent;
      final textCenterY = textOffset.dy + _popupPainter!.height / 2;
      final isRtl = _popupTextDirection == TextDirection.rtl;

      final iconCenterX = isRtl
          ? bgRect.right - kPopupHorizontalPadding - iconExtent / 2
          : textOffset.dx + iconExtent / 2;
      if (!isRtl) {
        textOffset = Offset(
          textOffset.dx + iconExtent + _popupIconGap,
          textOffset.dy,
        );
      }

      SparkleIcon.paint(
        canvas,
        Rect.fromCenter(
          center: Offset(iconCenterX, textCenterY),
          width: iconExtent,
          height: iconExtent,
        ),
        _primaryColor,
      );
    }

    // Paint the text.
    _popupPainter!.paint(canvas, textOffset);
  }

  @override
  void detach() {
    _tapRecognizer.dispose();
    _doubleTapRecognizer.dispose();
    _longPressRecognizer.dispose();
    _panRecognizer.dispose();
    _popupDismissTimer?.cancel();
    super.detach();
  }
}

// A custom HitTestEntry to carry the specific word ID that was hit.
class HebrewGreekWordHitTestEntry extends HitTestEntry {
  HebrewGreekWordHitTestEntry(this.renderObject, this.wordRenderer)
    : super(renderObject);

  final RenderHebrewGreekText renderObject;
  final WordRenderer wordRenderer;

  String get wordId => wordRenderer.word.id;

  @override
  String toString() =>
      '${renderObject.runtimeType} hit test with word ID: $wordId';
}

// A custom HitTestEntry to carry the specific verse number that was hit.
class VerseNumberHitTestEntry extends HitTestEntry {
  VerseNumberHitTestEntry(this.renderObject, this.verseNumber)
    : super(renderObject);

  final RenderHebrewGreekText renderObject;
  final int verseNumber;

  @override
  String toString() =>
      '${renderObject.runtimeType} hit test with verse number: $verseNumber';
}

// A custom HitTestEntry to carry the specific verse checkbox that was hit.
class VerseCheckboxHitTestEntry extends HitTestEntry {
  VerseCheckboxHitTestEntry(this.renderObject, this.verseNumber)
    : super(renderObject);

  final RenderHebrewGreekText renderObject;
  final int verseNumber;

  @override
  String toString() =>
      '${renderObject.runtimeType} hit test with verse number: $verseNumber';
}
