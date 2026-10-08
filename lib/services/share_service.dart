import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What sharing did, for the message the user sees.
sealed class ShareOutcome {
  const ShareOutcome();
}

/// The system share sheet opened (Android).
class SharedViaSheet extends ShareOutcome {
  const SharedViaSheet();
}

/// The text went to the clipboard (desktop, which has no share sheet).
class CopiedToClipboard extends ShareOutcome {
  const CopiedToClipboard();
}

/// The file was saved here (desktop, which has no share sheet).
class SavedFile extends ShareOutcome {
  const SavedFile(this.path);
  final String path;
}

const _channel = MethodChannel('org.buetow.turbonotes/share');

/// Hands notes to other apps: the Android share sheet, or on the desktop
/// the clipboard (text) and the Downloads folder (files).
class ShareService {
  const ShareService();

  bool get _hasShareSheet => Platform.isAndroid;

  Future<ShareOutcome> shareText(String text, {required String subject}) async {
    if (_hasShareSheet) {
      await _channel.invokeMethod<void>('shareText', {
        'text': text,
        'subject': subject,
      });
      return const SharedViaSheet();
    }
    await Clipboard.setData(ClipboardData(text: text));
    return const CopiedToClipboard();
  }

  /// Shares [bytes] as a file called [fileName] of type [mime].
  Future<ShareOutcome> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mime,
    required String subject,
  }) async {
    if (_hasShareSheet) {
      // The app's cache: what the Android side serves to the receiving app.
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'share'),
      );
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      await _channel.invokeMethod<void>('shareFile', {
        'name': fileName,
        'mime': mime,
        'subject': subject,
      });
      return const SharedViaSheet();
    }
    final downloads =
        await getDownloadsDirectory() ??
        Directory(p.join(Platform.environment['HOME'] ?? '.', 'Downloads'));
    await downloads.create(recursive: true);
    final target = await _freeName(downloads.path, fileName);
    await File(target).writeAsBytes(bytes, flush: true);
    return SavedFile(target);
  }

  /// [name] in [dir], with ` (2)`, ` (3)`... added until nothing is there.
  Future<String> _freeName(String dir, String name) async {
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var candidate = p.join(dir, name);
    for (var n = 2; await File(candidate).exists(); n++) {
      candidate = p.join(dir, '$stem ($n)$ext');
    }
    return candidate;
  }

  /// Opens [path] with the desktop's default app; false when there is none
  /// (no `xdg-open`, or it failed).
  Future<bool> open(String path) async {
    try {
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}

/// A file name for sharing [notePath] with [extension]: its display name,
/// minus characters other apps choke on.
String shareFileName(String displayName, String extension) {
  final safe = displayName.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  return '${safe.isEmpty ? 'note' : safe}$extension';
}
