// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get welcomeTitle => 'Your secret place to tell your stories';

  @override
  String get welcomeMessage => 'No account, no password.';

  @override
  String get welcomeEncrypted => 'Every Entry is encrypted on this device';

  @override
  String get welcomeStart => 'Let\'s start writing';

  @override
  String get firstBookName => 'My Book';

  @override
  String get settings => 'Settings';

  @override
  String get tabBooks => 'Books';

  @override
  String get timeline => 'Timeline';

  @override
  String get timelineEmptyTitle => 'No Entries yet';

  @override
  String get timelineEmptyMessage =>
      'Entries you write in your Books will show up here.';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockHint => 'Fingerprint or the device\'s screen lock';

  @override
  String get lockAgain => 'Lock again';

  @override
  String get lockAgainHint => 'After 1 minute in the background';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'Follow system';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageDevice => 'Follow device';

  @override
  String get languageNameIndonesian => 'Indonesian';

  @override
  String get languageNameEnglish => 'English';

  @override
  String get settingsData => 'Data';

  @override
  String get export => 'Export';

  @override
  String get exportHint => 'All Books in one archive';

  @override
  String get import => 'Import';

  @override
  String get importHint => 'Merge from an export archive';

  @override
  String get settingsAbout => 'About';

  @override
  String get aboutKronoer => 'About Kronoer';

  @override
  String get aboutHint => 'Version, open source licenses, privacy';

  @override
  String version(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get privacyNote => 'Your data is only on this device';

  @override
  String get aboutText =>
      'Kronoer is a private place to write. What you write is kept as Entries in Books, encrypted on your device.';

  @override
  String get openSourceText =>
      'Kronoer is open source. The app is licensed under AGPL-3.0, its cryptographic core under MIT or Apache-2.0. Fonts, icons, and other libraries use their own licenses.';

  @override
  String get licenses => 'Open source licenses';

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
  String bookCardImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: 'Photo',
    );
    return '$_temp0';
  }

  @override
  String get bookCardNoEntries => 'No Entries yet';

  @override
  String get bookName => 'Book name';

  @override
  String get bookNameRequired => 'Enter a name for the Book.';

  @override
  String get createBook => 'Create Book';

  @override
  String get bookMenu => 'Book menu';

  @override
  String get bookInfo => 'Book info';

  @override
  String get renameBook => 'Edit name';

  @override
  String get renameBookTitle => 'Edit Book name';

  @override
  String get saveBookName => 'Save name';

  @override
  String get editBookDescription => 'Edit description';

  @override
  String get addBookDescription => 'Add description';

  @override
  String get bookDescription => 'Description';

  @override
  String get saveBookDescription => 'Save description';

  @override
  String get showMoreDescription => 'More';

  @override
  String get addCover => 'Add cover';

  @override
  String get openCover => 'Cover, open full screen';

  @override
  String get changeCover => 'Change cover';

  @override
  String get removeCover => 'Remove cover';

  @override
  String get coverCropFrame =>
      'Cover frame. Drag and pinch the photo to fit it.';

  @override
  String get coverCropHint => 'Drag and pinch to fit';

  @override
  String coverOf(String name) {
    return 'Cover of $name';
  }

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

  @override
  String get editEntry => 'Edit Entry';

  @override
  String get entryMenu => 'Entry menu';

  @override
  String get deleteEntry => 'Delete Entry';

  @override
  String get entryDeleted => 'Entry deleted';

  @override
  String get undo => 'Undo';

  @override
  String get close => 'Close';

  @override
  String imagePosition(int index, int count) {
    return '$index / $count';
  }

  @override
  String get done => 'Done';

  @override
  String get saved => 'Saved';

  @override
  String get firstEntryPlaceholder => 'Write anything. Only you can read it.';

  @override
  String get entryPlaceholder => 'Start writing…';

  @override
  String get entryDateQuestion => 'When did this happen?';

  @override
  String get addPhoto => 'Add a photo';

  @override
  String imageCount(int count, int max) {
    return '$count/$max';
  }

  @override
  String get removeImage => 'Remove photo';

  @override
  String get gallery => 'Gallery';

  @override
  String get camera => 'Camera';

  @override
  String imageLimit(int max) {
    return 'An Entry can hold up to $max photos.';
  }

  @override
  String get imageNotAdded => 'This photo couldn\'t be added.';

  @override
  String get imagePreparing => 'Preparing photo';

  @override
  String get imageUnreadable => 'Photo can\'t be opened';

  @override
  String openImage(int index, int count) {
    return 'Photo $index of $count, open full screen';
  }

  @override
  String get searchAllBooks => 'Search all Books';

  @override
  String searchInBook(String name) {
    return 'Search $name';
  }

  @override
  String get searchStartAll => 'Search for words in every Entry.';

  @override
  String searchStartBook(String name) {
    return 'Search for words in the Entries of $name.';
  }

  @override
  String get searchClear => 'Clear search';

  @override
  String entryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Entries',
      one: '1 Entry',
    );
    return '$_temp0';
  }

  @override
  String bookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Books',
      one: '1 Book',
    );
    return '$_temp0';
  }

  @override
  String searchFoundAll(String entries, String books) {
    return '$entries in $books';
  }

  @override
  String searchFoundBook(String entries, String name) {
    return '$entries in $name';
  }

  @override
  String searchMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'See $count more Entries',
      one: 'See 1 more Entry',
    );
    return '$_temp0';
  }

  @override
  String searchNoneAll(String query) {
    return 'No Entry matches “$query”';
  }

  @override
  String get searchNoneHint => 'Try another word, or just the start of one.';

  @override
  String searchNoneHintExample(String start) {
    return 'Try another word, or just the start of one, like “$start”.';
  }

  @override
  String searchNoneBook(String query, String name) {
    return '“$query” isn\'t in $name';
  }

  @override
  String get searchNoneBookHint => 'The Entry may be in another Book.';

  @override
  String get styleBold => 'Bold';

  @override
  String get styleItalic => 'Italic';

  @override
  String get styleStrikethrough => 'Strikethrough';

  @override
  String get styleMonospace => 'Mono';

  @override
  String get styleCode => 'Code';

  @override
  String get styleBulletedList => 'Bulleted list';

  @override
  String get styleNumberedList => 'Numbered list';

  @override
  String get styleQuote => 'Quote';
}
