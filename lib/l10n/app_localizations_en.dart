// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get add => 'Add';

  @override
  String get addPagesFromFile => 'Add pages from file';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get addText => 'Add text';

  @override
  String get cancel => 'Cancel';

  @override
  String get cannotDeleteOnlyPage => 'The only page cannot be deleted';

  @override
  String get clear => 'Clear';

  @override
  String get clearList => 'Clear list';

  @override
  String get clearRecentMessage => 'Local copies in the recent list will be deleted. Original files will not be deleted.';

  @override
  String get clearRecentTitle => 'Clear recent documents?';

  @override
  String get continueLabel => 'Continue';

  @override
  String couldNotDisplayPdf(String details) {
    return 'Could not display PDF: $details';
  }

  @override
  String get couldNotOpenFile => 'Could not open file';

  @override
  String couldNotOpenFileDetails(String details) {
    return 'Could not open file: $details';
  }

  @override
  String get couldNotReadFile => 'Could not read file';

  @override
  String get couldNotReadPdf => 'Could not read PDF (the file may be damaged or password-protected)';

  @override
  String get delete => 'Delete';

  @override
  String get deletePageMessage => 'The page and all edits on it will be deleted.';

  @override
  String deletePageTitle(int page) {
    return 'Delete page $page?';
  }

  @override
  String get deletePhoto => 'Delete photo';

  @override
  String get deletePhotoMessage => 'The photo will be removed from the page.';

  @override
  String get deletePhotoTitle => 'Delete photo?';

  @override
  String get deleteTextTitle => 'Delete text?';

  @override
  String get down => 'Down';

  @override
  String get draw => 'Draw';

  @override
  String get drawing => 'Drawing';

  @override
  String get editText => 'Edit text';

  @override
  String get emptyFile => 'The file is empty';

  @override
  String get enterText => 'Enter text';

  @override
  String errorWithDetails(String details) {
    return 'Error: $details';
  }

  @override
  String get fileNoLongerExists => 'The file no longer exists';

  @override
  String get hasUnsavedChanges => 'There are unsaved changes';

  @override
  String get highlighter => 'Highlighter';

  @override
  String get highlighterHint => 'Translucent yellow highlighter';

  @override
  String get homeDescription => 'Open PDF, photo, and text files. Draw, add text, rotate, reorder, and delete pages.';

  @override
  String get homeTitle => 'Edit PDFs\nin just a few taps';

  @override
  String get imagePrepareError => 'Could not prepare the image';

  @override
  String get imageReadError => 'Could not read the image (the format is not supported by this device)';

  @override
  String get left => 'Left';

  @override
  String get nextPage => 'Next page';

  @override
  String get noRecentDocuments => 'No recent documents yet';

  @override
  String get openFile => 'Open file';

  @override
  String get openFileTypes => 'Open file (PDF, photo, text)';

  @override
  String get pageOrder => 'Page order';

  @override
  String pagesAdded(int count) {
    return 'Pages added: $count';
  }

  @override
  String get pdfSavedSuccessfully => 'PDF saved successfully';

  @override
  String get photo => 'Photo';

  @override
  String get photoHint => 'Tap a photo to select it,\ndrag to move it';

  @override
  String get previousPage => 'Previous page';

  @override
  String get recentDocuments => 'Recent documents';

  @override
  String get redo => 'Redo';

  @override
  String get removeFromRecent => 'Remove from recent';

  @override
  String get right => 'Right';

  @override
  String get rotation => 'Rotation';

  @override
  String get save => 'Save';

  @override
  String get saveAndShare => 'Save and share';

  @override
  String get savePdf => 'Save PDF';

  @override
  String get share => 'Share';

  @override
  String get shareFile => 'Share file';

  @override
  String shareFileTitle(String fileName) {
    return 'Share $fileName';
  }

  @override
  String get size => 'Size';

  @override
  String get tapPageForText => 'Tap a place on the page to add text';

  @override
  String get textEditHint => 'Tap to edit,\npress and hold to delete';

  @override
  String get textPrepareError => 'Could not prepare text for PDF';

  @override
  String get textTool => 'Text';

  @override
  String todayAt(String time) {
    return 'Today, $time';
  }

  @override
  String get txtAndOthers => 'TXT and others';

  @override
  String get undo => 'Undo';

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get unsavedChangesMessage => 'All unsaved edits will be lost. Continue?';

  @override
  String get unsavedShareQuestion => 'There are unsaved changes. What would you like to share?';

  @override
  String get unsupportedFormat => 'This format is not supported. Open a PDF, photo, or text file';

  @override
  String get up => 'Up';

  @override
  String get withoutChanges => 'Without changes';

  @override
  String get yes => 'Yes';

  @override
  String yesterdayAt(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get zoom => 'Zoom';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';
}
