import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter/services.dart';

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
const double _kMaxZoom = 3;

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
TextStyle _labelStyle(double fontSize, Color color) =>
    TextStyle(inherit: false, fontSize: fontSize, color: color);

// ===========================================================================
// Widget
// ===========================================================================

/// Public entry point. Wraps the editor in its own theme, so the screen looks
/// the same no matter how the host app is themed (dialogs included).
class PdfEditorScreen extends StatelessWidget {
  const PdfEditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _buildEditorTheme(Theme.of(context)),
      child: const _PdfEditorView(),
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
  const _PdfEditorView();

  @override
  State<_PdfEditorView> createState() => _PdfEditorViewState();
}

enum _EditorTool { none, draw, text }

class _PdfEditorViewState extends State<_PdfEditorView> {
  final PdfViewerController controller = PdfViewerController();
static const MethodChannel _openFileChannel =
    MethodChannel('pdf_editor/open_file');
  Uint8List? pdfBytes;
  int _documentRevision = 0;
  bool _documentLoaded = false;
  int _currentPage = 1;

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

  // All custom edits live in ONE ordered list. That single source of truth is
  // what makes undo/redo work the same way for strokes and text.
  //
  // Coordinates are stored in the ORIGINAL (unrotated) PDF page coordinate
  // system, normalized to 0..1, so edits follow the page when it is rotated.
  final List<_PageAnnotation> _annotations = <_PageAnnotation>[];
  final List<_PageAnnotation> _redoStack = <_PageAnnotation>[];
  _StrokeAnnotation? _activeStroke;

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
@override
void initState() {
  super.initState();

  _openFileChannel.setMethodCallHandler(
    (MethodCall call) async {
      if (call.method == 'openPdf') {
        final dynamic arguments = call.arguments;

        if (arguments is Uint8List) {
          await _openPdfBytes(arguments);
        }
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _checkInitialPdf();
  });
}
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // =================== SMALL HELPERS ===================
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmLabel = 'Да',
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
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _confirmDiscardChanges() {
    if (!_dirty) return Future<bool>.value(true);
    return _confirm(
      title: 'Несохранённые изменения',
      message: 'Все несохранённые правки будут потеряны. Продолжить?',
      confirmLabel: 'Продолжить',
      icon: Icons.warning_amber_rounded,
    );
  }

  /// Runs [action] as the only async operation in flight and reports errors
  /// instead of letting them escape as unhandled exceptions.
  Future<void> _runExclusive(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _showMessage('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
  Future<void> _checkInitialPdf() async {
  try {
    final Uint8List? bytes =
        await _openFileChannel.invokeMethod<Uint8List>(
      'getInitialPdf',
    );

    if (bytes != null && bytes.isNotEmpty) {
      await _openPdfBytes(bytes);
    }
  } catch (e) {
    debugPrint('Initial PDF error: $e');
  }
}
  Future<void> pickPDF() async {
    if (_busy || !await _confirmDiscardChanges()) return;

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final PlatformFile picked = result.files.single;
    Uint8List? bytes = picked.bytes;

    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }

    if (bytes == null) {
      _showMessage('Не удалось открыть PDF');
      return;
    }

    await _openPdfBytes(bytes);
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
Future<void> _openPdfBytes(Uint8List bytes) async {
  if (bytes.isEmpty) return;

  final List<_PageInfo> infos;

  try {
    infos = _readPageInfos(bytes);
  } catch (_) {
    _showMessage(
      'Не удалось прочитать PDF '
      '(файл повреждён или защищён паролем)',
    );

    return;
  }

  if (!mounted) return;

  controller.annotationMode = PdfAnnotationMode.none;
  controller.zoomLevel = 1;

  setState(() {
    pdfBytes = bytes;

    _pageInfos = infos;

    _currentPage = 1;
    _pendingPage = 1;

    _tool = _EditorTool.none;

    _documentLoaded = false;
    _documentRevision++;

    _annotations.clear();
    _redoStack.clear();

    _activeStroke = null;

    _resetZoomState();

    _dirty = false;
  });
}
  // =================== TOOL SELECTION ===================
  void _selectTool(_EditorTool tool) {
    if (pdfBytes == null) return;

    if (_tool == tool) {
      tool = _EditorTool.none;
    }

    controller.annotationMode = PdfAnnotationMode.none;
    controller.zoomLevel = 1;

    setState(() {
      _tool = tool;
      _activeStroke = null;
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

  double _rotationRadians(PdfPageRotateAngle rotation) {
    switch (rotation) {
      case PdfPageRotateAngle.rotateAngle90:
        return math.pi / 2;
      case PdfPageRotateAngle.rotateAngle180:
        return math.pi;
      case PdfPageRotateAngle.rotateAngle270:
        return math.pi * 1.5;
      case PdfPageRotateAngle.rotateAngle0:
        return 0;
    }
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
    final _StrokeAnnotation stroke = _StrokeAnnotation(
      pageIndex: pageIndex,
      color: _penColor,
      width: _penWidth,
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
    final _StrokeAnnotation dot = _StrokeAnnotation(
      pageIndex: pageIndex,
      color: _penColor,
      width: _penWidth,
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

    final PdfPageRotateAngle rotation = _pageInfos[pageIndex].rotation;
    final Offset canonical =
        _screenToCanonical(localPosition, pageRect, rotation);

    setState(() {
      _commit(
        _TextAnnotation(
          pageIndex: pageIndex,
          text: result.text,
          fontSize: result.fontSize,
          color: _penColor,
          canonicalPosition: canonical,
        ),
      );
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
      title: 'Удалить текст?',
      message: annotation.text,
      confirmLabel: 'Удалить',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    setState(() {
      _annotations.remove(annotation);
      _redoStack.remove(annotation);
      _dirty = true;
    });
  }

  void _moveText(
    _TextAnnotation annotation,
    Offset delta,
    Rect pageRect,
    int pageIndex,
  ) {
    final PdfPageRotateAngle rotation = _pageInfos[pageIndex].rotation;
    final Offset currentScreen = _canonicalToScreen(
      annotation.canonicalPosition,
      pageRect,
      rotation,
    );

    // _screenToCanonical clamps to the page, so the label slides along the
    // edge instead of getting stuck on it.
    setState(() {
      annotation.canonicalPosition =
          _screenToCanonical(currentScreen + delta, pageRect, rotation);
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
      _showMessage('Нельзя удалить единственную страницу');
      return;
    }

    final int removeIndex = _currentPage - 1;
    final bool ok = await _confirm(
      title: 'Удалить страницу $_currentPage?',
      message: 'Страница и все правки на ней будут удалены.',
      confirmLabel: 'Удалить',
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
      final int insertAt = to < from ? to : to + 1;
      final PdfPage newPage =
          doc.pages.insert(insertAt, sourcePage.size, noMargins);
      newPage.rotation = sourcePage.rotation;
      newPage.graphics
          .drawPdfTemplate(sourcePage.createTemplate(), Offset.zero);

      doc.pages.removeAt(to < from ? from + 1 : from);

      // IMPORTANT: sourceDoc must stay alive until doc.save() has finished -
      // the template still references its resources. It is disposed in
      // `finally`, i.e. only after the bytes are produced.
      return Uint8List.fromList(await doc.save());
    } finally {
      sourceDoc.dispose();
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

  // =================== SAVE ===================
  Future<_RenderedTextImage> _renderTextToPng(
    String text,
    double fontSize,
    Color color,
  ) async {
    const double pad = _kTextPaddingPt * _kTextPixelRatio;

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _labelStyle(fontSize * _kTextPixelRatio, color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final int widthPx = math.max(1, (painter.width + pad * 2).ceil());
    final int heightPx = math.max(1, (painter.height + pad * 2).ceil());

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    painter.paint(canvas, const Offset(pad, pad));
    painter.dispose();

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(widthPx, heightPx);
    picture.dispose();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (data == null) {
      throw StateError('Не удалось подготовить текст для PDF');
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
  }

  Future<void> _bakeText(PdfPage page, _TextAnnotation annotation) async {
    // Text is rendered by Flutter and embedded as a transparent PNG. This makes
    // Cyrillic / Slovak / any script work without bundling a TrueType font.
    final _RenderedTextImage rendered = await _renderTextToPng(
      annotation.text,
      annotation.fontSize,
      annotation.color,
    );

    final double pw = page.size.width;
    final double ph = page.size.height;

    // Only shrink if the label is bigger than the whole page.
    final double fit = math.min(
      1.0,
      math.min(pw / rendered.widthPoints, ph / rendered.heightPoints),
    );
    final double width = rendered.widthPoints * fit;
    final double height = rendered.heightPoints * fit;

    // Slide the label back inside the page instead of squeezing it, so text
    // placed near an edge keeps its size and stays readable.
    final double x = (annotation.canonicalPosition.dx * pw)
        .clamp(0.0, math.max(0.0, pw - width))
        .toDouble();
    final double y = (annotation.canonicalPosition.dy * ph)
        .clamp(0.0, math.max(0.0, ph - height))
        .toDouble();

    page.graphics.drawImage(
      PdfBitmap(rendered.bytes),
      Rect.fromLTWH(x, y, width, height),
    );
  }

  Future<Uint8List> _bakeAnnotations(Uint8List bytes) async {
    // Snapshot: rendering text is async and the list must not change meanwhile.
    final List<_PageAnnotation> snapshot =
        List<_PageAnnotation>.of(_annotations);
    final PdfDocument doc = PdfDocument(inputBytes: bytes);

    try {
      // Strokes first, then text - same layering as the on-screen preview.
      for (final _StrokeAnnotation s in snapshot.whereType<_StrokeAnnotation>()) {
        if (s.pageIndex < 0 || s.pageIndex >= doc.pages.count) continue;
        _bakeStroke(doc.pages[s.pageIndex], s);
      }

      for (final _TextAnnotation t in snapshot.whereType<_TextAnnotation>()) {
        if (t.pageIndex < 0 || t.pageIndex >= doc.pages.count) continue;
        await _bakeText(doc.pages[t.pageIndex], t);
      }

      return Uint8List.fromList(await doc.save());
    } finally {
      doc.dispose();
    }
  }

  Future<void> savePdf() {
    return _runExclusive(() async {
      final Uint8List? bytes = pdfBytes;
      if (bytes == null) return;

      final Uint8List finalBytes = await _bakeAnnotations(bytes);

      final String fileName =
          'edited_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
        bytes: finalBytes,
      );

      if (outputPath == null) return;

      // On mobile the plugin writes `bytes` itself; on desktop it only returns
      // the chosen path, so without this the user would get an empty save.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final String path = outputPath.toLowerCase().endsWith('.pdf')
            ? outputPath
            : '$outputPath.pdf';
        await File(path).writeAsBytes(finalBytes, flush: true);
      }

      final List<_PageInfo> infos = _readPageInfos(finalBytes);

      if (!mounted) return;

      // Strokes/text are now physically written into the PDF, so the temporary
      // overlays are cleared to avoid drawing everything twice.
      _applyNewDocument(
        finalBytes,
        infos,
        currentPage: _currentPage,
        dirty: false,
        alsoUpdate: () {
          _annotations.clear();
          _redoStack.clear();
        },
      );

      _showMessage('PDF сохранён успешно');
    });
  }

  // =================== ZOOM ===================
  void _resetZoomState() {
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
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _endStroke();
      _beginPinch();
    }
  }

  void _beginPinch() {
    if (pdfBytes == null || !_documentLoaded || _busy) return;
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
      setState(() {
        _pan = _clampPan(_pan + e.delta, _viewport, _zoom);
      });
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.length < 2) _finishPinch();
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

  // =================== UI ===================
  @override
  Widget build(BuildContext context) {
    final bool canAct = !_busy && _documentLoaded;
    final ColorScheme cs = Theme.of(context).colorScheme;

    return PopScope(
      // Warn before the user accidentally throws away unsaved work.
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool leave = await _confirmDiscardChanges();
        if (leave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: _buildAppBar(cs, canAct),
        body: pdfBytes == null ? _buildEmptyState(cs) : _buildEditorBody(canAct),
        bottomNavigationBar: pdfBytes == null ? null : _buildBottomBar(canAct),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs, bool canAct) {
    return AppBar(
      titleSpacing: 16,
      title: Row(
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
            child: Icon(Icons.picture_as_pdf_rounded,
                size: 19, color: cs.onPrimary),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'PDF Editor',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Есть несохранённые изменения',
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
        IconButton(
          tooltip: 'Открыть PDF',
          icon: const Icon(Icons.folder_open_rounded),
          onPressed: _busy ? null : pickPDF,
        ),
        if (pdfBytes != null)
          IconButton.filled(
            tooltip: 'Сохранить PDF',
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: canAct ? savePdf : null,
          ),
        const SizedBox(width: 10),
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
                'Редактируй PDF\nза пару касаний',
                textAlign: TextAlign.center,
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Рисуй, добавляй текст, поворачивай, переставляй и удаляй страницы.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: pickPDF,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Открыть PDF'),
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
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  _FeatureChip(icon: Icons.draw_rounded, label: 'Рисование'),
                  _FeatureChip(
                      icon: Icons.text_fields_rounded, label: 'Текст'),
                  _FeatureChip(icon: Icons.zoom_in_rounded, label: 'Зум'),
                  _FeatureChip(
                      icon: Icons.rotate_right_rounded, label: 'Поворот'),
                  _FeatureChip(
                      icon: Icons.swap_vert_rounded, label: 'Порядок страниц'),
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
                pdfBytes!,
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
                    });
                  }
                },
                onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                  if (!mounted) return;
                  _showMessage('Не удалось отобразить PDF: ${details.description}');
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
                onPageChanged: (PdfPageChangedDetails details) {
                  if (!mounted || _pendingPage != null) return;
                  setState(() {
                    _currentPage = details.newPageNumber;
                    _activeStroke = null;
                  });
                },
              ),
            ),

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
            if (interactive && _tool == _EditorTool.draw)
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
            tooltip: 'Предыдущая страница',
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
            tooltip: 'Следующая страница',
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
          IconButton(
            tooltip: 'Приблизить',
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
            tooltip: 'Отдалить',
            icon: const Icon(Icons.remove_rounded),
            onPressed: canOut ? () => _zoomBy(1 / 1.5) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTextOverlay(_TextAnnotation t, Rect pageRect, int pageIndex) {
    final _PageInfo info = _pageInfos[pageIndex];
    final Offset screenPosition =
        _canonicalToScreen(t.canonicalPosition, pageRect, info.rotation);
    final double scale = _pageScale(pageRect, info);
    final bool editable = _tool == _EditorTool.text;

    final Widget label = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: editable ? () => _editText(t) : null,
      onLongPress: editable ? () => _deleteText(t) : null,
      onPanUpdate: editable
          ? (DragUpdateDetails d) =>
              _moveText(t, d.delta, pageRect, pageIndex)
          : null,
      child: Transform.rotate(
        angle: _rotationRadians(info.rotation),
        alignment: Alignment.topLeft,
        child: Container(
          padding: EdgeInsets.all(_kTextPaddingPt * scale),
          decoration: BoxDecoration(
            color: editable
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          // foregroundDecoration does not affect layout, so the preview
          // keeps matching the saved PDF exactly.
          foregroundDecoration: editable
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.7),
                    width: 1,
                  ),
                )
              : null,
          child: Text(
            t.text,
            softWrap: false, // the saved PNG never wraps either
            style: _labelStyle(t.fontSize * scale, t.color),
          ),
        ),
      ),
    );

    return Positioned(
      left: screenPosition.dx,
      top: screenPosition.dy,
      child: editable ? label : IgnorePointer(child: label),
    );
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
            for (final Color c in _kPalette)
              _ColorDot(
                color: c,
                selected: c == _penColor,
                onTap: () => setState(() => _penColor = c),
              ),
            const SizedBox(width: 6),
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
            ] else
              Expanded(
                child: Text(
                  'Тап — править,\nудержание — удалить',
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
                          icon: Icons.draw_rounded,
                          label: 'Рисовать',
                          selected: _tool == _EditorTool.draw,
                          onPressed: canAct
                              ? () => _selectTool(_EditorTool.draw)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.text_fields_rounded,
                          label: 'Текст',
                          selected: _tool == _EditorTool.text,
                          onPressed: canAct
                              ? () {
                                  _selectTool(_EditorTool.text);
                                  if (_tool == _EditorTool.text) {
                                    _showMessage(
                                        'Нажми на место на странице для текста');
                                  }
                                }
                              : null,
                        ),
                        divider(),
                        _ToolButton(
                          icon: Icons.undo_rounded,
                          label: 'Отмена',
                          onPressed: canAct && _canUndo ? undoCustomEdit : null,
                        ),
                        _ToolButton(
                          icon: Icons.redo_rounded,
                          label: 'Вернуть',
                          onPressed: canAct && _canRedo ? redoCustomEdit : null,
                        ),
                        divider(),
                        _ToolButton(
                          icon: Icons.rotate_left_rounded,
                          label: 'Влево',
                          onPressed:
                              canAct ? () => rotatePage(clockwise: false) : null,
                        ),
                        _ToolButton(
                          icon: Icons.rotate_right_rounded,
                          label: 'Вправо',
                          onPressed: canAct ? () => rotatePage() : null,
                        ),
                        divider(),
                        _ToolButton(
                          icon: Icons.arrow_upward_rounded,
                          label: 'Вверх',
                          onPressed: canAct && _currentPage > 1
                              ? () => movePage(_currentPage - 2)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.arrow_downward_rounded,
                          label: 'Вниз',
                          onPressed: canAct && _currentPage < _pageInfos.length
                              ? () => movePage(_currentPage)
                              : null,
                        ),
                        _ToolButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'Удалить',
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
        ..color = stroke.color
        ..strokeWidth = stroke.width * scale;

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
      title: Text(widget.isEditing ? 'Изменить текст' : 'Добавить текст'),
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
                hintText: 'Введите текст',
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
                const Text('Размер'),
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
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final String value = _textController.text.trim();
            if (value.isEmpty) return;
            Navigator.of(context).pop(
              _TextDialogResult(text: value, fontSize: _fontSize),
            );
          },
          child: Text(widget.isEditing ? 'Сохранить' : 'Добавить'),
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
    required Offset first,
  })  : points = <Offset?>[first],
        super(pageIndex);

  final Color color;

  /// Line width in PDF points.
  final double width;

  /// Canonical points; a `null` entry means "pen lifted / left the page".
  final List<Offset?> points;
}

class _TextAnnotation extends _PageAnnotation {
  _TextAnnotation({
    required int pageIndex,
    required this.text,
    required this.fontSize,
    required this.color,
    required this.canonicalPosition,
  }) : super(pageIndex);

  String text;
  double fontSize;
  final Color color;
  Offset canonicalPosition;
}