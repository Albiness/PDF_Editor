// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get add => 'Додати';

  @override
  String get addPagesFromFile => 'Додати сторінки з файлу';

  @override
  String get addPhoto => 'Додати фото';

  @override
  String get addText => 'Додати текст';

  @override
  String get cancel => 'Скасувати';

  @override
  String get cannotDeleteOnlyPage => 'Не можна видалити єдину сторінку';

  @override
  String get clear => 'Очистити';

  @override
  String get clearList => 'Очистити список';

  @override
  String get clearRecentMessage =>
      'Локальні копії зі списку нещодавніх буде видалено. Початкові файли не видаляються.';

  @override
  String get clearRecentTitle => 'Очистити нещодавні?';

  @override
  String get continueLabel => 'Продовжити';

  @override
  String couldNotDisplayPdf(String details) {
    return 'Не вдалося відобразити PDF: $details';
  }

  @override
  String get couldNotOpenFile => 'Не вдалося відкрити файл';

  @override
  String couldNotOpenFileDetails(String details) {
    return 'Не вдалося відкрити файл: $details';
  }

  @override
  String get couldNotReadFile => 'Не вдалося прочитати файл';

  @override
  String get couldNotReadPdf =>
      'Не вдалося прочитати PDF (файл пошкоджено або захищено паролем)';

  @override
  String get delete => 'Видалити';

  @override
  String get deletePageMessage => 'Сторінку та всі зміни на ній буде видалено.';

  @override
  String deletePageTitle(int page) {
    return 'Видалити сторінку $page?';
  }

  @override
  String get deletePhoto => 'Видалити фото';

  @override
  String get deletePhotoMessage => 'Фото буде видалено зі сторінки.';

  @override
  String get deletePhotoTitle => 'Видалити фото?';

  @override
  String get deleteTextTitle => 'Видалити текст?';

  @override
  String get down => 'Вниз';

  @override
  String get draw => 'Малювати';

  @override
  String get drawing => 'Малювання';

  @override
  String get editText => 'Змінити текст';

  @override
  String get emptyFile => 'Файл порожній';

  @override
  String get enterText => 'Введіть текст';

  @override
  String errorWithDetails(String details) {
    return 'Помилка: $details';
  }

  @override
  String get fileNoLongerExists => 'Файл більше не існує';

  @override
  String get hasUnsavedChanges => 'Є незбережені зміни';

  @override
  String get highlighter => 'Маркер';

  @override
  String get highlighterHint => 'Напівпрозорий жовтий маркер';

  @override
  String get homeDescription =>
      'Відкривайте PDF, фото та текстові файли. Малюйте, додавайте текст, повертайте, переставляйте та видаляйте сторінки.';

  @override
  String get homeTitle => 'Редагуйте PDF\nза кілька дотиків';

  @override
  String get imagePrepareError => 'Не вдалося підготувати зображення';

  @override
  String get imageReadError =>
      'Не вдалося прочитати зображення (формат не підтримується пристроєм)';

  @override
  String get left => 'Ліворуч';

  @override
  String get nextPage => 'Наступна сторінка';

  @override
  String get noRecentDocuments => 'Нещодавніх документів поки немає';

  @override
  String get openFile => 'Відкрити файл';

  @override
  String get openFileTypes => 'Відкрити файл (PDF, фото, текст)';

  @override
  String get pageOrder => 'Порядок сторінок';

  @override
  String pagesAdded(int count) {
    return 'Додано сторінок: $count';
  }

  @override
  String get pdfSavedSuccessfully => 'PDF успішно збережено';

  @override
  String get photo => 'Фото';

  @override
  String get photoHint =>
      'Торкніться фото, щоб вибрати,\nперетягуйте, щоб перемістити';

  @override
  String get previousPage => 'Попередня сторінка';

  @override
  String get recentDocuments => 'Нещодавні документи';

  @override
  String get redo => 'Повторити';

  @override
  String get removeFromRecent => 'Видалити з нещодавніх';

  @override
  String get right => 'Праворуч';

  @override
  String get rotation => 'Поворот';

  @override
  String get save => 'Зберегти';

  @override
  String get saveAndShare => 'Зберегти й поділитися';

  @override
  String get savePdf => 'Зберегти PDF';

  @override
  String get share => 'Поділитися';

  @override
  String get shareFile => 'Поділитися файлом';

  @override
  String shareFileTitle(String fileName) {
    return 'Поділитися $fileName';
  }

  @override
  String get size => 'Розмір';

  @override
  String get tapPageForText => 'Торкніться місця на сторінці, щоб додати текст';

  @override
  String get textEditHint =>
      'Торкніться, щоб редагувати,\nутримуйте, щоб видалити';

  @override
  String get textPrepareError => 'Не вдалося підготувати текст для PDF';

  @override
  String get textTool => 'Текст';

  @override
  String todayAt(String time) {
    return 'Сьогодні, $time';
  }

  @override
  String get txtAndOthers => 'TXT та інші';

  @override
  String get undo => 'Скасувати';

  @override
  String get unsavedChanges => 'Незбережені зміни';

  @override
  String get unsavedChangesMessage =>
      'Усі незбережені зміни буде втрачено. Продовжити?';

  @override
  String get unsavedShareQuestion => 'Є незбережені зміни. Що надіслати?';

  @override
  String get unsupportedFormat =>
      'Цей формат не підтримується. Відкрийте PDF, фото або текстовий файл';

  @override
  String get up => 'Вгору';

  @override
  String get withoutChanges => 'Без змін';

  @override
  String get yes => 'Так';

  @override
  String yesterdayAt(String time) {
    return 'Учора, $time';
  }

  @override
  String get zoom => 'Масштаб';

  @override
  String get zoomIn => 'Наблизити';

  @override
  String get zoomOut => 'Віддалити';
}
