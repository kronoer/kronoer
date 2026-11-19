// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tagline => 'A private place to write things down.';

  @override
  String get welcomeStart => 'Start';

  @override
  String get settings => 'Settings';

  @override
  String get newBook => 'New Book';

  @override
  String get bookListEmptyTitle => 'No Books yet';

  @override
  String get bookListEmptyMessage =>
      'Create your first Book, then start writing.';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get bookName => 'Book name';

  @override
  String get bookNameRequired => 'Enter a name for the Book.';

  @override
  String get createBook => 'Create Book';

  @override
  String get bookMenu => 'Book menu';

  @override
  String get renameBook => 'Rename';

  @override
  String get renameBookTitle => 'Rename Book';

  @override
  String get saveBookName => 'Save name';

  @override
  String get deleteBook => 'Delete Book';

  @override
  String get deleteBookTitle => 'Delete Book?';

  @override
  String deleteBookMessage(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$name” and the $count Entries in it will be gone forever. This can\'t be undone.',
      one:
          '“$name” and the Entry in it will be gone forever. This can\'t be undone.',
      zero: '“$name” will be gone forever. This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String get deleteBookConfirm => 'Yes, delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get writeEntry => 'Write Entry';

  @override
  String get bookEmptyTitle => 'No Entries yet';

  @override
  String get bookEmptyMessage => 'Write the first Entry in this Book.';

  @override
  String get storageErrorTitle => 'Kronoer can\'t open';

  @override
  String get storageErrorMessage =>
      'Your Books and Entries are still on this device. Nothing was deleted. Try closing Kronoer and opening it again.';
}
