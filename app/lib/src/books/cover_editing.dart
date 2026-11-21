import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/cover_crop_screen.dart';
import 'package:kronoer/src/books/cover_processing.dart';
import 'package:kronoer/src/entries/photo_picker.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// What the Cover sheet offers.
enum CoverAction { gallery, camera, remove }

/// The Cover sheet: Galeri, Kamera, and, when [canRemove], Hapus sampul in
/// red. Null when closed without a choice.
Future<CoverAction?> showCoverSheet(
  BuildContext context, {
  required bool canRemove,
}) {
  final l10n = AppLocalizations.of(context);
  final error = Theme.of(context).colorScheme.error;

  return showModalBottomSheet<CoverAction>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const KIcon(KIcons.image),
            title: Text(l10n.gallery),
            onTap: () => Navigator.pop(context, CoverAction.gallery),
          ),
          ListTile(
            leading: const KIcon(KIcons.camera),
            title: Text(l10n.camera),
            onTap: () => Navigator.pop(context, CoverAction.camera),
          ),
          if (canRemove)
            ListTile(
              leading: KIcon(KIcons.bin, color: error),
              textColor: error,
              title: Text(l10n.removeCover),
              onTap: () => Navigator.pop(context, CoverAction.remove),
            ),
          const SizedBox(height: Space.s),
        ],
      ),
    ),
  );
}

/// Gets a photo from the gallery or the camera, lets the user frame it, and
/// saves it as the Book's Cover. Nothing changes when no photo is picked or
/// framing is cancelled.
Future<void> pickCover(
  BuildContext context,
  WidgetRef ref, {
  required String bookId,
  required CoverAction source,
}) async {
  assert(source != CoverAction.remove, 'Removing is not picking');
  // Read before waiting: the screen and its ref may be gone by then.
  final picker = ref.read(photoPickerProvider);
  final decode = ref.read(coverPhotoDecoderProvider);
  final process = ref.read(coverProcessorProvider);
  final books = ref.read(bookRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final unreadable = AppLocalizations.of(context).imageUnreadable;
  void tellUnreadable() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(unreadable)));

  final PickedPhoto? picked;
  try {
    picked = source == CoverAction.camera
        ? await picker.camera()
        : await picker.galleryPhoto();
  } on Exception catch (error) {
    debugPrint('No photo picked: $error');
    return;
  }
  if (picked == null) return;

  final ui.Image photo;
  try {
    photo = await decode(await picked.read());
  } on Exception catch (error) {
    debugPrint('The picked photo did not open: $error');
    tellUnreadable();
    return;
  } finally {
    unawaited(picked.discard());
  }

  if (!context.mounted) {
    photo.dispose();
    return;
  }
  // The crop screen owns the photo from here, and disposes it.
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CoverCropScreen(
        photo: photo,
        onDone: (frame) async {
          try {
            await books.setBookCover(bookId, await process(photo, frame));
          } on Object catch (error) {
            debugPrint('The Cover was not saved: $error');
            tellUnreadable();
          }
        },
      ),
    ),
  );
}
