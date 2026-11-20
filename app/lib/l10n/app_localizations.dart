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
  /// In id, this message translates to:
  /// **'Ruang rahasiamu untuk bercerita'**
  String get welcomeTitle;

  /// Welcome, under the title.
  ///
  /// In id, this message translates to:
  /// **'Tanpa akun, tanpa password.'**
  String get welcomeMessage;

  /// Welcome, next to a lock above the start button.
  ///
  /// In id, this message translates to:
  /// **'Setiap Entry terenkripsi di perangkat ini'**
  String get welcomeEncrypted;

  /// Button on Welcome that creates the first Book and opens the editor.
  ///
  /// In id, this message translates to:
  /// **'Yuk, mulai cerita'**
  String get welcomeStart;

  /// Name of the Book created on first launch.
  ///
  /// In id, this message translates to:
  /// **'Buku Saya'**
  String get firstBookName;

  /// Tooltip of the gear on the Book list, and title of Settings.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan'**
  String get settings;

  /// Settings section header.
  ///
  /// In id, this message translates to:
  /// **'Keamanan'**
  String get settingsSecurity;

  /// Settings row with a switch; disabled until App lock exists.
  ///
  /// In id, this message translates to:
  /// **'Kunci aplikasi'**
  String get appLock;

  /// Under App lock in Settings.
  ///
  /// In id, this message translates to:
  /// **'Sidik jari atau kunci layar perangkat'**
  String get appLockHint;

  /// Settings row: when the app locks again; disabled until App lock exists.
  ///
  /// In id, this message translates to:
  /// **'Kunci lagi'**
  String get lockAgain;

  /// Under Lock again in Settings.
  ///
  /// In id, this message translates to:
  /// **'Setelah 1 menit di latar belakang'**
  String get lockAgainHint;

  /// Settings section header.
  ///
  /// In id, this message translates to:
  /// **'Tampilan'**
  String get settingsAppearance;

  /// Settings row and title of the theme page.
  ///
  /// In id, this message translates to:
  /// **'Tema'**
  String get theme;

  /// Theme choice: light or dark as the device is.
  ///
  /// In id, this message translates to:
  /// **'Ikuti sistem'**
  String get themeSystem;

  /// Theme choice.
  ///
  /// In id, this message translates to:
  /// **'Terang'**
  String get themeLight;

  /// Theme choice.
  ///
  /// In id, this message translates to:
  /// **'Gelap'**
  String get themeDark;

  /// Settings row and title of the language page.
  ///
  /// In id, this message translates to:
  /// **'Bahasa'**
  String get language;

  /// Language choice: the device's language.
  ///
  /// In id, this message translates to:
  /// **'Ikuti perangkat'**
  String get languageDevice;

  /// Settings section header.
  ///
  /// In id, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// Settings row; disabled until Export & import exists.
  ///
  /// In id, this message translates to:
  /// **'Ekspor'**
  String get export;

  /// Under Export in Settings.
  ///
  /// In id, this message translates to:
  /// **'Semua Book dalam satu arsip'**
  String get exportHint;

  /// Settings row; disabled until Export & import exists.
  ///
  /// In id, this message translates to:
  /// **'Impor'**
  String get import;

  /// Under Import in Settings.
  ///
  /// In id, this message translates to:
  /// **'Gabungkan dari arsip ekspor'**
  String get importHint;

  /// Settings section header.
  ///
  /// In id, this message translates to:
  /// **'Tentang'**
  String get settingsAbout;

  /// Settings row and title of the About page.
  ///
  /// In id, this message translates to:
  /// **'Tentang Kronoer'**
  String get aboutKronoer;

  /// Under About Kronoer in Settings.
  ///
  /// In id, this message translates to:
  /// **'Versi, lisensi open source, privasi'**
  String get aboutHint;

  /// App version on the About page.
  ///
  /// In id, this message translates to:
  /// **'Versi {version} ({build})'**
  String version(String version, String build);

  /// Privacy note on the About page.
  ///
  /// In id, this message translates to:
  /// **'Data kamu hanya ada di perangkat ini'**
  String get privacyNote;

  /// About page, what Kronoer is.
  ///
  /// In id, this message translates to:
  /// **'Kronoer adalah tempat pribadi untuk menulis. Tulisanmu disimpan sebagai Entry di dalam Book, terenkripsi di perangkatmu.'**
  String get aboutText;

  /// About page, the licenses.
  ///
  /// In id, this message translates to:
  /// **'Kronoer open source. Aplikasinya berlisensi AGPL-3.0, inti kriptografinya MIT atau Apache-2.0. Font, ikon, dan pustaka lain memakai lisensinya masing-masing.'**
  String get openSourceText;

  /// Button on the About page that opens the licenses page.
  ///
  /// In id, this message translates to:
  /// **'Lisensi open source'**
  String get licenses;

  /// FAB on the Book list and title of the Create Book page.
  ///
  /// In id, this message translates to:
  /// **'Book baru'**
  String get newBook;

  /// Empty Book list, title.
  ///
  /// In id, this message translates to:
  /// **'Belum ada Book'**
  String get bookListEmptyTitle;

  /// Empty Book list, message under the title.
  ///
  /// In id, this message translates to:
  /// **'Bikin Book pertamamu, lalu mulai bercerita.'**
  String get bookListEmptyMessage;

  /// Activity time on a Book card when it was yesterday.
  ///
  /// In id, this message translates to:
  /// **'Kemarin'**
  String get yesterday;

  /// Label of the Book name field.
  ///
  /// In id, this message translates to:
  /// **'Nama Book'**
  String get bookName;

  /// Error under the Book name field when it is empty.
  ///
  /// In id, this message translates to:
  /// **'Isi nama Book dulu.'**
  String get bookNameRequired;

  /// Tooltip of the check FAB on the Create Book page.
  ///
  /// In id, this message translates to:
  /// **'Buat Book'**
  String get createBook;

  /// Tooltip of the ⋮ button in the Book app bar.
  ///
  /// In id, this message translates to:
  /// **'Menu Book'**
  String get bookMenu;

  /// Book menu item that opens the Rename Book page.
  ///
  /// In id, this message translates to:
  /// **'Ganti nama'**
  String get renameBook;

  /// Title of the Rename Book page.
  ///
  /// In id, this message translates to:
  /// **'Ganti nama Book'**
  String get renameBookTitle;

  /// Tooltip of the check FAB on the Rename Book page.
  ///
  /// In id, this message translates to:
  /// **'Simpan nama'**
  String get saveBookName;

  /// Book menu item that asks to delete the Book.
  ///
  /// In id, this message translates to:
  /// **'Hapus Book'**
  String get deleteBook;

  /// Title of the delete Book dialog.
  ///
  /// In id, this message translates to:
  /// **'Hapus Book?'**
  String get deleteBookTitle;

  /// Message of the delete Book dialog.
  ///
  /// In id, this message translates to:
  /// **'{count, plural, =0{“{name}” akan hilang selamanya. Ini tidak bisa dibatalkan.} other{“{name}” dan {count} Entry di dalamnya akan hilang selamanya. Ini tidak bisa dibatalkan.}}'**
  String deleteBookMessage(String name, int count);

  /// Destructive button of the delete Book dialog.
  ///
  /// In id, this message translates to:
  /// **'Ya, hapus'**
  String get deleteBookConfirm;

  /// Button that closes a dialog without doing anything.
  ///
  /// In id, this message translates to:
  /// **'Batal'**
  String get cancel;

  /// Accessibility label of the pen FAB inside a Book.
  ///
  /// In id, this message translates to:
  /// **'Tulis Entry'**
  String get writeEntry;

  /// Empty Book, title.
  ///
  /// In id, this message translates to:
  /// **'Belum ada Entry'**
  String get bookEmptyTitle;

  /// Empty Book, message under the title.
  ///
  /// In id, this message translates to:
  /// **'Tulis Entry pertama di Book ini.'**
  String get bookEmptyMessage;

  /// Title of the screen shown when the encrypted store cannot be opened at launch.
  ///
  /// In id, this message translates to:
  /// **'Kronoer tidak bisa dibuka'**
  String get storageErrorTitle;

  /// Message on the store error screen. Must reassure that nothing was deleted.
  ///
  /// In id, this message translates to:
  /// **'Book dan Entry-mu masih tersimpan di perangkat ini, tidak ada yang dihapus. Coba tutup lalu buka lagi Kronoer.'**
  String get storageErrorMessage;

  /// Tooltip of the pen in the Entry read view, which opens the editor.
  ///
  /// In id, this message translates to:
  /// **'Ubah Entry'**
  String get editEntry;

  /// Tooltip of the ⋮ button of an Entry.
  ///
  /// In id, this message translates to:
  /// **'Menu Entry'**
  String get entryMenu;

  /// Entry menu item that deletes the Entry at once, with undo.
  ///
  /// In id, this message translates to:
  /// **'Hapus Entry'**
  String get deleteEntry;

  /// Snackbar after an Entry is deleted.
  ///
  /// In id, this message translates to:
  /// **'Entry dihapus'**
  String get entryDeleted;

  /// Snackbar action that brings back what was just deleted.
  ///
  /// In id, this message translates to:
  /// **'Urungkan'**
  String get undo;

  /// Tooltip of the × that closes the full-screen image viewer.
  ///
  /// In id, this message translates to:
  /// **'Tutup'**
  String get close;

  /// Title of the image viewer: which image of the Entry is shown.
  ///
  /// In id, this message translates to:
  /// **'{index} / {count}'**
  String imagePosition(int index, int count);

  /// Button in the editor that closes it. The Entry is already saved.
  ///
  /// In id, this message translates to:
  /// **'Selesai'**
  String get done;

  /// Editor status once every change is saved.
  ///
  /// In id, this message translates to:
  /// **'Tersimpan'**
  String get saved;

  /// Placeholder of the editor for the first Entry, right after Welcome.
  ///
  /// In id, this message translates to:
  /// **'Tulis apa saja. Hanya kamu yang bisa membacanya.'**
  String get firstEntryPlaceholder;

  /// Placeholder of the editor for a new Entry.
  ///
  /// In id, this message translates to:
  /// **'Mulai menulis…'**
  String get entryPlaceholder;

  /// Title of the date and time pickers for the Entry date.
  ///
  /// In id, this message translates to:
  /// **'Kapan ini terjadi?'**
  String get entryDateQuestion;

  /// Editor button that adds images to the Entry.
  ///
  /// In id, this message translates to:
  /// **'Selipkan foto'**
  String get addPhoto;

  /// How many images the Entry has, of the most it can hold.
  ///
  /// In id, this message translates to:
  /// **'{count}/{max}'**
  String imageCount(int count, int max);

  /// Accessibility label of the × on an image in the editor.
  ///
  /// In id, this message translates to:
  /// **'Hapus foto'**
  String get removeImage;

  /// Add-photo sheet: pick from the gallery.
  ///
  /// In id, this message translates to:
  /// **'Galeri'**
  String get gallery;

  /// Add-photo sheet: take a photo.
  ///
  /// In id, this message translates to:
  /// **'Kamera'**
  String get camera;

  /// Snackbar when "Selipkan foto" is tapped on an Entry that already holds the most images it can.
  ///
  /// In id, this message translates to:
  /// **'Satu Entry bisa memuat paling banyak {max} foto.'**
  String imageLimit(int max);

  /// Snackbar when a picked photo cannot be read or prepared.
  ///
  /// In id, this message translates to:
  /// **'Foto ini tidak bisa ditambahkan.'**
  String get imageNotAdded;

  /// Accessibility label of an image in the editor that is still being prepared.
  ///
  /// In id, this message translates to:
  /// **'Menyiapkan foto'**
  String get imagePreparing;

  /// Accessibility label of the placeholder shown for an image that cannot be opened.
  ///
  /// In id, this message translates to:
  /// **'Foto tidak bisa dibuka'**
  String get imageUnreadable;

  /// Accessibility label of an image in the Entry read view.
  ///
  /// In id, this message translates to:
  /// **'Foto {index} dari {count}, buka layar penuh'**
  String openImage(int index, int count);

  /// Search field on the Book list, hint of the search field across all Books, and the button that switches a search in one Book to all Books.
  ///
  /// In id, this message translates to:
  /// **'Cari di semua Book'**
  String get searchAllBooks;

  /// Hint of the search field in one Book, and tooltip of the search icon on a Book.
  ///
  /// In id, this message translates to:
  /// **'Cari di {name}'**
  String searchInBook(String name);

  /// Search across all Books, before anything is typed.
  ///
  /// In id, this message translates to:
  /// **'Cari kata di semua Entry.'**
  String get searchStartAll;

  /// Search in one Book, before anything is typed.
  ///
  /// In id, this message translates to:
  /// **'Cari kata di Entry {name}.'**
  String searchStartBook(String name);

  /// Tooltip of the button that empties the search field.
  ///
  /// In id, this message translates to:
  /// **'Hapus pencarian'**
  String get searchClear;

  /// A number of Entries, as in search results.
  ///
  /// In id, this message translates to:
  /// **'{count} Entry'**
  String entryCount(int count);

  /// A number of Books, as in search results.
  ///
  /// In id, this message translates to:
  /// **'{count} Book'**
  String bookCount(int count);

  /// Above the results across all Books, e.g. “15 Entry di 3 Book”.
  ///
  /// In id, this message translates to:
  /// **'{entries} di {books}'**
  String searchFoundAll(String entries, String books);

  /// Above the results in one Book, e.g. “12 Entry di Buku Saya”.
  ///
  /// In id, this message translates to:
  /// **'{entries} di {name}'**
  String searchFoundBook(String entries, String name);

  /// Under a Book's first results across all Books; opens the search in that Book.
  ///
  /// In id, this message translates to:
  /// **'Lihat {count} Entry lainnya'**
  String searchMore(int count);

  /// Search across all Books found nothing.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada Entry yang cocok dengan “{query}”'**
  String searchNoneAll(String query);

  /// Under searchNoneAll when the word typed is too short to give an example.
  ///
  /// In id, this message translates to:
  /// **'Coba kata lain, atau awal katanya saja.'**
  String get searchNoneHint;

  /// Under searchNoneAll.
  ///
  /// In id, this message translates to:
  /// **'Coba kata lain, atau awal katanya saja, misalnya “{start}”.'**
  String searchNoneHintExample(String start);

  /// Search in one Book found nothing.
  ///
  /// In id, this message translates to:
  /// **'“{query}” tidak ada di {name}'**
  String searchNoneBook(String query, String name);

  /// Under searchNoneBook, above the button that searches all Books.
  ///
  /// In id, this message translates to:
  /// **'Mungkin Entry-nya ada di Book lain.'**
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
