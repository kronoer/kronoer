import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:material_ui/material_ui.dart';

/// Whether [entry] has text to copy: an Entry of Images only has none.
bool hasText(Entry entry) => entry.text.trim().isNotEmpty;

/// The text of [entries] as copied, in the order given: each one's [dateLine]
/// of its Entry date, a blank line, then its text as [plainText], with two
/// blank lines between Entries. Entries with no text are left out.
String copiedText(
  Iterable<Entry> entries,
  String Function(DateTime dateTime) dateLine,
) => [
  for (final entry in entries)
    if (hasText(entry))
      '${dateLine(entry.dateTime)}\n\n${plainText(entry.text)}',
].join('\n\n\n');

/// What became of copying text.
enum CopyResult {
  /// On the clipboard, with nothing on screen to say so.
  copied,

  /// On the clipboard, and the system shows its own preview of it, as
  /// Android 13 and higher do.
  copiedWithPreview,

  /// Too large for the clipboard: nothing was copied.
  tooLong,
}

/// Puts text on the system clipboard.
abstract interface class TextClipboard {
  /// Copies [text], marked sensitive: Android 13 and higher then hide it in
  /// their clipboard preview, and keyboards do not offer it.
  Future<CopyResult> copySensitive(String text);
}

final textClipboardProvider = Provider<TextClipboard>(
  (ref) => PlatformClipboard(),
);

/// The device's clipboard. On Android a small platform channel copies, since
/// Flutter's [Clipboard.setData] cannot mark a clip sensitive; elsewhere, as
/// in tests on the host, it is [Clipboard.setData].
class PlatformClipboard implements TextClipboard {
  PlatformClipboard({bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  final bool _isAndroid;

  static const channel = MethodChannel('app.kronoer/clipboard');

  /// The most UTF-16 code units copied at once. A clip goes to the system in
  /// one binder transaction, which holds about 1 MB, two bytes a code unit.
  static const maxLength = 450 * 1024;

  @override
  Future<CopyResult> copySensitive(String text) async {
    if (text.length > maxLength) return CopyResult.tooLong;
    if (!_isAndroid) {
      await Clipboard.setData(ClipboardData(text: text));
      return CopyResult.copied;
    }
    final result = await channel.invokeMethod<String>('copySensitive', text);
    return switch (result) {
      'copiedWithPreview' => CopyResult.copiedWithPreview,
      'tooLong' => CopyResult.tooLong,
      _ => CopyResult.copied,
    };
  }
}

/// Copies the text of [entries], in the order given, and says so where the
/// system does not. Returns whether it was copied.
///
/// With [several], as from selection mode, text too long to copy asks for
/// fewer Entries.
Future<bool> copyEntriesText(
  BuildContext context,
  WidgetRef ref,
  List<Entry> entries, {
  bool several = true,
}) async {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toString();
  final messenger = ScaffoldMessenger.of(context);
  final date = DateFormat.yMMMMEEEEd(locale);
  final time = DateFormat.Hm(locale);

  final text = copiedText(
    entries,
    (dateTime) =>
        l10n.copiedEntryDate(date.format(dateTime), time.format(dateTime)),
  );
  final result = await ref.read(textClipboardProvider).copySensitive(text);

  void say(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), persist: false));

  switch (result) {
    case CopyResult.copiedWithPreview:
      break;
    case CopyResult.copied:
      say(l10n.textCopied(entries.where(hasText).length));
    case CopyResult.tooLong:
      say(several ? l10n.copyTooLong : l10n.copyTooLongEntry);
  }
  return result != CopyResult.tooLong;
}
