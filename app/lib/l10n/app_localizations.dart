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

  /// Welcome, under the start button, before the link welcomeImport: for someone who exported their Books on another phone.
  ///
  /// In en, this message translates to:
  /// **'Have an archive?'**
  String get welcomeHaveArchive;

  /// Link on Welcome, after welcomeHaveArchive: opens the Import page instead of creating the first Book.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get welcomeImport;

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

  /// Timeline with no Entry in any Book: the title, under the heading for today.
  ///
  /// In en, this message translates to:
  /// **'No Entries yet'**
  String get timelineEmptyTitle;

  /// Timeline with no Entry in any Book, under the title. The Timeline shows each Entry under the heading of its day.
  ///
  /// In en, this message translates to:
  /// **'Write a first Entry in a Book. Entries from every Book show up here, under their day.'**
  String get timelineEmptyMessage;

  /// Timeline: the heading of today's Entries, above the date.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get timelineToday;

  /// Timeline: the heading of yesterday's Entries, above the date.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timelineYesterday;

  /// Timeline: the first date crumb above the date strip, before the year and the month. Tapping it shows the years in the strip.
  ///
  /// In en, this message translates to:
  /// **'All years'**
  String get timelineAllYears;

  /// Timeline, for screen readers: a day, month, or year in the date strip, or a run of days in the list, that has no Entry.
  ///
  /// In en, this message translates to:
  /// **'{date}, no Entry'**
  String timelineStripNoEntry(String date);

  /// Settings section header.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// Settings row with a switch: App lock asks for the device's own lock before Kronoer opens.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLock;

  /// Under App lock in Settings.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint or the device\'s screen lock'**
  String get appLockHint;

  /// Under App lock in Settings, only on Android 8 to 12, where hiding Kronoer from Recents also blocks screenshots.
  ///
  /// In en, this message translates to:
  /// **'On this Android version, screenshots of Kronoer are blocked too while the lock is on'**
  String get appLockScreenshots;

  /// Shown under App lock in Settings when the device has no PIN, pattern, or password; followed by openDeviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Set a screen lock on this phone first to use App lock'**
  String get appLockNoScreenLock;

  /// Settings row and page title: how long Kronoer may be in the background before App lock asks again.
  ///
  /// In en, this message translates to:
  /// **'Lock again'**
  String get lockAgain;

  /// Note at the top of the Lock again page.
  ///
  /// In en, this message translates to:
  /// **'When Kronoer is in the background longer than this, your fingerprint or screen lock is asked for again.'**
  String get lockAgainNote;

  /// Lock again option.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get lockAgainImmediately;

  /// Under the Immediately option, and under the Lock again row in Settings when it is picked.
  ///
  /// In en, this message translates to:
  /// **'Every time you leave Kronoer'**
  String get lockAgainImmediatelyHint;

  /// Lock again option: after this many minutes in the background.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{After 1 minute} other{After {minutes} minutes}}'**
  String lockAgainAfter(int minutes);

  /// Under the Lock again row in Settings.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{After 1 minute in the background} other{After {minutes} minutes in the background}}'**
  String lockAgainHint(int minutes);

  /// Title of the lock screen App lock shows over the app.
  ///
  /// In en, this message translates to:
  /// **'Kronoer is locked'**
  String get lockedTitle;

  /// Under lockedTitle on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'Unlock with your fingerprint or the device\'s screen lock.'**
  String get lockedMessage;

  /// Lock screen button: asks for the device's lock again.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// Title of the Android system prompt on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'Unlock Kronoer'**
  String get unlockPrompt;

  /// Title of the Android system prompt when turning App lock on.
  ///
  /// In en, this message translates to:
  /// **'Turn on App lock'**
  String get turnOnAppLockPrompt;

  /// Title of the Android system prompt when turning App lock off.
  ///
  /// In en, this message translates to:
  /// **'Turn off App lock'**
  String get turnOffAppLockPrompt;

  /// Dialog title, shown once after App lock turned itself off because the device's screen lock was removed.
  ///
  /// In en, this message translates to:
  /// **'App lock turned off'**
  String get appLockTurnedOffTitle;

  /// Dialog text under appLockTurnedOffTitle.
  ///
  /// In en, this message translates to:
  /// **'This phone no longer has a screen lock, so Kronoer can\'t be locked. Set a screen lock, then turn it on again in Settings.'**
  String get appLockTurnedOffMessage;

  /// Card on the Book list after the third Entry, suggesting App lock.
  ///
  /// In en, this message translates to:
  /// **'Lock Kronoer with your fingerprint?'**
  String get appLockSuggestionTitle;

  /// Text under appLockSuggestionTitle on the card.
  ///
  /// In en, this message translates to:
  /// **'Kronoer is locked when it opens. You can change this anytime in Settings.'**
  String get appLockSuggestionMessage;

  /// Button on the App lock card: closes it, and it is not shown again.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get appLockSuggestionLater;

  /// Button on the App lock card: turns App lock on through the device's prompt.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get appLockSuggestionTurnOn;

  /// Title of the reminder to export on the Book list, after 30 days or more without an Export, with Entries created since.
  ///
  /// In en, this message translates to:
  /// **'{days} days without an export'**
  String exportReminderTitle(int days);

  /// Text of the reminder to export: how many Entries were created since the last Export, and why to keep a copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new Entry} other{{count} new Entries}} since your last export. Keep a copy so nothing is lost if your phone breaks or goes missing.'**
  String exportReminderText(int count);

  /// Title of the reminder to export on the Book list, when there has never been an Export and the first Entry is 30 days old or more.
  ///
  /// In en, this message translates to:
  /// **'No export yet'**
  String get exportReminderNeverTitle;

  /// Text of the reminder to export when there has never been an Export.
  ///
  /// In en, this message translates to:
  /// **'It\'s been {days} days since your first Entry. Keep a copy so nothing is lost if your phone breaks or goes missing.'**
  String exportReminderNeverText(int days);

  /// Button on the reminder to export: hides it for 7 days.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get exportReminderLater;

  /// Button on the reminder to export: opens the export page.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportReminderExport;

  /// Title of the banner on the Book list in Kronoer Preview when GitHub has a newer Preview. name is 'Kronoer Preview' and its version, such as 'Kronoer Preview 0.2.0', and stays untranslated.
  ///
  /// In en, this message translates to:
  /// **'{name} is out'**
  String updateTitle(String name);

  /// Text of the banner for a newer Kronoer Preview, under updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Download it from GitHub and install it over this one. What you wrote stays.'**
  String get updateText;

  /// Button on the banner for a newer Kronoer Preview: hides it until a version newer than that one.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// Button on the banner for a newer Kronoer Preview: opens its release page on GitHub in the browser.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// Snackbar when Download on the banner for a newer Kronoer Preview finds no browser on the device.
  ///
  /// In en, this message translates to:
  /// **'No browser to open GitHub'**
  String get updateNoBrowser;

  /// Book info row with a switch: hides the Book from the Book list; it opens only after the device's own lock.
  ///
  /// In en, this message translates to:
  /// **'Lock Book'**
  String get lockBook;

  /// Under lockBook while the Book is not locked.
  ///
  /// In en, this message translates to:
  /// **'Hide it from the Book list'**
  String get lockBookOff;

  /// Under lockBook while the Book is a Locked Book.
  ///
  /// In en, this message translates to:
  /// **'Hidden from the Book list, opened with your fingerprint or screen lock'**
  String get lockBookOn;

  /// Under lockBook on a phone without a screen lock, above a button to the device settings.
  ///
  /// In en, this message translates to:
  /// **'Set a screen lock on this phone first to lock a Book'**
  String get lockBookNoScreenLock;

  /// Book list selection mode action: locks every selected Book.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lockBooks;

  /// Title of the Android system prompt when locking Books.
  ///
  /// In en, this message translates to:
  /// **'Lock Book'**
  String get lockBookPrompt;

  /// Title of the Android system prompt when unlocking a Book.
  ///
  /// In en, this message translates to:
  /// **'Unlock Book'**
  String get unlockBookPrompt;

  /// Snackbar after Books were locked; they left the Book list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Book locked} other{{count} Books locked}}'**
  String booksLocked(int count);

  /// Dialog title when a Book is locked on a phone without a screen lock.
  ///
  /// In en, this message translates to:
  /// **'Set a screen lock first'**
  String get noScreenLockTitle;

  /// Dialog text under noScreenLockTitle.
  ///
  /// In en, this message translates to:
  /// **'A Locked Book opens with this phone\'s fingerprint or screen lock, and this phone has no screen lock yet.'**
  String get noScreenLockMessage;

  /// The link that appears when the Book list is pulled down past its top, and the title of the page it opens, listing the Locked Books.
  ///
  /// In en, this message translates to:
  /// **'Locked Books'**
  String get lockedBooks;

  /// Title of the Android system prompt before the Locked Books page opens.
  ///
  /// In en, this message translates to:
  /// **'Open Locked Books'**
  String get openLockedBooksPrompt;

  /// Empty state of the Locked Books page, after its last Book was unlocked or deleted.
  ///
  /// In en, this message translates to:
  /// **'No Locked Books'**
  String get lockedBooksEmptyTitle;

  /// Under lockedBooksEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock a Book from its Book info or the Book list.'**
  String get lockedBooksEmptyMessage;

  /// One row in the Trash in place of the deleted Locked Books and Entries from Locked Books; tapping it asks for the device's lock, then shows them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item from Locked Books} other{{count} items from Locked Books}}'**
  String trashLockedItems(int count);

  /// Dialog button that only closes it.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

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

  /// Settings section header, for the Writing reminder.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsReminders;

  /// Settings row with a switch: a daily notification that invites the user to write.
  ///
  /// In en, this message translates to:
  /// **'Writing reminder'**
  String get writingReminder;

  /// Hint under the Writing reminder row.
  ///
  /// In en, this message translates to:
  /// **'A daily notification to start writing'**
  String get writingReminderHint;

  /// Settings row under the Writing reminder: the time of day it comes. Opens a time picker.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get reminderTime;

  /// Hint under the reminder Time row: the picked time, in the device's format, and that the device may deliver it late.
  ///
  /// In en, this message translates to:
  /// **'{time} · may arrive a few minutes late'**
  String reminderTimeHint(String time);

  /// Title of the time picker for the Writing reminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get reminderTimeTitle;

  /// Settings row with a switch under the Writing reminder.
  ///
  /// In en, this message translates to:
  /// **'Skip if I already wrote'**
  String get skipIfWritten;

  /// Hint under the 'Skip if I already wrote' row: a day the user created an Entry on goes without the reminder.
  ///
  /// In en, this message translates to:
  /// **'Not shown on days you already wrote an Entry'**
  String get skipIfWrittenHint;

  /// Shown under the Writing reminder row when the device does not let Kronoer notify.
  ///
  /// In en, this message translates to:
  /// **'Allow Kronoer notifications in the device settings'**
  String get notificationsBlocked;

  /// Button under notificationsBlocked: opens Kronoer's notification settings on the device.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openDeviceSettings;

  /// Text of the daily Writing reminder notification, under the title 'Kronoer'. Fixed: shown in full on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'What happened today?'**
  String get reminderNotificationText;

  /// Settings section header.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// Settings row: opens the Export page.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// Under Export in Settings before any Export from this device finished.
  ///
  /// In en, this message translates to:
  /// **'All Books in one archive'**
  String get exportHint;

  /// Settings row: opens the Import page.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// Under Import in Settings.
  ///
  /// In en, this message translates to:
  /// **'Merge from an export archive'**
  String get importHint;

  /// Under Export in Settings, after an Export from this device finished. The date is short, as in 'Nov 2, 2026'.
  ///
  /// In en, this message translates to:
  /// **'All Books · last exported {date}'**
  String exportLast(String date);

  /// Under Export in Settings, when the last Export from this device finished today.
  ///
  /// In en, this message translates to:
  /// **'All Books · last exported today'**
  String get exportLastToday;

  /// Under Export in Settings while there is no Entry outside the Trash; the row is then disabled.
  ///
  /// In en, this message translates to:
  /// **'No Entries yet'**
  String get exportNoEntries;

  /// Title of the Export page, opened from Settings, above exportWarning.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get exportTitle;

  /// On the Export page, before anything is written: the archive does not exist yet.
  ///
  /// In en, this message translates to:
  /// **'The archive that will be made is not encrypted. Anyone who holds the file later can read all your Entries, so keep it somewhere only you can open.'**
  String get exportWarning;

  /// Button on the Export page: opens the device's picker for where the archive is saved.
  ///
  /// In en, this message translates to:
  /// **'Choose location'**
  String get exportPick;

  /// Title of the device's own lock prompt before an Export, shown when there is a Locked Book.
  ///
  /// In en, this message translates to:
  /// **'Export all Books'**
  String get exportPrompt;

  /// Title of the page shown while the archive is written.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get exporting;

  /// Under the progress bar while exporting: Entries and photos written so far, of all in the archive. Numbers are grouped as the language does (1,240).
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} items'**
  String exportProgress(int done, int total);

  /// At the end of the progress bar while exporting or importing.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String exportPercent(int percent);

  /// Note while exporting; Kronoer keeps the screen on meanwhile.
  ///
  /// In en, this message translates to:
  /// **'Keep Kronoer open until it\'s done. The screen won\'t turn off.'**
  String get exportKeepOpen;

  /// Title of the page shown when an Export did not finish.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// Under exportFailed when the picked storage is full.
  ///
  /// In en, this message translates to:
  /// **'The chosen location doesn\'t have enough space. The unfinished file has been deleted.'**
  String get exportStorageFull;

  /// Under exportFailed when the picked file could not be written for another reason.
  ///
  /// In en, this message translates to:
  /// **'The archive couldn\'t be written to the chosen location. The unfinished file has been deleted.'**
  String get exportWriteFailed;

  /// Under exportFailed when Kronoer's own storage could not be read, as when a photo is missing.
  ///
  /// In en, this message translates to:
  /// **'Kronoer couldn\'t read everything the archive needs. The unfinished file has been deleted.'**
  String get exportStoreFailed;

  /// Button on the failed Export page: back to the Export page.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Snackbar in Settings after an Export finished: the file's name as the device's storage shows it.
  ///
  /// In en, this message translates to:
  /// **'Archive saved: {name}'**
  String archiveSaved(String name);

  /// Title of the Import page, opened from Settings, above importText.
  ///
  /// In en, this message translates to:
  /// **'Import from an archive'**
  String get importTitle;

  /// On the Import page, before a file is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose an archive file exported from Kronoer. Entries that are already here are skipped, so nothing is overwritten.'**
  String get importText;

  /// Button on the Import page: opens the device's picker for the archive file.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get importPick;

  /// Title of the page shown while an archive is imported; the file's name is under it.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get importing;

  /// First step while importing, while the whole archive is checked before anything is added.
  ///
  /// In en, this message translates to:
  /// **'Checking the archive'**
  String get importChecking;

  /// First step while importing, once the archive is found whole; importContents is under it.
  ///
  /// In en, this message translates to:
  /// **'Archive checked'**
  String get importChecked;

  /// Under importChecked: what the archive holds, as importBooks, importEntries, and importPhotos.
  ///
  /// In en, this message translates to:
  /// **'{books}, {entries}, {photos}'**
  String importContents(String books, String entries, String photos);

  /// Second step while importing: the Books and Entries this phone lacks are prepared, then added at once.
  ///
  /// In en, this message translates to:
  /// **'Adding what is missing'**
  String get importAdding;

  /// Under importAdding: how many Books and Entries will be added, as importAnd of importBooks and importEntries.
  ///
  /// In en, this message translates to:
  /// **'{items} new'**
  String importNew(String items);

  /// Under the progress bar while importing: new Entries ready so far, of all the Import adds. Numbers are grouped as the language does (1,240).
  ///
  /// In en, this message translates to:
  /// **'{done} of {total, plural, =1{1 Entry} other{{total} Entries}}'**
  String importProgress(int done, int total);

  /// Note under the progress while importing: everything is added at once at the end.
  ///
  /// In en, this message translates to:
  /// **'Nothing changes until the import is done. Cancel leaves nothing behind.'**
  String get importKeepOpen;

  /// A number of Books, in the Import's texts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Book} other{{count} Books}}'**
  String importBooks(int count);

  /// A number of Entries, in the Import's texts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Entry} other{{count} Entries}}'**
  String importEntries(int count);

  /// A number of photos (Images and Covers) in an archive, in importContents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String importPhotos(int count);

  /// Joins two numbers of things in the Import's texts, as in '2 Books and 31 Entries'.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String importAnd(String first, String second);

  /// Title of the page after an Import that added something, or skipped something in the Trash.
  ///
  /// In en, this message translates to:
  /// **'Import done'**
  String get importDone;

  /// First sentence on the page after an Import: what it added, as importBooks, importEntries, or importAnd of both.
  ///
  /// In en, this message translates to:
  /// **'{items} added.'**
  String importAdded(String items);

  /// Sentence after importAdded when the phone already had some of the archive's Entries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Entry was already here, so it was skipped.} other{{count} Entries were already here, so they were skipped.}}'**
  String importSkipped(int count);

  /// Last sentence on the page after an Import.
  ///
  /// In en, this message translates to:
  /// **'Nothing was overwritten.'**
  String get importNothingOverwritten;

  /// In the list after an Import, under the name of a Book the Import added.
  ///
  /// In en, this message translates to:
  /// **'New Book'**
  String get importNewBook;

  /// In the list after an Import, under the name of a Book the phone had: how many of its Entries in the archive it already had.
  ///
  /// In en, this message translates to:
  /// **'{count} already here'**
  String importExisting(int count);

  /// In the list after an Import, the one row for all Locked Books, whose names are not shown.
  ///
  /// In en, this message translates to:
  /// **'Locked Books'**
  String get importLockedBooks;

  /// Under importLockedBooks in the list after an Import.
  ///
  /// In en, this message translates to:
  /// **'Names are not shown'**
  String get importNamesHidden;

  /// In the list after an Import, under a Book that is in the Trash: its new Entries were not imported.
  ///
  /// In en, this message translates to:
  /// **'In the Trash. Restore it first, then import again.'**
  String get importInTrash;

  /// At the end of a row in the list after an Import: how many Entries were added to that Book.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String importAddedCount(int count);

  /// At the end of the row of a Book in the Trash, after an Import: its new Entries that were not imported.
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String importTrashSkipped(int count);

  /// Button after an Import that added something: opens the Book list.
  ///
  /// In en, this message translates to:
  /// **'See the result'**
  String get importSeeResult;

  /// Title of the page after an Import that added nothing: the phone had everything in the archive.
  ///
  /// In en, this message translates to:
  /// **'All already here'**
  String get importAllThere;

  /// Under importAllThere. The items are importAnd of importBooks and importEntries.
  ///
  /// In en, this message translates to:
  /// **'All {items} in this archive are already on this phone. Nothing was added or changed.'**
  String importAllThereText(String items);

  /// Title of the Import page when the archive was refused; one of the importFailed… texts says why.
  ///
  /// In en, this message translates to:
  /// **'This archive can\'t be imported'**
  String get importFailed;

  /// Why an archive was refused: it is not a whole Kronoer archive, or could not be read.
  ///
  /// In en, this message translates to:
  /// **'This file is damaged or isn\'t a Kronoer archive.'**
  String get importDamaged;

  /// Why an archive was refused: a photo in it is not a JPEG that opens, or is too large.
  ///
  /// In en, this message translates to:
  /// **'A photo in this archive doesn\'t open, so the archive isn\'t complete.'**
  String get importImage;

  /// Why an archive was refused: its format is newer than this app reads.
  ///
  /// In en, this message translates to:
  /// **'This archive was made by a newer version of Kronoer. Update Kronoer, then import again.'**
  String get importNewer;

  /// Why an Import failed when the archive was fine: Kronoer's own store failed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while adding it. Try again.'**
  String get importStoreFailed;

  /// Note under why an Import failed.
  ///
  /// In en, this message translates to:
  /// **'Nothing was added. This phone stays as it was.'**
  String get importNothingAdded;

  /// Button after an Import failed: opens the device's picker again.
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get importPickAnother;

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

  /// Settings row with a switch, under About, in Kronoer Preview only: once a day, asks GitHub whether a newer Preview is out.
  ///
  /// In en, this message translates to:
  /// **'Check for a new version'**
  String get updateCheck;

  /// Under updateCheck in Settings.
  ///
  /// In en, this message translates to:
  /// **'Once a day, on GitHub'**
  String get updateCheckHint;

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

  /// Tooltip of the ⋮ button on the Book info page.
  ///
  /// In en, this message translates to:
  /// **'Book menu'**
  String get bookMenu;

  /// Menu item in the ⋮ menu of a Book, and what TalkBack reads for the Book name in its app bar; both open the Book info page.
  ///
  /// In en, this message translates to:
  /// **'Book info'**
  String get bookInfo;

  /// Book info menu item that opens the Edit Book name page.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get renameBook;

  /// Title of the Edit Book name page.
  ///
  /// In en, this message translates to:
  /// **'Edit Book name'**
  String get renameBookTitle;

  /// Tooltip of the check FAB on the Edit Book name page.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get saveBookName;

  /// Book info menu item that opens the Edit description page, and the title of that page.
  ///
  /// In en, this message translates to:
  /// **'Edit description'**
  String get editBookDescription;

  /// Button on the Book info page of a Book without a Description; opens the Edit description page.
  ///
  /// In en, this message translates to:
  /// **'Add description'**
  String get addBookDescription;

  /// Label of the Book Description field.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get bookDescription;

  /// Tooltip of the check FAB on the Edit description page.
  ///
  /// In en, this message translates to:
  /// **'Save description'**
  String get saveBookDescription;

  /// Link right after a Book Description folded to 3 lines on the Book info page; shows all of it.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get showMoreDescription;

  /// Label on the large empty tile on the Book info page of a Book without a Cover; opens the choices Gallery and Camera.
  ///
  /// In en, this message translates to:
  /// **'Add cover'**
  String get addCover;

  /// Screen reader label of the large Cover on the Book info page; tapping it shows the Cover full screen.
  ///
  /// In en, this message translates to:
  /// **'Cover, open full screen'**
  String get openCover;

  /// Tooltip of the pen in the top bar of the full screen Cover; opens the choices Gallery, Camera, and Remove cover.
  ///
  /// In en, this message translates to:
  /// **'Change cover'**
  String get changeCover;

  /// Red choice in the Cover sheet; removes the Book's Cover at once, without asking.
  ///
  /// In en, this message translates to:
  /// **'Remove cover'**
  String get removeCover;

  /// Screen reader label of the fixed portrait frame on the screen where the user fits a photo into a Book's Cover.
  ///
  /// In en, this message translates to:
  /// **'Cover frame. Drag and pinch the photo to fit it.'**
  String get coverCropFrame;

  /// Short hint under the frame on the screen where the user fits a photo into a Book's Cover.
  ///
  /// In en, this message translates to:
  /// **'Drag and pinch to fit'**
  String get coverCropHint;

  /// Screen reader label of a Book's Cover shown full screen.
  ///
  /// In en, this message translates to:
  /// **'Cover of {name}'**
  String coverOf(String name);

  /// Row at the bottom of Book info, in the error color, that asks to delete the Book.
  ///
  /// In en, this message translates to:
  /// **'Delete Book'**
  String get deleteBook;

  /// Title of the delete Book dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Book?'**
  String get deleteBookTitle;

  /// Message of the delete Book dialog. The Book goes to the Trash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{“{name}” will be kept in the Trash for {days} days, then be gone forever.} =1{“{name}” and the Entry in it will be kept in the Trash for {days} days, then be gone forever.} other{“{name}” and the {count} Entries in it will be kept in the Trash for {days} days, then be gone forever.}}'**
  String deleteBookMessage(String name, int count, int days);

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

  /// Popover under the date chip of a new Entry, offering the time its photo was taken as its Entry date. dateTime is written like the chip: 'Saturday, 14 Nov 2026 · 16:20'. Never say 'metadata' or 'EXIF'.
  ///
  /// In en, this message translates to:
  /// **'Photo taken {dateTime}'**
  String timeTakenOffer(String dateTime);

  /// Second line of the popover offering the time the photo was taken, under 'Photo taken …'.
  ///
  /// In en, this message translates to:
  /// **'Use it as this Entry\'s date?'**
  String get timeTakenQuestion;

  /// Text button in the time-taken popover: closes it, the Entry date stays as it is.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get timeTakenDismiss;

  /// Text button in the time-taken popover: sets the Entry's date and time to when the photo was taken.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get timeTakenUse;

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

  /// Editor's bottom bar, before 'Saved': how many words the Entry has, counted like the Book insight. Hidden at 0. The number is grouped as the language does (1,234).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} word} other{{count} words}}'**
  String editorWordCount(int count);

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

  /// Hint of the search field in one Book.
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

  /// Text selection menu item: makes the selected text bold, or no longer bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get styleBold;

  /// Text selection menu item: makes the selected text italic, or no longer italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get styleItalic;

  /// Text selection menu item: strikes the selected text through, or no longer.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get styleStrikethrough;

  /// Text selection menu item: puts the selected lines in a monospace block, or takes them out. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get styleMonospace;

  /// Text selection menu item: shows the selected words as inline code in a monospace font, or no longer.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get styleCode;

  /// Text selection menu item: makes each selected line a bulleted list item, or no longer.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get styleBulletedList;

  /// Text selection menu item: makes each selected line a numbered list item, or no longer.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get styleNumberedList;

  /// Text selection menu item: makes the selected lines a quote, or no longer.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get styleQuote;

  /// Tooltip of the ⋮ button in the app bar of a Book and of the Timeline.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// Menu item in the ⋮ menu of a Book and of the Timeline; opens the search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Menu item in the ⋮ menu of a Book and of the Timeline; opens a submenu to choose the order of the Entries.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortEntries;

  /// Sort submenu item: Entries with the latest Entry date at the top. The default.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// Sort submenu item: Entries with the earliest Entry date at the top.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get oldestFirst;

  /// Screen reader label of the number in the Book list's top bar while Books are selected; the bar shows only the number.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String booksSelected(int count);

  /// Tooltip of the top bar button that pins the selected Books to the top of the Book list. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinBooks;

  /// Tooltip of the top bar button that unpins the selected Books; shown instead of Pin when every selected Book is pinned. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinBooks;

  /// Tooltip of the top bar button that asks to delete the selected Books.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteBooks;

  /// Screen reader label of the pin icon on a Pinned Book's row in the Book list.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinnedBook;

  /// Snackbar when pinning the selected Books would make more Pinned Books than allowed; nothing was pinned.
  ///
  /// In en, this message translates to:
  /// **'You can pin up to {max} Books'**
  String tooManyPinnedBooks(int max);

  /// Title of the dialog that deletes several selected Books at once.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} Books?'**
  String deleteBooksTitle(int count);

  /// Message of the dialog that deletes several selected Books at once. They go to the Trash.
  ///
  /// In en, this message translates to:
  /// **'{entries, plural, =0{The {books} Books will be kept in the Trash for {days} days, then be gone forever.} =1{The {books} Books and the Entry in them will be kept in the Trash for {days} days, then be gone forever.} other{The {books} Books and the {entries} Entries in them will be kept in the Trash for {days} days, then be gone forever.}}'**
  String deleteBooksMessage(int books, int entries, int days);

  /// Screen reader label of the number in a Book's top bar while Entries are selected; the bar shows only the number.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String entriesSelected(int count);

  /// Tooltip of the top bar button that moves the selected Entries to another Book. The Entries are not copied: they leave this Book. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveEntries;

  /// Tooltip of the top bar button that asks to delete the selected Entries.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteEntries;

  /// Title of the page that lists the Books to move Entries to; tapping one moves them there at once.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get moveTo;

  /// On the Move to page, next to the Book the Entries are in now, which cannot be picked.
  ///
  /// In en, this message translates to:
  /// **'This Book'**
  String get thisBook;

  /// Item of an Entry's ⋮ menu in the read view: opens the Move to page for this Entry.
  ///
  /// In en, this message translates to:
  /// **'Move to another Book'**
  String get moveToAnotherBook;

  /// Snackbar after Entries were moved to another Book, with an Undo button that moves them back.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Entry moved to {book}} other{{count} Entries moved to {book}}}'**
  String entriesMoved(int count, String book);

  /// Tooltip of the top bar button that copies the whole text of the selected Entries to the clipboard. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyEntries;

  /// Item of an Entry's ⋮ menu in the read view: copies the Entry's whole text to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyEntryText;

  /// The first line of each Entry's copied text: its Entry date and time, as the read view shows them.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String copiedEntryDate(String date, String time);

  /// Snackbar after Entries' text was copied, on Android 12 and lower; newer Android shows its own clipboard preview instead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Text copied} other{Text of {count} Entries copied}}'**
  String textCopied(int count);

  /// Snackbar when the text of the selected Entries is too large for the clipboard; nothing was copied and they stay selected.
  ///
  /// In en, this message translates to:
  /// **'The text is too long to copy. Select fewer Entries.'**
  String get copyTooLong;

  /// Snackbar when one Entry's text is too large for the clipboard; nothing was copied.
  ///
  /// In en, this message translates to:
  /// **'The text is too long to copy.'**
  String get copyTooLongEntry;

  /// Book insight card in Book info, under the Description: the label under the number of Entries in the Book. The number is shown on its own above it, in large type.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Entry} other{Entries}}'**
  String insightEntries(int count);

  /// Book insight card in Book info: the label under the number of words written in all the Book's Entries. The number is shown on its own above it, in large type.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{word} other{words}}'**
  String insightWords(int count);

  /// Book insight card in Book info: the label under the number of photos (Images) in all the Book's Entries, not counting the Cover. The number is shown on its own above it, in large type.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{photo} other{photos}}'**
  String insightPhotos(int count);

  /// Book info row with a switch: whether this Book's Entries show in the Timeline. Only this device remembers it.
  ///
  /// In en, this message translates to:
  /// **'Show in Timeline'**
  String get showInTimeline;

  /// Hint under Show in Timeline in Book info while the switch is on.
  ///
  /// In en, this message translates to:
  /// **'This Book\'s Entries show in the Timeline'**
  String get showInTimelineOn;

  /// Hint under Show in Timeline in Book info while the switch is off.
  ///
  /// In en, this message translates to:
  /// **'This Book\'s Entries don\'t show in the Timeline'**
  String get showInTimelineOff;

  /// Item in the Timeline's ⋮ menu, and the title of the page it opens: every Book with a checkbox for whether the Timeline shows its Entries.
  ///
  /// In en, this message translates to:
  /// **'Books in Timeline'**
  String get booksInTimeline;

  /// Timeline empty state when there are Entries but every Book is kept out of the Timeline.
  ///
  /// In en, this message translates to:
  /// **'No Book is shown in the Timeline'**
  String get timelineNoBooksShown;

  /// Tooltip of the selection mode top bar button that stars the selected Entries, shown while any of them is not starred yet. A star marks an Entry to find it again easily; it is the user's own. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get starEntries;

  /// Tooltip of the selection mode top bar button that removes the star from the selected Entries, shown when every one of them is starred. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'Unstar'**
  String get unstarEntries;

  /// Item of an Entry's ⋮ menu in the read view: stars the Entry, to find it again easily under Starred Entries in Book info.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get starEntry;

  /// Item of an Entry's ⋮ menu in the read view, for a starred Entry: removes its star.
  ///
  /// In en, this message translates to:
  /// **'Unstar'**
  String get unstarEntry;

  /// What a screen reader says for the small star on the card of a starred Entry, next to its time.
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get starredEntry;

  /// Book info row that opens the Book's starred Entries, and the title of that page.
  ///
  /// In en, this message translates to:
  /// **'Starred Entries'**
  String get starredEntries;

  /// Starred Entries page when none of the Book's Entries is starred.
  ///
  /// In en, this message translates to:
  /// **'No starred Entries yet'**
  String get starredEntriesEmpty;

  /// Snackbar on the Starred Entries page after the star was removed from Entries, with an Undo button that stars them again.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Star removed} other{{count} stars removed}}'**
  String starsRemoved(int count);

  /// Snackbar after Entries were deleted, with an Undo button that restores them. They wait in the Trash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Entry moved to the Trash} other{{count} Entries moved to the Trash}}'**
  String entriesTrashed(int count);

  /// Snackbar after Books were deleted, with an Undo button that restores them. They wait in the Trash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Book moved to the Trash} other{{count} Books moved to the Trash}}'**
  String booksTrashed(int count);

  /// The Trash: where deleted Books and Entries wait before they are gone for good. Title of its Settings row and its page.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// Hint under the Trash row in Settings: how many items it holds, and for how long it keeps them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Empty · kept {days} days} =1{1 item · kept {days} days} other{{count} items · kept {days} days}}'**
  String trashSummary(int count, int days);

  /// Row on the Trash page that opens the list of deleted Books and Entries, and that list's title.
  ///
  /// In en, this message translates to:
  /// **'Books and Entries'**
  String get trashBooksAndEntries;

  /// Hint under the Books and Entries row on the Trash page.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Empty} =1{1 item} other{{count} items}}'**
  String trashItemCount(int count);

  /// Line on the empty Trash list, saying what the Trash keeps and for how long.
  ///
  /// In en, this message translates to:
  /// **'Deleted Books and Entries are kept here for {days} days, then they are gone forever.'**
  String trashHint(int days);

  /// Line under the rows of the Trash page, saying what the Trash keeps until the time chosen in Keep for.
  ///
  /// In en, this message translates to:
  /// **'Deleted Books and Entries are kept here, then they are gone forever after this time.'**
  String get trashHubHint;

  /// Row on the Trash page, and title of its dialog, for how long the Trash keeps deleted Books and Entries.
  ///
  /// In en, this message translates to:
  /// **'Keep for'**
  String get trashKeepFor;

  /// Line in the Keep for dialog, under its title.
  ///
  /// In en, this message translates to:
  /// **'After that, Books and Entries in the Trash are gone forever.'**
  String get trashKeepForHint;

  /// A number of days the Trash can keep deleted items: a choice in the Keep for dialog, and the value under the Keep for row.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String trashDaysChoice(int days);

  /// Title of the dialog asking before a shorter Keep for time deletes items for good.
  ///
  /// In en, this message translates to:
  /// **'Keep for only {days} days?'**
  String shortenTrashTitle(int days);

  /// Body of the dialog asking before a shorter Keep for time deletes items for good.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item deleted more than {days} days ago will be gone forever right away.} other{{count} items deleted more than {days} days ago will be gone forever right away.}} This can\'t be undone.'**
  String shortenTrashMessage(int count, int days);

  /// Button that confirms the shorter Keep for time, deleting the items past it.
  ///
  /// In en, this message translates to:
  /// **'Yes, change'**
  String get shortenTrashConfirm;

  /// Title of the list of deleted Books and Entries when there are none.
  ///
  /// In en, this message translates to:
  /// **'The Trash is empty'**
  String get trashEmpty;

  /// Tooltip of the ⋮ button on the list of deleted Books and Entries.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get trashMenu;

  /// Item of the ⋮ menu on the Trash list that deletes everything in it for good.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get emptyTrash;

  /// Title of the dialog that asks before emptying the Trash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get emptyTrashTitle;

  /// Message of the dialog that asks before emptying the Trash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The item in the Trash will be gone forever. This can\'t be undone.} other{The {count} items in the Trash will be gone forever. This can\'t be undone.}}'**
  String emptyTrashMessage(int count);

  /// Destructive button of the dialog that empties the Trash.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get emptyTrashConfirm;

  /// On a deleted Book or Entry in the Trash: how many days are left before it is gone for good.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String trashDaysLeft(int days);

  /// On a deleted Book in the Trash list: it is a Book, and how many Entries come back with it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Book · 1 Entry} other{Book · {count} Entries}}'**
  String trashBookCount(int count);

  /// Button that takes a Book or an Entry out of the Trash, back where it was.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// Button that deletes a Book or an Entry in the Trash for good.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get deleteForever;

  /// Title of the dialog that asks before deleting items in the Trash for good.
  ///
  /// In en, this message translates to:
  /// **'Delete forever?'**
  String get deleteForeverTitle;

  /// Message of the dialog that asks before deleting one Entry in the Trash for good.
  ///
  /// In en, this message translates to:
  /// **'This Entry and its photos will be gone forever. This can\'t be undone.'**
  String get deleteForeverEntry;

  /// Message of the dialog that asks before deleting one Book in the Trash for good, with all its Entries, those in the Trash on their own too.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{“{name}” will be gone forever. This can\'t be undone.} =1{“{name}” and its Entry will be gone forever. This can\'t be undone.} other{“{name}” and its {count} Entries will be gone forever. This can\'t be undone.}}'**
  String deleteForeverBook(String name, int count);

  /// Message of the dialog that asks before deleting several selected items in the Trash for good.
  ///
  /// In en, this message translates to:
  /// **'These {count} items will be gone forever. This can\'t be undone.'**
  String deleteForeverItems(int count);

  /// Destructive button of the dialog that deletes items in the Trash for good.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteForeverConfirm;

  /// Banner over a deleted Entry opened from the Trash.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{In the Trash · 1 day left} other{In the Trash · {days} days left}}'**
  String trashEntryBanner(int days);

  /// Banner over a deleted Book opened from the Trash, which shows only its Cover, name, and counts.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{In the Trash · 1 day left. Restore it to read its Entries.} other{In the Trash · {days} days left. Restore it to read its Entries.}}'**
  String trashBookBanner(int days);

  /// Top bar title of a deleted Book opened from the Trash.
  ///
  /// In en, this message translates to:
  /// **'Book in the Trash'**
  String get trashBookTitle;

  /// Under the name of a deleted Book opened from the Trash: what comes back with it.
  ///
  /// In en, this message translates to:
  /// **'{entries, plural, =1{1 Entry} other{{entries} Entries}} · {images, plural, =1{1 photo} other{{images} photos}}'**
  String trashBookCounts(int entries, int images);

  /// Screen reader label of the number in the Trash list's top bar while items are selected; the bar shows only the number.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String itemsSelected(int count);

  /// Title of the page that asks where to restore Entries whose Book is in the Trash too.
  ///
  /// In en, this message translates to:
  /// **'Restore to'**
  String get restoreTo;

  /// Line on the Restore to page when the Entries' Book is in the Trash too.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This Entry\'s Book, {book}, is in the Trash too.} other{The Book of these {count} Entries, {book}, is in the Trash too.}}'**
  String restoreToHint(int count, String book);

  /// Line on the Restore to page when the Entries come from several Books that are in the Trash too.
  ///
  /// In en, this message translates to:
  /// **'The Books of these {count} Entries are in the Trash too.'**
  String restoreToHintBooks(int count);

  /// Hint of the first option on the Restore to page: the Entries' own Book comes back too.
  ///
  /// In en, this message translates to:
  /// **'Restore this Book too, with its Entries'**
  String get restoreWithBook;

  /// Title of the first option on the Restore to page when the Entries come from several Books in the Trash.
  ///
  /// In en, this message translates to:
  /// **'Their own Books'**
  String get restoreWithBooksTitle;

  /// Hint of the first option on the Restore to page when the Entries come from several Books in the Trash.
  ///
  /// In en, this message translates to:
  /// **'Restore their Books too, with their Entries'**
  String get restoreWithBooks;

  /// Header over the user's other Books on the Restore to page.
  ///
  /// In en, this message translates to:
  /// **'Other Books'**
  String get otherBooks;

  /// Snackbar after Entries were restored from the Trash, naming the Book they went back to.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Entry restored to {book}} other{{count} Entries restored to {book}}}'**
  String entriesRestored(int count, String book);

  /// Snackbar after a Book was restored from the Trash: it is back in the Book list.
  ///
  /// In en, this message translates to:
  /// **'“{name}” restored'**
  String bookRestored(String name);

  /// Snackbar after several Books and Entries were restored from the Trash, to more than one place.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item restored} other{{count} items restored}}'**
  String itemsRestored(int count);
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
