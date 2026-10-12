import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show listEquals;

extension _L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

// ===========================================================================
// Shared constants & pure helpers
// ===========================================================================

/// Text labels get the same padding (in PDF points) in the on-screen preview
/// and in the saved PNG, so what you see is exactly what you save (WYSIWYG).
const double _kTextPaddingPt = 3;

/// Labels are rasterised at 3x so they stay crisp when zoomed in a PDF reader.
const double _kTextPixelRatio = 3;

/// Zoom limits. Zoom works by laying the viewer out at `zoom x viewport` size
/// (so the PDF is re-rendered crisply, not just stretched) and panning it.
const double _kMinZoom = 1;
const double _kMaxZoom = 4;

/// Minimum width of an inserted photo (in pt) and the max pixel size of its raster.
const double _kMinImageWidthPt = 40;
const int _kStampMaxPixels = 1600;

/// The text selection menu in the viewer (Copy / Highlight / ...) may
/// trigger a "back" on the page. During this window after the last
/// selection event such calls are not treated as an attempt to exit.
const Duration _kSelectionMenuPopWindow = Duration(milliseconds: 1200);

// Highlighter: wide translucent yellow stroke. Multiply keeps dark PDF text
// readable while tinting the light background yellow.
const Color _kHighlighterColor = Color(0xFFFFEB3B);
const double _kHighlighterWidth = 20; // PDF points
const double _kHighlighterOpacity = 0.32;

const String _errUnsupportedFormat = 'unsupportedFormat';
const String _errImageRead = 'imageRead';
const String _errImagePrepare = 'imagePrepare';
const String _errEmptyFile = 'emptyFile';
const String _errTextPrepare = 'textPrepare';


const List<Color> _kPalette = <Color>[
  Color(0xFFE53935), // red
  Color(0xFF212121), // near-black
  Color(0xFF1E88E5), // blue
  Color(0xFF2E7D32), // green
  Color(0xFF8E24AA), // purple
];

/// Clockwise order of page rotations.
const List<PdfPageRotateAngle> _kRotationOrder = <PdfPageRotateAngle>[
  PdfPageRotateAngle.rotateAngle0,
  PdfPageRotateAngle.rotateAngle90,
  PdfPageRotateAngle.rotateAngle180,
  PdfPageRotateAngle.rotateAngle270,
];

/// Canonical (unrotated page, 0..1) -> display (rotated page, 0..1).
Offset _canonicalToDisplayNormalized(Offset p, PdfPageRotateAngle rotation) {
  switch (rotation) {
    case PdfPageRotateAngle.rotateAngle90:
      return Offset(1 - p.dy, p.dx);
    case PdfPageRotateAngle.rotateAngle180:
      return Offset(1 - p.dx, 1 - p.dy);
    case PdfPageRotateAngle.rotateAngle270:
      return Offset(p.dy, 1 - p.dx);
    case PdfPageRotateAngle.rotateAngle0:
      return p;
  }
}

/// Exact inverse of [_canonicalToDisplayNormalized].
Offset _displayToCanonicalNormalized(Offset p, PdfPageRotateAngle rotation) {
  switch (rotation) {
    case PdfPageRotateAngle.rotateAngle90:
      return Offset(p.dy, 1 - p.dx);
    case PdfPageRotateAngle.rotateAngle180:
      return Offset(1 - p.dx, 1 - p.dy);
    case PdfPageRotateAngle.rotateAngle270:
      return Offset(1 - p.dy, p.dx);
    case PdfPageRotateAngle.rotateAngle0:
      return p;
  }
}

PdfColor _pdfColor(Color c) => PdfColor(
      (c.r * 255).round().clamp(0, 255).toInt(),
      (c.g * 255).round().clamp(0, 255).toInt(),
      (c.b * 255).round().clamp(0, 255).toInt(),
    );

/// `inherit: false` keeps the Material theme from leaking into the preview,
/// so the on-screen label and the rasterised PNG use identical metrics.
TextStyle _labelStyle(double fontSize, Color color) => TextStyle(
      inherit: false,
      fontFamily: _kTextFontFamily,
      fontSize: fontSize,
      color: color,
    );

/// Font used for text labels. The SAME file is declared in pubspec.yaml (for
/// the on-screen preview) and embedded into the PDF (so the saved text is real,
/// selectable and searchable text, with Cyrillic / Slovak / Ukrainian support).
const String _kTextFontFamily = 'PdfEditorText';
const String _kTextFontAsset = 'assets/fonts/DejaVuSans.ttf';

/// Names of the files embedded into the saved PDF. They hold the editable
/// source of the user's marks, so the marks can be edited again later.
const String _kEditableBaseName = 'pdf_editor_base.pdf';
const String _kEditableDataName = 'pdf_editor_annotations.json';
const String _kEditableImagePrefix = 'pdf_editor_image_';
const int _kEditableFormat = 1;

/// Loads (and caches) the TrueType font used to write text into the PDF.
class _PdfTextFont {
  static Uint8List? _cache;
  static bool _tried = false;

  static Future<Uint8List?> load() async {
    if (_cache != null || _tried) return _cache;
    _tried = true;
    try {
      final ByteData data = await rootBundle.load(_kTextFontAsset);
      _cache = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return _cache;
    } catch (e) {
      debugPrint('Text font asset not found ($e). Trying system fonts.');
    }
    const List<String> candidates = <String>[
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
      r'C:\Windows\Fonts\arial.ttf',
      '/Library/Fonts/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ];
    for (final String path in candidates) {
      try {
        final File f = File(path);
        if (await f.exists()) {
          _cache = await f.readAsBytes();
          return _cache;
        }
      } catch (_) {}
    }
    return null; // caller falls back to the old PNG way
  }
}

/// Small built-in strings for the search UI (ru / en / sk / uk), so no ARB
/// file has to be touched.
String _tr(BuildContext context, String key) {
  const Map<String, Map<String, String>> t = <String, Map<String, String>>{
    'fitWidth': <String, String>{
  'en': 'Fit to width',
  'ru': 'По ширине',
  'sk': 'Prispôsobiť šírke',
  'uk': 'За шириною',
},
    'search': <String, String>{
      'en': 'Search',
      'ru': 'Поиск',
      'sk': 'Hľadať',
      'uk': 'Пошук',
    },
    'searchHint': <String, String>{
      'en': 'Find in document',
      'ru': 'Найти в документе',
      'sk': 'Nájsť v dokumente',
      'uk': 'Знайти в документі',
    },
    'notFound': <String, String>{
      'en': 'Nothing found',
      'ru': 'Ничего не найдено',
      'sk': 'Nič sa nenašlo',
      'uk': 'Нічого не знайдено',
    },
    'prev': <String, String>{
      'en': 'Previous',
      'ru': 'Предыдущее',
      'sk': 'Predchádzajúce',
      'uk': 'Попереднє',
    },
    'next': <String, String>{
      'en': 'Next',
      'ru': 'Следующее',
      'sk': 'Ďalšie',
      'uk': 'Наступне',
    },
    'close': <String, String>{
      'en': 'Close search',
      'ru': 'Закрыть поиск',
      'sk': 'Zavrieť hľadanie',
      'uk': 'Закрити пошук',
    },
  };
  final String lang = Localizations.localeOf(context).languageCode;
  final Map<String, String>? m = t[key];
  return m == null ? key : (m[lang] ?? m['en'] ?? key);
}

// ===========================================================================
// Language persistence
// ===========================================================================

/// Remembers the selected UI language between app launches.
/// Uses a tiny file in the app support directory, so no extra package is needed.
class _LanguageStore {
  static const List<String> supported = <String>['en', 'ru', 'sk', 'uk'];

  static Future<File> _file() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}language.txt');
  }

  static Future<String?> load() async {
    try {
      final File f = await _file();
      if (!await f.exists()) return null;
      final String code = (await f.readAsString()).trim();
      return supported.contains(code) ? code : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String code) async {
    try {
      final File f = await _file();
      await f.writeAsString(code, flush: true);
    } catch (e) {
      debugPrint('Language save error: $e');
    }
  }
}

/// Optional: call this in main() before runApp() so the app starts directly
/// in the saved language (no flash of the default one):
///
///   WidgetsFlutterBinding.ensureInitialized();
///   final Locale? saved = await loadSavedLocale();
///   runApp(MyApp(initialLocale: saved));
Future<Locale?> loadSavedLocale() async {
  final String? code = await _LanguageStore.load();
  return code == null ? null : Locale(code);
}

// ===========================================================================
// File formats: detection and conversion to PDF
// ===========================================================================
//
// Idea: any supported file (photo, text) is turned into a regular PDF,
// and then the whole existing editor works on it: drawing, text, zoom,
// page rotation, saving. This way no separate viewer is needed for
// each format.

const List<String> _kImageExtensions = <String>[
  'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'heic', 'heif',
];

const List<String> _kTextExtensions = <String>[
  'txt', 'md', 'log', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml', 'ini', 'conf',
];

/// Everything that can be picked in the open-file dialog.
const List<String> _kOpenExtensions = <String>[
  'pdf',
  ..._kImageExtensions,
  ..._kTextExtensions,
];

/// Long side of a page created from a photo (A4 = 842 pt). The short side
/// is computed from the image proportions, so there are no white margins around the photo.
const double _kPageLongSidePt = 842;

/// Large photos are downscaled to this long side (in pixels) so the
/// PDF does not balloon to tens of megabytes.
const int _kImageMaxPixels = 2400;

/// Limits for text files.
const int _kMaxTextChars = 300000;
const int _kMaxTextPages = 300;

enum _FileKind { pdf, image, text, unsupported }

String _extensionOf(String? name) {
  if (name == null) return '';
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

bool _hasSignature(Uint8List b, List<int> sig, [int offset = 0]) {
  if (b.length < offset + sig.length) return false;
  for (int i = 0; i < sig.length; i++) {
    if (b[offset + i] != sig[i]) return false;
  }
  return true;
}

bool _looksLikeText(Uint8List bytes) {
  final int n = math.min(bytes.length, 4096);
  if (n == 0) return false;
  for (int i = 0; i < n; i++) {
    if (bytes[i] == 0) return false; // a zero byte = binary file
  }
  final String sample = utf8.decode(bytes.sublist(0, n), allowMalformed: true);
  int broken = 0;
  for (final int unit in sample.codeUnits) {
    if (unit == 0xFFFD) broken++;
  }
  return broken <= sample.length * 0.02 + 1;
}

/// The format is detected by content (signature), not only by name:
/// a file coming from another app may have no extension at all.
_FileKind _detectFileKind(Uint8List bytes, {String? name}) {
  if (_hasSignature(bytes, const <int>[0x25, 0x50, 0x44, 0x46])) {
    return _FileKind.pdf; // %PDF
  }
  if (_hasSignature(bytes, const <int>[0x89, 0x50, 0x4E, 0x47]) || // PNG
      _hasSignature(bytes, const <int>[0xFF, 0xD8, 0xFF]) || // JPEG
      _hasSignature(bytes, const <int>[0x47, 0x49, 0x46, 0x38]) || // GIF
      _hasSignature(bytes, const <int>[0x42, 0x4D]) || // BMP
      (_hasSignature(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
          _hasSignature(bytes, const <int>[0x57, 0x45, 0x42, 0x50], 8))) {
    return _FileKind.image; // WEBP = RIFF....WEBP
  }
  if (_hasSignature(bytes, const <int>[0x66, 0x74, 0x79, 0x70], 4)) {
    // 'ftyp' - HEIC/HEIF container (iPhone photos)
    return _FileKind.image;
  }

  final String ext = _extensionOf(name);
  if (ext == 'pdf') return _FileKind.pdf;
  if (_kImageExtensions.contains(ext)) return _FileKind.image;
  if (_kTextExtensions.contains(ext) || _looksLikeText(bytes)) {
    return _FileKind.text;
  }
  return _FileKind.unsupported;
}

/// Turns any supported file into a PDF. A PDF is returned as is.
/// Throws a [FormatException] with a user-friendly message.
Future<Uint8List> _convertToPdf(Uint8List bytes, {String? name}) async {
  switch (_detectFileKind(bytes, name: name)) {
    case _FileKind.pdf:
      return bytes;
    case _FileKind.image:
      return _imageToPdf(bytes);
    case _FileKind.text:
      return _textToPdf(bytes);
    case _FileKind.unsupported:
      throw const FormatException(
        _errUnsupportedFormat,
      );
  }
}

class _DecodedImage {
  const _DecodedImage(this.png, this.width, this.height);

  final Uint8List png;
  final int width;
  final int height;
}

/// Decodes any supported photo and returns a PNG (long side
/// at most [maxSide] px).
Future<_DecodedImage> _decodeImageToPng(Uint8List bytes, int maxSide) async {
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int w = descriptor.width;
      final int h = descriptor.height;
      final bool shrink = math.max(w, h) > maxSide;

      // Only one side is set - the other is derived from the proportions.
      codec = await descriptor.instantiateCodec(
        targetWidth: shrink && w >= h ? maxSide : null,
        targetHeight: shrink && h > w ? maxSide : null,
      );
    } catch (_) {
      throw const FormatException(
        _errImageRead,
      );
    }

    final ui.FrameInfo frame = await codec.getNextFrame(); // for GIF - the first frame
    final ui.Image image = frame.image;
    final int iw = image.width;
    final int ih = image.height;
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (data == null || iw <= 0 || ih <= 0) {
      throw const FormatException(_errImagePrepare);
    }
    return _DecodedImage(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      iw,
      ih,
    );
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// One photo = one PDF page with the same proportions.
Future<Uint8List> _imageToPdf(Uint8List bytes) async {
  final _DecodedImage img = await _decodeImageToPng(bytes, _kImageMaxPixels);
  final int iw = img.width;
  final int ih = img.height;

  final double k = _kPageLongSidePt / math.max(iw, ih);
  final double pageW = iw * k;
  final double pageH = ih * k;

  final PdfDocument doc = PdfDocument();
  try {
    doc.pageSettings.margins.all = 0;
    doc.pageSettings.size = Size(pageW, pageH);
    final PdfPage page = doc.pages.add();
    final Size client = page.getClientSize();

    // contain: the picture is not distorted even if the page size was rounded.
    final double fit =
        math.min(client.width / iw, client.height / ih).toDouble();
    final double dw = iw * fit;
    final double dh = ih * fit;
    page.graphics.drawImage(
      PdfBitmap(img.png),
      Rect.fromLTWH((client.width - dw) / 2, (client.height - dh) / 2, dw, dh),
    );
    return Uint8List.fromList(await doc.save());
  } finally {
    doc.dispose();
  }
}

// ===========================================================================
// Placed items (text labels and photos)
// ===========================================================================
//
// A signature or photo is stored like this:
//  - `center`: center in CANONICAL page coordinates (before rotation), 0..1;
//  - `turns`: how many clockwise quarter turns the content is
//    rotated relative to the canonical page.
//
// At creation time turns = -(page rotation), so on an already
// flipped page the signature looks upright. If the page is rotated later,
// the element rotates with it. On screen it is rotated by
// (page rotation + turns) quarter turns.

/// Clockwise quarter turns (0..3) for a page rotation.
int _quarterTurns(PdfPageRotateAngle rotation) =>
    _kRotationOrder.indexOf(rotation);

double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

/// Size of a label in pt (with padding) - the same metrics as the saved PNG.
Size _measureTextSize(String text, double fontSize, {required double maxWidth}) {
  const double ratio = _kTextPixelRatio;
  const double pad = _kTextPaddingPt * ratio;
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: _labelStyle(fontSize * ratio, const Color(0xFF000000)),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1.0, (maxWidth - 2 * _kTextPaddingPt) * ratio));
  final Size size = Size(maxWidth, (painter.height + pad * 2) / ratio);
  painter.dispose();
  return size;
}

/// Where the element will actually end up on the page (in pt, canonical system).
/// Used for both preview and saving - which is why they match.
class _Placement {
  const _Placement({
    required this.content,
    required this.bbox,
    required this.center,
    required this.fit,
  });

  /// Content size (before rotation), already shrunk to fit the page.
  final Size content;

  /// Footprint on the canonical page (taking the turns rotation into account).
  final Size bbox;

  /// Center in pt, clamped so the element does not leave the page.
  final Offset center;

