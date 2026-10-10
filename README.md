# \# 📄 Ultra PDF Editor

# 

# A Flutter-based PDF editor designed primarily for Android, with support for viewing, drawing, adding text, rearranging pages, rotating pages, zooming, and saving edited PDF documents.

# 

# The application focuses on keeping annotations visually attached to the PDF page even when pages are zoomed, rotated, or rearranged.

# 

# \---

# 

# \## ✨ Features

# 

# \### 📂 PDF Files

# 

# \- Open PDF documents from device storage.

# \- Display multi-page PDF documents.

# \- Save the edited document as a new PDF file.

# \- Detect loading and processing states.

# \- Confirmation before opening another file when unsaved changes exist.

# 

# \---

# 

# \## 🔍 Zoom \& Navigation

# 

# The editor supports custom PDF zooming designed for touch screens.

# 

# \### Gestures

# 

# \- \*\*Pinch with two fingers\*\* to zoom from \*\*100% to 300%\*\*.

# \- \*\*Drag with one finger\*\* to move around the page while zoomed in.

# \- \*\*Double tap\*\* the page to return to the full-page view.

# \- Tap the displayed zoom percentage to reset zoom to \*\*100%\*\*.

# 

# \### Zoom Controls

# 

# Buttons in the bottom-right corner provide:

# 

# \- `+` — Zoom in.

# \- `−` — Zoom out.

# \- `%` — Current zoom level / reset zoom.

# 

# After a pinch gesture finishes, the PDF page is rendered again at the new size instead of simply stretching the existing image. This keeps PDF text and graphics sharp.

# 

# While the fingers are moving, the page may temporarily look slightly blurred. Once the gesture finishes, the page is re-rendered and becomes sharp again.

# 

# \---

# 

# \## 📖 Page Navigation

# 

# When the document is zoomed in, normal page-swiping is disabled so that horizontal gestures can be used for moving around the enlarged page.

# 

# Page navigation is available through the page counter at the top of the editor:

# 

# ```text

# ‹   2 / 5   ›

# ```

# 

# \- Left arrow — previous page.

# \- Right arrow — next page.

# \- Changing the page resets the zoom.

# \- The first page cannot be moved further upward.

# \- The last page cannot be moved further downward.

# 

# \---

# 

# \## ✏️ Drawing

# 

# The editor includes freehand drawing directly over PDF pages.

# 

# Features:

# 

# \- Draw using touch input.

# \- Tap once in drawing mode to create a dot.

# \- Draw while the page is zoomed.

# \- Drawing remains attached to the PDF page.

# \- Drawings follow page rotation.

# \- Drawings follow pages when their order is changed.

# \- Drawings are permanently written into the PDF when the file is saved.

# 

# \### Pen customization

# 

# The editor provides several pen colors:

# 

# \- 🔴 Red

# \- ⚫ Black

# \- 🔵 Blue

# \- 🟢 Green

# \- 🟣 Purple

# 

# The line thickness can also be adjusted using a slider.

# 

# \---

# 

# \## 📝 Text Annotations

# 

# Text can be added directly to any position on a PDF page.

# 

# Features:

# 

# \- Tap on the page to select the text position.

# \- Custom font size.

# \- Multiple lines of text.

# \- Different text colors.

# \- Drag text to another position.

# \- Tap existing text to edit it.

# \- Long-press existing text to delete it.

# \- Text stays attached to the page during rotation and page reordering.

# \- Unicode text can be saved, including Cyrillic and Slovak characters.

# 

# When saving, text is rendered and embedded into the PDF so the saved document visually matches the editor preview.

# 

# \---

# 

# \## ↩️ Undo \& Redo

# 

# The editor has a common editing history for drawings and text.

# 

# Supported actions:

# 

# \- \*\*Undo\*\* the most recent change on the current page.

# \- \*\*Redo\*\* previously undone changes.

# 

# Adding a new edit after an undo clears the redo history, following standard editor behavior.

# 

# \---

# 

# \## 🔄 Page Rotation

# 

# PDF pages can be rotated in both directions.

# 

# Available actions:

# 

# \- Rotate 90° clockwise.

# \- Rotate 90° counter-clockwise.

# 

# Possible orientations:

# 

# ```text

# 0° → 90° → 180° → 270°

# ```

# 

# Drawings and text use page-relative coordinates, allowing them to stay attached to their original location when the page orientation changes.

# 

# \---

