import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VerseSelectionDialog extends StatefulWidget {
  const VerseSelectionDialog({
    super.key,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
    this.onBookmarkCreated,
    this.onBookmarkRemoved,
  });

  final int bookId;
  final int chapter;
  final int verse;
  final String text;
  final ValueChanged<int>? onBookmarkCreated;
  final ValueChanged<int>? onBookmarkRemoved;

  @override
  State<VerseSelectionDialog> createState() => _VerseSelectionDialogState();
}

class _VerseSelectionDialogState extends State<VerseSelectionDialog> {
  bool _isCopied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 24.0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Stack(
          alignment: AlignmentDirectional.topCenter,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_buildActionButtons(context)],
              ),
            ),
            _buildCloseButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.onBookmarkCreated != null)
          IconButton(
            icon: Icon(Icons.bookmark_add, color: iconColor),
            onPressed: () {
              widget.onBookmarkCreated?.call(widget.verse);
              Navigator.of(context).pop();
            },
          ),
        if (widget.onBookmarkRemoved != null)
          IconButton(
            icon: Icon(Icons.bookmark_remove, color: iconColor),
            onPressed: () {
              widget.onBookmarkRemoved?.call(widget.verse);
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(width: 24),
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              _isCopied ? Icons.check : Icons.copy,
              key: ValueKey<bool>(_isCopied),
              color: _isCopied ? Colors.green : iconColor,
            ),
          ),
          onPressed: () => _handleCopy(widget.text),
        ),
      ],
    );
  }

  Future<void> _handleCopy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      _isCopied = true;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isCopied = false;
    });
  }

  Widget _buildCloseButton(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}