  /// Shrink factor (1 = no shrinking).
  final double fit;
}

_Placement _placementOf(_PlacedAnnotation a, Size page) {
  final Size raw = a.contentSizePt;
  final bool odd = a.turns.isOdd;
  final double rawBw = odd ? raw.height : raw.width;
  final double rawBh = odd ? raw.width : raw.height;

  final double fit = math.min(
    1.0,
    math.min(
      page.width / math.max(0.0001, rawBw),
      page.height / math.max(0.0001, rawBh),
    ),
  );
  final Size bbox = Size(rawBw * fit, rawBh * fit);
  final double hx = bbox.width / 2;
  final double hy = bbox.height / 2;

  final double cx = (a.center.dx * page.width)
      .clamp(hx, math.max(hx, page.width - hx))
      .toDouble();
  final double cy = (a.center.dy * page.height)
      .clamp(hy, math.max(hy, page.height - hy))
      .toDouble();

  return _Placement(
    content: Size(raw.width * fit, raw.height * fit),
    bbox: bbox,
    center: Offset(cx, cy),
    fit: fit,
  );
}

/// Rotates a PNG by [turns] clockwise quarter turns.
Future<Uint8List> _rotatePngQuarterTurns(Uint8List png, int turns) async {
  final int k = turns % 4;
  if (k == 0) return png;

  final ui.Codec codec = await ui.instantiateImageCodec(png);
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;
    final int w = src.width;
    final int h = src.height;
    final bool odd = k.isOdd;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    switch (k) {
      case 1:
        canvas.translate(h.toDouble(), 0);
        break;
      case 2:
        canvas.translate(w.toDouble(), h.toDouble());
        break;
      default:
        canvas.translate(0, w.toDouble());
    }
    canvas.rotate(k * math.pi / 2);
    canvas.drawImage(src, Offset.zero, Paint()..filterQuality = FilterQuality.none);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image out = await picture.toImage(odd ? h : w, odd ? w : h);
    picture.dispose();
    src.dispose();

    final ByteData? data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (data == null) {
      throw const FormatException(_errImagePrepare);
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    codec.dispose();
  }
}

/// Text file -> A4 pages. Text is drawn with Flutter and
/// placed into the PDF as an image (like labels in the editor), so
/// Cyrillic and any other alphabets work without custom fonts.
Future<Uint8List> _textToPdf(Uint8List bytes) async {
  String text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\t', '    ');
  if (text.trim().isEmpty) {
    throw const FormatException(_errEmptyFile);
  }
  if (text.length > _kMaxTextChars) text = text.substring(0, _kMaxTextChars);

  const double pageW = 595;
  const double pageH = 842;
  const double margin = 40;
  const double contentW = pageW - margin * 2;
  const double contentH = pageH - margin * 2;
  const double ratio = 2;

  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: _labelStyle(11, const Color(0xFF212121)).copyWith(height: 1.3),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: contentW);

  // Pagination + storing the text of each line.
  final List<double> starts = <double>[0];
  final List<double> ends = <double>[];
  final List<_TextLine> lines = <_TextLine>[];
  double lastBottom = 0;
  int lastEnd = 0;
  bool capped = false;

  for (final ui.LineMetrics m in painter.computeLineMetrics()) {
    final double top = m.baseline - m.ascent;
    final double bottom = m.baseline + m.descent;
    if (bottom - starts.last > contentH && top > starts.last + 0.5) {
      ends.add(lastBottom);
      if (starts.length >= _kMaxTextPages) {
        capped = true;
        break;
      }
      starts.add(top);
    }
    lastBottom = bottom;

    final TextPosition pos = painter.getPositionForOffset(
      Offset(m.left + 1, m.baseline - m.ascent / 2),
    );
    final TextRange range = painter.getLineBoundary(pos);
    if (range.start >= lastEnd && range.end > range.start) {
      lastEnd = range.end;
      final String line = text
          .substring(range.start, math.min(range.end, text.length))
          .replaceAll(RegExp(r'[\r\n]+$'), '');
      if (line.trim().isNotEmpty) {
        lines.add(_TextLine(
          page: starts.length - 1,
          top: top,
          bottom: bottom,
          left: m.left,
          text: line,
        ));
      }
    }
  }
  if (!capped) ends.add(lastBottom);

  final Uint8List? fontData = await _PdfTextFont.load();
  final PdfDocument doc = PdfDocument();
  try {
    doc.pageSettings.margins.all = 0;
    doc.pageSettings.size = const Size(pageW, pageH);

    // ---------- VECTOR PATH: actual text, to be searched for and copied ----------
    if (fontData != null) {
      try {
        final PdfTrueTypeFont font = PdfTrueTypeFont(fontData, 11);
        final PdfSolidBrush brush = PdfSolidBrush(PdfColor(0x21, 0x21, 0x21));
        final PdfStringFormat format = PdfStringFormat(
          wordWrap: PdfWordWrapType.none,
          lineAlignment: PdfVerticalAlignment.top,
        );

        for (int i = 0; i < starts.length; i++) {
          final PdfPage page = doc.pages.add();
          for (final _TextLine l in lines.where((_TextLine l) => l.page == i)) {
            // Center the PDF font string within the Flutter string (due to height: 1.3).
            final double y = margin +
                (l.top - starts[i]) +
                ((l.bottom - l.top) - font.height) / 2;
            page.graphics.drawString(
              l.text,
              font,
              brush: brush,
              bounds: Rect.fromLTWH(margin + l.left, y, 0, 0),
              format: format,
            );
          }
        }
        return Uint8List.fromList(await doc.save());
      } catch (e) {
        debugPrint('Vector text PDF failed, using PNG fallback: $e');
        // Discard the incomplete document and switch to the raster path.
        while (doc.pages.count > 0) {
          doc.pages.removeAt(0);
        }
      }
    }

    // ---------- BACKUP PATH: how it used to be (PNG, non-searchable) ----------
    for (int i = 0; i < starts.length; i++) {
      final double start = starts[i];
      final double visibleH = math.min(contentH, ends[i] - start + 1);

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.scale(ratio);
      canvas.clipRect(Rect.fromLTWH(margin, margin, contentW, visibleH));
      painter.paint(canvas, Offset(margin, margin - start));

      final ui.Picture picture = recorder.endRecording();
      final ui.Image image =
          await picture.toImage((pageW * ratio).round(), (pageH * ratio).round());
      picture.dispose();
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        throw const FormatException(_errTextPrepare);
      }

      final PdfPage page = doc.pages.add();
      final Size client = page.getClientSize();
      page.graphics.drawImage(
        PdfBitmap(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)),
        Rect.fromLTWH(0, 0, client.width, client.height),
      );
    }

    return Uint8List.fromList(await doc.save());
  } finally {
    painter.dispose();
    doc.dispose();
  }
}
// ===========================================================================
// Recent documents + sharing helpers
// ===========================================================================

String _safeFileName(String name) {
  final String cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  return cleaned.isEmpty ? 'document' : cleaned;
}

String _mimeForName(String name) {
  switch (_extensionOf(name)) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    case 'json':
      return 'application/json';
    case 'xml':
      return 'application/xml';
    case 'csv':
      return 'text/csv';
    case 'txt':
    case 'md':
    case 'log':
    case 'tsv':
    case 'yaml':
    case 'yml':
    case 'ini':
    case 'conf':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

String _editedPdfName(String sourceName) {
  final String safe = _safeFileName(sourceName);
  final int dot = safe.lastIndexOf('.');
  final String base = dot > 0 ? safe.substring(0, dot) : safe;
  return base.startsWith('edited_') ? '$base.pdf' : 'edited_$base.pdf';
}

class _RecentDocument {
  const _RecentDocument({
    required this.name,
    required this.path,
    required this.lastOpened,
    required this.size,
  });

  final String name;
  final String path;
  final DateTime lastOpened;
  final int size;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'path': path,
        'lastOpened': lastOpened.toIso8601String(),
        'size': size,
      };

  factory _RecentDocument.fromJson(Map<String, dynamic> json) {
    return _RecentDocument(
      name: json['name'] as String? ?? 'document.pdf',
      path: json['path'] as String? ?? '',
      lastOpened: DateTime.tryParse(json['lastOpened'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class _RecentDocumentResult {
  const _RecentDocumentResult({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class _RecentDocumentsService {
  static const int _maxDocuments = 20;

  static Future<Directory> _directory() async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      '${root.path}${Platform.pathSeparator}pdf_editor_recent',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _indexFile() async {
    final Directory dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}recent.json');
  }

  static Future<List<_RecentDocument>> load() async {
    try {
      final File index = await _indexFile();
      if (!await index.exists()) return <_RecentDocument>[];
      final String raw = await index.readAsString();
      if (raw.trim().isEmpty) return <_RecentDocument>[];

      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <_RecentDocument>[];

      final List<_RecentDocument> result = <_RecentDocument>[];
      for (final Object? item in decoded) {
        if (item is! Map) continue;
        final _RecentDocument document = _RecentDocument.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (document.path.isNotEmpty && await File(document.path).exists()) {
          result.add(document);
        }
      }
      result.sort((_RecentDocument a, _RecentDocument b) =>
          b.lastOpened.compareTo(a.lastOpened));
      return result;
    } catch (_) {
      return <_RecentDocument>[];
    }
  }

  static Future<void> _saveIndex(List<_RecentDocument> documents) async {
    final File index = await _indexFile();
    await index.writeAsString(
      jsonEncode(documents.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

 static Future<bool> _sameContent(_RecentDocument d, Uint8List bytes) async {
  if (d.size != bytes.length) return false;
  try {
    final File f = File(d.path);
    if (!await f.exists()) return false;
    return listEquals(await f.readAsBytes(), bytes);
  } catch (_) {
    return false;
  }
}
static Future<String> add({
  required Uint8List bytes,
  required String fileName,
  String? replacePath,
}) async {
  final Directory dir = await _directory();
  final List<_RecentDocument> documents = await load();

  final List<_RecentDocument> old = <_RecentDocument>[];
  for (final _RecentDocument d in documents) {
    if (replacePath != null && d.path == replacePath) {
      old.add(d);
    } else if (d.name == fileName && await _sameContent(d, bytes)) {
      old.add(d);
    }
  }
  for (final _RecentDocument d in old) {
    final File f = File(d.path);
    if (await f.exists()) await f.delete();
    documents.remove(d);
  }

  final String stored =
      '${DateTime.now().microsecondsSinceEpoch}_${_safeFileName(fileName)}';
  final File copy = File('${dir.path}${Platform.pathSeparator}$stored');
  await copy.writeAsBytes(bytes, flush: true);

  documents.insert(
    0,
    _RecentDocument(
      name: fileName,
      path: copy.path,
      lastOpened: DateTime.now(),
      size: bytes.length,
    ),
  );

  while (documents.length > _maxDocuments) {
    final _RecentDocument removed = documents.removeLast();
    final File f = File(removed.path);
    if (await f.exists()) await f.delete();
  }
  await _saveIndex(documents);
  return copy.path;
}
  static Future<Uint8List?> read(_RecentDocument document) async {
    final File file = File(document.path);
    if (!await file.exists()) return null;
    final Uint8List bytes = await file.readAsBytes();

    final List<_RecentDocument> documents = await load();
    documents.removeWhere((_RecentDocument d) => d.path == document.path);
    documents.insert(
      0,
      _RecentDocument(
        name: document.name,
        path: document.path,
        lastOpened: DateTime.now(),
        size: bytes.length,
      ),
    );
    await _saveIndex(documents);
    return bytes;
  }

  static Future<void> remove(_RecentDocument document) async {
    final File file = File(document.path);
    if (await file.exists()) await file.delete();
    final List<_RecentDocument> documents = await load();
    documents.removeWhere((_RecentDocument d) => d.path == document.path);
    await _saveIndex(documents);
  }

  static Future<void> clear() async {
    final List<_RecentDocument> documents = await load();
    for (final _RecentDocument document in documents) {
      final File file = File(document.path);
      if (await file.exists()) await file.delete();
    }
    await _saveIndex(<_RecentDocument>[]);
  }
}

class _RecentDocumentsScreen extends StatefulWidget {
  const _RecentDocumentsScreen();

  @override
  State<_RecentDocumentsScreen> createState() => _RecentDocumentsScreenState();
}

class _RecentDocumentsScreenState extends State<_RecentDocumentsScreen> {
  bool _loading = true;
  List<_RecentDocument> _documents = <_RecentDocument>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<_RecentDocument> documents = await _RecentDocumentsService.load();
    if (!mounted) return;
    setState(() {
      _documents = documents;
      _loading = false;
    });
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _date(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime value = DateTime(date.year, date.month, date.day);
    final int days = today.difference(value).inDays;
    final String time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (days == 0) return context.l10n.todayAt(time);
    if (days == 1) return context.l10n.yesterdayAt(time);
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}, $time';
  }

  Future<void> _open(_RecentDocument document) async {
    final Uint8List? bytes = await _RecentDocumentsService.read(document);
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.fileNoLongerExists)),
      );
      await _load();
      return;
    }
    Navigator.of(context).pop(
      _RecentDocumentResult(bytes: bytes, fileName: document.name),
    );
  }

  Future<void> _remove(_RecentDocument document) async {
    await _RecentDocumentsService.remove(document);
    await _load();
  }

  Future<void> _clearAll() async {
    if (_documents.isEmpty) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.clearRecentTitle),
        content: Text(context.l10n.clearRecentMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.clear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _RecentDocumentsService.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.recentDocuments),
        actions: <Widget>[
          if (_documents.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clearList,
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.history_rounded, size: 72),
                      const SizedBox(height: 16),
                      Text(context.l10n.noRecentDocuments),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _documents.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final _RecentDocument document = _documents[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file_rounded),
                      title: Text(
                        document.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${_date(document.lastOpened)} • ${_size(document.size)}'),
                      onTap: () => _open(document),
                      trailing: IconButton(
                        tooltip: context.l10n.removeFromRecent,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _remove(document),
                      ),
                    );
                  },
                ),
    );
  }
}

// ===========================================================================
// Widget
// ===========================================================================

/// Public entry point. Wraps the editor in its own theme, so the screen looks
/// the same no matter how the host app is themed (dialogs included).
class PdfEditorScreen extends StatelessWidget {
  const PdfEditorScreen({
    super.key,
    required this.onLanguageChanged,
  });

  final ValueChanged<Locale> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _buildEditorTheme(Theme.of(context)),
      child: _PdfEditorView(
        onLanguageChanged: onLanguageChanged,
      ),
    );
  }
}

ThemeData _buildEditorTheme(ThemeData base) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F46E5),
    brightness: base.brightness,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLow,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: base.sliderTheme.copyWith(trackHeight: 4),
  );
}

class _PdfEditorView extends StatefulWidget {
   const _PdfEditorView({
    required this.onLanguageChanged,
  });
  final ValueChanged<Locale> onLanguageChanged;

  @override
  State<_PdfEditorView> createState() => _PdfEditorViewState();
}

enum _EditorTool { none, draw, highlight, text, image }

