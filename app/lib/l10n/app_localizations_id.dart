// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get welcomeTitle => 'Ruang rahasiamu untuk bercerita';

  @override
  String get welcomeMessage => 'Tanpa akun, tanpa password.';

  @override
  String get welcomeEncrypted => 'Setiap Entry terenkripsi di perangkat ini';

  @override
  String get welcomeStart => 'Yuk, mulai cerita';

  @override
  String get firstBookName => 'Buku Saya';

  @override
  String get settings => 'Pengaturan';

  @override
  String get tabBooks => 'Book';

  @override
  String get timeline => 'Linimasa';

  @override
  String get timelineEmptyTitle => 'Belum ada Entry';

  @override
  String get timelineEmptyMessage =>
      'Entry yang kamu tulis di Book akan muncul di sini.';

  @override
  String get settingsSecurity => 'Keamanan';

  @override
  String get appLock => 'Kunci aplikasi';

  @override
  String get appLockHint => 'Sidik jari atau kunci layar perangkat';

  @override
  String get lockAgain => 'Kunci lagi';

  @override
  String get lockAgainHint => 'Setelah 1 menit di latar belakang';

  @override
  String get settingsAppearance => 'Tampilan';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Ikuti sistem';

  @override
  String get themeLight => 'Terang';

  @override
  String get themeDark => 'Gelap';

  @override
  String get language => 'Bahasa';

  @override
  String get languageDevice => 'Ikuti perangkat';

  @override
  String get languageNameIndonesian => 'Bahasa Indonesia';

  @override
  String get languageNameEnglish => 'Inggris';

  @override
  String get settingsData => 'Data';

  @override
  String get export => 'Ekspor';

  @override
  String get exportHint => 'Semua Book dalam satu arsip';

  @override
  String get import => 'Impor';

  @override
  String get importHint => 'Gabungkan dari arsip ekspor';

  @override
  String get settingsAbout => 'Tentang';

  @override
  String get aboutKronoer => 'Tentang Kronoer';

  @override
  String get aboutHint => 'Versi, lisensi open source, privasi';

  @override
  String version(String version, String build) {
    return 'Versi $version ($build)';
  }

  @override
  String get privacyNote => 'Data kamu hanya ada di perangkat ini';

  @override
  String get aboutText =>
      'Kronoer adalah tempat pribadi untuk menulis. Tulisanmu disimpan sebagai Entry di dalam Book, terenkripsi di perangkatmu.';

  @override
  String get openSourceText =>
      'Kronoer open source. Aplikasinya berlisensi AGPL-3.0, inti kriptografinya MIT atau Apache-2.0. Font, ikon, dan pustaka lain memakai lisensinya masing-masing.';

  @override
  String get licenses => 'Lisensi open source';

  @override
  String get newBook => 'Book baru';

  @override
  String get bookListEmptyTitle => 'Belum ada Book';

  @override
  String get bookListEmptyMessage =>
      'Bikin Book pertamamu, lalu mulai bercerita.';

  @override
  String get yesterday => 'Kemarin';

  @override
  String bookCardImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count foto',
      one: 'Foto',
    );
    return '$_temp0';
  }

  @override
  String get bookCardNoEntries => 'Belum ada Entry';

  @override
  String get bookName => 'Nama Book';

  @override
  String get bookNameRequired => 'Isi nama Book dulu.';

  @override
  String get createBook => 'Buat Book';

  @override
  String get bookMenu => 'Menu Book';

  @override
  String get bookInfo => 'Info Book';

  @override
  String get renameBook => 'Ubah nama';

  @override
  String get renameBookTitle => 'Ubah nama Book';

  @override
  String get saveBookName => 'Simpan nama';

  @override
  String get editBookDescription => 'Ubah deskripsi';

  @override
  String get addBookDescription => 'Tambah deskripsi';

  @override
  String get bookDescription => 'Deskripsi';

  @override
  String get saveBookDescription => 'Simpan deskripsi';

  @override
  String get showMoreDescription => 'Selengkapnya';

  @override
  String get addCover => 'Tambah sampul';

  @override
  String get openCover => 'Sampul, buka layar penuh';

  @override
  String get changeCover => 'Ubah sampul';

  @override
  String get removeCover => 'Hapus sampul';

  @override
  String get coverCropFrame =>
      'Bingkai sampul. Geser dan cubit foto untuk mengatur.';

  @override
  String get coverCropHint => 'Geser dan cubit untuk mengatur';

  @override
  String coverOf(String name) {
    return 'Sampul $name';
  }

  @override
  String get deleteBook => 'Hapus Book';

  @override
  String get deleteBookTitle => 'Hapus Book?';

  @override
  String deleteBookMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$name” dan $count Entry di dalamnya akan hilang selamanya. Ini tidak bisa dibatalkan.',
      zero: '“$name” akan hilang selamanya. Ini tidak bisa dibatalkan.',
    );
    return '$_temp0';
  }

  @override
  String get deleteBookConfirm => 'Ya, hapus';

  @override
  String get cancel => 'Batal';

  @override
  String get writeEntry => 'Tulis Entry';

  @override
  String get bookEmptyTitle => 'Belum ada Entry';

  @override
  String get bookEmptyMessage => 'Tulis Entry pertama di Book ini.';

  @override
  String get storageErrorTitle => 'Kronoer tidak bisa dibuka';

  @override
  String get storageErrorMessage =>
      'Book dan Entry-mu masih tersimpan di perangkat ini, tidak ada yang dihapus. Coba tutup lalu buka lagi Kronoer.';

  @override
  String get editEntry => 'Ubah Entry';

  @override
  String get entryMenu => 'Menu Entry';

  @override
  String get deleteEntry => 'Hapus Entry';

  @override
  String get entryDeleted => 'Entry dihapus';

  @override
  String get undo => 'Urungkan';

  @override
  String get close => 'Tutup';

  @override
  String imagePosition(int index, int count) {
    return '$index / $count';
  }

  @override
  String get done => 'Selesai';

  @override
  String get saved => 'Tersimpan';

  @override
  String get firstEntryPlaceholder =>
      'Tulis apa saja. Hanya kamu yang bisa membacanya.';

  @override
  String get entryPlaceholder => 'Mulai menulis…';

  @override
  String get entryDateQuestion => 'Kapan ini terjadi?';

  @override
  String get addPhoto => 'Selipkan foto';

  @override
  String imageCount(int count, int max) {
    return '$count/$max';
  }

  @override
  String get removeImage => 'Hapus foto';

  @override
  String get gallery => 'Galeri';

  @override
  String get camera => 'Kamera';

  @override
  String imageLimit(int max) {
    return 'Satu Entry bisa memuat paling banyak $max foto.';
  }

  @override
  String get imageNotAdded => 'Foto ini tidak bisa ditambahkan.';

  @override
  String get imagePreparing => 'Menyiapkan foto';

  @override
  String get imageUnreadable => 'Foto tidak bisa dibuka';

  @override
  String openImage(int index, int count) {
    return 'Foto $index dari $count, buka layar penuh';
  }

  @override
  String get searchAllBooks => 'Cari di semua Book';

  @override
  String searchInBook(String name) {
    return 'Cari di $name';
  }

  @override
  String get searchStartAll => 'Cari kata di semua Entry.';

  @override
  String searchStartBook(String name) {
    return 'Cari kata di Entry $name.';
  }

  @override
  String get searchClear => 'Hapus pencarian';

  @override
  String entryCount(int count) {
    return '$count Entry';
  }

  @override
  String bookCount(int count) {
    return '$count Book';
  }

  @override
  String searchFoundAll(String entries, String books) {
    return '$entries di $books';
  }

  @override
  String searchFoundBook(String entries, String name) {
    return '$entries di $name';
  }

  @override
  String searchMore(int count) {
    return 'Lihat $count Entry lainnya';
  }

  @override
  String searchNoneAll(String query) {
    return 'Tidak ada Entry yang cocok dengan “$query”';
  }

  @override
  String get searchNoneHint => 'Coba kata lain, atau awal katanya saja.';

  @override
  String searchNoneHintExample(String start) {
    return 'Coba kata lain, atau awal katanya saja, misalnya “$start”.';
  }

  @override
  String searchNoneBook(String query, String name) {
    return '“$query” tidak ada di $name';
  }

  @override
  String get searchNoneBookHint => 'Mungkin Entry-nya ada di Book lain.';

  @override
  String get styleBold => 'Tebal';

  @override
  String get styleItalic => 'Miring';

  @override
  String get styleStrikethrough => 'Coret';

  @override
  String get styleMonospace => 'Mono';

  @override
  String get styleCode => 'Kode';

  @override
  String get styleBulletedList => 'Daftar poin';

  @override
  String get styleNumberedList => 'Daftar bernomor';

  @override
  String get styleQuote => 'Kutipan';

  @override
  String get moreOptions => 'Opsi lainnya';

  @override
  String get search => 'Cari';

  @override
  String get sortEntries => 'Urutkan';

  @override
  String get newestFirst => 'Terbaru dulu';

  @override
  String get oldestFirst => 'Terlama dulu';

  @override
  String booksSelected(int count) {
    return '$count dipilih';
  }

  @override
  String get pinBooks => 'Sematkan';

  @override
  String get unpinBooks => 'Lepas sematan';

  @override
  String get deleteBooks => 'Hapus';

  @override
  String get pinnedBook => 'Disematkan';

  @override
  String tooManyPinnedBooks(int max) {
    return 'Maksimal $max Book yang disematkan';
  }

  @override
  String deleteBooksTitle(int count) {
    return 'Hapus $count Book?';
  }

  @override
  String deleteBooksMessage(int books, int entries) {
    String _temp0 = intl.Intl.pluralLogic(
      entries,
      locale: localeName,
      other:
          '$books Book dan $entries Entry di dalamnya akan hilang selamanya. Ini tidak bisa dibatalkan.',
      zero: '$books Book akan hilang selamanya. Ini tidak bisa dibatalkan.',
    );
    return '$_temp0';
  }

  @override
  String entriesSelected(int count) {
    return '$count dipilih';
  }

  @override
  String get moveEntries => 'Pindahkan';

  @override
  String get deleteEntries => 'Hapus';

  @override
  String get moveTo => 'Pindahkan ke';

  @override
  String get thisBook => 'Book ini';

  @override
  String get moveToAnotherBook => 'Pindahkan ke Book lain';

  @override
  String entriesMoved(int count, String book) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Entry dipindahkan ke $book',
      one: 'Entry dipindahkan ke $book',
    );
    return '$_temp0';
  }

  @override
  String deleteEntriesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hapus $count Entry?',
      one: 'Hapus Entry?',
    );
    return '$_temp0';
  }

  @override
  String deleteEntriesMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Entry ini dan fotonya akan hilang selamanya. Ini tidak bisa dibatalkan.',
      one: 'Entry ini dan fotonya akan hilang selamanya. Ini tidak bisa dibatalkan.',
    );
    return '$_temp0';
  }

  @override
  String get deleteEntriesConfirm => 'Ya, hapus';

  @override
  String get copyEntries => 'Salin';

  @override
  String get copyEntryText => 'Salin teks';

  @override
  String copiedEntryDate(String date, String time) {
    return '$date pukul $time';
  }

  @override
  String textCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Teks $count Entry disalin',
      one: 'Teks disalin',
    );
    return '$_temp0';
  }

  @override
  String get copyTooLong =>
      'Teksnya terlalu panjang untuk disalin. Pilih lebih sedikit Entry.';

  @override
  String get copyTooLongEntry => 'Teksnya terlalu panjang untuk disalin.';

  @override
  String get showInTimeline => 'Tampilkan di Linimasa';

  @override
  String get showInTimelineOn => 'Entry Book ini muncul di Linimasa';

  @override
  String get showInTimelineOff => 'Entry Book ini tidak muncul di Linimasa';

  @override
  String get booksInTimeline => 'Book di Linimasa';

  @override
  String get timelineNoBooksShown =>
      'Tidak ada Book yang ditampilkan di Linimasa';
}
