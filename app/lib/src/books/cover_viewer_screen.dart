import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/books/cover_editing.dart';
import 'package:kronoer/src/books/cover_processing.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// The Hero tag a Book's Cover flies with between Book info and full screen.
Object coverHeroTag(String bookId) => 'book-cover-$bookId';

/// A Book's Cover full screen on black, with pinch to zoom. The pen opens
/// the Cover sheet to replace or remove it.
class CoverViewerScreen extends ConsumerWidget {
  const CoverViewerScreen({required this.bookId, super.key});

  final String bookId;

  void _close(BuildContext context) =>
      context.canPop() ? context.pop() : context.go(Routes.bookInfo(bookId));

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final action = await showCoverSheet(context, canRemove: true);
    if (action == null || !context.mounted) return;

    if (action == CoverAction.remove) {
      // At once, without asking: only the picture is lost.
      final books = ref.read(bookRepositoryProvider);
      _close(context);
      await books.removeBookCover(bookId);
    } else {
      await pickCover(context, ref, bookId: bookId, source: action);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;
    final coverId = book?.coverId;

    return Theme(
      data: buildTheme(darkColorScheme),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: l10n.close,
            color: Colors.white,
            onPressed: () => _close(context),
            icon: const KIcon(KIcons.x),
          ),
          actions: [
            if (book != null)
              IconButton(
                tooltip: l10n.changeCover,
                color: Colors.white,
                onPressed: () => _change(context, ref),
                icon: const KIcon(KIcons.pen),
              ),
          ],
        ),
        body: book == null || coverId == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: kToolbarHeight),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: coverAspectRatio,
                      child: Hero(
                        tag: coverHeroTag(bookId),
                        child: BookCoverImage(
                          bookId: bookId,
                          coverId: coverId,
                          thumbnail: false,
                          semanticLabel: l10n.coverOf(book.name),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