class _PdfEditorViewState extends State<_PdfEditorView>
    with SingleTickerProviderStateMixin {
  final PdfViewerController controller = PdfViewerController();
static const MethodChannel _openFileChannel =
    MethodChannel('pdf_editor/open_file');
  Uint8List? pdfBytes;
  Uint8List? _originalFileBytes;
  String _currentFileName = 'document.pdf';
  int _documentRevision = 0;
  bool _documentLoaded = false;
  int _currentPage = 1;
  String? _lastSavedRecentPath;
  Offset? _lastTapPosition;
Duration? _lastTapTime;
  /// Page we must land on after a (re)load. While set, the viewer's own
  /// onPageChanged events are ignored: right after a rotate/move the viewer
  /// re-lays out and briefly reports a wrong page (e.g. page 2).
  int? _pendingPage;
  _EditorTool _tool = _EditorTool.none;

  /// True while an async operation (rotate / move / delete / save) is running.
  /// Prevents double-taps from racing two edits against the same bytes.
  bool _busy = false;

  /// True when there is anything that has not been saved yet.
  bool _dirty = false;

  Color _penColor = _kPalette.first;
  double _penWidth = 2; // in PDF points, same unit as the saved line width
  bool _immersive = false;
  // All custom edits live in ONE ordered list. That single source of truth is
  // what makes undo/redo work the same way for strokes and text.
  //
  // Coordinates are stored in the ORIGINAL (unrotated) PDF page coordinate
  // system, normalized to 0..1, so edits follow the page when it is rotated.
  final List<_PageAnnotation> _annotations = <_PageAnnotation>[];
  final List<_PageAnnotation> _redoStack = <_PageAnnotation>[];
  _StrokeAnnotation? _activeStroke;

  /// Photo selected in "Photo" mode (frame + resize handle).
  _ImageAnnotation? _selectedImage;
  _TextAnnotation? _selectedText;

  // Text selection state in the built-in viewer. Needed to
  // tell a tap in its menu (Copy / Highlight ...) from a real "back".
  bool _textSelectionActive = false;
  DateTime _lastSelectionEvent = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- search ----
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  PdfTextSearchResult _searchResult = PdfTextSearchResult();
  bool _searchNotFound = false;

  /// While searching, the viewer shows a temporary copy of the document in
  /// which the user's marks are already written as real text. That is what
  /// makes the added text findable. The editable working document
  /// ([pdfBytes]) is never replaced by this copy.
  Uint8List? _searchCopyBytes;
  String? _pendingSearchQuery;
  Timer? _searchDebounce;
  String _searchedQuery = '';

  /// The selected photo, if it still exists and is on the current page.
  _ImageAnnotation? get _selected {
    final _ImageAnnotation? i = _selectedImage;
    if (i == null ||
        !_annotations.contains(i) ||
        i.pageIndex != _currentPage - 1) {
      return null;
    }
    return i;
  }

  List<_PageInfo> _pageInfos = <_PageInfo>[];

  // ---- zoom / pan state ----
  /// Committed zoom: the viewer really is laid out this many times larger.
  double _zoom = 1;

  /// Top-left corner of the zoomed content, in viewport pixels (<= 0).
  Offset _pan = Offset.zero;

  /// Fingers currently touching the screen (used for pinch + pan).
  final Map<int, Offset> _pointers = <int, Offset>{};
  bool _pinching = false;
  double _pinchStartDistance = 1;
  Offset _pinchStartFocal = Offset.zero;
  double _liveScale = 1;
  Offset _liveFocal = Offset.zero;
  Size _viewport = Size.zero;
  bool _settling = false;
  int _settleSerial = 0;

  // ---- inertial panning ("slide" after a quick swipe while zoomed) ----
  Ticker? _flingTicker;
  FrictionSimulation? _flingX;
  FrictionSimulation? _flingY;
  VelocityTracker? _velocityTracker;
  bool _panning = false;

  /// Friction of the slide. Lower = slides longer.
  static const double _kFlingDrag = 0.135;
  @override
  void initState() {
    super.initState();

    _openFileChannel.setMethodCallHandler(
      (MethodCall call) async {
        if (call.method == 'openPdf') {
          await _openExternalPayload(call.arguments);
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLanguage();
      _checkInitialPdf();
    });
  }

  @override
  void dispose() {
    _openFileChannel.setMethodCallHandler(null);
    _flingTicker?.dispose();
    _searchDebounce?.cancel();
    _searchResult.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // =================== SMALL HELPERS ===================
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _localizedFormatException(FormatException e) {
    final String code = e.message;
    switch (code) {
      case _errUnsupportedFormat:
        return context.l10n.unsupportedFormat;
      case _errImageRead:
        return context.l10n.imageReadError;
      case _errImagePrepare:
        return context.l10n.imagePrepareError;
      case _errEmptyFile:
        return context.l10n.emptyFile;
      case _errTextPrepare:
        return context.l10n.textPrepareError;
      default:
        return code;
    }
  }
Future<void> _toggleImmersive() async {
  if (pdfBytes == null) return;

  final bool next = !_immersive;

  setState(() {
    _immersive = next;
  });

  await SystemChrome.setEnabledSystemUIMode(
    next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );

  if (!mounted) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _settleViewer();
  });
}
  Future<bool> _confirm({
    required String title,
    required String message,
    String? confirmLabel,
    IconData icon = Icons.help_outline_rounded,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon: Icon(icon),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, maxLines: 5, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel ?? context.l10n.yes),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _confirmDiscardChanges() {
    if (!_dirty) return Future<bool>.value(true);
    return _confirm(
      title: context.l10n.unsavedChanges,
      message: context.l10n.unsavedChangesMessage,
      confirmLabel: context.l10n.continueLabel,
      icon: Icons.warning_amber_rounded,
    );
  }

  Future<void> _goHome() async {
    if (_busy || !await _confirmDiscardChanges()) return;
    if (!mounted) return;

    controller.annotationMode = PdfAnnotationMode.none;
    controller.zoomLevel = 1;

    setState(() {
      pdfBytes = null;
      _originalFileBytes = null;
      _currentFileName = 'document.pdf';
      _pageInfos = <_PageInfo>[];
      _annotations.clear();
      _redoStack.clear();
      _selectedText = null;
      _selectedImage = null;
      _activeStroke = null;
      _currentPage = 1;
      _pendingPage = null;
      _tool = _EditorTool.none;
      _documentLoaded = false;
      _documentRevision++;
      _resetZoomState();
      _dirty = false;
    });
  }

  /// Runs [action] as the only async operation in flight and reports errors
  /// instead of letting them escape as unhandled exceptions.
 Future<void> _runExclusive(Future<void> Function() action) async {
  if (_busy) return;

  setState(() => _busy = true);

  try {
    await action();
  } catch (e) {
    if (!mounted) return;

    _showMessage(
      context.l10n.errorWithDetails(
        e.toString(),
      ),
    );
  } finally {
    if (mounted) {
      setState(() => _busy = false);
    }
  }
}

  /// Swaps in a freshly generated document and resets the viewer.
  void _applyNewDocument(
    Uint8List bytes,
    List<_PageInfo> infos, {
    required int currentPage,
    required bool dirty,
    VoidCallback? alsoUpdate,
  }) {
    controller.annotationMode = PdfAnnotationMode.none;
    _resetSearchState();
    setState(() {
      pdfBytes = bytes;
      _pageInfos = infos;
      _currentPage = currentPage.clamp(1, math.max(1, infos.length)).toInt();
      _pendingPage = _currentPage;
      _documentLoaded = false;
      _documentRevision++;
      _tool = _EditorTool.none;
      _activeStroke = null;
      _resetZoomState();
      _dirty = dirty;
      alsoUpdate?.call();
    });
  }

  // =================== OPEN PDF ===================
  /// Applies the language saved on the previous launch.
  Future<void> _restoreLanguage() async {
    final String? code = await _LanguageStore.load();
    if (code == null || !mounted) return;
    if (Localizations.localeOf(context).languageCode == code) return;
    widget.onLanguageChanged(Locale(code));
  }

  /// Opens a file handed over by the platform ("Open with" / share intent).
  /// [payload] is either raw bytes or a map `{bytes: Uint8List, name: String}`.
  /// Without a real file name every such file used to be called
  /// "document.pdf" and replaced the previous one in the recent list.
  Future<void> _openExternalPayload(dynamic payload, {String? name}) async {
    Uint8List? bytes;
    String? fileName = name;

    if (payload is Uint8List) {
      bytes = payload;
    } else if (payload is Map) {
      final Object? b = payload['bytes'];
      if (b is Uint8List) bytes = b;
      final Object? n = payload['name'] ?? payload['fileName'];
      if (n is String && n.trim().isNotEmpty) fileName = n;
    }

    if (bytes == null || bytes.isEmpty) return;
    if (!await _confirmDiscardChanges()) return;
    if (!mounted) return;

    await _openAnyBytes(
      bytes,
      name: fileName ?? _fallbackExternalName(bytes),
    );
  }

  /// A unique name for files that arrive without one, so they do not
  /// overwrite each other in the recent documents list.
  String _fallbackExternalName(Uint8List bytes) {
    final String ext;
    switch (_detectFileKind(bytes)) {
      case _FileKind.image:
        ext = 'jpg';
      case _FileKind.text:
        ext = 'txt';
      case _FileKind.pdf:
      case _FileKind.unsupported:
        ext = 'pdf';
    }
    final DateTime t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'document_${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.$ext';
  }

  Future<void> _checkInitialPdf() async {
    try {
      final dynamic payload =
          await _openFileChannel.invokeMethod<dynamic>('getInitialPdf');
      if (payload == null) return;

      // Native side may optionally provide the real name separately.
      String? name;
      try {
        name = await _openFileChannel.invokeMethod<String>('getInitialFileName');
      } catch (_) {
        name = null;
      }

      await _openExternalPayload(payload, name: name);
    } catch (e) {
      debugPrint('Initial PDF error: $e');
    }
  }
  Future<Uint8List?> _readPicked(PlatformFile picked) async {
    try {
      // In file_picker 12+ bytes are read via the file method, not withData.
      return await picked.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Opens a PDF, photo or text file. Photos and text are first
  /// converted to PDF, then everything works like with a regular PDF.
  Future<void> openFile() async {
    if (_busy || !await _confirmDiscardChanges()) return;

    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kOpenExtensions,
    );

    if (picked == null) return;

    await _runExclusive(() async {
  final Uint8List? bytes = await _readPicked(picked);

  if (!mounted) return;

  if (bytes == null) {
    _showMessage(
      context.l10n.couldNotOpenFile,
    );
    return;
  }

  await _openAnyBytes(
    bytes,
    name: picked.name,
  );
});
  }

  /// Detects the format, converts to PDF if needed and opens it.
  Future<void> _openAnyBytes(
    Uint8List bytes, {
    String? name,
    bool addToRecent = true,
  }) async {
    if (bytes.isEmpty) return;

    final l10n = context.l10n;

    final String fileName =
        (name == null || name.trim().isEmpty) ? 'document.pdf' : name.trim();
    final Uint8List original = Uint8List.fromList(bytes);

    final Uint8List pdf;
    try {
      pdf = await _convertToPdf(bytes, name: fileName);
    } on FormatException catch (e) {
      _showMessage(_localizedFormatException(e));
      return;
    } catch (e) {
  _showMessage(
    l10n.couldNotOpenFileDetails(
      e.toString(),
    ),
  );
  return;
}

    if (!mounted) return;
    await _openPdfBytes(pdf);
    if (!mounted || pdfBytes == null) return;

    setState(() {
      _originalFileBytes = original;
      _currentFileName = fileName;
      _lastSavedRecentPath = null;
    });

    if (addToRecent) {
      try {
        await _RecentDocumentsService.add(
          bytes: original,
          fileName: fileName,
        );
      } catch (e) {
        debugPrint('Recent documents error: $e');
      }
    }
  }

  /// Appends pages from another file (PDF / photo / text) to the end
  /// of the current document. This lets you build one PDF from several photos.
  Future<void> addPagesFromFile() async {
    if (_busy || pdfBytes == null) return;

    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kOpenExtensions,
    );
    if (picked == null) return;

    await _runExclusive(() async {
  final Uint8List? raw = await _readPicked(picked);

  if (!mounted) return;

  if (raw == null) {
    _showMessage(
      context.l10n.couldNotReadFile,
    );
    return;
  }

      final Uint8List addition;
      try {
        addition = await _convertToPdf(raw, name: picked.name);
      } on FormatException catch (e) {
        _showMessage(_localizedFormatException(e));
        return;
      }

      final Uint8List? current = pdfBytes;
      if (current == null) return;

      final int oldCount = _pageInfos.length;
      final Uint8List merged = await _appendDocument(current, addition);
      final List<_PageInfo> infos = _readPageInfos(merged);

      if (!mounted) return;
      // New pages are appended at the end, so the indexes of old edits
      // do not change - no remapping needed.
      _applyNewDocument(
        merged,
        infos,
        currentPage: oldCount + 1,
        dirty: true,
      );
      _showMessage(context.l10n.pagesAdded(infos.length - oldCount));
    });
  }

  Future<Uint8List> _appendDocument(Uint8List base, Uint8List addition) async {
    final PdfDocument doc = PdfDocument(inputBytes: base);
    final PdfDocument source = PdfDocument(inputBytes: addition);
    try {
      // The same zero margins as in _reorderPage(): otherwise the page content
      // shifts by 40 pt.
      doc.pageSettings.margins.all = 0;
      final PdfMargins noMargins = PdfMargins()..all = 0;

      final int firstNew = doc.pages.count;
      final Map<int, PdfPageRotateAngle> rotations =
          <int, PdfPageRotateAngle>{};

      for (int i = 0; i < source.pages.count; i++) {
        final PdfPage src = source.pages[i];
        final PdfPage page =
            doc.pages.insert(doc.pages.count, src.size, noMargins);
        page.rotation = src.rotation;
        rotations[firstNew + i] = src.rotation;
        page.graphics.drawPdfTemplate(src.createTemplate(), Offset.zero);
      }

      // source must live until save() finishes: templates reference its resources.
      final Uint8List saved = Uint8List.fromList(await doc.save());
      return await _restoreRotations(saved, rotations);
    } finally {
      source.dispose();
      doc.dispose();
    }
  }

  List<_PageInfo> _readPageInfos(Uint8List bytes) {
    final PdfDocument doc = PdfDocument(inputBytes: bytes);
    try {
      final List<_PageInfo> result = <_PageInfo>[];
      for (int i = 0; i < doc.pages.count; i++) {
        final PdfPage page = doc.pages[i];
        result.add(_PageInfo(size: page.size, rotation: page.rotation));
      }
      return result;
    } finally {
      doc.dispose();
    }
  }
Future<void> _openPdfBytes(Uint8List incoming) async {
  if (incoming.isEmpty) return;

  // A file saved by this editor carries the original pages and the editable
  // marks inside it. Restore them, so the marks can be edited again.
  Uint8List bytes = incoming;
  List<_PageAnnotation> restored = <_PageAnnotation>[];
  final _EditableBundle? bundle = _readEditableBundle(incoming);

  List<_PageInfo> infos;
  try {
    if (bundle != null) {
      infos = _readPageInfos(bundle.baseBytes);
      final bool consistent = infos.length == bundle.pageCount &&
          bundle.annotations.every(
              (_PageAnnotation a) => a.pageIndex >= 0 && a.pageIndex < infos.length);
      if (consistent) {
        bytes = bundle.baseBytes;
        restored = bundle.annotations;
      } else {
        infos = _readPageInfos(incoming);
      }
    } else {
      infos = _readPageInfos(incoming);
    }
  } catch (_) {
    _showMessage(context.l10n.couldNotReadPdf);

    return;
  }

  if (!mounted) return;

  controller.annotationMode = PdfAnnotationMode.none;
  controller.zoomLevel = 1;
  _resetSearchState();

  setState(() {
    pdfBytes = bytes;

    _pageInfos = infos;

    _currentPage = 1;
    _pendingPage = 1;

    _tool = _EditorTool.none;

    _documentLoaded = false;
    _documentRevision++;

    _annotations
      ..clear()
      ..addAll(restored);
    _redoStack.clear();
    _selectedText = null;
    _selectedImage = null;

    _activeStroke = null;

    _resetZoomState();

    _dirty = false;
  });
}
  // =================== TOOL SELECTION ===================
  void _selectTool(_EditorTool tool) {
    if (pdfBytes == null) return;
    if (_searchOpen) _closeSearch();

    if (_tool == tool) {
      tool = _EditorTool.none;
    }

    controller.annotationMode = PdfAnnotationMode.none;
    controller.zoomLevel = 1;

    setState(() {
      _tool = tool;
      _activeStroke = null;
      _selectedImage = null;
      _selectedText = null;
    });
  }

  // =================== PAGE GEOMETRY ===================
  bool _isQuarterTurn(PdfPageRotateAngle rotation) {
    return rotation == PdfPageRotateAngle.rotateAngle90 ||
        rotation == PdfPageRotateAngle.rotateAngle270;
  }

  Size _displayPageSize(_PageInfo info) {
    if (_isQuarterTurn(info.rotation)) {
      return Size(info.size.height, info.size.width);
    }
    return info.size;
  }

  Rect _pageRect(Size viewportSize, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pageInfos.length) {
      return Rect.zero;
    }

    final Size pageSize = _displayPageSize(_pageInfos[pageIndex]);

    if (pageSize.width <= 0 ||
        pageSize.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return Rect.zero;
    }

    final FittedSizes fitted = applyBoxFit(
      BoxFit.contain,
      pageSize,
      viewportSize,
    );

    return Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & viewportSize,
    );
  }

  Offset _screenToCanonical(
    Offset screenPoint,
    Rect pageRect,
    PdfPageRotateAngle rotation,
  ) {
    // clamp() keeps every point on the page, even if the finger slides off it.
    final Offset displayNormalized = Offset(
      ((screenPoint.dx - pageRect.left) / pageRect.width).clamp(0.0, 1.0),
      ((screenPoint.dy - pageRect.top) / pageRect.height).clamp(0.0, 1.0),
    );

    return _displayToCanonicalNormalized(displayNormalized, rotation);
  }

  Offset _canonicalToScreen(
    Offset canonicalPoint,
    Rect pageRect,
    PdfPageRotateAngle rotation,
  ) {
    final Offset displayNormalized =
        _canonicalToDisplayNormalized(canonicalPoint, rotation);

    return Offset(
      pageRect.left + displayNormalized.dx * pageRect.width,
      pageRect.top + displayNormalized.dy * pageRect.height,
    );
  }

  /// Screen pixels per PDF point for the current page.
  double _pageScale(Rect pageRect, _PageInfo info) {
    final Size displayedPageSize = _displayPageSize(info);
    if (displayedPageSize.width == 0) return 1;
    return pageRect.width / displayedPageSize.width;
  }

  // =================== UNDO / REDO ===================
  /// Any new edit invalidates the redo history (standard editor behaviour).
  void _commit(_PageAnnotation annotation) {
    _annotations.add(annotation);
    _redoStack.clear();
    _dirty = true;
  }

  bool get _canUndo =>
      _annotations.any((_PageAnnotation a) => a.pageIndex == _currentPage - 1);

  bool get _canRedo =>
      _redoStack.any((_PageAnnotation a) => a.pageIndex == _currentPage - 1);

  /// Undoes the most recent edit (stroke OR text) made on the current page,
  /// regardless of which tool happens to be selected.
  void undoCustomEdit() {
    final int pageIndex = _currentPage - 1;
    final int i =
        _annotations.lastIndexWhere((_PageAnnotation a) => a.pageIndex == pageIndex);
    if (i < 0) return;

    setState(() {
      _redoStack.add(_annotations.removeAt(i));
      _dirty = true;
    });
  }

  void redoCustomEdit() {
    final int pageIndex = _currentPage - 1;
    final int i =
        _redoStack.lastIndexWhere((_PageAnnotation a) => a.pageIndex == pageIndex);
    if (i < 0) return;

    setState(() {
      _annotations.add(_redoStack.removeAt(i));
      _dirty = true;
    });
  }

  /// Re-targets every stored edit after pages were moved or deleted.
  /// Return -1 from [mapIndex] to drop the edits of a page.
  void _remapAnnotations(int Function(int oldIndex) mapIndex) {
    for (final List<_PageAnnotation> list in <List<_PageAnnotation>>[
      _annotations,
      _redoStack,
    ]) {
      for (final _PageAnnotation a in list) {
        a.pageIndex = mapIndex(a.pageIndex);
      }
      list.removeWhere((_PageAnnotation a) => a.pageIndex < 0);
    }
  }

  // =================== DRAW ===================
  void _startStroke(Offset localPosition, Rect pageRect, int pageIndex) {
    if (_pointers.length > 1) return; // two fingers = pinch / pan, not draw
    if (pageRect == Rect.zero || !pageRect.contains(localPosition)) return;

    final PdfPageRotateAngle rotation = _pageInfos[pageIndex].rotation;
    final bool isHighlighter = _tool == _EditorTool.highlight;
    final _StrokeAnnotation stroke = _StrokeAnnotation(
      pageIndex: pageIndex,
      color: isHighlighter ? _kHighlighterColor : _penColor,
      width: isHighlighter ? _kHighlighterWidth : _penWidth,
      isHighlighter: isHighlighter,
      first: _screenToCanonical(localPosition, pageRect, rotation),
    );

    setState(() {
      _activeStroke = stroke;
      _commit(stroke);
    });
  }

  void _updateStroke(Offset localPosition, Rect pageRect, int pageIndex) {
    if (_pointers.length > 1) return;
    final _StrokeAnnotation? stroke = _activeStroke;
    if (stroke == null || pageRect == Rect.zero) return;

    if (!pageRect.contains(localPosition)) {
      // The finger left the page: break the line here so it doesn't draw a
      // long diagonal when the finger comes back in somewhere else.
      if (stroke.points.isNotEmpty && stroke.points.last != null) {
        setState(() {
          stroke.points.add(null);
        });
      }
      return;
    }

    final PdfPageRotateAngle rotation = _pageInfos[pageIndex].rotation;
    final Offset point = _screenToCanonical(localPosition, pageRect, rotation);

    setState(() {
      stroke.points.add(point);
    });
  }

  void _endStroke() {
    final _StrokeAnnotation? stroke = _activeStroke;
    if (stroke == null) return;

    setState(() {
      if (stroke.points.isNotEmpty && stroke.points.last != null) {
        stroke.points.add(null);
      }
      _activeStroke = null;
    });
  }

  /// A simple tap leaves a dot (a zero-length line with round caps) - handy
  /// for i-dots and punctuation in signatures.
  void _dotAt(Offset localPosition, Rect pageRect, int pageIndex) {
    if (_pointers.length > 1) return;
    if (pageRect == Rect.zero || !pageRect.contains(localPosition)) return;

    final PdfPageRotateAngle rotation = _pageInfos[pageIndex].rotation;
    final Offset p = _screenToCanonical(localPosition, pageRect, rotation);
    final bool isHighlighter = _tool == _EditorTool.highlight;
    final _StrokeAnnotation dot = _StrokeAnnotation(
      pageIndex: pageIndex,
      color: isHighlighter ? _kHighlighterColor : _penColor,
      width: isHighlighter ? _kHighlighterWidth : _penWidth,
      isHighlighter: isHighlighter,
      first: p,
    );
    dot.points
      ..add(p)
      ..add(null);

    setState(() {
      _commit(dot);
    });
  }

  // =================== TEXT ===================
  Future<void> _addTextAt(
    Offset localPosition,
    Rect pageRect,
    int pageIndex,
  ) async {
    if (!pageRect.contains(localPosition)) return;

    final _TextDialogResult? result = await showDialog<_TextDialogResult>(
      context: context,
      builder: (BuildContext context) => const _AddTextDialog(),
    );

    if (result == null || !mounted) return;

    final _PageInfo info = _pageInfos[pageIndex];
    final PdfPageRotateAngle rotation = info.rotation;

    // A signature is always created "upright" relative to what the user sees:
    // on a flipped page it compensates for the page rotation.
    final int turns = (4 - _quarterTurns(rotation)) % 4;

    // Tap position = top-left corner of the signature on screen.
    final Size display = _displayPageSize(info);
    final double widthPt = math.min(220.0, display.width);
    final Size size = _measureTextSize(result.text, result.fontSize, maxWidth: widthPt);
    final Offset tap = Offset(
      _clamp01((localPosition.dx - pageRect.left) / pageRect.width),
      _clamp01((localPosition.dy - pageRect.top) / pageRect.height),
    );
    final Offset centerDisplay = Offset(
      _clamp01(tap.dx + size.width / 2 / display.width),
      _clamp01(tap.dy + size.height / 2 / display.height),
    );

    final _TextAnnotation annotation = _TextAnnotation(
      pageIndex: pageIndex,
      text: result.text,
      fontSize: result.fontSize,
      widthPt: widthPt,
      color: _penColor,
      center: _displayToCanonicalNormalized(centerDisplay, rotation),
      turns: turns,
    );
    _normalizeCenter(annotation, info);

    setState(() {
      _commit(annotation);
    });
  }

  Future<void> _editText(_TextAnnotation annotation) async {
    final _TextDialogResult? result = await showDialog<_TextDialogResult>(
      context: context,
      builder: (BuildContext context) => _AddTextDialog(
        initialText: annotation.text,
        initialFontSize: annotation.fontSize,
        isEditing: true,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      annotation.text = result.text;
      annotation.fontSize = result.fontSize;
      _dirty = true;
    });
  }

  Future<void> _deleteText(_TextAnnotation annotation) async {
    final bool ok = await _confirm(
      title: context.l10n.deleteTextTitle,
      message: annotation.text,
      confirmLabel: context.l10n.delete,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    setState(() {
      _annotations.remove(annotation);
      _redoStack.remove(annotation);
      if (identical(_selectedText, annotation)) _selectedText = null;
      _dirty = true;
    });
  }

  /// Writes back the center clamped to the page (so that when shrinking,
  /// the element does not "return" to its old place beyond the edge).
  void _normalizeCenter(_PlacedAnnotation a, _PageInfo info) {
    final _Placement pl = _placementOf(a, info.size);
    a.center = Offset(
      pl.center.dx / info.size.width,
      pl.center.dy / info.size.height,
    );
  }

  void _resizeTextByDrag(
    _TextAnnotation annotation,
    Offset delta,
    Rect pageRect,
    int pageIndex,
  ) {
    final _PageInfo info = _pageInfos[pageIndex];
    final double scale = _pageScale(pageRect, info);
    if (scale <= 0) return;
    final int turns = (_quarterTurns(info.rotation) + annotation.turns) % 4;
    final double movement = switch (turns) {
      1 => delta.dy,
      2 => -delta.dx,
      3 => -delta.dy,
      _ => delta.dx,
    };
    // The unrotated text width cannot exceed the corresponding page dimension.
    final double maxWidth = annotation.turns.isOdd
        ? info.size.height
        : info.size.width;
    setState(() {
      annotation.widthPt = (annotation.widthPt + movement / scale)
          .clamp(math.min(60.0, maxWidth), maxWidth)
          .toDouble();
      _normalizeCenter(annotation, info);
      _dirty = true;
    });
  }

  void _movePlaced(
    _PlacedAnnotation annotation,
    Offset delta,
    Rect pageRect,
    int pageIndex,
  ) {
    final _PageInfo info = _pageInfos[pageIndex];
    final Offset currentScreen =
        _canonicalToScreen(annotation.center, pageRect, info.rotation);

    // _screenToCanonical clamps to the page, so the item slides along the
    // edge instead of getting stuck on it.
    setState(() {
      annotation.center =
          _screenToCanonical(currentScreen + delta, pageRect, info.rotation);
      _normalizeCenter(annotation, info);
      _dirty = true;
    });
  }

  // =================== PHOTOS ON THE PAGE ===================
  double _maxImageWidth(_ImageAnnotation img, Size page) {
    final double a = img.aspect; // width / height
    final bool odd = img.turns.isOdd;
    final double byWidth = odd ? page.width * a : page.width;
    final double byHeight = odd ? page.height : page.height * a;
    return math.min(byWidth, byHeight);
  }

  void _setImageWidth(_ImageAnnotation img, double width, _PageInfo info) {
    final double maxW = _maxImageWidth(img, info.size);
    final double minW = math.min(_kMinImageWidthPt, maxW);
    setState(() {
      img.widthPt = width.clamp(minW, math.max(minW, maxW)).toDouble();
      _normalizeCenter(img, info);
      _dirty = true;
    });
  }

  /// Dragging the corner: the size changes proportionally, along the photo diagonal.
  void _resizeImageByDrag(
    _ImageAnnotation img,
    Offset delta,
    Size displayBox,
    _PageInfo info,
  ) {
    final double diag2 =
        displayBox.width * displayBox.width + displayBox.height * displayBox.height;
    if (diag2 <= 0) return;
    final double ratio =
        1 + 2 * (delta.dx * displayBox.width + delta.dy * displayBox.height) / diag2;
    _setImageWidth(img, img.widthPt * ratio, info);
  }

  Future<void> _onImageToolPressed() async {
    if (_tool == _EditorTool.image) {
      _selectTool(_EditorTool.image); // tapping again turns the mode off
      return;
    }
    _selectTool(_EditorTool.image);
    await _insertImage();
  }

  /// Picks a photo and puts it on the current page (in the center). Then it
  /// can be moved, resized and deleted.
  Future<void> _insertImage() async {
    if (_busy || pdfBytes == null || _pageInfos.isEmpty) return;

    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kImageExtensions,
    );
    if (picked == null) return;

   await _runExclusive(() async {
  final Uint8List? raw = await _readPicked(picked);

  if (!mounted) return;

  if (raw == null) {
    _showMessage(
      context.l10n.couldNotReadFile,
    );
    return;
  }

      final _DecodedImage decoded;
      try {
        decoded = await _decodeImageToPng(raw, _kStampMaxPixels);
      } on FormatException catch (e) {
        _showMessage(_localizedFormatException(e));
        return;
      }
      if (!mounted) return;

      final int pageIndex = _currentPage - 1;
      if (pageIndex < 0 || pageIndex >= _pageInfos.length) return;
      final _PageInfo info = _pageInfos[pageIndex];
      final Size display = _displayPageSize(info);
      final double aspect = decoded.width / decoded.height;

      final _ImageAnnotation image = _ImageAnnotation(
        pageIndex: pageIndex,
        png: decoded.png,
        pixelWidth: decoded.width,
        pixelHeight: decoded.height,
        // Initial size: 40% of the page width, but not more than half of the height.
        widthPt: math.min(display.width * 0.4, display.height * 0.5 * aspect),
        center: _displayToCanonicalNormalized(
            const Offset(0.5, 0.5), info.rotation),
        turns: (4 - _quarterTurns(info.rotation)) % 4,
      );
      _normalizeCenter(image, info);

      setState(() {
        _commit(image);
        _selectedImage = image;
      });
    });
  }

  Future<void> _deleteImage(_ImageAnnotation image) async {
    final bool ok = await _confirm(
      title: context.l10n.deletePhotoTitle,
      message: context.l10n.deletePhotoMessage,
      confirmLabel: context.l10n.delete,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    setState(() {
      _annotations.remove(image);
      _redoStack.remove(image);
      if (identical(_selectedImage, image)) _selectedImage = null;
      _dirty = true;
    });
  }

  // =================== DOCUMENT EDITING (rotate / move / delete) ===================
  /// Opens [bytes], lets [edit] mutate the document, saves, and ALWAYS
  /// disposes the document, even when something throws.
  Future<Uint8List> _editDocument(
    Uint8List bytes,
    void Function(PdfDocument doc) edit,
  ) async {
    final PdfDocument doc = PdfDocument(inputBytes: bytes);
    try {
      edit(doc);
      return Uint8List.fromList(await doc.save());
    } finally {
      doc.dispose();
    }
  }

  Future<void> rotatePage({bool clockwise = true}) {
    return _runExclusive(() async {
      final Uint8List? bytes = pdfBytes;
      final int pageNumber = _currentPage;
      final int pageIndex = pageNumber - 1;
      if (bytes == null || pageIndex < 0 || pageIndex >= _pageInfos.length) {
        return;
      }

      final Uint8List saved = await _editDocument(bytes, (PdfDocument doc) {
        final PdfPage page = doc.pages[pageIndex];
        final int i = _kRotationOrder.indexOf(page.rotation);
        // +3 == -1 modulo 4, i.e. counter-clockwise.
        page.rotation = _kRotationOrder[(i + (clockwise ? 1 : 3)) % 4];
      });
      final List<_PageInfo> infos = _readPageInfos(saved);

      if (!mounted) return;
      _applyNewDocument(saved, infos, currentPage: pageNumber, dirty: true);
    });
  }

  Future<void> deletePage() async {
    if (_busy || pdfBytes == null) return;
    if (_pageInfos.length <= 1) {
      _showMessage(context.l10n.cannotDeleteOnlyPage);
      return;
    }

    final int removeIndex = _currentPage - 1;
    final bool ok = await _confirm(
      title: context.l10n.deletePageTitle(_currentPage),
      message: context.l10n.deletePageMessage,
      confirmLabel: context.l10n.delete,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;

    await _runExclusive(() async {
      final Uint8List? bytes = pdfBytes;
      if (bytes == null || removeIndex < 0 || removeIndex >= _pageInfos.length) {
        return;
      }

      final Uint8List saved = await _editDocument(
        bytes,
        (PdfDocument doc) => doc.pages.removeAt(removeIndex),
      );
      final List<_PageInfo> infos = _readPageInfos(saved);

      if (!mounted) return;
      _applyNewDocument(
        saved,
        infos,
        currentPage: removeIndex + 1,
        dirty: true,
        alsoUpdate: () => _remapAnnotations((int old) {
          if (old == removeIndex) return -1;
          return old > removeIndex ? old - 1 : old;
        }),
      );
    });
  }

  Future<void> movePage(int toIndex) {
    return _runExclusive(() async {
      final Uint8List? bytes = pdfBytes;
      final int fromIndex = _currentPage - 1;
      if (bytes == null ||
          _pageInfos.isEmpty ||
          fromIndex == toIndex ||
          toIndex < 0 ||
          toIndex >= _pageInfos.length) {
        return;
      }

      final Uint8List saved = await _reorderPage(bytes, fromIndex, toIndex);
      final List<_PageInfo> infos = _readPageInfos(saved);

      if (!mounted) return;
      _applyNewDocument(
        saved,
        infos,
        currentPage: toIndex + 1,
        dirty: true,
        alsoUpdate: () => _remapAnnotations(_moveMapper(fromIndex, toIndex)),
      );
    });
  }

  Future<Uint8List> _reorderPage(Uint8List bytes, int from, int to) async {
    final PdfDocument doc = PdfDocument(inputBytes: bytes);
    final PdfDocument sourceDoc = PdfDocument(inputBytes: bytes);
    try {
      // pages.insert() creates the page with its own default margins (40 pt),
      // NOT with doc.pageSettings. Those margins shifted the copied content,
      // and the shift stacked up with every move. Pass zero margins
      // explicitly so the template lands exactly at the page origin.
      doc.pageSettings.margins.all = 0;
      final PdfMargins noMargins = PdfMargins()..all = 0;

      final PdfPage sourcePage = sourceDoc.pages[from];
      final PdfPageRotateAngle sourceRotation = sourcePage.rotation;
      final int insertAt = to < from ? to : to + 1;
      final PdfPage newPage =
          doc.pages.insert(insertAt, sourcePage.size, noMargins);
      newPage.rotation = sourceRotation;
      newPage.graphics
          .drawPdfTemplate(sourcePage.createTemplate(), Offset.zero);

      doc.pages.removeAt(to < from ? from + 1 : from);

      // IMPORTANT: sourceDoc must stay alive until doc.save() has finished -
      // the template still references its resources. It is disposed in
      // `finally`, i.e. only after the bytes are produced.
      final Uint8List saved = Uint8List.fromList(await doc.save());

      // A page created via pages.insert() can lose its /Rotate value, so the
      // moved page snapped back to the standard position. Re-apply it on the
      // saved document, the same way rotatePage() does.
      return await _restoreRotations(
        saved,
        <int, PdfPageRotateAngle>{to: sourceRotation},
      );
    } finally {
      sourceDoc.dispose();
      doc.dispose();
    }
  }

  /// Sets the given page rotations on an already saved document.
  Future<Uint8List> _restoreRotations(
    Uint8List bytes,
    Map<int, PdfPageRotateAngle> rotations,
  ) async {
    final Map<int, PdfPageRotateAngle> wanted =
        Map<int, PdfPageRotateAngle>.from(rotations)
          ..removeWhere((int _, PdfPageRotateAngle r) =>
              r == PdfPageRotateAngle.rotateAngle0);
    if (wanted.isEmpty) return bytes;

    final PdfDocument doc = PdfDocument(inputBytes: bytes);
    try {
      wanted.forEach((int index, PdfPageRotateAngle angle) {
        if (index >= 0 && index < doc.pages.count) {
          doc.pages[index].rotation = angle;
        }
      });
      return Uint8List.fromList(await doc.save());
    } finally {
      doc.dispose();
    }
  }

  /// Maps old page indexes to new ones after moving page [from] to [to].
  int Function(int) _moveMapper(int from, int to) {
    return (int oldIndex) {
      if (oldIndex == from) return to;

      if (from < to) {
        if (oldIndex > from && oldIndex <= to) return oldIndex - 1;
      } else {
        if (oldIndex >= to && oldIndex < from) return oldIndex + 1;
      }

      return oldIndex;
    };
  }

  // =================== RECENT / SHARE ===================
  Future<void> _openRecentDocuments() async {
    if (_busy) return;

    final _RecentDocumentResult? result =
        await Navigator.of(context).push<_RecentDocumentResult>(
      MaterialPageRoute<_RecentDocumentResult>(
        builder: (BuildContext context) => const _RecentDocumentsScreen(),
      ),
    );

    if (result == null || !mounted) return;
    if (!await _confirmDiscardChanges()) return;
    if (!mounted) return;

    await _runExclusive(() async {
      await _openAnyBytes(
        result.bytes,
        name: result.fileName,
        addToRecent: false,
      );
    });
  }

  Future<void> _shareBytes(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        title: context.l10n.shareFileTitle(fileName),
        files: <XFile>[
          XFile.fromData(bytes, mimeType: mimeType),
        ],
        fileNameOverrides: <String>[_safeFileName(fileName)],
      ),
    );
  }

  Future<bool> _savePdfBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final Uri? savedUri = await FilePicker.saveFile(
      dialogTitle: context.l10n.savePdf,
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    return savedUri != null;
  }

  /// After saving, the marks stay editable objects in the editor. The saved
  /// file also carries them inside, so they are editable after re-opening.
  Future<void> _acceptSavedVersion(
    Uint8List finalBytes, {
    required String fileName,
  }) async {
    if (!mounted) return;

    setState(() {
      _dirty = false;
      _originalFileBytes = Uint8List.fromList(finalBytes);
      _currentFileName = fileName;
    });

   try {
  _lastSavedRecentPath = await _RecentDocumentsService.add(
    bytes: finalBytes,
    fileName: fileName,
    replacePath: _lastSavedRecentPath,
  );
} catch (e) {
  debugPrint('Recent documents error: $e');
}
  }

  Future<void> _shareFile() async {
    if (_busy || pdfBytes == null) return;

    final Uint8List? original = _originalFileBytes;

    if (!_dirty) {
      if (original != null) {
        await _shareBytes(
          original,
          fileName: _currentFileName,
          mimeType: _mimeForName(_currentFileName),
        );
      } else {
        await _shareBytes(
          pdfBytes!,
          fileName: _editedPdfName(_currentFileName),
          mimeType: 'application/pdf',
        );
      }
      return;
    }

    final String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.share_rounded),
        title: Text(context.l10n.shareFile),
        content: Text(context.l10n.unsavedShareQuestion),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          if (original != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'original'),
              child: Text(context.l10n.withoutChanges),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'edited'),
            child: Text(context.l10n.saveAndShare),
          ),
        ],
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'original' && original != null) {
      await _shareBytes(
        original,
        fileName: _currentFileName,
        mimeType: _mimeForName(_currentFileName),
      );
      return;
    }

    if (action == 'edited') {
      await _runExclusive(() async {
        final Uint8List? working = pdfBytes;
        if (working == null) return;

        final Uint8List finalBytes = await _bakeAnnotations(working);
        final String fileName = _editedPdfName(_currentFileName);

        final bool saved = await _savePdfBytes(
          finalBytes,
          fileName: fileName,
        );
        if (!saved || !mounted) return;

        await _acceptSavedVersion(finalBytes, fileName: fileName);
        if (!mounted) return;

        await _shareBytes(
          finalBytes,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
      });
    }
  }

  // =================== SAVE ===================
  Future<_RenderedTextImage> _renderTextToPng(
    String text,
    double fontSize,
    Color color,
    double widthPt,
  ) async {
    const double pad = _kTextPaddingPt * _kTextPixelRatio;

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _labelStyle(fontSize * _kTextPixelRatio, color),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(1.0, (widthPt - 2 * _kTextPaddingPt) * _kTextPixelRatio));

    final int widthPx = math.max(1, (widthPt * _kTextPixelRatio).ceil());
    final int heightPx = math.max(1, (painter.height + pad * 2).ceil());

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    painter.paint(canvas, const Offset(pad, pad));
    painter.dispose();

    final ui.Picture picture = recorder.endRecording();
    final l10n = context.l10n;
    final ui.Image image = await picture.toImage(widthPx, heightPx);
    
    picture.dispose();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (data == null) {
  throw StateError(
    l10n.textPrepareError,
  );
}

    return _RenderedTextImage(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      widthPoints: widthPx / _kTextPixelRatio,
      heightPoints: heightPx / _kTextPixelRatio,
    );
  }

  void _bakeStroke(PdfPage page, _StrokeAnnotation stroke) {
    // Round caps/joins: without them thick lines made of many short segments
    // look jagged and leave tiny gaps at the corners.
    final PdfPen pen = PdfPen(_pdfColor(stroke.color), width: stroke.width);
    pen.lineCap = PdfLineCap.round;
    pen.lineJoin = PdfLineJoin.round;

    final double w = page.size.width;
    final double h = page.size.height;
    final PdfGraphicsState? state = stroke.isHighlighter ? page.graphics.save() : null;

    if (stroke.isHighlighter) {
      // Multiply tints the page while preserving dark letters underneath.
      page.graphics.setTransparency(
        _kHighlighterOpacity,
        alphaBrush: _kHighlighterOpacity,
        mode: PdfBlendMode.multiply,
      );
    }

    for (int i = 0; i < stroke.points.length - 1; i++) {
      final Offset? p1 = stroke.points[i];
      final Offset? p2 = stroke.points[i + 1];
      if (p1 == null || p2 == null) continue;

      page.graphics.drawLine(
        pen,
        Offset(p1.dx * w, p1.dy * h),
        Offset(p2.dx * w, p2.dy * h),
      );
    }

    if (state != null) {
      page.graphics.restore(state);
    }
  }

  /// Writes a text label as REAL PDF text (embedded TrueType font), so it can
  /// be selected, copied and found by search in any PDF reader.
  ///
  /// Line breaks are taken from Flutter's own layout, so the saved result is
  /// identical to what the user saw on screen.
  void _bakeTextAsVector(
    PdfPage page,
    _TextAnnotation a,
    Uint8List fontData,
    Map<double, PdfTrueTypeFont> fonts,
  ) {
    final _Placement pl = _placementOf(a, page.size);
    const double ratio = _kTextPixelRatio;

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: a.text,
        style: _labelStyle(a.fontSize * ratio, a.color),
      ),
      textDirection: TextDirection.ltr,
    )..layout(
        maxWidth: math.max(1.0, (a.widthPt - 2 * _kTextPaddingPt) * ratio),
      );

    final List<ui.LineMetrics> lines = painter.computeLineMetrics();
    final double fit = pl.fit;
    final double fontSize = math.max(1.0, a.fontSize * fit);
    final double fontKey = (fontSize * 100).round() / 100;
    final PdfTrueTypeFont font = fonts.putIfAbsent(
      fontKey,
      () => PdfTrueTypeFont(fontData, fontKey),
    );
    final PdfSolidBrush brush = PdfSolidBrush(_pdfColor(a.color));
    final PdfStringFormat format = PdfStringFormat(
      wordWrap: PdfWordWrapType.none,
      lineAlignment: PdfVerticalAlignment.top,
    );

    final PdfGraphics g = page.graphics;
    final PdfGraphicsState state = g.save();
    try {
      // Move the origin to the label center and rotate like the PNG was.
      g.translateTransform(pl.center.dx, pl.center.dy);
      if (a.turns % 4 != 0) g.rotateTransform(90.0 * (a.turns % 4));

      final double left = -pl.content.width / 2;
      final double top = -pl.content.height / 2;

      int lastEnd = 0;
      for (final ui.LineMetrics m in lines) {
        final TextPosition pos = painter.getPositionForOffset(
          Offset(m.left + 1, m.baseline - m.ascent / 2),
        );
        final TextRange range = painter.getLineBoundary(pos);
        if (range.start < lastEnd || range.end <= range.start) continue;
        lastEnd = range.end;

        final String line = a.text
            .substring(range.start, math.min(range.end, a.text.length))
            .replaceAll(RegExp(r'[\r\n]+$'), '');
        if (line.trim().isEmpty) continue;

        final double x = left + (_kTextPaddingPt + m.left / ratio) * fit;
        final double y =
            top + (_kTextPaddingPt + (m.baseline - m.ascent) / ratio) * fit;
        g.drawString(
          line,
          font,
          brush: brush,
          bounds: Rect.fromLTWH(x, y, 0, 0),
          format: format,
        );
      }
    } finally {
      g.restore(state);   
      painter.dispose();
    }
  }

  /// Signature or photo -> PNG rotated by `turns`, fitted to its footprint on the page.
  Future<void> _bakePlaced(PdfPage page, _PlacedAnnotation a) async {
    final _Placement pl = _placementOf(a, page.size);

    Uint8List png;
    if (a is _TextAnnotation) {
      // Fallback only (no TrueType font available): text as a transparent PNG.
      png = (await _renderTextToPng(a.text, a.fontSize, a.color, a.widthPt)).bytes;
    } else if (a is _ImageAnnotation) {
      png = a.png;
    } else {
      return;
    }

    png = await _rotatePngQuarterTurns(png, a.turns);

    page.graphics.drawImage(
      PdfBitmap(png),
      Rect.fromCenter(
        center: pl.center,
        width: pl.bbox.width,
        height: pl.bbox.height,
      ),
    );
  }

  Future<Uint8List> _bakeAnnotations(
    Uint8List bytes, {
    bool embedEditableSource = true,
  }) async {
    // Snapshot: rendering text is async and the list must not change meanwhile.
    final List<_PageAnnotation> snapshot =
        List<_PageAnnotation>.of(_annotations);
    if (snapshot.isEmpty) return bytes;

    final Uint8List? fontData = await _PdfTextFont.load();
    final Map<double, PdfTrueTypeFont> fonts = <double, PdfTrueTypeFont>{};
    final PdfDocument doc = PdfDocument(inputBytes: bytes);

    try {
      // Photos first (underneath), then strokes, then text - the same
      // layering as the on-screen preview.
      for (final _ImageAnnotation i in snapshot.whereType<_ImageAnnotation>()) {
        if (i.pageIndex < 0 || i.pageIndex >= doc.pages.count) continue;
        await _bakePlaced(doc.pages[i.pageIndex], i);
      }

      for (final _StrokeAnnotation s in snapshot.whereType<_StrokeAnnotation>()) {
        if (s.pageIndex < 0 || s.pageIndex >= doc.pages.count) continue;
        _bakeStroke(doc.pages[s.pageIndex], s);
      }

      for (final _TextAnnotation t in snapshot.whereType<_TextAnnotation>()) {
        if (t.pageIndex < 0 || t.pageIndex >= doc.pages.count) continue;
        if (fontData != null) {
          try {
            _bakeTextAsVector(doc.pages[t.pageIndex], t, fontData, fonts);
            continue;
          } catch (e) {
            debugPrint('Vector text failed, using PNG fallback: $e');
          }
        }
        await _bakePlaced(doc.pages[t.pageIndex], t);
      }

      // The editable source: original pages + a description of every mark.
      // Other PDF readers ignore it; this editor restores the marks from it.
      if (embedEditableSource) {
        _attachEditableBundle(doc, bytes, snapshot);
      }

      return Uint8List.fromList(await doc.save());
    } finally {
      doc.dispose();
    }
  }


  // =================== EDITABLE SOURCE INSIDE THE PDF ===================
  void _attachEditableBundle(
    PdfDocument doc,
    Uint8List baseBytes,
    List<_PageAnnotation> items,
  ) {
    final List<Map<String, Object?>> json = <Map<String, Object?>>[];
    final List<Uint8List> images = <Uint8List>[];

    for (final _PageAnnotation a in items) {
      if (a is _StrokeAnnotation) {
        json.add(<String, Object?>{
          't': 'stroke',
          'p': a.pageIndex,
          'c': a.color.toARGB32(),
          'w': a.width,
          'h': a.isHighlighter,
          'pts': a.points
              .map((Offset? o) => o == null ? null : <double>[o.dx, o.dy])
              .toList(),
        });
      } else if (a is _TextAnnotation) {
        json.add(<String, Object?>{
          't': 'text',
          'p': a.pageIndex,
          'text': a.text,
          'fs': a.fontSize,
          'c': a.color.toARGB32(),
          'w': a.widthPt,
          'cx': a.center.dx,
          'cy': a.center.dy,
          'turns': a.turns,
        });
      } else if (a is _ImageAnnotation) {
        images.add(a.png);
        json.add(<String, Object?>{
          't': 'image',
          'p': a.pageIndex,
          'img': images.length - 1,
          'pw': a.pixelWidth,
          'ph': a.pixelHeight,
          'w': a.widthPt,
          'cx': a.center.dx,
          'cy': a.center.dy,
          'turns': a.turns,
        });
      }
    }

    final String data = jsonEncode(<String, Object?>{
      'v': _kEditableFormat,
      'pageCount': doc.pages.count,
      'items': json,
    });

    doc.attachments.add(PdfAttachment(
      _kEditableBaseName,
      baseBytes,
      description: 'PDF Editor: original pages',
      mimeType: 'application/pdf',
    ));
    doc.attachments.add(PdfAttachment(
      _kEditableDataName,
      utf8.encode(data),
      description: 'PDF Editor: editable marks',
      mimeType: 'application/json',
    ));
    for (int i = 0; i < images.length; i++) {
      doc.attachments.add(PdfAttachment(
        '$_kEditableImagePrefix$i.png',
        images[i],
        description: 'PDF Editor: photo $i',
        mimeType: 'image/png',
      ));
    }
  }

  Future<void> savePdf() {
    return _runExclusive(() async {
      final Uint8List? bytes = pdfBytes;
      if (bytes == null) return;

      final Uint8List finalBytes = await _bakeAnnotations(bytes);
      final String fileName = _editedPdfName(_currentFileName);

      final bool saved = await _savePdfBytes(
        finalBytes,
        fileName: fileName,
      );
      if (!saved || !mounted) return;

      await _acceptSavedVersion(finalBytes, fileName: fileName);
      if (mounted) _showMessage(context.l10n.pdfSavedSuccessfully);
    });
  }

  // =================== ZOOM ===================
  void _resetZoomState() {
    _stopFling();
    _panning = false;
    _velocityTracker = null;
    _zoom = 1;
    _pan = Offset.zero;
    _pinching = false;
    _liveScale = 1;
    _settling = false;
    _pointers.clear();
  }

  /// Keeps the zoomed content covering the whole viewport (no empty borders).
  Offset _clampPan(Offset pan, Size viewport, double zoom) {
    final double minX = math.min(0.0, viewport.width * (1 - zoom));
    final double minY = math.min(0.0, viewport.height * (1 - zoom));
    return Offset(
      pan.dx.clamp(minX, 0.0).toDouble(),
      pan.dy.clamp(minY, 0.0).toDouble(),
    );
  }

  void _setZoom(double zoom, Offset pan, Size viewport) {
    _stopFling();
    final double z = zoom.clamp(_kMinZoom, _kMaxZoom).toDouble();
    final Offset p = _clampPan(pan, viewport, z);
    final bool sizeChanged = (z - _zoom).abs() >= 0.001;
    if (!sizeChanged && (p - _pan).distance < 0.5) return;

    setState(() {
      _zoom = z;
      _pan = p;
    });
    if (sizeChanged) _settleViewer();
  }

  /// After the viewer is laid out at a new size it may briefly report a wrong
  /// page, exactly like after rotate/move. Same cure: ignore its page events
  /// for a moment, then jump back to the page we are really on.
  void _settleViewer() {
    if (!_documentLoaded) return;
    if (_pendingPage != null && !_settling) return; // a reload owns it
    final int page = _currentPage;
    final int revision = _documentRevision;
    final int serial = ++_settleSerial;

    setState(() {
      _settling = true;
      _pendingPage = page;
    });

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || revision != _documentRevision || serial != _settleSerial) {
        return;
      }
      controller.jumpToPage(page);
      setState(() {
        _settling = false;
        _pendingPage = null;
      });
    });
  }

  void _zoomBy(double factor) {
    final Size vp = _viewport;
    if (vp.isEmpty || pdfBytes == null) return;

    final double nz = (_zoom * factor).clamp(_kMinZoom, _kMaxZoom).toDouble();
    if ((nz - _zoom).abs() < 0.001) return;

    // Zoom around the centre of the screen.
    final Offset c = vp.center(Offset.zero);
    final double r = nz / _zoom;
    _setZoom(nz, c - (c - _pan) * r, vp);
  }

  void _resetZoom() => _setZoom(1, Offset.zero, _viewport);
  void _fitWidth() {
  if (pdfBytes == null || !_documentLoaded || _pageInfos.isEmpty) {
    return;
  }

  final Size vp = _viewport;
  if (vp.isEmpty) return;

  final int pageIndex =
      (_currentPage - 1).clamp(0, _pageInfos.length - 1).toInt();

  final Rect page = _pageRect(vp, pageIndex);
  if (page.width <= 0) return;

  final double targetZoom =
      (vp.width / page.width).clamp(_kMinZoom, _kMaxZoom).toDouble();

  if (targetZoom <= 1.01) {
    _resetZoom();
    return;
  }

  final Offset targetPan = Offset(
    -page.left * targetZoom,
    -page.top * targetZoom,
  );

  _setZoom(targetZoom, targetPan, vp);
}
  void _toggleDoubleTapZoom(Offset position) {
  if (pdfBytes == null || !_documentLoaded || _busy) return;

  final Size vp = _viewport;
  if (vp.isEmpty) return;

  if (_zoom > 1.01) {
    _resetZoom();
    return;
  }

  const double targetZoom = 3.0;
  final double ratio = targetZoom / _zoom;

  final Offset newPan =
      position - (position - _pan) * ratio;

  _setZoom(targetZoom, newPan, vp);
}
  void _goToPage(int page) {
    final int target =
        page.clamp(1, math.max(1, _pageInfos.length)).toInt();
    if (target == _currentPage) return;

    if (_zoom > 1) {
      setState(() {
        _zoom = 1;
        _pan = Offset.zero;
        _currentPage = target;
        _activeStroke = null;
      });
      _settleViewer();
    } else {
      controller.jumpToPage(target);
    }
  }

  // ---- pinch (2 fingers) and pan (1 finger while zoomed) ----
  // A raw Listener is used on purpose: it never enters the gesture arena, so
  // it cannot steal swipes from the viewer or strokes from the pen.
  void _onPointerDown(PointerDownEvent e) {
    _stopFling(); // a touch stops a running slide immediately
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _panning = false;
      _velocityTracker = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.localPosition);
    }
    if (_pointers.length == 2) {
      _panning = false;
      _velocityTracker = null;
      _endStroke();
      _beginPinch();
    }
  }

  void _beginPinch() {
    if (pdfBytes == null || !_documentLoaded || _busy) return;
    _stopFling();
    final List<Offset> pts = _pointers.values.take(2).toList();
    setState(() {
      _pinching = true;
      _pinchStartDistance = math.max(1.0, (pts[0] - pts[1]).distance);
      _pinchStartFocal = (pts[0] + pts[1]) / 2;
      _liveFocal = _pinchStartFocal;
      _liveScale = 1;
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_pinching && _pointers.length >= 2) {
      final List<Offset> pts = _pointers.values.take(2).toList();
      final double raw = (pts[0] - pts[1]).distance / _pinchStartDistance;
      setState(() {
        _liveScale = raw.clamp(_kMinZoom / _zoom, _kMaxZoom / _zoom).toDouble();
        _liveFocal = (pts[0] + pts[1]) / 2;
      });
    } else if (!_pinching &&
        _pointers.length == 1 &&
        _zoom > 1 &&
        _tool == _EditorTool.none) {
      _velocityTracker?.addPosition(e.timeStamp, e.localPosition);
      _panning = true;
      setState(() {
        _pan = _clampPan(_pan + e.delta, _viewport, _zoom);
      });
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (e is PointerUpEvent &&
    _pointers.length == 1 &&
    !_pinching &&
    !_panning &&
    _tool == _EditorTool.none) {

  final Duration now = e.timeStamp;
  final Offset position = e.localPosition;

  final bool isDoubleTap =
      _lastTapTime != null &&
      _lastTapPosition != null &&
      (now - _lastTapTime!).inMilliseconds < 300 &&
      (position - _lastTapPosition!).distance < 40;

  if (isDoubleTap) {
    _lastTapTime = null;
    _lastTapPosition = null;

    _toggleDoubleTapZoom(position);
  } else {
    _lastTapTime = now;
    _lastTapPosition = position;
  }
}
    final bool wasPanning = _panning && _pointers.length == 1;
    final Velocity? velocity = wasPanning && e is PointerUpEvent
        ? _velocityTracker?.getVelocity()
        : null;

    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      _panning = false;
      _velocityTracker = null;
    }
    if (_pinching && _pointers.length < 2) _finishPinch();

    // Let the page keep sliding after a quick swipe, like a native scroll.
    if (velocity != null && !_pinching && _zoom > 1) {
      _startFling(velocity.pixelsPerSecond);
    }
  }

  void _stopFling() {
    _flingTicker?.stop();
    _flingX = null;
    _flingY = null;
  }

  void _startFling(Offset velocity) {
    _stopFling();
    if (velocity.distance < kMinFlingVelocity) return;

    _flingX = FrictionSimulation(_kFlingDrag, _pan.dx, velocity.dx);
    _flingY = FrictionSimulation(_kFlingDrag, _pan.dy, velocity.dy);
    _flingTicker ??= createTicker(_onFlingTick);
    _flingTicker!.start();
  }

  void _onFlingTick(Duration elapsed) {
    final FrictionSimulation? fx = _flingX;
    final FrictionSimulation? fy = _flingY;
    if (fx == null || fy == null || !mounted || _zoom <= 1 || _pinching) {
      _stopFling();
      return;
    }

    final double t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final Offset raw = Offset(fx.x(t), fy.x(t));
    final Offset next = _clampPan(raw, _viewport, _zoom);

    // An axis is finished when its slide died out or it hit the page edge.
    final bool xDone = fx.isDone(t) || (next.dx - raw.dx).abs() > 0.5;
    final bool yDone = fy.isDone(t) || (next.dy - raw.dy).abs() > 0.5;

    setState(() => _pan = next);
    if (xDone && yDone) _stopFling();
  }

  /// Where a pinch in progress would end up: (zoom, pan).
  (double, Offset) _pinchTarget(Size vp) {
    final double nz = (_zoom * _liveScale).clamp(_kMinZoom, _kMaxZoom).toDouble();
    final double r = nz / _zoom;
    final Offset base = _clampPan(_pan, vp, _zoom);
    final Offset raw = _liveFocal + (base - _pinchStartFocal) * r;
    return (nz, _clampPan(raw, vp, nz));
  }

  void _finishPinch() {
    final Size vp = _viewport;
    final (double, Offset) target = _pinchTarget(vp);
    setState(() {
      _pinching = false;
      _liveScale = 1;
    });
    _setZoom(target.$1, target.$2, vp);
  }


  // =================== SEARCH ===================
  void _resetSearchState() {
    _searchDebounce?.cancel();
    _searchResult.removeListener(_onSearchChanged);
    try {
      _searchResult.clear();
    } catch (_) {}
    _searchResult = PdfTextSearchResult();
    _searchOpen = false;
    _searchNotFound = false;
    _searchCopyBytes = null;
    _pendingSearchQuery = null;
    _searchedQuery = '';
    _searchController.clear();
  }

  /// Opens the search bar. If the document has text labels added by the user,
  /// the viewer temporarily shows a copy where they are real PDF text -
  /// that is what lets the search find them.
  Future<void> _openSearch() async {
    if (pdfBytes == null || _busy) return;
    if (_searchOpen) {
      _searchFocus.requestFocus();
      return;
    }

    controller.annotationMode = PdfAnnotationMode.none;
    setState(() {
      _searchOpen = true;
      _tool = _EditorTool.none;
      _activeStroke = null;
      _selectedImage = null;
      _selectedText = null;
    });
    _searchFocus.requestFocus();

    final bool hasText = _annotations.whereType<_TextAnnotation>().isNotEmpty;
    if (!hasText) return;

    await _runExclusive(() async {
      final Uint8List? base = pdfBytes;
      if (base == null) return;
      final Uint8List copy =
          await _bakeAnnotations(base, embedEditableSource: false);
      if (!mounted || !_searchOpen) return;
      setState(() {
        _searchCopyBytes = copy;
        _documentLoaded = false;
        _pendingPage = _currentPage;
        _documentRevision++;
        _resetZoomState();
      });
    });
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    final bool hadCopy = _searchCopyBytes != null;

    _searchDebounce?.cancel();
    _searchResult.removeListener(_onSearchChanged);
    try {
      _searchResult.clear();
    } catch (_) {}
    _searchResult = PdfTextSearchResult();
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _searchOpen = false;
      _searchNotFound = false;
      _pendingSearchQuery = null;
      _searchController.clear();
      if (hadCopy) {
        _searchCopyBytes = null;
        _documentLoaded = false;
        _pendingPage = _currentPage;
        _documentRevision++;
        _resetZoomState();
      }
    });
  }

  void _runSearch(String text) {
    final String q = text.trim();

    _searchResult.removeListener(_onSearchChanged);
    try {
      _searchResult.clear();
    } catch (_) {}
    _searchResult = PdfTextSearchResult();

    if (q.isEmpty) {
      setState(() => _searchNotFound = false);
      return;
    }

    // The viewer is still (re)loading: remember the query, run it when ready.
    if (!_documentLoaded || _busy) {
      _pendingSearchQuery = q;
      setState(() => _searchNotFound = false);
      return;
    }

    _pendingSearchQuery = null;
    _searchedQuery = q;
    final PdfTextSearchResult result = controller.searchText(q);
    result.addListener(_onSearchChanged);
    setState(() {
      _searchResult = result;
      _searchNotFound = false;
    });
  }

  void _flushPendingSearch() {
    final String? q = _pendingSearchQuery;
    if (q == null || !mounted || !_searchOpen) return;
    _runSearch(q);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchNotFound =
          _searchResult.isSearchCompleted && !_searchResult.hasResult;
    });
  }

  void _onSearchTextChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _searchOpen) _runSearch(text);
    });
  }

  void _onSearchSubmitted(String text) {
    _searchDebounce?.cancel();
    // Enter on an unchanged query = "next result".
    if (_searchResult.hasResult && text.trim() == _searchedQuery) {
      _searchResult.nextInstance();
    } else {
      _runSearch(text);
    }
  }

  void _searchStep({required bool forward}) {
    if (!_searchResult.hasResult) return;
    if (forward) {
      _searchResult.nextInstance();
    } else {
      _searchResult.previousInstance();
    }
  }

  PreferredSizeWidget _buildSearchBar(ColorScheme cs) {
    final bool has = _searchResult.hasResult;
    final int total = _searchResult.totalInstanceCount;
    final int current = _searchResult.currentInstanceIndex;

    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: _tr(context, 'close'),
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _closeSearch,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchTextChanged,
        onSubmitted: _onSearchSubmitted,
        decoration: InputDecoration(
          hintText: _tr(context, 'searchHint'),
          border: InputBorder.none,
          suffixText: has
              ? '$current/$total'
              : (_searchNotFound ? _tr(context, 'notFound') : null),
          suffixStyle: TextStyle(
            color: _searchNotFound ? cs.error : cs.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: _tr(context, 'prev'),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: has ? () => _searchStep(forward: false) : null,
        ),
        IconButton(
          tooltip: _tr(context, 'next'),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: has ? () => _searchStep(forward: true) : null,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // =================== UI ===================
  @override
  Widget build(BuildContext context) {
    final bool canAct = !_busy && _documentLoaded;
    final ColorScheme cs = Theme.of(context).colorScheme;

    return PopScope(
      // Warn before the user accidentally throws away unsaved work.
      canPop: !_dirty && !_searchOpen,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        if (_searchOpen) {
          _closeSearch();
          return;
        }

        // A tap in the text selection menu (Copy / Highlight / ...) must not
        // be treated as an attempt to leave the document.
        if (_textSelectionActive) {
          final DateTime before = _lastSelectionEvent;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          // Selection changed -> it was a menu action. Otherwise it is a
          // real "back": as in the system, it first clears the selection.
          if (_lastSelectionEvent == before) controller.clearSelection();
          return;
        }
        if (DateTime.now().difference(_lastSelectionEvent) <
            _kSelectionMenuPopWindow) {
          return;
        }

        final bool leave = await _confirmDiscardChanges();
        if (!context.mounted) return;
        if (leave) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: _immersive ? null : _buildAppBar(cs, canAct),
        body: pdfBytes == null
            ? Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildEmptyState(cs),
                  if (_busy)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                ],
              )
            : _buildEditorBody(canAct),
        bottomNavigationBar:
    (pdfBytes == null || _immersive)
        ? null
        : _buildBottomBar(canAct),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs, bool canAct) {
    if (_searchOpen && pdfBytes != null) return _buildSearchBar(cs);
    return AppBar(
      titleSpacing: 16,
      title: Row(
        children: <Widget>[
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: pdfBytes == null ? null : _goHome,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[cs.primary, cs.tertiary],
                        ),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 19,
                        color: cs.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        'PDF Editor',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: context.l10n.hasUnsavedChanges,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFA000),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
         PopupMenuButton<String>(
    tooltip: 'Language',
    icon: const Icon(Icons.language_rounded),
    onSelected: (String value) {
      widget.onLanguageChanged(Locale(value));
      _LanguageStore.save(value); // remembered for the next launch
    },
    itemBuilder: (BuildContext context) => const [
      PopupMenuItem<String>(
        value: 'en',
        child: Text('English'),
      ),
      PopupMenuItem<String>(
        value: 'ru',
        child: Text('Русский'),
      ),
      PopupMenuItem<String>(
        value: 'sk',
        child: Text('Slovenčina'),
      ),
      PopupMenuItem<String>(
        value: 'uk',
        child: Text('Українська'),
      ),
    ],
  ),

        IconButton(
          tooltip: context.l10n.recentDocuments,
          icon: const Icon(Icons.history_rounded),
          onPressed: _busy ? null : _openRecentDocuments,
        ),
        if (pdfBytes != null)
        IconButton(
          tooltip: context.l10n.share,
          icon: const Icon(Icons.share_rounded),
          onPressed: pdfBytes == null || _busy ? null : _shareFile,
        ),
        if (pdfBytes != null)
        IconButton(
          tooltip: context.l10n.openFileTypes,
          icon: const Icon(Icons.folder_open_rounded),
          onPressed: _busy ? null : openFile,
        ),
        if (pdfBytes != null)
          IconButton(
            tooltip: context.l10n.addPagesFromFile,
            icon: const Icon(Icons.note_add_rounded),
            onPressed: canAct ? addPagesFromFile : null,
          ),
        if (pdfBytes != null)
          IconButton.filled(
            tooltip: context.l10n.savePdf,
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: canAct ? savePdf : null,
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    final TextTheme tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[cs.primary, cs.tertiary],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Icon(Icons.description_rounded,
                    size: 54, color: cs.onPrimary),
              ),
              const SizedBox(height: 32),
              Text(
                context.l10n.homeTitle,
                textAlign: TextAlign.center,
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.homeDescription,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : openFile,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(context.l10n.openFile),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  _FeatureChip(
                      icon: Icons.photo_library_rounded, label: context.l10n.photo),
                  _FeatureChip(
                      icon: Icons.article_rounded, label: context.l10n.txtAndOthers),
                  _FeatureChip(icon: Icons.draw_rounded, label: context.l10n.drawing),
                  _FeatureChip(
                      icon: Icons.text_fields_rounded, label: context.l10n.textTool),
                  _FeatureChip(icon: Icons.zoom_in_rounded, label: context.l10n.zoom),
                  _FeatureChip(
                      icon: Icons.rotate_right_rounded, label: context.l10n.rotation),
                  _FeatureChip(
                      icon: Icons.swap_vert_rounded, label: context.l10n.pageOrder),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorBody(bool canAct) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _viewport = viewport;

        // The page area is `zoom x viewport` big. Every overlay below is
        // computed against THIS size, so strokes and labels follow the zoom
        // exactly and stay sharp.
        final double zoom = _zoom;
        final Size content = viewport * zoom;
        final Offset pan = _clampPan(_pan, viewport, zoom);

        final int pageIndex = (_currentPage - 1)
            .clamp(0, math.max(0, _pageInfos.length - 1))
            .toInt();

        final Rect currentPageRect =
            _pageInfos.isEmpty ? Rect.zero : _pageRect(content, pageIndex);

        // Overlays are only trusted once the viewer has actually loaded the
        // current revision of the document; before that the geometry is stale.
        final bool overlaysReady = _documentLoaded &&
            _searchCopyBytes == null &&
            _pageInfos.isNotEmpty &&
            currentPageRect != Rect.zero;
        final bool interactive = overlaysReady && !_busy;

        // Live (blurry but instant) transform while two fingers are down. When
        // they lift, the zoom is committed and the page re-renders sharp.
        Matrix4 live = Matrix4.identity();
        if (_pinching) {
          final (double, Offset) t = _pinchTarget(viewport);
          final double r = t.$1 / zoom;
          live = Matrix4.translationValues(t.$2.dx, t.$2.dy, 0) *
              Matrix4.diagonal3Values(r, r, 1) *
              Matrix4.translationValues(-pan.dx, -pan.dy, 0);
        }

        final Widget pageStack = Stack(
          children: <Widget>[
            IgnorePointer(
              ignoring: _pinching,
              child: SfPdfViewer.memory(
                _searchCopyBytes ?? pdfBytes!,
                key: ValueKey<int>(_documentRevision),
                controller: controller,
                pageLayoutMode: PdfPageLayoutMode.single,
                scrollDirection: PdfScrollDirection.horizontal,
                pageSpacing: 0,
                initialPageNumber: _currentPage,
                initialZoomLevel: 1,
                maxZoomLevel: 1,
                enableDoubleTapZooming: false,
                canShowScrollHead: false,
                canShowScrollStatus: false,
                onDocumentLoaded: (_) {
                  if (!mounted) return;
                  final int? target = _pendingPage;
                  final int revision = _documentRevision;
                  setState(() {
                    _documentLoaded = true;
                  });

                  if (target == null) _flushPendingSearch();

                  if (target != null) {
                    controller.jumpToPage(target);
                    // Let the viewer finish its layout, then trust it again.
                    // The revision check drops this callback if another edit
                    // replaced the document in the meantime.
                    Future<void>.delayed(const Duration(milliseconds: 300), () {
                      if (!mounted || revision != _documentRevision) return;
                      controller.jumpToPage(target);
                      setState(() {
                        _currentPage = target;
                        _pendingPage = null;
                      });
                      _flushPendingSearch();
                    });
                  }
                },
                onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                  if (!mounted) return;
                  _showMessage(context.l10n.couldNotDisplayPdf(details.description));
                  setState(() {
                    pdfBytes = null;
                    _pageInfos = <_PageInfo>[];
                    _annotations.clear();
                    _redoStack.clear();
                    _activeStroke = null;
                    _documentLoaded = false;
                    _pendingPage = null;
                    _resetZoomState();
                    _dirty = false;
                  });
                },
                onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
                  final String? selected = details.selectedText;
                  _textSelectionActive = selected != null && selected.isNotEmpty;
                  _lastSelectionEvent = DateTime.now();
                },
                onPageChanged: (PdfPageChangedDetails details) {
                  if (!mounted || _pendingPage != null) return;
                  setState(() {
                    _currentPage = details.newPageNumber;
                    _activeStroke = null;
                  });
                },
              ),
            ),

            // Photos live UNDER the pen strokes (same order as in the saved
            // PDF). While the photo tool is active they are moved to the top
            // instead, so they can be touched.
            if (overlaysReady && _tool != _EditorTool.image)
              ..._annotations
                  .whereType<_ImageAnnotation>()
                  .where((_ImageAnnotation i) => i.pageIndex == pageIndex)
                  .map((_ImageAnnotation i) => _buildImageOverlay(
                      i, currentPageRect, pageIndex,
                      editable: false)),

            // Freehand preview. IgnorePointer is essential: when the draw tool
            // is off, normal PDF interaction still works.
            if (overlaysReady)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _StrokePainter(
                      strokes: _annotations
                          .whereType<_StrokeAnnotation>()
                          .where((_StrokeAnnotation s) => s.pageIndex == pageIndex)
                          .toList(),
                      pageRect: currentPageRect,
                      rotation: _pageInfos[pageIndex].rotation,
                      scale: _pageScale(currentPageRect, _pageInfos[pageIndex]),
                    ),
                  ),
                ),
              ),

            // While zoomed in, the viewer must not react to touches (a swipe
            // would flip the page). Panning is done by the Listener instead.
            // Double tap returns to the full-page view.
            if (zoom > 1)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _resetZoom,
                  child: const SizedBox.expand(),
                ),
              ),

            // Drawing input is accepted ONLY inside the visible PDF page.
            if (interactive &&
                (_tool == _EditorTool.draw || _tool == _EditorTool.highlight))
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails d) =>
                      _dotAt(d.localPosition, currentPageRect, pageIndex),
                  onPanStart: (DragStartDetails d) =>
                      _startStroke(d.localPosition, currentPageRect, pageIndex),
                  onPanUpdate: (DragUpdateDetails d) =>
                      _updateStroke(d.localPosition, currentPageRect, pageIndex),
                  onPanEnd: (_) => _endStroke(),
                  onPanCancel: _endStroke,
                ),
              ),

            // Tap on the PDF page to add text at exactly that location.
            if (interactive && _tool == _EditorTool.text)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (TapUpDetails d) =>
                      _addTextAt(d.localPosition, currentPageRect, pageIndex),
                ),
              ),

            // Photo tool: tap on an empty spot clears the selection; the
            // photos themselves are above this layer.
            if (interactive && _tool == _EditorTool.image)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _selectedImage = null),
                ),
              ),
            if (overlaysReady && _tool == _EditorTool.image)
              ..._annotations
                  .whereType<_ImageAnnotation>()
                  .where((_ImageAnnotation i) => i.pageIndex == pageIndex)
                  .map((_ImageAnnotation i) => _buildImageOverlay(
                      i, currentPageRect, pageIndex,
                      editable: true)),

            // Text labels sit above the gesture layers, so tapping an existing
            // label edits it instead of spawning a new one underneath.
            if (overlaysReady)
              ..._annotations
                  .whereType<_TextAnnotation>()
                  .where((_TextAnnotation t) => t.pageIndex == pageIndex)
                  .map((_TextAnnotation t) =>
                      _buildTextOverlay(t, currentPageRect, pageIndex)),
          ],
        );

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: ClipRect(
                  child: Transform(
                    transform: live,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: content.width,
                      maxWidth: content.width,
                      minHeight: content.height,
                      maxHeight: content.height,
                      child: Transform.translate(
                        offset: pan,
                        child: SizedBox(
                          width: content.width,
                          height: content.height,
                          child: pageStack,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (!_documentLoaded || _busy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 3),
                ),

              if (_pageInfos.isNotEmpty)
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildPagePill(canAct)),
                ),
Positioned(
  right: 12,
  bottom: 12,
  child: _buildZoomControls(canAct),
),
             Positioned(
  left: 30,
  top: 12,
  child: FloatingActionButton.small(
    heroTag: 'immersive',
    //tooltip: _immersive ? 'Выйти из полного экрана' : 'Полный экран',
    onPressed: _toggleImmersive,
    child: Icon(
      _immersive
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded,
    ),
  ),
),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPagePill(bool canAct) {
    return Material(
      color: Colors.black.withValues(alpha: 0.66),
      shape: const StadiumBorder(),
      elevation: 3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _PillButton(
            icon: Icons.chevron_left_rounded,
            tooltip: context.l10n.previousPage,
            onPressed:
                canAct && _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          ),
          Text(
            '$_currentPage / ${_pageInfos.length}',
            style: const TextStyle(
              inherit: false,
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
            ),
          ),
          _PillButton(
            icon: Icons.chevron_right_rounded,
            tooltip: context.l10n.nextPage,
            onPressed: canAct && _currentPage < _pageInfos.length
                ? () => _goToPage(_currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls(bool canAct) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool canIn = canAct && _zoom < _kMaxZoom - 0.01;
    final bool canOut = canAct && _zoom > _kMinZoom + 0.01;

    return Material(
      color: cs.surfaceContainerHigh.withValues(alpha: 0.96),
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (MediaQuery.of(context).orientation == Orientation.landscape)
  IconButton(
    tooltip: _tr(context, 'fitWidth'),
    icon: const Icon(Icons.fit_screen_rounded),
    onPressed: canAct ? _fitWidth : null,
  ),
          IconButton(
            tooltip: context.l10n.zoomIn,
            icon: const Icon(Icons.add_rounded),
            onPressed: canIn ? () => _zoomBy(1.5) : null,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: canOut ? _resetZoom : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '${(_zoom * 100).round()}%',
                style: TextStyle(
                  inherit: false,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: canOut ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.zoomOut,
            icon: const Icon(Icons.remove_rounded),
            onPressed: canOut ? () => _zoomBy(1 / 1.5) : null,
          ),
        ],
      ),
    );
  }

  /// Shared geometry of a signature/photo on screen.
  ({
    _Placement placement,
    double pageScale,
    int totalTurns,
    Offset centerScreen,
    Size box,
  }) _screenGeometry(
    _PlacedAnnotation a,
    Rect pageRect,
    _PageInfo info,
  ) {
    final double pageScale = _pageScale(pageRect, info);
    final _Placement pl = _placementOf(a, info.size);
    // The element is rotated by (page rotation + its own rotation).
    final int totalTurns = (_quarterTurns(info.rotation) + a.turns) % 4;
    final Offset centerScreen = _canonicalToScreen(
      Offset(pl.center.dx / info.size.width, pl.center.dy / info.size.height),
      pageRect,
      info.rotation,
    );
    final bool swap = totalTurns.isOdd;
    final Size box = Size(
      (swap ? pl.content.height : pl.content.width) * pageScale,
      (swap ? pl.content.width : pl.content.height) * pageScale,
    );
    return (
      placement: pl,
      pageScale: pageScale,
      totalTurns: totalTurns,
      centerScreen: centerScreen,
      box: box,
    );
  }

  Widget _buildTextOverlay(_TextAnnotation t, Rect pageRect, int pageIndex) {
    final _PageInfo info = _pageInfos[pageIndex];
    final bool editable = _tool == _EditorTool.text;
    final bool selected = editable && identical(t, _selectedText);
    final g = _screenGeometry(t, pageRect, info);
    final double displayScale = g.pageScale * g.placement.fit;
    final ColorScheme cs = Theme.of(context).colorScheme;

    final Widget label = SizedBox(
      width: g.box.width,
      height: g.box.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editable ? () {
                if (selected) {
                  _editText(t);
                } else {
                  setState(() => _selectedText = t);
                }
              } : null,
              onLongPress: editable ? () => _deleteText(t) : null,
              onPanStart: editable ? (_) => setState(() => _selectedText = t) : null,
              onPanUpdate: editable
                  ? (d) => _movePlaced(t, d.delta, pageRect, pageIndex)
                  : null,
              child: RotatedBox(
                quarterTurns: g.totalTurns,
                child: Container(
                  padding: EdgeInsets.all(_kTextPaddingPt * displayScale),
                  color: editable
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.transparent,
                  child: Text(
                    t.text,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: _labelStyle(t.fontSize * displayScale, t.color),
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
              ),
            ),
          if (selected)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) =>
                    _resizeTextByDrag(t, d.delta, pageRect, pageIndex),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.open_in_full_rounded,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Positioned(
      left: g.centerScreen.dx - g.box.width / 2,
      top: g.centerScreen.dy - g.box.height / 2,
      child: editable ? label : IgnorePointer(child: label),
    );
  }

  Widget _buildImageOverlay(
    _ImageAnnotation img,
    Rect pageRect,
    int pageIndex, {
    required bool editable,
  }) {
    final _PageInfo info = _pageInfos[pageIndex];
    final ColorScheme cs = Theme.of(context).colorScheme;
    final g = _screenGeometry(img, pageRect, info);
    final bool selected = editable && identical(img, _selected);

    final double contentW = g.placement.content.width * g.pageScale;
    final double contentH = g.placement.content.height * g.pageScale;

    final Widget picture = RotatedBox(
      quarterTurns: g.totalTurns,
      child: SizedBox(
        width: contentW,
        height: contentH,
        child: Image.memory(
          img.png,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );

    final Widget body = SizedBox(
      width: g.box.width,
      height: g.box.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            // Gestures outside the rotation: delta is always in screen coordinates.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editable ? () => setState(() => _selectedImage = img) : null,
              onPanStart: editable
                  ? (DragStartDetails d) =>
                      setState(() => _selectedImage = img)
                  : null,
              onPanUpdate: editable
                  ? (DragUpdateDetails d) =>
                      _movePlaced(img, d.delta, pageRect, pageIndex)
                  : null,
              onLongPress: editable ? () => _deleteImage(img) : null,
              child: picture,
            ),
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
              ),
            ),
          if (selected)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails d) =>
                    _resizeImageByDrag(img, d.delta, g.box, info),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.open_in_full_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Positioned(
      left: g.centerScreen.dx - g.box.width / 2,
      top: g.centerScreen.dy - g.box.height / 2,
      child: editable ? body : IgnorePointer(child: body),
    );
  }

  List<Widget> _imageToolOptions() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final _ImageAnnotation? sel = _selected;

    final Widget addButton = IconButton(
      tooltip: context.l10n.addPhoto,
      icon: const Icon(Icons.add_photo_alternate_rounded),
      onPressed: _busy ? null : _insertImage,
    );

    if (sel == null) {
      return <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              context.l10n.photoHint,
              maxLines: 2,
              style: TextStyle(
                inherit: false,
                fontSize: 11,
                height: 1.25,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        addButton,
      ];
    }

    final _PageInfo info = _pageInfos[sel.pageIndex];
    final double maxW = _maxImageWidth(sel, info.size);
    final double minW = math.min(_kMinImageWidthPt, maxW);
    final double sliderMax = math.max(minW + 1, maxW);

    return <Widget>[
      Icon(Icons.photo_size_select_large_rounded,
          size: 20, color: cs.onSurfaceVariant),
      Expanded(
        child: Slider(
          min: minW,
          max: sliderMax,
          value: sel.widthPt.clamp(minW, sliderMax).toDouble(),
          onChanged: (double v) => _setImageWidth(sel, v, info),
        ),
      ),
      IconButton(
        tooltip: context.l10n.deletePhoto,
        icon: Icon(Icons.delete_outline_rounded, color: cs.error),
        onPressed: () => _deleteImage(sel),
      ),
      addButton,
    ];
  }

  Widget _buildToolOptions() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            if (_tool == _EditorTool.draw || _tool == _EditorTool.text) ...<Widget>[
              for (final Color c in _kPalette)
                _ColorDot(
                  color: c,
                  selected: c == _penColor,
                  onTap: () => setState(() => _penColor = c),
                ),
              const SizedBox(width: 6),
            ],
            if (_tool == _EditorTool.draw) ...<Widget>[
              Icon(Icons.line_weight_rounded,
                  size: 20, color: cs.onSurfaceVariant),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 12,
                  divisions: 11,
                  value: _penWidth,
                  label: '${_penWidth.round()} pt',
                  onChanged: (double v) => setState(() => _penWidth = v),
                ),
              ),
            ] else if (_tool == _EditorTool.highlight)
              Expanded(
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 24,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _kHighlighterColor.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.highlighterHint,
                        style: TextStyle(
                          inherit: false,
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_tool == _EditorTool.image)
              ..._imageToolOptions()
            else
              Expanded(
                child: Text(
                  context.l10n.textEditHint,
                  maxLines: 2,
                  style: TextStyle(
                    inherit: false,
                    fontSize: 11,
                    height: 1.25,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool canAct) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    Widget divider() => SizedBox(
          height: 30,
          child: VerticalDivider(
            width: 14,
            thickness: 1,
            color: cs.outlineVariant,
          ),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: _tool == _EditorTool.none
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildToolOptions(),
                    ),
            ),
            Material(
              color: cs.surfaceContainerHigh,
              elevation: 6,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        _ToolButton(
                          icon: Icons.search_rounded,
                          label: _tr(context, 'search'),
                          onPressed: canAct ? _openSearch : null,
                        ),
                        _ToolButton(
                          icon: Icons.draw_rounded,
                          label: context.l10n.draw,
                          selected: _tool == _EditorTool.draw,
                          onPressed: canAct
                              ? () => _selectTool(_EditorTool.draw)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.highlight_rounded,
                          label: context.l10n.highlighter,
                          selected: _tool == _EditorTool.highlight,
                          onPressed: canAct
                              ? () => _selectTool(_EditorTool.highlight)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.text_fields_rounded,
                          label: context.l10n.textTool,
                          selected: _tool == _EditorTool.text,
                          onPressed: canAct
                              ? () {
                                  _selectTool(_EditorTool.text);
                                  if (_tool == _EditorTool.text) {
                                    _showMessage(context.l10n.tapPageForText);
                                  }
                                }
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.add_photo_alternate_rounded,
                          label: context.l10n.photo,
                          selected: _tool == _EditorTool.image,
                          onPressed: canAct ? _onImageToolPressed : null,
                        ),
                        divider(),
                        _ToolButton(
                          icon: Icons.undo_rounded,
                          label: context.l10n.undo,
                          onPressed: canAct && _canUndo ? undoCustomEdit : null,
                        ),
                        _ToolButton(
                          icon: Icons.redo_rounded,
                          label: context.l10n.redo,
                          onPressed: canAct && _canRedo ? redoCustomEdit : null,
                        ),
                        divider(),
                        _ToolButton(
                          icon: Icons.rotate_left_rounded,
                          label: context.l10n.left,
                          onPressed:
                              canAct ? () => rotatePage(clockwise: false) : null,
                        ),
                        _ToolButton(
                          icon: Icons.rotate_right_rounded,
                          label: context.l10n.right,
                          onPressed: canAct ? () => rotatePage() : null,
                        ),
                        divider(),
                        _ToolButton(
                          icon: Icons.arrow_upward_rounded,
                          label: context.l10n.up,
                          onPressed: canAct && _currentPage > 1
                              ? () => movePage(_currentPage - 2)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.arrow_downward_rounded,
                          label: context.l10n.down,
                          onPressed: canAct && _currentPage < _pageInfos.length
                              ? () => movePage(_currentPage)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.delete_outline_rounded,
                          label: context.l10n.delete,
                          danger: true,
                          onPressed: canAct ? deletePage : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Painter
// ===========================================================================
class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.pageRect,
    required this.rotation,
    required this.scale,
  });

  final List<_StrokeAnnotation> strokes;
  final Rect pageRect;
  final PdfPageRotateAngle rotation;

  /// Screen pixels per PDF point. The saved line width is in points, so the
  /// preview must scale it too, otherwise the saved result looks different.
  final double scale;

  Offset _toScreen(Offset canonical) {
    final Offset p = _canonicalToDisplayNormalized(canonical, rotation);
    return Offset(
      pageRect.left + p.dx * pageRect.width,
      pageRect.top + p.dy * pageRect.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRect(pageRect);

    for (final _StrokeAnnotation stroke in strokes) {
      paint
        ..color = stroke.isHighlighter
            ? stroke.color.withValues(alpha: _kHighlighterOpacity)
            : stroke.color
        ..strokeWidth = stroke.width * scale
        ..blendMode = stroke.isHighlighter ? BlendMode.multiply : BlendMode.srcOver;

      for (int i = 0; i < stroke.points.length - 1; i++) {
        final Offset? p1 = stroke.points[i];
        final Offset? p2 = stroke.points[i + 1];
        if (p1 == null || p2 == null) continue;
        canvas.drawLine(_toScreen(p1), _toScreen(p2), paint);
      }
    }

    canvas.restore();
  }

  // Strokes are mutated in place while drawing, so identity checks would miss
  // updates. Repainting a handful of lines is cheap.
  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}

// ===========================================================================
// Small widgets
// ===========================================================================
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;

    final Color fg = !enabled
        ? cs.onSurface.withValues(alpha: 0.38)
        : selected
            ? cs.onPrimaryContainer
            : danger
                ? cs.error
                : cs.onSurface;

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 24, color: fg),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    inherit: false,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 22,
      color: Colors.white,
      disabledColor: Colors.white30,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              inherit: false,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color ring = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? ring : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

// =================== TEXT DIALOG ===================
class _AddTextDialog extends StatefulWidget {
  const _AddTextDialog({
    this.initialText = '',
    this.initialFontSize = 18,
    this.isEditing = false,
  });

  final String initialText;
  final double initialFontSize;
  final bool isEditing;

  @override
  State<_AddTextDialog> createState() => _AddTextDialogState();
}

class _AddTextDialogState extends State<_AddTextDialog> {
  late final TextEditingController _textController =
      TextEditingController(text: widget.initialText);
  late double _fontSize = widget.initialFontSize;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        widget.isEditing ? Icons.edit_rounded : Icons.text_fields_rounded,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(widget.isEditing ? context.l10n.editText : context.l10n.addText),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _textController,
              autofocus: true,
              // Multi-line labels work end to end (preview and saved PDF).
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: context.l10n.enterText,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Icon(Icons.format_size_rounded,
                    size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(context.l10n.size),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_fontSize.round()} pt',
                    style: TextStyle(
                      inherit: false,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              min: 10,
              max: 48,
              value: _fontSize,
              onChanged: (double value) {
                setState(() {
                  _fontSize = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final String value = _textController.text.trim();
            if (value.isEmpty) return;
            Navigator.of(context).pop(
              _TextDialogResult(text: value, fontSize: _fontSize),
            );
          },
          child: Text(widget.isEditing ? context.l10n.save : context.l10n.add),
        ),
      ],
    );
  }
}

