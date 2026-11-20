import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/theme/colors.dart';
import 'package:kronoer/src/theme/theme.dart';
import 'package:kronoer/src/ui/banner.dart';
import 'package:kronoer/src/ui/buttons.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/empty_state.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

const _light = lightColorScheme;
const _dark = darkColorScheme;

Widget _app(Widget child, {ColorScheme scheme = _light}) => MaterialApp(
  theme: buildTheme(scheme),
  home: Scaffold(body: child),
);

/// The outermost [Material] a widget builds, which carries its color and shape.
Material _surfaceOf(WidgetTester tester, Type widget) =>
    tester.widget<Material>(
      find
          .descendant(of: find.byType(widget), matching: find.byType(Material))
          .first,
    );

TextTheme _textTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold))).textTheme;

void main() {
  group('KCard', () {
    testWidgets('the whole card is the tap target', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(KCard(onTap: () => taps++, child: const Text('Buku Saya'))),
      );

      // Tap the right side of the card, away from its text. Not a corner:
      // the rounded corners are clipped, so taps there miss the card.
      await tester.tapAt(
        tester.getRect(find.byType(KCard)).centerRight - const Offset(24, 0),
      );
      expect(taps, 1);
    });

    testWidgets('sits on surfaceContainerLow, radius 20, padding 16', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const KCard(child: Text('Buku Saya'))));

      final surface = _surfaceOf(tester, KCard);
      expect(surface.color, _light.surfaceContainerLow);
      expect(
        surface.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
      expect(
        find.descendant(
          of: find.byType(KCard),
          matching: find.byWidgetPredicate(
            (w) => w is Padding && w.padding == const EdgeInsets.all(16),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('KBanner', () {
    Widget banner({
      BannerTone tone = BannerTone.neutral,
      VoidCallback? onDismiss,
      VoidCallback? onAction,
    }) => KBanner(
      icon: KIcons.download,
      title: 'Sudah 30 hari belum ekspor',
      message: 'Ada 12 Entry baru sejak ekspor terakhir.',
      dismissLabel: 'Nanti',
      onDismiss: onDismiss ?? () {},
      actionLabel: 'Ekspor',
      onAction: onAction ?? () {},
      tone: tone,
    );

    testWidgets('neutral sits on surfaceContainerHigh with muted text', (
      tester,
    ) async {
      await tester.pumpWidget(_app(banner()));

      expect(_surfaceOf(tester, KBanner).color, _light.surfaceContainerHigh);
      expect(
        tester
            .widget<Text>(find.text('Ada 12 Entry baru sejak ekspor terakhir.'))
            .style
            ?.color,
        _light.onSurfaceVariant,
      );
      expect(tester.widget<KIcon>(find.byType(KIcon)).color, _light.primary);
    });

    testWidgets('suggestion sits on primaryContainer', (tester) async {
      await tester.pumpWidget(_app(banner(tone: BannerTone.suggestion)));

      expect(_surfaceOf(tester, KBanner).color, _light.primaryContainer);
      expect(
        tester
            .widget<Text>(find.text('Ada 12 Entry baru sejak ekspor terakhir.'))
            .style
            ?.color,
        _light.onPrimaryContainer,
      );
    });

    testWidgets('title is titleMedium, message is bodyMedium', (tester) async {
      await tester.pumpWidget(_app(banner()));
      final text = _textTheme(tester);

      final title = tester.widget<Text>(
        find.text('Sudah 30 hari belum ekspor'),
      );
      final message = tester.widget<Text>(
        find.text('Ada 12 Entry baru sejak ekspor terakhir.'),
      );
      expect(title.style?.fontSize, text.titleMedium!.fontSize);
      expect(title.style?.fontWeight, text.titleMedium!.fontWeight);
      expect(message.style?.fontSize, text.bodyMedium!.fontSize);
      expect(message.style?.fontWeight, text.bodyMedium!.fontWeight);
    });

    testWidgets('each button calls its own callback', (tester) async {
      var dismissed = 0;
      var acted = 0;
      await tester.pumpWidget(
        _app(banner(onDismiss: () => dismissed++, onAction: () => acted++)),
      );

      await tester.tap(find.text('Nanti'));
      expect((dismissed, acted), (1, 0));

      await tester.tap(find.text('Ekspor'));
      expect((dismissed, acted), (1, 1));
    });
  });

  group('EmptyState', () {
    String ringsAsset(WidgetTester tester) =>
        (tester.widget<VectorGraphic>(find.byType(VectorGraphic)).loader
                as AssetBytesLoader)
            .assetName;

    const emptyState = EmptyState(
      title: 'Belum ada Entry',
      message: 'Tulis Entry pertama di Book ini.',
    );

    testWidgets('shows the title and the help line', (tester) async {
      await tester.pumpWidget(_app(emptyState));

      expect(find.text('Belum ada Entry'), findsOneWidget);
      expect(find.text('Tulis Entry pertama di Book ini.'), findsOneWidget);
    });

    testWidgets('uses the light rings in light mode', (tester) async {
      await tester.pumpWidget(_app(emptyState));
      expect(ringsAsset(tester), 'assets/brand/rings.vec');
    });

    testWidgets('uses the dark rings in dark mode', (tester) async {
      await tester.pumpWidget(_app(emptyState, scheme: _dark));
      expect(ringsAsset(tester), 'assets/brand/rings_dark.vec');
    });
  });

  group('destructive styles', () {
    test('text button and menu item use the error color', () {
      expect(
        destructiveTextButton(_light).foregroundColor?.resolve({}),
        _light.error,
      );
      final menuItem = destructiveMenuItem(_light);
      expect(menuItem.foregroundColor?.resolve({}), _light.error);
      expect(menuItem.iconColor?.resolve({}), _light.error);
    });
  });

  group('buildTheme', () {
    final theme = buildTheme(_light);

    test('text fields are outlined, radius 4, with a 2 dp error border', () {
      final fields = theme.inputDecorationTheme;
      expect(fields.enabledBorder, isA<OutlineInputBorder>());
      expect(
        (fields.enabledBorder! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(4),
      );
      expect(
        fields.focusedBorder!.borderSide,
        BorderSide(color: _light.primary, width: 2),
      );
      expect(
        fields.errorBorder!.borderSide,
        BorderSide(color: _light.error, width: 2),
      );
    });

    test('dialogs dim the screen with a 40% black scrim', () {
      expect(
        theme.dialogTheme.barrierColor,
        Colors.black.withValues(alpha: 0.4),
      );
    });

    test('snackbars float, radius 8', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(
        theme.snackBarTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
    });

    test('menus have radius 8', () {
      expect(
        theme.menuTheme.style?.shape?.resolve({}),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
    });
  });
}
