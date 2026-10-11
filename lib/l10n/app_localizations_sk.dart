// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovak (`sk`).
class AppLocalizationsSk extends AppLocalizations {
  AppLocalizationsSk([String locale = 'sk']) : super(locale);

  @override
  String get add => 'Pridať';

  @override
  String get addPagesFromFile => 'Pridať strany zo súboru';

  @override
  String get addPhoto => 'Pridať fotografiu';

  @override
  String get addText => 'Pridať text';

  @override
  String get cancel => 'Zrušiť';

  @override
  String get cannotDeleteOnlyPage => 'Jedinú stranu nemožno odstrániť';

  @override
  String get clear => 'Vymazať';

  @override
  String get clearList => 'Vymazať zoznam';

  @override
  String get clearRecentMessage => 'Lokálne kópie zo zoznamu nedávnych dokumentov sa odstránia. Pôvodné súbory sa neodstránia.';

  @override
  String get clearRecentTitle => 'Vymazať nedávne dokumenty?';

  @override
  String get continueLabel => 'Pokračovať';

  @override
  String couldNotDisplayPdf(String details) {
    return 'PDF sa nepodarilo zobraziť: $details';
  }

  @override
  String get couldNotOpenFile => 'Súbor sa nepodarilo otvoriť';

  @override
  String couldNotOpenFileDetails(String details) {
    return 'Súbor sa nepodarilo otvoriť: $details';
  }

  @override
  String get couldNotReadFile => 'Súbor sa nepodarilo načítať';

  @override
  String get couldNotReadPdf => 'PDF sa nepodarilo načítať (súbor môže byť poškodený alebo chránený heslom)';

  @override
  String get delete => 'Odstrániť';

  @override
  String get deletePageMessage => 'Strana a všetky úpravy na nej sa odstránia.';

  @override
  String deletePageTitle(int page) {
    return 'Odstrániť stranu $page?';
  }

  @override
  String get deletePhoto => 'Odstrániť fotografiu';

  @override
  String get deletePhotoMessage => 'Fotografia sa odstráni zo strany.';

  @override
  String get deletePhotoTitle => 'Odstrániť fotografiu?';

  @override
  String get deleteTextTitle => 'Odstrániť text?';

  @override
  String get down => 'Nadol';

  @override
  String get draw => 'Kresliť';

  @override
  String get drawing => 'Kreslenie';

  @override
  String get editText => 'Upraviť text';

  @override
  String get emptyFile => 'Súbor je prázdny';

  @override
  String get enterText => 'Zadajte text';

  @override
  String errorWithDetails(String details) {
    return 'Chyba: $details';
  }

  @override
  String get fileNoLongerExists => 'Súbor už neexistuje';

  @override
  String get hasUnsavedChanges => 'Existujú neuložené zmeny';

  @override
  String get highlighter => 'Zvýrazňovač';

  @override
  String get highlighterHint => 'Priesvitný žltý zvýrazňovač';

  @override
  String get homeDescription => 'Otvárajte PDF, fotografie a textové súbory. Kreslite, pridávajte text, otáčajte, presúvajte a odstraňujte strany.';

  @override
  String get homeTitle => 'Upravujte PDF\nna pár ťuknutí';

  @override
  String get imagePrepareError => 'Obrázok sa nepodarilo pripraviť';

  @override
  String get imageReadError => 'Obrázok sa nepodarilo načítať (formát zariadenie nepodporuje)';

  @override
  String get left => 'Doľava';

  @override
  String get nextPage => 'Nasledujúca strana';

  @override
  String get noRecentDocuments => 'Zatiaľ žiadne nedávne dokumenty';

  @override
  String get openFile => 'Otvoriť súbor';

  @override
  String get openFileTypes => 'Otvoriť súbor (PDF, fotografia, text)';

  @override
  String get pageOrder => 'Poradie strán';

  @override
  String pagesAdded(int count) {
    return 'Pridané strany: $count';
  }

  @override
  String get pdfSavedSuccessfully => 'PDF bolo úspešne uložené';

  @override
  String get photo => 'Fotografia';

  @override
  String get photoHint => 'Ťuknutím vyberte fotografiu,\npotiahnutím ju presuňte';

  @override
  String get previousPage => 'Predchádzajúca strana';

  @override
  String get recentDocuments => 'Nedávne dokumenty';

  @override
  String get redo => 'Znova';

  @override
  String get removeFromRecent => 'Odstrániť z nedávnych';

  @override
  String get right => 'Doprava';

  @override
  String get rotation => 'Otočenie';

  @override
  String get save => 'Uložiť';

  @override
  String get saveAndShare => 'Uložiť a zdieľať';

  @override
  String get savePdf => 'Uložiť PDF';

  @override
  String get share => 'Zdieľať';

  @override
  String get shareFile => 'Zdieľať súbor';

  @override
  String shareFileTitle(String fileName) {
    return 'Zdieľať $fileName';
  }

  @override
  String get size => 'Veľkosť';

  @override
  String get tapPageForText => 'Ťuknite na miesto na strane, kam chcete pridať text';

  @override
  String get textEditHint => 'Ťuknite na úpravu,\npodržte na odstránenie';

  @override
  String get textPrepareError => 'Text pre PDF sa nepodarilo pripraviť';

  @override
  String get textTool => 'Text';

  @override
  String todayAt(String time) {
    return 'Dnes, $time';
  }

  @override
  String get txtAndOthers => 'TXT a ďalšie';

  @override
  String get undo => 'Späť';

  @override
  String get unsavedChanges => 'Neuložené zmeny';

  @override
  String get unsavedChangesMessage => 'Všetky neuložené úpravy sa stratia. Pokračovať?';

  @override
  String get unsavedShareQuestion => 'Existujú neuložené zmeny. Čo chcete zdieľať?';

  @override
  String get unsupportedFormat => 'Tento formát nie je podporovaný. Otvorte PDF, fotografiu alebo textový súbor';

  @override
  String get up => 'Nahor';

  @override
  String get withoutChanges => 'Bez zmien';

  @override
  String get yes => 'Áno';

  @override
  String yesterdayAt(String time) {
    return 'Včera, $time';
  }

  @override
  String get zoom => 'Priblíženie';

  @override
  String get zoomIn => 'Priblížiť';

  @override
  String get zoomOut => 'Oddialiť';
}
