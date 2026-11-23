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
      'Write a first Entry in a Book. Entries from every Book show up here, under their day.';

  @override
  String get timelineToday => 'Today';

  @override
  String get timelineYesterday => 'Yesterday';

  @override
  String get timelineAllYears => 'All years';

  @override
  String timelineStripNoEntry(String date) {
    return '$date, no Entry';
  }

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
  String get settingsReminders => 'Reminders';

  @override
  String get writingReminder => 'Writing reminder';

  @override
  String get writingReminderHint => 'A daily notification to start writing';

  @override
  String get reminderTime => 'Time';

  @override
  String reminderTimeHint(String time) {
    return '$time · may arrive a few minutes late';
  }

  @override
  String get reminderTimeTitle => 'Reminder time';

  @override
  String get skipIfWritten => 'Skip if I already wrote';

  @override
  String get skipIfWrittenHint =>
      'Not shown on days you already wrote an Entry';

  @override
  String get notificationsBlocked =>
      'Allow Kronoer notifications in the device settings';

  @override
  String get openDeviceSettings => 'Open settings';

  @override
  String get reminderNotificationText => 'What happened today?';

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
  String deleteBookMessage(String name, int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$name” and the $count Entries in it will be kept in the Trash for $days days, then be gone forever.',
      one:
          '“$name” and the Entry in it will be kept in the Trash for $days days, then be gone forever.',
      zero:
          '“$name” will be kept in the Trash for $days days, then be gone forever.',
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
  String editorWordCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString words',
      one: '$countString word',
    );
    return '$_temp0';
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

  @override
  String get moreOptions => 'More options';

  @override
  String get search => 'Search';

  @override
  String get sortEntries => 'Sort';

  @override
  String get newestFirst => 'Newest first';

  @override
  String get oldestFirst => 'Oldest first';

  @override
  String booksSelected(int count) {
    return '$count selected';
  }

  @override
  String get pinBooks => 'Pin';

  @override
  String get unpinBooks => 'Unpin';

  @override
  String get deleteBooks => 'Delete';

  @override
  String get pinnedBook => 'Pinned';

  @override
  String tooManyPinnedBooks(int max) {
    return 'You can pin up to $max Books';
  }

  @override
  String deleteBooksTitle(int count) {
    return 'Delete $count Books?';
  }

  @override
  String deleteBooksMessage(int books, int entries, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      entries,
      locale: localeName,
      other:
          'The $books Books and the $entries Entries in them will be kept in the Trash for $days days, then be gone forever.',
      one:
          'The $books Books and the Entry in them will be kept in the Trash for $days days, then be gone forever.',
      zero:
          'The $books Books will be kept in the Trash for $days days, then be gone forever.',
    );
    return '$_temp0';
  }

  @override
  String entriesSelected(int count) {
    return '$count selected';
  }

  @override
  String get moveEntries => 'Move';

  @override
  String get deleteEntries => 'Delete';

  @override
  String get moveTo => 'Move to';

  @override
  String get thisBook => 'This Book';

  @override
  String get moveToAnotherBook => 'Move to another Book';

  @override
  String entriesMoved(int count, String book) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Entries moved to $book',
      one: 'Entry moved to $book',
    );
    return '$_temp0';
  }

  @override
  String get copyEntries => 'Copy';

  @override
  String get copyEntryText => 'Copy text';

  @override
  String copiedEntryDate(String date, String time) {
    return '$date at $time';
  }

  @override
  String textCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Text of $count Entries copied',
      one: 'Text copied',
    );
    return '$_temp0';
  }

  @override
  String get copyTooLong =>
      'The text is too long to copy. Select fewer Entries.';

  @override
  String get copyTooLongEntry => 'The text is too long to copy.';

  @override
  String insightEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Entries',
      one: 'Entry',
    );
    return '$_temp0';
  }

  @override
  String insightWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'words',
      one: 'word',
    );
    return '$_temp0';
  }

  @override
  String insightPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'photos',
      one: 'photo',
    );
    return '$_temp0';
  }

  @override
  String get showInTimeline => 'Show in Timeline';

  @override
  String get showInTimelineOn => 'This Book\'s Entries show in the Timeline';

  @override
  String get showInTimelineOff =>
      'This Book\'s Entries don\'t show in the Timeline';

  @override
  String get booksInTimeline => 'Books in Timeline';

  @override
  String get timelineNoBooksShown => 'No Book is shown in the Timeline';

  @override
  String get starEntries => 'Star';

  @override
  String get unstarEntries => 'Unstar';

  @override
  String get starEntry => 'Star';

  @override
  String get unstarEntry => 'Unstar';

  @override
  String get starredEntry => 'Starred';

  @override
  String get starredEntries => 'Starred Entries';

  @override
  String get starredEntriesEmpty => 'No starred Entries yet';

  @override
  String starsRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars removed',
      one: 'Star removed',
    );
    return '$_temp0';
  }

  @override
  String entriesTrashed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Entries moved to the Trash',
      one: 'Entry moved to the Trash',
    );
    return '$_temp0';
  }

  @override
  String booksTrashed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Books moved to the Trash',
      one: 'Book moved to the Trash',
    );
    return '$_temp0';
  }

  @override
  String get trash => 'Trash';

  @override
  String trashSummary(int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items · kept $days days',
      one: '1 item · kept $days days',
      zero: 'Empty · kept $days days',
    );
    return '$_temp0';
  }

  @override
  String get trashBooksAndEntries => 'Books and Entries';

  @override
  String trashItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'Empty',
    );
    return '$_temp0';
  }

  @override
  String trashHint(int days) {
    return 'Deleted Books and Entries are kept here for $days days, then they are gone forever.';
  }

  @override
  String get trashHubHint =>
      'Deleted Books and Entries are kept here, then they are gone forever after this time.';

  @override
  String get trashKeepFor => 'Keep for';

  @override
  String get trashKeepForHint =>
      'After that, Books and Entries in the Trash are gone forever.';

  @override
  String trashDaysChoice(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String shortenTrashTitle(int days) {
    return 'Keep for only $days days?';
  }

  @override
  String shortenTrashMessage(int count, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count items deleted more than $days days ago will be gone forever right away.',
      one:
          '1 item deleted more than $days days ago will be gone forever right away.',
    );
    return '$_temp0 This can\'t be undone.';
  }

  @override
  String get shortenTrashConfirm => 'Yes, change';

  @override
  String get trashEmpty => 'The Trash is empty';

  @override
  String get trashMenu => 'More options';

  @override
  String get emptyTrash => 'Empty Trash';

  @override
  String get emptyTrashTitle => 'Empty Trash?';

  @override
  String emptyTrashMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count items in the Trash will be gone forever. This can\'t be undone.',
      one: 'The item in the Trash will be gone forever. This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String get emptyTrashConfirm => 'Empty';

  @override
  String trashDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String trashBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Book · $count Entries',
      one: 'Book · 1 Entry',
    );
    return '$_temp0';
  }

  @override
  String get restore => 'Restore';

  @override
  String get deleteForever => 'Delete forever';

  @override
  String get deleteForeverTitle => 'Delete forever?';

  @override
  String get deleteForeverEntry =>
      'This Entry and its photos will be gone forever. This can\'t be undone.';

  @override
  String deleteForeverBook(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$name” and its $count Entries will be gone forever. This can\'t be undone.',
      one: '“$name” and its Entry will be gone forever. This can\'t be undone.',
      zero: '“$name” will be gone forever. This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String deleteForeverItems(int count) {
    return 'These $count items will be gone forever. This can\'t be undone.';
  }

  @override
  String get deleteForeverConfirm => 'Delete';

  @override
  String trashEntryBanner(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'In the Trash · $days days left',
      one: 'In the Trash · 1 day left',
    );
    return '$_temp0';
  }

  @override
  String trashBookBanner(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'In the Trash · $days days left. Restore it to read its Entries.',
      one: 'In the Trash · 1 day left. Restore it to read its Entries.',
    );
    return '$_temp0';
  }

  @override
  String get trashBookTitle => 'Book in the Trash';

  @override
  String trashBookCounts(int entries, int images) {
    String _temp0 = intl.Intl.pluralLogic(
      entries,
      locale: localeName,
      other: '$entries Entries',
      one: '1 Entry',
    );
    String _temp1 = intl.Intl.pluralLogic(
      images,
      locale: localeName,
      other: '$images photos',
      one: '1 photo',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String itemsSelected(int count) {
    return '$count selected';
  }

  @override
  String get restoreTo => 'Restore to';

  @override
  String restoreToHint(int count, String book) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The Book of these $count Entries, $book, is in the Trash too.',
      one: 'This Entry\'s Book, $book, is in the Trash too.',
    );
    return '$_temp0';
  }

  @override
  String restoreToHintBooks(int count) {
    return 'The Books of these $count Entries are in the Trash too.';
  }

  @override
  String get restoreWithBook => 'Restore this Book too, with its Entries';

  @override
  String get restoreWithBooksTitle => 'Their own Books';

  @override
  String get restoreWithBooks => 'Restore their Books too, with their Entries';

  @override
  String get otherBooks => 'Other Books';

  @override
  String entriesRestored(int count, String book) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Entries restored to $book',
      one: 'Entry restored to $book',
    );
    return '$_temp0';
  }

  @override
  String bookRestored(String name) {
    return '“$name” restored';
  }

  @override
  String itemsRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items restored',
      one: '1 item restored',
    );
    return '$_temp0';
  }
}
