// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get add => 'Добавить';

  @override
  String get addPagesFromFile => 'Добавить страницы из файла';

  @override
  String get addPhoto => 'Добавить фото';

  @override
  String get addText => 'Добавить текст';

  @override
  String get cancel => 'Отмена';

  @override
  String get cannotDeleteOnlyPage => 'Нельзя удалить единственную страницу';

  @override
  String get clear => 'Очистить';

  @override
  String get clearList => 'Очистить список';

  @override
  String get clearRecentMessage =>
      'Локальные копии из списка недавних будут удалены. Исходные файлы не удаляются.';

  @override
  String get clearRecentTitle => 'Очистить недавние?';

  @override
  String get continueLabel => 'Продолжить';

  @override
  String couldNotDisplayPdf(String details) {
    return 'Не удалось отобразить PDF: $details';
  }

  @override
  String get couldNotOpenFile => 'Не удалось открыть файл';

  @override
  String couldNotOpenFileDetails(String details) {
    return 'Не удалось открыть файл: $details';
  }

  @override
  String get couldNotReadFile => 'Не удалось прочитать файл';

  @override
  String get couldNotReadPdf =>
      'Не удалось прочитать PDF (файл повреждён или защищён паролем)';

  @override
  String get delete => 'Удалить';

  @override
  String get deletePageMessage => 'Страница и все правки на ней будут удалены.';

  @override
  String deletePageTitle(int page) {
    return 'Удалить страницу $page?';
  }

  @override
  String get deletePhoto => 'Удалить фото';

  @override
  String get deletePhotoMessage => 'Фото будет удалено со страницы.';

  @override
  String get deletePhotoTitle => 'Удалить фото?';

  @override
  String get deleteTextTitle => 'Удалить текст?';

  @override
  String get down => 'Вниз';

  @override
  String get draw => 'Рисовать';

  @override
  String get drawing => 'Рисование';

  @override
  String get editText => 'Изменить текст';

  @override
  String get emptyFile => 'Файл пустой';

  @override
  String get enterText => 'Введите текст';

  @override
  String errorWithDetails(String details) {
    return 'Ошибка: $details';
  }

  @override
  String get fileNoLongerExists => 'Файл больше не существует';

  @override
  String get hasUnsavedChanges => 'Есть несохранённые изменения';

  @override
  String get highlighter => 'Маркер';

  @override
  String get highlighterHint => 'Полупрозрачный жёлтый маркер';

  @override
  String get homeDescription =>
      'Открывай PDF, фото и текстовые файлы. Рисуй, добавляй текст, поворачивай, переставляй и удаляй страницы.';

  @override
  String get homeTitle => 'Редактируй PDF\nза пару касаний';

  @override
  String get imagePrepareError => 'Не удалось подготовить изображение';

  @override
  String get imageReadError =>
      'Не удалось прочитать изображение (формат не поддерживается устройством)';

  @override
  String get left => 'Влево';

  @override
  String get nextPage => 'Следующая страница';

  @override
  String get noRecentDocuments => 'Недавних документов пока нет';

  @override
  String get openFile => 'Открыть файл';

  @override
  String get openFileTypes => 'Открыть файл (PDF, фото, текст)';

  @override
  String get pageOrder => 'Порядок страниц';

  @override
  String pagesAdded(int count) {
    return 'Добавлено страниц: $count';
  }

  @override
  String get pdfSavedSuccessfully => 'PDF сохранён успешно';

  @override
  String get photo => 'Фото';

  @override
  String get photoHint => 'Тап по фото — выбрать,\nтяните — переместить';

  @override
  String get previousPage => 'Предыдущая страница';

  @override
  String get recentDocuments => 'Недавние документы';

  @override
  String get redo => 'Вернуть';

  @override
  String get removeFromRecent => 'Удалить из недавних';

  @override
  String get right => 'Вправо';

  @override
  String get rotation => 'Поворот';

  @override
  String get save => 'Сохранить';

  @override
  String get saveAndShare => 'Сохранить и отправить';

  @override
  String get savePdf => 'Сохранить PDF';

  @override
  String get share => 'Поделиться';

  @override
  String get shareFile => 'Поделиться файлом';

  @override
  String shareFileTitle(String fileName) {
    return 'Поделиться $fileName';
  }

  @override
  String get size => 'Размер';

  @override
  String get tapPageForText => 'Нажми на место на странице для текста';

  @override
  String get textEditHint => 'Тап — править,\nудержание — удалить';

  @override
  String get textPrepareError => 'Не удалось подготовить текст для PDF';

  @override
  String get textTool => 'Текст';

  @override
  String todayAt(String time) {
    return 'Сегодня, $time';
  }

  @override
  String get txtAndOthers => 'TXT и другие';

  @override
  String get undo => 'Отмена';

  @override
  String get unsavedChanges => 'Несохранённые изменения';

  @override
  String get unsavedChangesMessage =>
      'Все несохранённые правки будут потеряны. Продолжить?';

  @override
  String get unsavedShareQuestion =>
      'Есть несохранённые изменения. Что отправить?';

  @override
  String get unsupportedFormat =>
      'Этот формат не поддерживается. Откройте PDF, фото или текстовый файл';

  @override
  String get up => 'Вверх';

  @override
  String get withoutChanges => 'Без изменений';

  @override
  String get yes => 'Да';

  @override
  String yesterdayAt(String time) {
    return 'Вчера, $time';
  }

  @override
  String get zoom => 'Зум';

  @override
  String get zoomIn => 'Приблизить';

  @override
  String get zoomOut => 'Отдалить';
}
