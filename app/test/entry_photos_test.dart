import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/rendering.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/app.dart';
import 'package:kronoer/src/books/book.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_editor_screen.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/entries/photo_picker.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:kronoer/src/welcome/has_started.dart';
import 'package:material_ui/material_ui.dart';

Finder _kIcon(KIcons icon) =>
    find.byWidgetPredicate((w) => w is KIcon && w.icon == icon);

class _Photo implements PickedPhoto {
  _Photo(int byte) : bytes = Uint8List.fromList([byte]);

  final Uint8List bytes;
  var discarded = false;

  @override
  Future<Uint8List> read() async => bytes;

  @override
  Future<void> discard() async => discarded = true;
}

class _Picker implements PhotoPicker {
  var photos = <_Photo>[];
  int? limitAsked;

  /// When set, the picker answers only once this completes, like a picker
  /// that takes a moment to open.
  Completer<void>? opening;

  /// Thrown instead of answering.
  Exception? failure;

  Future<void> _open() async {
    await opening?.future;
    if (failure case final failure?) throw failure;
  }

  @override
  Future<List<PickedPhoto>> gallery({required int limit}) async {
    limitAsked = limit;
    await _open();
    return photos;
  }

  @override
  Future<PickedPhoto?> galleryPhoto() async {
    await _open();
    return photos.firstOrNull;
  }

  @override
  Future<PickedPhoto?> camera() async {
    await _open();
    return photos.firstOrNull;
  }
}

/// Prepares a photo as its one byte, repeated: full twice, thumbnail once.
Future<ProcessedImage> _prepare(Uint8List bytes) async {
  final byte = bytes.single;
  if (byte == 0) throw const UnreadableImage('not a photo');
  return ProcessedImage(
    full: Uint8List.fromList([byte, byte]),
    thumbnail: Uint8List.fromList([byte]),
  );
}

