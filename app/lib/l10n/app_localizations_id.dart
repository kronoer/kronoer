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
  String get bookName => 'Nama Book';

  @override
  String get bookNameRequired => 'Isi nama Book dulu.';

  @override
  String get createBook => 'Buat Book';

  @override
  String get bookMenu => 'Menu Book';

  @override
  String get renameBook => 'Ganti nama';

  @override
  String get renameBookTitle => 'Ganti nama Book';

  @override
  String get saveBookName => 'Simpan nama';

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
}
