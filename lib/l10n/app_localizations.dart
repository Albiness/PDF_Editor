import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_sk.dart';
import 'app_localizations_uk.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('ru'),
    Locale('sk'),
    Locale('uk'),
  ];

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addPagesFromFile.
  ///
  /// In en, this message translates to:
  /// **'Add pages from file'**
  String get addPagesFromFile;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @addText.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addText;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cannotDeleteOnlyPage.
  ///
  /// In en, this message translates to:
  /// **'The only page cannot be deleted'**
  String get cannotDeleteOnlyPage;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearList.
  ///
  /// In en, this message translates to:
  /// **'Clear list'**
  String get clearList;

  /// No description provided for @clearRecentMessage.
  ///
  /// In en, this message translates to:
  /// **'Local copies in the recent list will be deleted. Original files will not be deleted.'**
  String get clearRecentMessage;

  /// No description provided for @clearRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear recent documents?'**
  String get clearRecentTitle;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @couldNotDisplayPdf.
  ///
  /// In en, this message translates to:
  /// **'Could not display PDF: {details}'**
  String couldNotDisplayPdf(String details);

  /// No description provided for @couldNotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Could not open file'**
  String get couldNotOpenFile;

  /// No description provided for @couldNotOpenFileDetails.
  ///
  /// In en, this message translates to:
  /// **'Could not open file: {details}'**
  String couldNotOpenFileDetails(String details);

  /// No description provided for @couldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get couldNotReadFile;

  /// No description provided for @couldNotReadPdf.
  ///
  /// In en, this message translates to:
  /// **'Could not read PDF (the file may be damaged or password-protected)'**
  String get couldNotReadPdf;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deletePageMessage.
  ///
  /// In en, this message translates to:
  /// **'The page and all edits on it will be deleted.'**
  String get deletePageMessage;

  /// No description provided for @deletePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete page {page}?'**
  String deletePageTitle(int page);

  /// No description provided for @deletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get deletePhoto;

  /// No description provided for @deletePhotoMessage.
  ///
  /// In en, this message translates to:
  /// **'The photo will be removed from the page.'**
  String get deletePhotoMessage;

  /// No description provided for @deletePhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get deletePhotoTitle;

  /// No description provided for @deleteTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete text?'**
  String get deleteTextTitle;

  /// No description provided for @down.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get down;

  /// No description provided for @draw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get draw;

  /// No description provided for @drawing.
  ///
  /// In en, this message translates to:
  /// **'Drawing'**
  String get drawing;

  /// No description provided for @editText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get editText;

  /// No description provided for @emptyFile.
  ///
  /// In en, this message translates to:
  /// **'The file is empty'**
  String get emptyFile;

  /// No description provided for @enterText.
  ///
  /// In en, this message translates to:
  /// **'Enter text'**
  String get enterText;

  /// No description provided for @errorWithDetails.
  ///
  /// In en, this message translates to:
  /// **'Error: {details}'**
  String errorWithDetails(String details);

  /// No description provided for @fileNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'The file no longer exists'**
  String get fileNoLongerExists;

  /// No description provided for @hasUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'There are unsaved changes'**
  String get hasUnsavedChanges;

  /// No description provided for @highlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get highlighter;

  /// No description provided for @highlighterHint.
  ///
  /// In en, this message translates to:
  /// **'Translucent yellow highlighter'**
  String get highlighterHint;

  /// No description provided for @homeDescription.
  ///
  /// In en, this message translates to:
  /// **'Open PDF, photo, and text files. Draw, add text, rotate, reorder, and delete pages.'**
  String get homeDescription;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit PDFs\nin just a few taps'**
  String get homeTitle;

  /// No description provided for @imagePrepareError.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the image'**
  String get imagePrepareError;

  /// No description provided for @imageReadError.
  ///
  /// In en, this message translates to:
  /// **'Could not read the image (the format is not supported by this device)'**
  String get imageReadError;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get left;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// No description provided for @noRecentDocuments.
  ///
  /// In en, this message translates to:
  /// **'No recent documents yet'**
  String get noRecentDocuments;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get openFile;

  /// No description provided for @openFileTypes.
  ///
  /// In en, this message translates to:
  /// **'Open file (PDF, photo, text)'**
  String get openFileTypes;

  /// No description provided for @pageOrder.
  ///
  /// In en, this message translates to:
  /// **'Page order'**
  String get pageOrder;

  /// No description provided for @pagesAdded.
  ///
  /// In en, this message translates to:
  /// **'Pages added: {count}'**
  String pagesAdded(int count);

  /// No description provided for @pdfSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'PDF saved successfully'**
  String get pdfSavedSuccessfully;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @photoHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a photo to select it,\ndrag to move it'**
  String get photoHint;

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// No description provided for @recentDocuments.
  ///
  /// In en, this message translates to:
  /// **'Recent documents'**
  String get recentDocuments;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @removeFromRecent.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent'**
  String get removeFromRecent;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// No description provided for @rotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get rotation;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveAndShare.
  ///
  /// In en, this message translates to:
  /// **'Save and share'**
  String get saveAndShare;

  /// No description provided for @savePdf.
  ///
  /// In en, this message translates to:
  /// **'Save PDF'**
  String get savePdf;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareFile.
  ///
  /// In en, this message translates to:
  /// **'Share file'**
  String get shareFile;

  /// No description provided for @shareFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Share {fileName}'**
  String shareFileTitle(String fileName);

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @tapPageForText.
  ///
  /// In en, this message translates to:
  /// **'Tap a place on the page to add text'**
  String get tapPageForText;

  /// No description provided for @textEditHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to edit,\npress and hold to delete'**
  String get textEditHint;

  /// No description provided for @textPrepareError.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare text for PDF'**
  String get textPrepareError;

  /// No description provided for @textTool.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textTool;

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String todayAt(String time);

  /// No description provided for @txtAndOthers.
  ///
  /// In en, this message translates to:
  /// **'TXT and others'**
  String get txtAndOthers;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @unsavedChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'All unsaved edits will be lost. Continue?'**
  String get unsavedChangesMessage;

  /// No description provided for @unsavedShareQuestion.
  ///
  /// In en, this message translates to:
  /// **'There are unsaved changes. What would you like to share?'**
  String get unsavedShareQuestion;

  /// No description provided for @unsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'This format is not supported. Open a PDF, photo, or text file'**
  String get unsupportedFormat;

  /// No description provided for @up.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get up;

  /// No description provided for @withoutChanges.
  ///
  /// In en, this message translates to:
  /// **'Without changes'**
  String get withoutChanges;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String yesterdayAt(String time);

  /// No description provided for @zoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get zoom;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;
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
      <String>['en', 'ru', 'sk', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'sk':
      return AppLocalizationsSk();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
