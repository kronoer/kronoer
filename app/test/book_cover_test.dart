import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/books/book_cover.dart';
import 'package:kronoer/src/books/book_info_screen.dart';
import 'package:kronoer/src/books/book_list_screen.dart';
import 'package:kronoer/src/books/book_screen.dart';
import 'package:kronoer/src/books/cover_crop_screen.dart';
import 'package:kronoer/src/books/cover_processing.dart';
import 'package:kronoer/src/books/cover_viewer_screen.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/entries/photo_picker.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/card.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

class _Photo implements PickedPhoto {
  var discarded = false;

  @override
  Future<Uint8List> read() async => Uint8List.fromList([1]);

  @override
  Future<void> discard() async => discarded = true;
}

class _Picker implements PhotoPicker {
  _Photo? photo = _Photo();
  final asked = <String>[];

  @override
  Future<List<PickedPhoto>> gallery({required int limit}) async =>
      throw UnimplementedError('A Cover is one photo');

  @override
  Future<PickedPhoto?> galleryPhoto() async {
    asked.add('gallery');
    return photo;
  }

  @override
  Future<PickedPhoto?> camera() async {
    asked.add('camera');
    return photo;
  }
}

final _cover = ProcessedImage(
  full: Uint8List.fromList([2, 2]),
  thumbnail: Uint8List.fromList([2]),
);

