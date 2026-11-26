import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/ui/wordmark.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// First launch: "Let's start writing" creates the first Book and opens the
/// editor for its first Entry. "Have an archive? Import" opens the Import page
/// instead, for someone moving to a new phone.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  var _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);

    final name = AppLocalizations.of(context).firstBookName;
    final router = GoRouter.of(context);
    final book = await ref.read(bookRepositoryProvider).createBook(name);

    ref.read(hasStartedProvider.notifier).markStarted();
    router.go(Routes.firstEntry(book.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.xl,
            Space.xl,
            Space.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      spacing: 20,
                      children: [
                        ExcludeSemantics(
                          child: VectorGraphic(
                            loader: AssetBytesLoader(
                              isDark
                                  ? 'assets/illustrations/tree_ring_book_dark.vec'
                                  : 'assets/illustrations/tree_ring_book.vec',
                            ),
                            width: 342,
                          ),
                        ),
                        const Wordmark(height: 60),
                        Column(
                          spacing: Space.s,
                          children: [
                            Text(
                              l10n.welcomeTitle,
                              style: theme.textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              l10n.welcomeMessage,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: muted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: Space.s,
                children: [
                  KIcon(KIcons.lock, size: 16, color: muted),
                  Flexible(
                    child: Text(
                      l10n.welcomeEncrypted,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: _starting ? null : _start,
                child: Text(l10n.welcomeStart),
              ),
              const SizedBox(height: Space.m),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      l10n.welcomeHaveArchive,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.square(Space.touch),
                      padding: const EdgeInsets.symmetric(horizontal: Space.s),
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: _starting
                        ? null
                        : () => context.go(Routes.welcomeImport),
                    child: Text(l10n.welcomeImport),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