void main() {
  final now = DateTime(2026, 11, 19, 14, 32);
  late InMemoryStore store;
  late _Picker picker;
  late Book book;

  setUp(() async {
    store = InMemoryStore(clock: () => now);
    picker = _Picker();
    book = await store.createBook('My Book');
  });
  tearDown(() => store.dispose());

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    Future<ProcessedImage> Function(Uint8List)? prepare,
  }) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => now),
          hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
          photoPickerProvider.overrideWithValue(picker),
          imageProcessorProvider.overrideWithValue(prepare ?? _prepare),
        ],
        child: const KronoerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> writeNew(
    WidgetTester tester, {
    Future<ProcessedImage> Function(Uint8List)? prepare,
  }) async {
    await pumpApp(tester, prepare: prepare);
    await tapAndSettle(tester, find.text(book.name));
    await tapAndSettle(tester, find.byType(FloatingActionButton));
    expect(find.byType(EntryEditorScreen), findsOneWidget);
  }

  Future<void> edit(WidgetTester tester, String text) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text(book.name));
    await tapAndSettle(tester, find.text(text));
    await tapAndSettle(tester, _kIcon(KIcons.pen));
  }

  /// Without [settle], only lets the sheet close: a photo still being
  /// prepared animates without end.
  Future<void> pickFromGallery(
    WidgetTester tester,
    List<_Photo> photos, {
    bool settle = true,
  }) async {
    picker.photos = photos;
    await tapAndSettle(tester, find.text('Add a photo'));
    await tester.tap(find.text('Gallery'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> autosave(WidgetTester tester) async {
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
  }

  Future<Entry> onlyEntry() async =>
      (await store.watchEntries(book.id).first).single;

  /// The thumbnail bytes of each of [entry]'s Images, in order.
  Future<List<int>> thumbnails(Entry entry) async => [
    for (final id in entry.imageIds)
      (await store.image(entry.id, id, thumbnail: true)).single,
  ];

  Finder removeButtons() => find.bySemanticsLabel('Remove photo');

  testWidgets('photos from the gallery are added and saved in order', (
    tester,
  ) async {
    await writeNew(tester);
    final photos = [_Photo(1), _Photo(2), _Photo(3)];

    await pickFromGallery(tester, photos);
    expect(picker.limitAsked, maxImages);
    expect(removeButtons(), findsNWidgets(3));
    expect(find.text('3/20'), findsOneWidget);

    await autosave(tester);
    final entry = await onlyEntry();
    expect(await thumbnails(entry), [1, 2, 3]);
    expect(
      await store.image(entry.id, entry.imageIds.first, thumbnail: false),
      [1, 1],
    );
    // Each picked file is deleted once prepared.
    expect(photos.map((p) => p.discarded), everyElement(isTrue));
  });

  testWidgets('a photo from the camera is added', (tester) async {
    await writeNew(tester);
    picker.photos = [_Photo(7)];

    await tapAndSettle(tester, find.text('Add a photo'));
    await tapAndSettle(tester, find.text('Camera'));
    await autosave(tester);

    expect(await thumbnails(await onlyEntry()), [7]);
    expect(picker.photos.single.discarded, isTrue);
  });

  testWidgets('an Entry with photos and no text is kept', (tester) async {
    await writeNew(tester);
    await pickFromGallery(tester, [_Photo(1)]);

    await tapAndSettle(tester, find.text('Done'));

    final entry = await onlyEntry();
    expect(entry.text, isEmpty);
    expect(entry.imageIds, hasLength(1));
  });

  testWidgets('each photo shows as loading until it is ready', (tester) async {
    final ready = Completer<void>();
    await writeNew(
      tester,
      prepare: (bytes) async {
        await ready.future;
        return _prepare(bytes);
      },
    );

    await pickFromGallery(tester, [_Photo(1)], settle: false);
    expect(find.bySemanticsLabel('Preparing photo'), findsOneWidget);
    await tester.pump(autosaveDelay * 2);
    expect(await store.watchEntries(book.id).first, isEmpty);

    ready.complete();
    await tester.pump();
    expect(find.bySemanticsLabel('Preparing photo'), findsNothing);
    await autosave(tester);
    expect(await thumbnails(await onlyEntry()), [1]);
  });

  group('while the picker opens', () {
    final waitingTile = find.byKey(const ValueKey('waiting'));

    /// Taps [source] in the sheet and lets the sheet close, with the picker
    /// still opening.
    Future<void> open(WidgetTester tester, String source) async {
      picker.opening = Completer();
      await tapAndSettle(tester, find.text('Add a photo'));
      await tester.tap(find.text(source));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    /// The picker answers; the photos it gave are prepared at once.
    Future<void> answer(WidgetTester tester) async {
      picker.opening!.complete();
      await tester.pumpAndSettle();
    }

    testWidgets('a waiting tile stands in until the gallery answers', (
      tester,
    ) async {
      await writeNew(tester);
      picker.photos = [_Photo(1), _Photo(2)];

      await open(tester, 'Gallery');
      expect(waitingTile, findsOneWidget);
      expect(find.bySemanticsLabel('Preparing photo'), findsOneWidget);
      // It is no Image: nothing to take out, and not counted.
      expect(removeButtons(), findsNothing);
      expect(find.text('2/20'), findsNothing);
      await tester.pump(autosaveDelay * 2);
      expect(await store.watchEntries(book.id).first, isEmpty);

      await answer(tester);
      expect(waitingTile, findsNothing);
      expect(removeButtons(), findsNWidgets(2));
      await autosave(tester);
      expect(await thumbnails(await onlyEntry()), [1, 2]);
    });

    testWidgets('it turns into the photo taken with the camera', (
      tester,
    ) async {
      await writeNew(tester);
      picker.photos = [_Photo(5)];

      await open(tester, 'Camera');
      expect(waitingTile, findsOneWidget);

      await answer(tester);
      expect(waitingTile, findsNothing);
      expect(removeButtons(), findsOneWidget);
    });

    testWidgets('it goes away when nothing is picked', (tester) async {
      await writeNew(tester);

      await open(tester, 'Camera');
      expect(waitingTile, findsOneWidget);

      await answer(tester);
      expect(waitingTile, findsNothing);
      expect(removeButtons(), findsNothing);
    });

    testWidgets('it goes away when the picker fails', (tester) async {
      await writeNew(tester);
      picker.failure = Exception('no picker');

      await open(tester, 'Gallery');
      expect(waitingTile, findsOneWidget);

      await answer(tester);
      expect(waitingTile, findsNothing);
      expect(removeButtons(), findsNothing);
    });

    testWidgets('it follows the photos already there', (tester) async {
      await writeNew(tester);
      await pickFromGallery(tester, [_Photo(1)]);

      await open(tester, 'Gallery');
      final kept = tester.getRect(find.byType(Image).first);
      expect(tester.getRect(waitingTile).left, greaterThan(kept.right));

      await answer(tester);
    });
  });

  testWidgets('leaving waits for photos still being prepared', (tester) async {
    final ready = Completer<void>();
    await writeNew(
      tester,
      prepare: (bytes) async {
        await ready.future;
        return _prepare(bytes);
      },
    );
    await pickFromGallery(tester, [_Photo(4)], settle: false);

    await tester.tap(find.text('Done'));
    await tester.pump();
    ready.complete();
    await tester.pumpAndSettle();

    expect(await thumbnails(await onlyEntry()), [4]);
  });

  testWidgets('a photo that cannot be read is not added', (tester) async {
    await writeNew(tester);

    await pickFromGallery(tester, [_Photo(0)]);

    expect(find.text('This photo couldn\'t be added.'), findsOneWidget);
    expect(removeButtons(), findsNothing);
    expect(picker.photos.single.discarded, isTrue);
  });

  group('the 20-photo limit', () {
    Future<void> withImages(int count) => store.createEntry(
      bookId: book.id,
      text: 'Banyak foto.',
      images: [
        for (var i = 1; i <= count; i++)
          NewImage(
            ProcessedImage(
              full: Uint8List.fromList([i]),
              thumbnail: Uint8List.fromList([i]),
            ),
          ),
      ],
    );

    testWidgets('the gallery picks only as many as are left', (tester) async {
      await withImages(18);
      await edit(tester, 'Banyak foto.');
      expect(find.text('18/20'), findsOneWidget);
      final photos = [_Photo(31), _Photo(32), _Photo(33)];

      await pickFromGallery(tester, photos);
      await autosave(tester);

      expect(picker.limitAsked, 2);
      expect(find.text('20/20'), findsOneWidget);
      final entry = await onlyEntry();
      expect(entry.imageIds, hasLength(maxImages));
      expect((await thumbnails(entry)).skip(18), [31, 32]);
      // The one too many is dropped and its file deleted all the same.
      expect(photos.map((p) => p.discarded), everyElement(isTrue));
    });

    testWidgets('at 20 the button explains the limit', (tester) async {
      await withImages(maxImages);
      await edit(tester, 'Banyak foto.');

      await tapAndSettle(tester, find.text('Add a photo'));

      expect(find.text('Gallery'), findsNothing);
      expect(find.text('An Entry can hold up to 20 photos.'), findsOneWidget);
    });
  });

  group('editing', () {
    late Entry entry;

    setUp(() async {
      entry = await store.createEntry(
        bookId: book.id,
        text: 'Tiga foto.',
        images: [
          for (final byte in [1, 2, 3])
            NewImage(
              ProcessedImage(
                full: Uint8List.fromList([byte, byte]),
                thumbnail: Uint8List.fromList([byte]),
              ),
            ),
        ],
      );
    });

    testWidgets('× takes a photo out', (tester) async {
      await edit(tester, 'Tiga foto.');

      await tapAndSettle(tester, removeButtons().at(1));
      await autosave(tester);

      expect(await thumbnails(await onlyEntry()), [1, 3]);
    });

    testWidgets('a photo is moved by dragging it', (tester) async {
      await edit(tester, 'Tiga foto.');
      final first = tester.getCenter(find.byType(EntryImage).first);

      final drag = await tester.startGesture(first);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      // Past both other photos (96 wide, 8 apart).
      for (var i = 0; i < 3; i++) {
        await drag.moveBy(const Offset(100, 0));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
      await autosave(tester);

      expect(await thumbnails(await onlyEntry()), [2, 3, 1]);
    });

    group('a lifted photo', () {
      /// What the app asked the device to vibrate.
      List<String> haptics(WidgetTester tester) {
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              calls.add(call.arguments as String? ?? 'longPress');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        return calls;
      }

      Future<TestGesture> lift(WidgetTester tester) async {
        final drag = await tester.startGesture(
          tester.getCenter(find.byType(EntryImage).first),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        // Past the 150 ms it grows over.
        await tester.pump(const Duration(milliseconds: 200));
        return drag;
      }

      Finder lifted() => find.byKey(const ValueKey('lifted'));

      double scale(WidgetTester tester) => tester
          .widget<Transform>(
            find.ancestor(of: lifted(), matching: find.byType(Transform)).first,
          )
          .transform
          .getMaxScaleOnAxis();

      testWidgets('vibrates on lift, ticks per new place, not on drop', (
        tester,
      ) async {
        await edit(tester, 'Tiga foto.');
        final calls = haptics(tester);

        final drag = await lift(tester);
        expect(calls, ['longPress']);

        // Past the second photo, then the third; no further place after.
        for (var i = 0; i < 3; i++) {
          await drag.moveBy(const Offset(100, 0));
          await tester.pump();
        }
        expect(calls, [
          'longPress',
          'HapticFeedbackType.selectionClick',
          'HapticFeedbackType.selectionClick',
        ]);

        await drag.up();
        await tester.pumpAndSettle();
        expect(calls, hasLength(3));
      });

      testWidgets('grows with a soft rounded shadow and no ×', (tester) async {
        await edit(tester, 'Tiga foto.');

        final drag = await lift(tester);

        expect(lifted(), findsOneWidget);
        expect(scale(tester), closeTo(1.05, 0.001));
        final shadow = tester.widget<DecoratedBox>(
          find
              .ancestor(of: lifted(), matching: find.byType(DecoratedBox))
              .first,
        );
        final decoration = shadow.decoration as BoxDecoration;
        expect(decoration.borderRadius, isNotNull);
        expect(decoration.boxShadow, isNotEmpty);
        expect(
          find.descendant(of: lifted(), matching: _kIcon(KIcons.x)),
          findsNothing,
        );

        await drag.up();
        await tester.pumpAndSettle();
        expect(lifted(), findsNothing);
        expect(removeButtons(), findsNWidgets(3));
      });

      testWidgets('with reduced motion it does not grow', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await edit(tester, 'Tiga foto.');

        final drag = await lift(tester);

        expect(scale(tester), 1);
        final shadow = tester.widget<DecoratedBox>(
          find
              .ancestor(of: lifted(), matching: find.byType(DecoratedBox))
              .first,
        );
        expect((shadow.decoration as BoxDecoration).boxShadow, isNotEmpty);

        await drag.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('TalkBack moves a photo with the move actions', (tester) async {
      final semantics = tester.ensureSemantics();
      await edit(tester, 'Tiga foto.');

      List<String> actions(int index) => [
        for (final action
            in tester
                    .getSemantics(find.byType(EntryImage).at(index))
                    .getSemanticsData()
                    .customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(action)!.label!,
      ];

      expect(actions(0), unorderedEquals(['Move right', 'Move to the end']));
      expect(
        actions(1),
        unorderedEquals([
          'Move to the start',
          'Move left',
          'Move right',
          'Move to the end',
        ]),
      );
      expect(actions(2), unorderedEquals(['Move to the start', 'Move left']));

      final first = tester.getSemantics(find.byType(EntryImage).first);
      final toEnd = first
          .getSemanticsData()
          .customSemanticsActionIds!
          .firstWhere(
            (id) =>
                CustomSemanticsAction.getAction(id)!.label == 'Move to the end',
          );
      first.owner!.performAction(first.id, SemanticsAction.customAction, toEnd);
      await tester.pumpAndSettle();
      await autosave(tester);

      expect(await thumbnails(await onlyEntry()), [2, 3, 1]);
      semantics.dispose();
    });

    testWidgets('editing the text keeps the same Images', (tester) async {
      await edit(tester, 'Tiga foto.');

      await tester.enterText(find.byType(TextField), 'Tiga foto, diedit.');
      await autosave(tester);

      final edited = await onlyEntry();
      expect(edited.text, 'Tiga foto, diedit.');
      expect(edited.imageIds, entry.imageIds);
    });

    testWidgets('new photos join kept ones, and reopening shows the same '
        'order', (tester) async {
      await edit(tester, 'Tiga foto.');
      await pickFromGallery(tester, [_Photo(4)]);
      await tapAndSettle(tester, removeButtons().first);
      await tapAndSettle(tester, find.text('Done'));

      final saved = await onlyEntry();
      expect(await thumbnails(saved), [2, 3, 4]);
      expect(saved.imageIds.take(2), entry.imageIds.skip(1));

      await tapAndSettle(tester, _kIcon(KIcons.pen));
      final shown = tester
          .widgetList<EntryImage>(find.byType(EntryImage))
          .map((image) => image.imageId);
      expect(shown, saved.imageIds);
    });
  });

  testWidgets('an Image that cannot be opened shows as broken', (tester) async {
    await store.createEntry(
      bookId: book.id,
      text: 'Foto rusak.',
      imageIds: ['hilang'],
    );
    await pumpApp(tester);

    await tapAndSettle(tester, find.text(book.name));
    // The repository read runs outside the test's fake time.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.byType(BrokenImage), findsOneWidget);
    expect(find.text('Foto rusak.'), findsOneWidget);
  });

  group('the time a photo was taken', () {
    /// When each test photo was taken, by its byte; now is Kamis, 19 Nov
    /// 2026 · 14.32.
    final taken = {
      1: DateTime(2026, 11, 14, 16, 20),
      2: DateTime(2026, 11, 13, 9, 5),
      // 3 has none.
      4: DateTime(2026, 11, 19, 14),
      5: DateTime(2026, 11, 21, 10),
    };

    Future<ProcessedImage> prepareTaken(Uint8List bytes) async {
      final image = await _prepare(bytes);
      return ProcessedImage(
        full: image.full,
        thumbnail: image.thumbnail,
        timeTaken: taken[bytes.single],
      );
    }

    Finder popover() => find.byKey(const ValueKey('timeTaken'));
    Finder offer(String date) => find.text('Photo taken $date');
    const sabtu = 'Saturday, 14 Nov 2026 · 16:20';
    const today = 'Thursday, 19 Nov 2026 · 14:32';

    testWidgets('is offered under the date chip, and Use sets the date', (
      tester,
    ) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      expect(offer(sabtu), findsOneWidget);
      expect(find.text('Use it as this Entry\'s date?'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      final chip = tester.getRect(
        find.ancestor(
          of: find.text(today),
          matching: find.byType(OutlinedButton),
        ),
      );
      final card = tester.getRect(popover());
      expect(card.top, greaterThan(chip.bottom));
      expect(card.top - chip.bottom, lessThan(16));
      expect(card.left, lessThanOrEqualTo(chip.left));

      await tapAndSettle(tester, find.text('Use'));
      expect(popover(), findsNothing);
      expect(find.text(sabtu), findsOneWidget);

      await autosave(tester);
      expect((await onlyEntry()).dateTime, DateTime(2026, 11, 14, 16, 20));
    });

    testWidgets('Dismiss closes it for this Entry, and keeps the date', (
      tester,
    ) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await tapAndSettle(tester, find.text('Dismiss'));
      expect(popover(), findsNothing);
      expect(find.text(today), findsOneWidget);

      // Not again, even for an earlier photo.
      await pickFromGallery(tester, [_Photo(2)]);
      expect(popover(), findsNothing);
      await autosave(tester);
      expect((await onlyEntry()).dateTime, now);
    });

    testWidgets('with several photos it is the earliest, and a photo ready '
        'later, taken earlier, moves it', (tester) async {
      final slow = Completer<void>();
      await writeNew(
        tester,
        prepare: (bytes) async {
          if (bytes.single == 2) await slow.future;
          return prepareTaken(bytes);
        },
      );
      await pickFromGallery(tester, [
        _Photo(3),
        _Photo(1),
        _Photo(2),
      ], settle: false);
      expect(offer(sabtu), findsOneWidget);

      slow.complete();
      await tester.pumpAndSettle();
      expect(offer(sabtu), findsNothing);
      expect(offer('Friday, 13 Nov 2026 · 09:05'), findsOneWidget);

      await tapAndSettle(tester, find.text('Use'));
      expect(find.text('Friday, 13 Nov 2026 · 09:05'), findsOneWidget);
    });

    testWidgets('adding photos is a tap outside: it closes', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await pickFromGallery(tester, [_Photo(2)]);
      expect(popover(), findsNothing);
      expect(find.text(today), findsOneWidget);
    });

    testWidgets('is not offered with no time, within the hour, or in the '
        'future', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(3), _Photo(4), _Photo(5)]);

      expect(popover(), findsNothing);
      expect(find.textContaining('Photo taken'), findsNothing);
      await autosave(tester);
    });

    testWidgets('typing dismisses it', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);
      expect(popover(), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Pagi');
      await tester.pumpAndSettle();
      expect(popover(), findsNothing);
      expect(find.text(today), findsOneWidget);

      await pickFromGallery(tester, [_Photo(2)]);
      expect(popover(), findsNothing);
    });

    testWidgets('typing before a photo does not keep it away', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await tester.enterText(find.byType(TextField), 'Pagi');
      await tester.pump();

      await pickFromGallery(tester, [_Photo(1)]);
      expect(offer(sabtu), findsOneWidget);
    });

    testWidgets('a tap outside dismisses it', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await tapAndSettle(tester, find.byType(TextField));
      expect(popover(), findsNothing);
      expect(find.text(today), findsOneWidget);
    });

    testWidgets('a tap on the card itself keeps it', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await tapAndSettle(tester, find.text('Use it as this Entry\'s date?'));
      expect(popover(), findsOneWidget);
    });

    testWidgets('the date chip closes it, and the picked date stays', (
      tester,
    ) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await tapAndSettle(tester, _kIcon(KIcons.calendar));
      await tapAndSettle(tester, find.text('17'));
      await tapAndSettle(tester, find.text('OK'));
      await tapAndSettle(tester, find.text('OK'));

      expect(popover(), findsNothing);
      expect(find.text('Tuesday, 17 Nov 2026 · 14:32'), findsOneWidget);
      await pickFromGallery(tester, [_Photo(2)]);
      expect(popover(), findsNothing);
    });

    testWidgets('is not offered once the date was chosen with the chip', (
      tester,
    ) async {
      await writeNew(tester, prepare: prepareTaken);
      await tapAndSettle(tester, _kIcon(KIcons.calendar));
      await tapAndSettle(tester, find.text('17'));
      await tapAndSettle(tester, find.text('OK'));
      await tapAndSettle(tester, find.text('OK'));

      await pickFromGallery(tester, [_Photo(1)]);
      expect(popover(), findsNothing);
      await autosave(tester);
    });

    testWidgets('taking the photo out takes the offer with it', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await tapAndSettle(tester, removeButtons().first);
      expect(popover(), findsNothing);
    });

    testWidgets('is never offered in an existing Entry', (tester) async {
      await store.createEntry(bookId: book.id, text: 'Sudah ada.');
      await pumpApp(tester, prepare: prepareTaken);
      await tapAndSettle(tester, find.text(book.name));
      await tapAndSettle(tester, find.text('Sudah ada.'));
      await tapAndSettle(tester, _kIcon(KIcons.pen));

      await pickFromGallery(tester, [_Photo(1)]);
      expect(popover(), findsNothing);
      expect(find.text(today), findsOneWidget);
    });

    testWidgets('closing the editor before Use keeps the date', (tester) async {
      await writeNew(tester, prepare: prepareTaken);
      await pickFromGallery(tester, [_Photo(1)]);

      await tapAndSettle(tester, find.text('Done'));
      expect((await onlyEntry()).dateTime, now);
    });
  });
}
