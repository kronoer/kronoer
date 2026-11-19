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

  /// Brand tagline, shown under the app name.
  ///
  /// In id, this message translates to:
  /// **'Tempat pribadi untuk mencatat.'**
  String get tagline;

  /// Button on Welcome that opens the Book list.
  ///
  /// In id, this message translates to:
  /// **'Mulai'**
  String get welcomeStart;

  /// Tooltip of the gear on the Book list.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan'**
  String get settings;

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