# 

# \## ↕️ Page Reordering

# 

# Pages can be moved forward or backward inside the document.

# 

# For example:

# 

# ```text

# Page 1

# Page 2

# Page 3

# ```

# 

# can be changed to:

# 

# ```text

# Page 2

# Page 1

# Page 3

# ```

# 

# Annotations belonging to the moved page are remapped together with the page.

# 

# The application also prevents invalid operations:

# 

# \- Page 1 cannot be moved further upward.

# \- The last page cannot be moved further downward.

# \- Editing controls are temporarily disabled while a document operation is being processed.

# 

# \---

# 

# \## 🗑️ Page Deletion

# 

# Individual pages can be removed from a PDF.

# 

# Before deletion, the application displays a confirmation dialog.

# 

# Deleting a page also:

# 

# \- removes annotations belonging to that page;

# \- recalculates annotation page indexes;

# \- preserves edits on the remaining pages.

# 

# The application prevents deletion if the document contains only one page.

# 

# \---

# 

# \## 💾 Saving

# 

# When saving the document:

# 

# 1\. Current PDF page modifications are collected.

# 2\. Drawing annotations are rendered into their corresponding pages.

# 3\. Text annotations are rendered into their corresponding pages.

# 4\. The resulting PDF document is generated.

# 5\. Android displays the system save dialog.

# 6\. The saved file becomes the current version inside the editor.

# 

# Temporary drawing and text overlays are removed after saving because they are already physically embedded in the resulting PDF.

# 

# Example generated filename:

# 

# ```text

# edited\_1760202345123.pdf

# ```

# 

# \---

# 

# \## 🛡️ Unsaved Changes Protection

# 

# The editor keeps track of document modifications.

# 

# When unsaved edits exist:

# 

# \- an indicator appears in the application header;

# \- closing the editor asks for confirmation;

# \- opening another PDF asks for confirmation.

# 

# Example:

# 

# ```text

# Unsaved changes

# 

# All unsaved edits will be lost.

# Continue?

# 

# \[ Cancel ] \[ Continue ]

# ```

# 

# This prevents accidental loss of work.

# 

# \---

# 

# \## 📊 Document Status

# 

# The interface displays:

# 

# \- current page number;

# \- total number of pages;

# \- current zoom percentage;

# \- selected editing tool;

# \- unsaved changes state;

# \- document loading state;

# \- document processing state.

# 

# During longer operations such as saving, rotating, deleting, or moving pages, a loading indicator is displayed and conflicting actions are temporarily disabled.

# 

# \---

# 

# \## 📱 Mobile UI

# 

# The application is designed with touch-screen use in mind.

# 

# Main editor controls include:

# 

# | Control | Function |

# |---|---|

# | 📂 | Open PDF |

# | 💾 | Save PDF |

# | ✏️ | Drawing mode |

# | `T` | Add text |

# | ↩️ | Undo |

# | ↪️ | Redo |

# | ↺ | Rotate left |

# | ↻ | Rotate right |

# | ↑ | Move page up |

# | ↓ | Move page down |

# | 🗑️ | Delete page |

# | `+` | Zoom in |

# | `−` | Zoom out |

# 

# Controls automatically become unavailable when their action is not possible.

# 

# \---

# 

# \## 🎨 Interface

# 

# The application uses Material Design with a custom color scheme.

# 

# The editor contains:

# 

# \- top application bar;

# \- PDF viewport;

# \- floating page counter;

# \- zoom controls;

# \- bottom editing toolbar;

# \- dialogs for text and destructive actions;

# \- loading indicators;

# \- snack-bar notifications.

# 

# \---

# 

# \## 🧠 Coordinate System

# 

# One of the important parts of the project is annotation positioning.

# 

# Drawing and text coordinates are not stored as raw phone-screen pixels.

# 

# Instead, annotations are stored relative to the original PDF page.

# 

# Conceptually:

# 

# ```text

# Screen position

# &#x20;     ↓

# Displayed PDF page position

# &#x20;     ↓

# Normalized page coordinates

# &#x20;     ↓

# Original PDF page coordinates

# ```

# 

# This allows annotations to remain connected to the page when:

# 

# \- the screen size changes;

# \- the page is rotated;

# \- the page is zoomed;

# \- pages are reordered.

# 

# \---

# 

# \## 🛠️ Technologies

# 

# The project is built using:

# 

# \- \*\*Flutter\*\*

