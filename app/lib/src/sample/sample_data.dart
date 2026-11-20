import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/misc.dart';
import 'package:image/image.dart' as img;
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/storage/core_repository.dart';
import 'package:kronoer/src/storage/entry_date.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';

// (age, text, image count), oldest first within each Book.
const _samples = [
  (
    'My buku gw',
    [
      (
        Duration(days: 150),
        'Jadi gini, saya dari tadi kehujanan. Payung ketinggalan di kantor, '
            'jadi berteduh di warung sambil menunggu reda.',
        0,
      ),
      (
        Duration(days: 121, hours: 5),
        'Hari pertama pakai sepeda ke kantor. Capek, tapi jalanan pagi '
            'ternyata sepi dan udaranya enak.',
        1,
      ),
      (
        Duration(days: 45, hours: 2),
        'Ulang tahun Ibu. Makan bersama di rumah, semua datang kecuali '
            'adik yang masih di luar kota.',
        2,
      ),
      (Duration(days: 12, hours: 9), 'Baca buku sampai lupa waktu.', 0),
      (
        Duration(hours: 3),
        'Pagi ini hujan, kopinya belum ada jadi harus beli dulu. Tapi hujan.',
        1,
      ),
    ],
  ),
  (
    'Perjalanan di sini aja',
    [
      (
        Duration(days: 80, hours: 6),
        'Sampai di stasiun jam tujuh pagi. Langsung cari sarapan gudeg di '
            'dekat pasar.',
        2,
      ),
      (
        Duration(days: 79, hours: 3),
        'Keliling kota naik sepeda sewaan. Mampir ke tiga museum kecil yang '
            'hampir tidak ada pengunjungnya.',
        3,
      ),
      (
        Duration(days: 76, hours: 8),
        'Hari terakhir. Beli oleh-oleh lalu pulang naik kereta sore.',
        0,
      ),
    ],
  ),
  (
    'Gila kamu! Kamu yang gila!',
    [
      (
        Duration(days: 100, hours: 4),
        'Hari ini aku mencoba menulis lagi setelah lama berhenti. Rasanya '
            'aneh, seperti menyapa teman lama yang sudah jarang ditemui.\n\n'
            'Dulu aku menulis hampir setiap malam. Tidak ada yang istimewa: '
            'apa yang dimakan, siapa yang ditemui, lagu apa yang terus '
            'diputar. Tapi ketika dibaca lagi bertahun-tahun kemudian, hal-hal '
            'kecil itulah yang paling berharga.\n\n'
            'Jadi mulai hari ini aku akan menulis lagi, walau hanya satu '
            'kalimat. Kita lihat berapa lama bertahan.',
        0,
      ),
      (Duration(days: 20, hours: 1), 'Ternyata bertahan sampai sekarang.', 1),
    ],
  ),
];

/// Where sample stores go: a new folder each launch, in the system's temporary
/// folder.
const _folderPrefix = 'kronoer_sample';

/// Plain colored JPEGs, one per Image the samples hold, each in its own
/// color and some upright, as a full image and a thumbnail.
List<ImageDraftItem> _sampleImages(int count) => [
  for (var i = 0; i < count; i++)
    () {
      final upright = i % 3 == 1;
      final color = img.ColorRgb8(
        [196, 120, 76, 214, 92][i % 5],
        [120, 150, 132, 176, 110][i % 5],
        [96, 128, 170, 120, 150][i % 5],
      );
      img.Image plain(int long) => img.Image(
        width: upright ? long * 3 ~/ 4 : long,
        height: upright ? long : long * 3 ~/ 4,
      )..clear(color);
      return ImageDraftItem(
        full: img.encodeJpg(plain(1024), quality: 85),
        thumbnail: img.encodeJpg(plain(512), quality: 80),
      );
    }(),
];

/// The sample Books and Entries, in a core store of their own, so the app
/// works on them as on the device's store, search included.
///
/// The store lives in a new temporary folder and its master key is never kept,
/// so nothing written there opens again after the app stops. Folders left by
/// earlier launches are deleted.
Future<List<Override>> sampleOverrides({DateTime? now}) async {
  final today = now ?? DateTime.now();

  // Only old ones: a young folder may belong to a test running side by side.
  final cutoff = DateTime.now().subtract(const Duration(hours: 1));
  await for (final old in Directory.systemTemp.list()) {
    final name = old.path.split(Platform.pathSeparator).last;
    if (old is! Directory || !name.startsWith(_folderPrefix)) continue;
    try {
      if ((await old.stat()).modified.isBefore(cutoff)) {
        await old.delete(recursive: true);
      }
    } on FileSystemException {
      // Gone already, or still open; the system cleans its temporary folder.
    }
  }
  final dir = await Directory.systemTemp.createTemp(_folderPrefix);
  final store = await CoreStore.open(
    dir: dir.path,
    keyring: Keyring.generate(),
  );

  final imageCount = _samples
      .expand((book) => book.$2)
      .fold(0, (sum, entry) => sum + entry.$3);
  final images = (await Isolate.run(() => _sampleImages(imageCount))).iterator;

  for (final (name, entries) in _samples) {
    final book = await store.createBook(name: name);

    for (final (age, text, count) in entries) {
      await store.saveEntry(
        draft: EntryDraftItem(
          bookId: book.id,
          date: formatEntryDate(today.subtract(age)),
          text: text,
          images: [
            for (var i = 0; i < count && images.moveNext(); i++) images.current,
          ],
        ),
      );
    }
  }

  final repository = CoreRepository(store);
  return [
    bookRepositoryProvider.overrideWithValue(repository),
    entryRepositoryProvider.overrideWithValue(repository),
    searchRepositoryProvider.overrideWithValue(repository),
    hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
  ];
}