class _TextDialogResult {
  const _TextDialogResult({
    required this.text,
    required this.fontSize,
  });

  final String text;
  final double fontSize;
}
class _TextLine {
  const _TextLine({
    required this.page,
    required this.top,
    required this.bottom,
    required this.left,
    required this.text,
  });

  final int page;
  final double top;
  final double bottom;
  final double left;
  final String text;
}
class _RenderedTextImage {
  const _RenderedTextImage({
    required this.bytes,
    required this.widthPoints,
    required this.heightPoints,
  });

  final Uint8List bytes;
  final double widthPoints;
  final double heightPoints;
}


// ===========================================================================
// Editable source stored inside a saved PDF
// ===========================================================================
class _EditableBundle {
  const _EditableBundle({
    required this.baseBytes,
    required this.pageCount,
    required this.annotations,
  });

  final Uint8List baseBytes;
  final int pageCount;
  final List<_PageAnnotation> annotations;
}

/// Returns the original pages and the editable marks if [bytes] was saved by
/// this editor, otherwise null. Never throws.
_EditableBundle? _readEditableBundle(Uint8List bytes) {
  PdfDocument? doc;
  try {
    doc = PdfDocument(inputBytes: bytes);
    Uint8List? base;
    String? dataJson;
    final Map<int, Uint8List> images = <int, Uint8List>{};

    for (int i = 0; i < doc.attachments.count; i++) {
      final PdfAttachment att = doc.attachments[i];
      final String name = att.fileName;
      if (name == _kEditableBaseName) {
        base = Uint8List.fromList(att.data);
      } else if (name == _kEditableDataName) {
        dataJson = utf8.decode(att.data, allowMalformed: true);
      } else if (name.startsWith(_kEditableImagePrefix) &&
          name.endsWith('.png')) {
        final int? index = int.tryParse(name.substring(
            _kEditableImagePrefix.length, name.length - '.png'.length));
        if (index != null) images[index] = Uint8List.fromList(att.data);
      }
    }
    if (base == null || dataJson == null) return null;

    final Object? decoded = jsonDecode(dataJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['v'] != _kEditableFormat) {
      return null;
    }
    final int pageCount = (decoded['pageCount'] as num).toInt();
    final List<_PageAnnotation> result = <_PageAnnotation>[];

    for (final dynamic raw in (decoded['items'] as List<dynamic>)) {
      final Map<String, dynamic> m = raw as Map<String, dynamic>;
      final int page = (m['p'] as num).toInt();
      switch (m['t']) {
        case 'stroke':
          final List<dynamic> pts = m['pts'] as List<dynamic>;
          if (pts.isEmpty) break;
          Offset? toOffset(dynamic v) => v == null
              ? null
              : Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
          final Offset first = toOffset(pts.first) ?? Offset.zero;
          final _StrokeAnnotation stroke = _StrokeAnnotation(
            pageIndex: page,
            color: Color((m['c'] as num).toInt()),
            width: (m['w'] as num).toDouble(),
            isHighlighter: m['h'] == true,
            first: first,
          );
          stroke.points
            ..clear()
            ..addAll(pts.map(toOffset));
          result.add(stroke);
        case 'text':
          result.add(_TextAnnotation(
            pageIndex: page,
            text: m['text'] as String,
            fontSize: (m['fs'] as num).toDouble(),
            color: Color((m['c'] as num).toInt()),
            widthPt: (m['w'] as num).toDouble(),
            center: Offset((m['cx'] as num).toDouble(),
                (m['cy'] as num).toDouble()),
            turns: (m['turns'] as num).toInt(),
          ));
        case 'image':
          final Uint8List? png = images[(m['img'] as num).toInt()];
          if (png == null) return null;
          result.add(_ImageAnnotation(
            pageIndex: page,
            png: png,
            pixelWidth: (m['pw'] as num).toInt(),
            pixelHeight: (m['ph'] as num).toInt(),
            widthPt: (m['w'] as num).toDouble(),
            center: Offset((m['cx'] as num).toDouble(),
                (m['cy'] as num).toDouble()),
            turns: (m['turns'] as num).toInt(),
          ));
      }
    }

    return _EditableBundle(
      baseBytes: base,
      pageCount: pageCount,
      annotations: result,
    );
  } catch (e) {
    debugPrint('Editable source not restored: $e');
    return null;
  } finally {
    doc?.dispose();
  }
}

