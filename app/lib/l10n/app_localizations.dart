// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// Welcome, the line under the wordmark.
  ///
  /// In en, this message translates to:
  /// **'Your secret place to tell your stories'**
  String get welcomeTitle;

  /// Welcome, under the title.
  ///
  /// In en, this message translates to:
  /// **'No account, no password.'**
  String get welcomeMessage;

  /// Welcome, next to a lock above the start button.
  ///
  /// In en, this message translates to:
  /// **'Every Entry is encrypted on this device'**
  String get welcomeEncrypted;

  /// Button on Welcome that creates the first Book and opens the editor.
  ///
  /// In en, this message translates to:
  /// **'Let\'s start writing'**
  String get welcomeStart;

  /// Name of the Book created on first launch.
  ///
  /// In en, this message translates to:
  /// **'My Book'**
  String get firstBookName;

  /// Title of Settings, and its tab in the bottom navigation.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Bottom navigation tab that shows the Book list.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get tabBooks;

  /// Title of the Timeline (every Entry from every Book), and its tab in the bottom navigation.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timeline;

  /// Timeline with no Entry in any Book, the title.
  ///
  /// In en, this message translates to:
  /// **'No Entries yet'**
  String get timelineEmptyTitle;

  /// Timeline with no Entry in any Book, under the title.
  ///
  /// In en, this message translates to:
  /// **'Entries you write in your Books will show up here.'**
  String get timelineEmptyMessage;

  /// Settings section header.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// Settings row with a switch; disabled until App lock exists.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLock;

  /// Under App lock in Settings.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint or the device\'s screen lock'**
  String get appLockHint;

  /// Settings row: when the app locks again; disabled until App lock exists.
  ///
  /// In en, this message translates to:
  /// **'Lock again'**
  String get lockAgain;

  /// Under Lock again in Settings.
  ///
  /// In en, this message translates to:
  /// **'After 1 minute in the background'**
  String get lockAgainHint;

  /// Settings section header.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Settings row and title of the theme page.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Theme choice: light or dark as the device is.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get themeSystem;

  /// Theme choice.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Theme choice.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Settings row and title of the language page.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Language choice: the device's language.
  ///
  /// In en, this message translates to:
  /// **'Follow device'**
  String get languageDevice;

  /// Indonesian, named in this language, under its own name on the language page. Hidden when it is the same as "Bahasa Indonesia".
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get languageNameIndonesian;

  /// English, named in this language, under its own name on the language page. Hidden when it is the same as "English".
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageNameEnglish;

  /// Settings section header.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// Settings row; disabled until Export & import exists.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// Under Export in Settings.
  ///
  /// In en, this message translates to:
  /// **'All Books in one archive'**
  String get exportHint;

  /// Settings row; disabled until Export & import exists.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// Under Import in Settings.
  ///
  /// In en, this message translates to:
  /// **'Merge from an export archive'**
  String get importHint;

  /// Settings section header.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Settings row and title of the About page.
  ///
  /// In en, this message translates to:
  /// **'About Kronoer'**
  String get aboutKronoer;

  /// Under About Kronoer in Settings.
  ///
  /// In en, this message translates to:
  /// **'Version, open source licenses, privacy'**
  String get aboutHint;

  /// App version on the About page.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String version(String version, String build);

  /// Privacy note on the About page.
  ///
  /// In en, this message translates to:
  /// **'Your data is only on this device'**
  String get privacyNote;

  /// About page, what Kronoer is.
  ///
  /// In en, this message translates to:
  /// **'Kronoer is a private place to write. What you write is kept as Entries in Books, encrypted on your device.'**
  String get aboutText;

  /// About page, the licenses.
  ///
  /// In en, this message translates to:
  /// **'Kronoer is open source. The app is licensed under AGPL-3.0, its cryptographic core under MIT or Apache-2.0. Fonts, icons, and other libraries use their own licenses.'**
  String get openSourceText;

  /// Button on the About page that opens the licenses page.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get licenses;

  /// FAB on the Book list and title of the Create Book page.
  ///
  /// In en, this message translates to:
  /// **'New Book'**
  String get newBook;

  /// Empty Book list, title.
  ///
  /// In en, this message translates to:
  /// **'No Books yet'**
  String get bookListEmptyTitle;

  /// Empty Book list, message under the title.
  ///
  /// In en, this message translates to:
  /// **'Create your first Book, then start writing.'**
  String get bookListEmptyMessage;

  /// Activity time on a Book card when it was yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Book card, under the name: how many Images the latest Entry has, after an image icon. Followed by " · " and the Entry's text when it has text.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Photo} other{{count} photos}}'**
  String bookCardImages(int count);

  /// Book card, under the name, after a pen icon: the Book has no Entries yet.
  ///
  /// In en, this message translates to:
  /// **'No Entries yet'**
  String get bookCardNoEntries;

  /// Label of the Book name field.
  ///
  /// In en, this message translates to:
  /// **'Book name'**
  String get bookName;

  /// Error under the Book name field when it is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for the Book.'**
  String get bookNameRequired;

  /// Tooltip of the check FAB on the Create Book page.
  ///
  /// In en, this message translates to:
  /// **'Create Book'**
  String get createBook;

  /// Tooltip of the ⋮ button in the Book app bar.
  ///
  /// In en, this message translates to:
  /// **'Book menu'**
  String get bookMenu;

  /// Book menu item that opens the Rename Book page.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameBook;

  /// Title of the Rename Book page.
  ///
  /// In en, this message translates to:
  /// **'Rename Book'**
  String get renameBookTitle;

  /// Tooltip of the check FAB on the Rename Book page.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get saveBookName;

  /// Book menu item that asks to delete the Book.
  ///
  /// In en, this message translates to:
  /// **'Delete Book'**
  String get deleteBook;

  /// Title of the delete Book dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Book?'**
  String get deleteBookTitle;

  /// Message of the delete Book dialog.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{“{name}” will be gone forever. This can\'t be undone.} =1{“{name}” and the Entry in it will be gone forever. This can\'t be undone.} other{“{name}” and the {count} Entries in it will be gone forever. This can\'t be undone.}}'**
  String deleteBookMessage(String name, int count);

  /// Destructive button of the delete Book dialog.
  ///
  /// In en, this message translates to:
  /// **'Yes, delete'**
  String get deleteBookConfirm;

  /// Button that closes a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Accessibility label of the pen FAB inside a Book.
  ///
  /// In en, this message translates to:
  /// **'Write Entry'**
  String get writeEntry;

  /// Empty Book, title.
  ///
  /// In en, this message translates to:
  /// **'No Entries yet'**
  String get bookEmptyTitle;

  /// Empty Book, message under the title.
  ///
  /// In en, this message translates to:
  /// **'Write the first Entry in this Book.'**
  String get bookEmptyMessage;

  /// Title of the screen shown when the encrypted store cannot be opened at launch.
  ///
  /// In en, this message translates to:
  /// **'Kronoer can\'t open'**
  String get storageErrorTitle;

  /// Message on the store error screen. Must reassure that nothing was deleted.
  ///
  /// In en, this message translates to:
  /// **'Your Books and Entries are still on this device. Nothing was deleted. Try closing Kronoer and opening it again.'**
  String get storageErrorMessage;

  /// Tooltip of the pen in the Entry read view, which opens the editor.
  ///
  /// In en, this message translates to:
  /// **'Edit Entry'**
  String get editEntry;

  /// Tooltip of the ⋮ button of an Entry.
  ///
  /// In en, this message translates to:
  /// **'Entry menu'**
  String get entryMenu;

  /// Entry menu item that deletes the Entry at once, with undo.
  ///
  /// In en, this message translates to:
  /// **'Delete Entry'**
  String get deleteEntry;

  /// Snackbar after an Entry is deleted.
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get entryDeleted;

  /// Snackbar action that brings back what was just deleted.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Tooltip of the × that closes the full-screen image viewer.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Title of the image viewer: which image of the Entry is shown.
  ///
  /// In en, this message translates to:
  /// **'{index} / {count}'**
  String imagePosition(int index, int count);

  /// Button in the editor that closes it. The Entry is already saved.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Editor status once every change is saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// Placeholder of the editor for the first Entry, right after Welcome.
  ///
  /// In en, this message translates to:
  /// **'Write anything. Only you can read it.'**
  String get firstEntryPlaceholder;

  /// Placeholder of the editor for a new Entry.
  ///
  /// In en, this message translates to:
  /// **'Start writing…'**
  String get entryPlaceholder;

  /// Title of the date and time pickers for the Entry date.
  ///
  /// In en, this message translates to:
  /// **'When did this happen?'**
  String get entryDateQuestion;

  /// Editor button that adds images to the Entry.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get addPhoto;

  /// How many images the Entry has, of the most it can hold.
  ///
  /// In en, this message translates to:
  /// **'{count}/{max}'**
  String imageCount(int count, int max);

  /// Accessibility label of the × on an image in the editor.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removeImage;

  /// Add-photo sheet: pick from the gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// Add-photo sheet: take a photo.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// Snackbar when "Add a photo" is tapped on an Entry that already holds the most images it can.
  ///
  /// In en, this message translates to:
  /// **'An Entry can hold up to {max} photos.'**
  String imageLimit(int max);

  /// Snackbar when a picked photo cannot be read or prepared.
  ///
  /// In en, this message translates to:
  /// **'This photo couldn\'t be added.'**
  String get imageNotAdded;

  /// Accessibility label of an image in the editor that is still being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing photo'**
  String get imagePreparing;

  /// Accessibility label of the placeholder shown for an image that cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Photo can\'t be opened'**
  String get imageUnreadable;

  /// Accessibility label of an image in the Entry read view.
  ///
  /// In en, this message translates to:
  /// **'Photo {index} of {count}, open full screen'**
  String openImage(int index, int count);

  /// Search field on the Book list, hint of the search field across all Books, and the button that switches a search in one Book to all Books.
  ///
  /// In en, this message translates to:
  /// **'Search all Books'**
  String get searchAllBooks;

  /// Hint of the search field in one Book, and tooltip of the search icon on a Book.
  ///
  /// In en, this message translates to:
  /// **'Search {name}'**
  String searchInBook(String name);

  /// Search across all Books, before anything is typed.
  ///
  /// In en, this message translates to:
  /// **'Search for words in every Entry.'**
  String get searchStartAll;

  /// Search in one Book, before anything is typed.
  ///
  /// In en, this message translates to:
  /// **'Search for words in the Entries of {name}.'**
  String searchStartBook(String name);

  /// Tooltip of the button that empties the search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClear;

  /// A number of Entries, as in search results.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Entry} other{{count} Entries}}'**
  String entryCount(int count);

  /// A number of Books, as in search results.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Book} other{{count} Books}}'**
  String bookCount(int count);

  /// Above the results across all Books, e.g. “15 Entry di 3 Book”.
  ///
  /// In en, this message translates to:
  /// **'{entries} in {books}'**
  String searchFoundAll(String entries, String books);

  /// Above the results in one Book, e.g. “12 Entry di Buku Saya”.
  ///
  /// In en, this message translates to:
  /// **'{entries} in {name}'**
  String searchFoundBook(String entries, String name);

  /// Under a Book's first results across all Books; opens the search in that Book.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{See 1 more Entry} other{See {count} more Entries}}'**
  String searchMore(int count);

  /// Search across all Books found nothing.
  ///
  /// In en, this message translates to:
  /// **'No Entry matches “{query}”'**
  String searchNoneAll(String query);

  /// Under searchNoneAll when the word typed is too short to give an example.
  ///
  /// In en, this message translates to:
  /// **'Try another word, or just the start of one.'**
  String get searchNoneHint;

  /// Under searchNoneAll.
  ///
  /// In en, this message translates to:
  /// **'Try another word, or just the start of one, like “{start}”.'**
  String searchNoneHintExample(String start);

  /// Search in one Book found nothing.
  ///
  /// In en, this message translates to:
  /// **'“{query}” isn\'t in {name}'**
  String searchNoneBook(String query, String name);

  /// Under searchNoneBook, above the button that searches all Books.
  ///
  /// In en, this message translates to:
  /// **'The Entry may be in another Book.'**
  String get searchNoneBookHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
