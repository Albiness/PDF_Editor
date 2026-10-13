<div align="center">

# 📄 PDF Editor

**A fast, privacy-friendly PDF editor for mobile, built with Flutter.**
Draw, highlight, add text and photos, rotate, reorder and merge pages — then save or share in a tap.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Material 3](https://img.shields.io/badge/Material-3-6750A4?logo=materialdesign&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey)
![Offline](https://img.shields.io/badge/works-100%25%20offline-success)

<!-- Replace with real screenshots -->
<!-- <img src="docs/screenshots/editor.png" width="260"> <img src="docs/screenshots/tools.png" width="260"> -->

</div>

---

## ✨ Overview

PDF Editor turns your phone into a lightweight PDF workshop. Open a PDF, a photo, or even a plain text file — everything is converted into a PDF on the fly, so **one editor handles every format**. All processing happens on-device: your documents never leave your phone unless you share them.

## 🚀 Features

### 📂 Open almost anything
| Type | Supported formats |
|------|-------------------|
| **PDF** | `.pdf` |
| **Images** | `jpg`, `jpeg`, `png`, `webp`, `bmp`, `gif`, `heic`, `heif` |
| **Text** | `txt`, `md`, `log`, `csv`, `tsv`, `json`, `xml`, `yaml`, `yml`, `ini`, `conf` |

- 🔍 **Smart format detection** — the file type is detected by its *signature (magic bytes)*, not just the extension, so files without an extension (e.g. received from other apps) still open correctly.
- 🖼️ **Photo → PDF** — each photo becomes a page with the same aspect ratio (no white borders). Large images are downscaled to keep the PDF small; HEIC/HEIF (iPhone photos) are supported.
- 📝 **Text → PDF** — plain-text files are paginated into a clean PDF (with safety limits on size and page count).
- 🔗 **Open from other apps** — receive files via the system "Open with" flow through a platform channel.
- 🕘 **Recent documents** — the last 20 files are cached locally with quick re-open, per-item removal and "clear all".

### ✏️ Annotation tools
| Tool | What it does |
|------|--------------|
| 🖊️ **Pen** | Freehand drawing, adjustable width (1–12 pt), 5-colour palette (red, black, blue, green, purple) |
| 🖍️ **Highlighter** | Wide translucent yellow stroke rendered with the **Multiply** blend mode — text stays readable while the background is tinted |
| 🔤 **Text labels** | Tap anywhere to add multi-line text, font size 10–48 pt, any palette colour. Tap to **edit**, drag to **move**, or delete |
| 🏞️ **Photos & stamps** | Insert an image from the gallery, drag it, **resize with a corner handle**, or delete it |
| ↩️ **Undo / Redo** | One unified history for strokes, text and photos |

### 📑 Page management
- 🔄 **Rotate** pages left or right (90° steps) — annotations rotate together with the page
- ⬆️⬇️ **Reorder** pages by moving the current page up or down
- 🗑️ **Delete** pages (the last remaining page is protected)
- ➕ **Add pages from another file** — append pages from another PDF, photo or text file to build one document (e.g. merge several photos into a single PDF)
- 🔢 Page indicator pill with previous / next navigation

### 🔎 Viewing & navigation
- **Pinch-to-zoom** (1×–2×) plus zoom in / zoom out / reset controls
- **Double-tap zoom** with a safe 2× cap to reduce excessive raster memory use on mobile
- **Crisp zoom** — the viewer is re-laid out at the zoomed size, so the PDF is re-rendered sharply instead of just being stretched
- Smooth two-finger pan while zoomed
- Built-in **text selection** (copy etc.) that doesn't conflict with the back button
- 🔎 **Optimised search** — native PDF text is searched by Syncfusion, while text added in the editor is searched directly in memory, avoiding full PDF rebuilds during search

### 💾 Save & share
- **Save as PDF** through the system file picker
- **Share** the document via the native share sheet; if there are unsaved edits, you choose whether to share the edited version or the original
- Smart file naming (`edited_<name>.pdf`) and sanitisation of unsafe characters
- **Unsaved-changes protection** — confirmation dialogs before leaving or opening another file

### 🌍 UI & polish
- Material 3 design with a dedicated indigo colour scheme, light & dark mode
- Fully **localised** UI (Flutter `l10n` / ARB) with in-app language switching
- 🌐 **Language persistence** — the selected language is remembered between app launches
- Floating snackbars, rounded dialogs, tooltips and a clean empty state with quick actions

---

## 🧠 How it works

### Everything becomes a PDF
Any opened file is routed through a single pipeline:

```
 file bytes ──▶ signature detection ──▶ PDF / image / text
                                          │        │       │
                                          ▼        ▼       ▼
                                        as-is   _imageToPdf  _textToPdf
                                          └────────┴───────┘
                                                   ▼
                                       Syncfusion PDF viewer + editor
```

This means drawing, text, zoom, rotation, reordering and saving work identically for every format — no per-format viewers required.

### WYSIWYG annotations
- All edits live in **one ordered list**, which is what makes undo/redo behave consistently across strokes, text and photos.
- Coordinates are stored **normalised (0..1) in the original, unrotated page space**, so annotations follow the page when it is rotated, moved or deleted.
- Text labels use the same layout metrics on screen and in the saved document. When the bundled TrueType font is available, labels are written as **real PDF text**, so they remain selectable, copyable and searchable in normal PDF readers.
- Placed items (text/photos) store a centre point and a quarter-turn offset, so a label added on an already-rotated page looks upright and rotates with the page afterwards.
- On save, strokes, highlights, text and photos are baked into the visible PDF page graphics; the highlighter uses a real `PdfBlendMode.multiply` with transparency.
- Saved files also carry a compact **editable source bundle** with the original pages and annotation metadata. Re-opening a PDF saved by the app restores supported annotations as editable objects instead of flattening the editing workflow permanently.


### Fast hybrid search
- Original PDF text is searched with `PdfViewerController.searchText(...)`.
- Text added in the editor is searched directly in `_TextAnnotation` objects already held in memory.
- The search bar uses a short debounce before running a query.
- Searching added text does **not** call `_bakeAnnotations()` and does not generate or reload a temporary PDF copy, which significantly reduces freezes on larger documents.
- Search navigation can jump to both native PDF matches and editor-added text matches.

### Safe, race-free editing
- Heavy operations (rotate / move / delete / save) run through an **exclusive executor** (`_busy` flag) to prevent competing edits on the same bytes.
- Zoom is capped at **2×** to reduce the risk of very large viewer raster allocations on Android devices.
- Page re-ordering recreates pages with **zero margins** to avoid the 40 pt shift that default margins would accumulate.
- Viewer page events are suppressed right after reloads to avoid the viewer briefly reporting the wrong page.

---

## 🛠️ Tech stack

| Package | Purpose |
|---------|---------|
| [`flutter`](https://flutter.dev) | UI framework (Material 3) |
| [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf) | Creating & editing PDF documents, baking annotations |
| [`syncfusion_flutter_pdfviewer`](https://pub.dev/packages/syncfusion_flutter_pdfviewer) | PDF rendering, native text search & text selection |
| [`file_picker`](https://pub.dev/packages/file_picker) | Opening and saving files |
| [`share_plus`](https://pub.dev/packages/share_plus) | Native share sheet |
| [`path_provider`](https://pub.dev/packages/path_provider) | Local storage for recent documents |
| `flutter_localizations` / `intl` | Localisation |

---

## 📦 Getting started

### Prerequisites
- Flutter SDK (stable channel)
- Android Studio / Xcode for device builds

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>

# 2. Install dependencies
flutter pub get

# 3. Generate localisation files
flutter gen-l10n

# 4. Run
flutter run
```

### Using the editor screen in your own app

```dart
import 'pdf_editor_screen.dart';

MaterialApp(
  home: PdfEditorScreen(
    onLanguageChanged: (Locale locale) {
      // update your app's locale here
    },
  ),
);
```

`PdfEditorScreen` wraps itself in its own theme, so it looks identical regardless of the host app's theme.


### Open-with integration (optional)
The screen listens on the `pdf_editor/open_file` platform channel. Send the file bytes with the `openPdf` method from your native side (Android intent / iOS document handler) to open files shared from other apps.

---

## 🗂️ Project structure

```
lib/
├── l10n/                    # ARB files & generated localisations
└── pdf_editor_screen.dart   # Editor: format detection, conversion,
                             # annotations, zoom, page tools, save/share,
                             # recent documents
```

Key building blocks inside the editor:

- **File layer** — `_detectFileKind`, `_convertToPdf`, `_imageToPdf`, `_textToPdf`
- **Models** — `_StrokeAnnotation`, `_TextAnnotation`, `_ImageAnnotation`
- **Rendering** — `_StrokePainter`, `_Placement` (shared preview/save geometry)
- **Services** — `_RecentDocumentsService` (local history, max 20 items), `_LanguageStore` (saved UI language)
- **Search** — hybrid native-PDF + in-memory annotation search
- **UI** — `_PdfEditorView`, `_AddTextDialog`, `_ToolButton`, `_ColorDot`

---

## 🗺️ Roadmap

- [ ] Eraser tool
- [ ] Shapes (rectangle, arrow, line)
- [ ] Digital signature
- [ ] Page thumbnails grid
- [ ] Password-protected PDFs
- [ ] Export pages as images

---

## 🤝 Contributing

Contributions, issues and feature requests are welcome!

1. Fork the project
2. Create your branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m "Add amazing feature"`
4. Push: `git push origin feature/amazing-feature`
5. Open a Pull Request

---

<div align="center">
Made with ❤️ and Flutter
</div>
