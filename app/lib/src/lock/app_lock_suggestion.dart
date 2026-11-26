import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/lock/app_lock.dart';
import 'package:kronoer/src/ui/banner.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How many Entries the user writes before the Book list suggests App lock:
/// by then there is something worth locking.
const appLockSuggestionEntries = 3;

/// Whether the Book list shows [AppLockSuggestion], given its [books] and
/// App lock's [lock].
bool showsAppLockSuggestion(List<BookSummary> books, AppLockState lock) =>
    lock.canSuggest &&
    books.fold(0, (sum, summary) => sum + summary.entryCount) >=
        appLockSuggestionEntries;

/// The Book list's card suggesting App lock. "Turn on" turns it on through
/// the same prompt as the switch in Settings; "Not now" closes the card for
/// good. A cancelled prompt leaves the card.
class AppLockSuggestion extends ConsumerWidget {
  const AppLockSuggestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(appLockProvider.notifier);

    return KBanner(
      tone: BannerTone.suggestion,
      icon: KIcons.fingerprintPattern,
      title: l10n.appLockSuggestionTitle,
      message: l10n.appLockSuggestionMessage,
      dismissLabel: l10n.appLockSuggestionLater,
      onDismiss: notifier.dismissSuggestion,
      actionLabel: l10n.appLockSuggestionTurnOn,
      onAction: () =>
          unawaited(notifier.turnOn(title: l10n.turnOnAppLockPrompt)),
    );
  }
}
