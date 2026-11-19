// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get tagline => 'Tempat pribadi untuk mencatat.';

  @override
  String get welcomeStart => 'Mulai';

  @override
  String get settings => 'Pengaturan';

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
}