// ===========================================================================
// Models
// ===========================================================================
class _PageInfo {
  const _PageInfo({
    required this.size,
    required this.rotation,
  });

  final Size size;
  final PdfPageRotateAngle rotation;
}

/// Base class for everything the user adds on top of a page.
abstract class _PageAnnotation {
  _PageAnnotation(this.pageIndex);

  int pageIndex;
}

class _StrokeAnnotation extends _PageAnnotation {
  _StrokeAnnotation({
    required int pageIndex,
    required this.color,
    required this.width,
    this.isHighlighter = false,
    required Offset first,
  })  : points = <Offset?>[first],
        super(pageIndex);

  final Color color;
  final bool isHighlighter;

  /// Line width in PDF points.
  final double width;

  /// Canonical points; a `null` entry means "pen lifted / left the page".
  final List<Offset?> points;
}

/// Signature or photo: center + rotation. See the description above [_quarterTurns].
abstract class _PlacedAnnotation extends _PageAnnotation {
  _PlacedAnnotation({
    required int pageIndex,
    required this.center,
    required this.turns,
  }) : super(pageIndex);

  /// Center in canonical page coordinates, 0..1.
  Offset center;

  /// Rotation of the content relative to the canonical page (clockwise quarter turns).
  final int turns;

  /// Content size in pt before rotation and shrinking.
  Size get contentSizePt;
}

class _TextAnnotation extends _PlacedAnnotation {
  _TextAnnotation({
    required super.pageIndex,
    required this.text,
    required this.fontSize,
    required this.color,
    required this.widthPt,
    required super.center,
    required super.turns,
  });
  String text;
  double fontSize;
  final Color color;
  double widthPt;

  @override
  Size get contentSizePt =>
      _measureTextSize(text, fontSize, maxWidth: widthPt);
}

class _ImageAnnotation
    extends _PlacedAnnotation {
  _ImageAnnotation({
    required super.pageIndex,
    required this.png,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.widthPt,
    required super.center,
    required super.turns,
  });
  final Uint8List png;
  final int pixelWidth;
  final int pixelHeight;

  /// Photo width on the page in pt (height is computed from the proportions).
  double widthPt;

  double get aspect => pixelWidth / pixelHeight;

  @override
  Size get contentSizePt => Size(widthPt, widthPt / aspect);
}
