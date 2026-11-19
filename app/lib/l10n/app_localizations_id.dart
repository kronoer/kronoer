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
}
