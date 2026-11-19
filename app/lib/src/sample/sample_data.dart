import 'package:flutter_riverpod/misc.dart';
import 'package:kronoer/src/rust/api/store.dart';
import 'package:kronoer/src/storage/in_memory_store.dart';
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

Future<List<Override>> sampleOverrides({DateTime? now}) async {
  final today = now ?? DateTime.now();
  DateTime? seedTime;
  final store = InMemoryStore(clock: () => seedTime ?? DateTime.now());

  for (final (name, entries) in _samples) {
    seedTime = today.subtract(entries.first.$1);
    final book = await store.createBook(name);

    for (final (age, text, images) in entries) {
      seedTime = today.subtract(age);
      await store.createEntry(
        bookId: book.id,
        text: text,
        imageIds: [for (var i = 0; i < images; i++) newId()],
      );
    }
  }

  seedTime = null;

  return [
    inMemoryStoreProvider.overrideWithValue(store),
    hasStartedProvider.overrideWith(() => HasStartedNotifier(true)),
  ];
}
