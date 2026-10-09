import 'dart:io';
import 'dart:typed_data';

import 'audio_timing.dart';

class AudioTimingDatabase {
    static const int _endSentinel = 0xFFFFFFFF;

    final List<List<AudioTiming>> data;

    AudioTimingDatabase(Uint8List bytes)
        : data = _openBytes(bytes);

    static Future<AudioTimingDatabase> openFile(String filepath) async {
      final file = File(filepath);
      final bytes = await file.readAsBytes();
      return AudioTimingDatabase(bytes);
    }

    List<AudioTiming>? getTimingsForChapter(int chapter) {
        if (chapter < 0 || chapter >= data.length) return null;
        return data[chapter];
    }

    static List<List<AudioTiming>> _openBytes(Uint8List bytes) {
      final buffer = ByteData.sublistView(bytes);

      const stride = 11;
      final recordCount = buffer.lengthInBytes ~/ stride;

      if (recordCount == 0) {
          return [];
      }

      final byChapter = <int, List<AudioTiming>>{};
      var maxChapter = 0;

      for (var i = 0; i < recordCount; i++) {
        final pos = i * stride;

        final book = buffer.getUint8(pos);
        final chapter = buffer.getUint8(pos + 1);
        final verse = buffer.getUint8(pos + 2);
        final verseId = (book * 1000 + chapter) * 1000 + verse;

        final double start = buffer.getUint32(pos + 3) / 100;
        final int endRaw = buffer.getUint32(pos + 7);
        final double end = endRaw == _endSentinel
            ? double.infinity
            : endRaw / 100;

        (byChapter[chapter] ??= []).add(
          AudioTiming(
            verseId: verseId,
            start: start,
            end: end
          ),
        );

        if (chapter > maxChapter) {
          maxChapter = chapter;
        }
      }

      return List<List<AudioTiming>>.generate(maxChapter, (index) {
        return byChapter[index + 1] ?? const [];
      });
    }
}