# \- \*\*Dart\*\*

# \- \*\*Android / Kotlin\*\*

# \- \*\*Syncfusion Flutter PDF Viewer\*\*

# \- \*\*Syncfusion Flutter PDF\*\*

# \- \*\*File Picker\*\*

# 

# Main packages:

# 

# ```yaml

# file\_picker

# syncfusion\_flutter\_pdfviewer

# syncfusion\_flutter\_pdf

# path\_provider

# signature

# ```

# 

# \---

# 

# \## 📁 Project Structure

# 

# ```text

# pdf\_editor\_android/

# │

# ├── android/

# │   └── Android-specific configuration

# │

# ├── ios/

# │   └── iOS project files

# │

# ├── lib/

# │   ├── main.dart

# │   └── pdf\_editor\_screen.dart

# │

# ├── linux/

# ├── macos/

# ├── web/

# ├── windows/

# ├── test/

# │

# ├── pubspec.yaml

# ├── pubspec.lock

# ├── analysis\_options.yaml

# └── README.md

# ```

# 

# The main PDF editor implementation is located in:

# 

# ```text

# lib/pdf\_editor\_screen.dart

# ```

# 

# \---

# 

# \## 🚀 Running the Project

# 

# \### Requirements

# 

# Make sure Flutter is installed:

# 

# ```bash

# flutter doctor

# ```

# 

# Install project dependencies:

# 

# ```bash

# flutter pub get

# ```

# 

# Check available devices:

# 

# ```bash

# flutter devices

# ```

# 

# Run the project:

# 

# ```bash

# flutter run

# ```

# 

# To run on a specific Android device:

# 

# ```bash

# flutter run -d <device-id>

# ```

# 

# Example:

# 

# ```bash

# flutter run -d EAZPTW494D4HQOBQ

# ```

# 

# \---

# 

# \## 📱 Running on a Physical Android Device

# 

# 1\. Enable \*\*Developer options\*\* on the Android phone.

# 2\. Enable \*\*USB debugging\*\*.

# 3\. Connect the phone to the computer using USB.

# 4\. Accept the USB debugging authorization dialog.

# 5\. Check the device:

# 

# ```bash

# flutter devices

# ```

# 

# 6\. Run:

# 

# ```bash

# flutter run -d <device-id>

# ```

# 

# \---

# 

# \## 🔧 Debug Commands

# 

# Hot reload:

# 

# ```text

# r

# ```

# 

# Hot restart:

# 

# ```text

# R

# ```

# 

# Stop the application:

# 

# ```text

# q

# ```

# 

# Clean the project:

# 

# ```bash

# flutter clean

# ```

# 

# Restore packages:

# 

# ```bash

# flutter pub get

# ```

# 

# \---

# 

# \## 📦 Android Build

# 

# Create a debug APK:

# 

# ```bash

# flutter build apk --debug

# ```

# 

# Create a release APK:

# 

# ```bash

# flutter build apk --release

# ```

# 

# Generated APK files can be found under:

# 

# ```text

# build/app/outputs/flutter-apk/

# ```

# 

# \---

# 

# \## ⚠️ Current Limitations

# 

# The application is a custom lightweight PDF editor rather than a complete replacement for professional desktop PDF software.

# 

# Current editing focuses mainly on:

# 

# \- freehand drawing;

# \- custom text;

# \- page rotation;

# \- page deletion;

# \- page reordering;

# \- zoom and navigation.

# 

# Annotations are flattened into the PDF during saving, which ensures visual consistency but means they are no longer independently editable after reopening the saved file.

# 

# \---

# 

# \## 🔮 Possible Future Improvements

# 

# Possible future features include:

# 

# \- text highlighting;

# \- image insertion;

# \- shapes and arrows;

# \- eraser tool;

# \- annotation selection;

# \- copy/paste annotations;

# \- page thumbnails;

# \- PDF search;

# \- form editing;

# \- password-protected PDF support;

# \- document metadata editing;

# \- automatic saving;

# \- recent documents;

# \- dark mode;

# \- opening PDFs directly through Android \*\*Open with\*\* integration.

# 

# \---

# 

# \## 📄 License

# 

# This project was created for educational and development purposes.

# 

# \---

# 

# \## 👨‍💻 Author

# 

# Developed as a Flutter PDF editing project with a focus on mobile interaction, page manipulation, accurate annotation positioning, and PDF document processing.