void main() {
  final now = DateTime(2026, 11, 19, 14, 32);
  late InMemoryStore store;
  late _Picker picker;
  late Book book;

  /// The photo the decoder hands over: 300×400, already a Cover's shape.
  late ui.Image photo;

  /// Each frame the processor was asked to cut.
  late List<Rect> frames;

  /// Thrown by the decoder instead of decoding, when set.
  Exception? unreadable;

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    picker = _Picker();
    book = await store.createBook('Buku Saya');
    frames = [];
    unreadable = null;
  });
  tearDown(() => store.dispose());

  Future<Book> stored() async => (await store.watchBook(book.id).first)!;

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    photo = (await tester.runAsync(
      () => createTestImage(width: 300, height: 400),
    ))!;
    addTearDown(photo.dispose);
    tester.platformDispatcher.localesTestValue = [const Locale('id')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => now),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
          photoPickerProvider.overrideWithValue(picker),
          coverPhotoDecoderProvider.overrideWithValue((bytes) async {
            if (unreadable case final error?) throw error;
            return photo.clone();
          }),
          coverProcessorProvider.overrideWithValue((photo, frame) async {
            frames.add(frame);
            return _cover;
          }),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openBook(WidgetTester tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text(book.name));
    expect(find.byType(BookScreen), findsOneWidget);
  }

  Future<void> openInfo(WidgetTester tester) async {
    await openBook(tester);
    await tapAndSettle(tester, find.byTooltip('Info Book'));
    expect(find.byType(BookInfoScreen), findsOneWidget);
  }

  Future<void> openViewer(WidgetTester tester) async {
    await store.setBookCover(book.id, _cover);
    await openInfo(tester);
    await tapAndSettle(
      tester,
      find.bySemanticsLabel('Sampul, buka layar penuh'),
    );
    expect(find.byType(CoverViewerScreen), findsOneWidget);
  }

  Finder inAppBar(Finder finder) =>
      find.descendant(of: find.byType(AppBar), matching: finder);

  group('Book list', () {
    testWidgets('a Book without a Cover shows a tile with the Book icon', (
      tester,
    ) async {
      await pumpApp(tester);

      final thumbnail = find.byType(CoverThumbnail);
      expect(tester.getSize(thumbnail), const Size(48, 64));
      expect(
        find.descendant(of: thumbnail, matching: _kIcon(KIcons.book)),
        findsOneWidget,
      );
      expect(find.byType(BookCoverImage), findsNothing);
    });

    testWidgets('a Book with a Cover shows its thumbnail', (tester) async {
      await store.setBookCover(book.id, _cover);
      await pumpApp(tester);

      final image = tester.widget<BookCoverImage>(
        find.descendant(
          of: find.byType(CoverThumbnail),
          matching: find.byType(BookCoverImage),
        ),
      );
      expect(image.thumbnail, isTrue);
      expect(find.byType(BookListScreen), findsOneWidget);
    });

    testWidgets('the Books are plain rows, not cards', (tester) async {
      await pumpApp(tester);

      expect(find.byType(KCard), findsNothing);
    });
  });

  group('Book screen top bar', () {
    testWidgets('no mini Cover when the Book has none', (tester) async {
      await openBook(tester);

      expect(inAppBar(find.byType(CoverThumbnail)), findsNothing);
    });

    testWidgets('the mini Cover sits left of the name and opens Book info', (
      tester,
    ) async {
      await store.setBookCover(book.id, _cover);
      await openBook(tester);

      final mini = inAppBar(find.byType(CoverThumbnail));
      expect(tester.getSize(mini), const Size(24, 32));
      expect(
        tester.getTopRight(mini).dx,
        lessThan(tester.getTopLeft(inAppBar(find.text(book.name))).dx),
      );

      await tapAndSettle(tester, mini);
      expect(find.byType(BookInfoScreen), findsOneWidget);
    });
  });

  group('Book info', () {
    testWidgets('without a Cover, a tile offers Galeri and Kamera only', (
      tester,
    ) async {
      await openInfo(tester);

      await tapAndSettle(tester, find.text('Tambah sampul'));

      expect(find.text('Galeri'), findsOneWidget);
      expect(find.text('Kamera'), findsOneWidget);
      expect(find.text('Hapus sampul'), findsNothing);
    });

    testWidgets('a photo from the gallery is framed and saved', (tester) async {
      await openInfo(tester);
      await tapAndSettle(tester, find.text('Tambah sampul'));
      await tapAndSettle(tester, find.text('Galeri'));

      expect(picker.asked, ['gallery']);
      expect(picker.photo!.discarded, isTrue);
      expect(find.byType(CoverCropScreen), findsOneWidget);
      expect(find.text('Geser dan cubit untuk mengatur'), findsOneWidget);

      await tapAndSettle(tester, find.text('Selesai'));

      // The photo is already 3:4, so at first the frame holds all of it.
      final frame = frames.single;
      expect(frame.left, closeTo(0, 0.01));
      expect(frame.top, closeTo(0, 0.01));
      expect(frame.width, closeTo(300, 0.01));
      expect(frame.height, closeTo(400, 0.01));
      expect((await stored()).coverId, isNotNull);
      expect(find.byType(CoverCropScreen), findsNothing);
      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Tambah sampul'), findsNothing);
      expect(find.bySemanticsLabel('Sampul, buka layar penuh'), findsOneWidget);
    });

    testWidgets('a photo from the camera is framed too', (tester) async {
      await openInfo(tester);
      await tapAndSettle(tester, find.text('Tambah sampul'));
      await tapAndSettle(tester, find.text('Kamera'));

      expect(picker.asked, ['camera']);
      expect(find.byType(CoverCropScreen), findsOneWidget);
    });

    testWidgets('a pinch zooms in, so a smaller part is framed', (
      tester,
    ) async {
      await openInfo(tester);
      await tapAndSettle(tester, find.text('Tambah sampul'));
      await tapAndSettle(tester, find.text('Galeri'));

      final center = tester.getCenter(find.byType(CoverCropScreen));
      final one = await tester.startGesture(center - const Offset(40, 0));
      final two = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      await one.moveTo(center - const Offset(120, 0));
      await two.moveTo(center + const Offset(120, 0));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('Selesai'));

      final frame = frames.single;
      expect(frame.width, lessThan(300));
      expect(frame.width / frame.height, closeTo(coverAspectRatio, 0.001));
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(300.01));
    });

    testWidgets('closing the frame saves nothing', (tester) async {
      await openInfo(tester);
      await tapAndSettle(tester, find.text('Tambah sampul'));
      await tapAndSettle(tester, find.text('Galeri'));

      await tapAndSettle(tester, find.byTooltip('Batal'));

      expect(frames, isEmpty);
      expect((await stored()).coverId, isNull);
      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Tambah sampul'), findsOneWidget);
    });

    testWidgets('no photo picked changes nothing', (tester) async {
      picker.photo = null;
      await openInfo(tester);
      await tapAndSettle(tester, find.text('Tambah sampul'));
      await tapAndSettle(tester, find.text('Galeri'));

      expect(find.byType(CoverCropScreen), findsNothing);
      expect((await stored()).coverId, isNull);
    });

    testWidgets('a photo that does not open says so', (tester) async {
      unreadable = const UnreadableImage('not a photo');
      await openInfo(tester);
      await tapAndSettle(tester, find.text('Tambah sampul'));
      await tapAndSettle(tester, find.text('Galeri'));

      expect(find.byType(CoverCropScreen), findsNothing);
      expect(find.text('Foto tidak bisa dibuka'), findsOneWidget);
      expect(picker.photo!.discarded, isTrue);
    });

    testWidgets('the Cover is shown large, 192×256', (tester) async {
      await store.setBookCover(book.id, _cover);
      await openInfo(tester);

      final image = find.byType(BookCoverImage);
      expect(tester.getSize(image), const Size(192, 256));
      expect(tester.widget<BookCoverImage>(image).thumbnail, isFalse);
    });

    testWidgets('the Cover rises into the top bar, level with its buttons', (
      tester,
    ) async {
      await store.setBookCover(book.id, _cover);
      await openInfo(tester);

      final cover = tester.getRect(find.byType(BookCoverImage));
      final back = tester.getRect(find.byType(BackButton));
      expect(cover.top, 24);
      expect(cover.top, lessThan(back.bottom));
      expect(cover.left, greaterThan(back.right));

      // The bar is clear: a tap on the Cover's top edge reaches it.
      await tester.tapAt(cover.topCenter.translate(0, 8));
      await tester.pumpAndSettle();
      expect(find.byType(CoverViewerScreen), findsOneWidget);
    });
  });

  group('full screen', () {
    testWidgets('tapping the Cover on Book info opens it on black', (
      tester,
    ) async {
      await openViewer(tester);

      final scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(CoverViewerScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.backgroundColor, Colors.black);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final image = tester.widget<BookCoverImage>(find.byType(BookCoverImage));
      expect(image.thumbnail, isFalse);
      expect(image.semanticLabel, 'Sampul Buku Saya');
      expect(find.byType(BookCoverImage), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Tutup'));
      expect(find.byType(CoverViewerScreen), findsNothing);
      expect(find.byType(BookInfoScreen), findsOneWidget);
    });

    testWidgets('the pen offers Galeri, Kamera, and Hapus sampul in red', (
      tester,
    ) async {
      await openViewer(tester);

      await tapAndSettle(tester, find.byTooltip('Ubah sampul'));

      expect(find.text('Galeri'), findsOneWidget);
      expect(find.text('Kamera'), findsOneWidget);
      final remove = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Hapus sampul'),
          matching: find.byType(ListTile),
        ),
      );
      final context = tester.element(find.text('Hapus sampul'));
      expect(remove.textColor, Theme.of(context).colorScheme.error);
    });

    testWidgets('Hapus sampul removes it at once, back on Book info', (
      tester,
    ) async {
      await openViewer(tester);
      await tapAndSettle(tester, find.byTooltip('Ubah sampul'));

      await tapAndSettle(tester, find.text('Hapus sampul'));

      expect((await stored()).coverId, isNull);
      expect(find.byType(CoverViewerScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BookInfoScreen), findsOneWidget);
      expect(find.text('Tambah sampul'), findsOneWidget);
    });

    testWidgets('a new Cover from the pen replaces the old one', (
      tester,
    ) async {
      await openViewer(tester);
      final first = (await stored()).coverId;
      await tapAndSettle(tester, find.byTooltip('Ubah sampul'));
      await tapAndSettle(tester, find.text('Galeri'));

      await tapAndSettle(tester, find.text('Selesai'));

      final second = (await stored()).coverId;
      expect(second, isNotNull);
      expect(second, isNot(first));
      expect(find.byType(CoverViewerScreen), findsOneWidget);
    });
  });
}
