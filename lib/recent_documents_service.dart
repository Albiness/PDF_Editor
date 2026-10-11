import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class RecentDocument {
  final String name;
  final String path;
  final DateTime lastOpened;
  final int size;

  const RecentDocument({
    required this.name,
    required this.path,
    required this.lastOpened,
    required this.size,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'path': path,
      'lastOpened': lastOpened.toIso8601String(),
      'size': size,
    };
  }

  factory RecentDocument.fromJson(Map<String, dynamic> json) {
    return RecentDocument(
      name: json['name'] as String,
      path: json['path'] as String,
      lastOpened: DateTime.parse(json['lastOpened'] as String),
      size: json['size'] as int,
    );
  }
}

class RecentDocumentsService {
  static const int _maxDocuments = 20;

  static Future<Directory> _recentDirectory() async {
    final Directory appDir =
        await getApplicationDocumentsDirectory();

    final Directory recentDir = Directory(
      '${appDir.path}${Platform.pathSeparator}recent_pdfs',
    );

    if (!await recentDir.exists()) {
      await recentDir.create(recursive: true);
    }

    return recentDir;
  }

  static Future<File> _indexFile() async {
    final Directory directory =
        await _recentDirectory();

    return File(
      '${directory.path}${Platform.pathSeparator}recent.json',
    );
  }

  static Future<List<RecentDocument>> load() async {
    try {
      final File file = await _indexFile();

      if (!await file.exists()) {
        return <RecentDocument>[];
      }

      final String content =
          await file.readAsString();

      if (content.trim().isEmpty) {
        return <RecentDocument>[];
      }

      final List<dynamic> jsonList =
          jsonDecode(content) as List<dynamic>;

      final List<RecentDocument> documents =
          jsonList
              .map(
                (dynamic item) =>
                    RecentDocument.fromJson(
                  Map<String, dynamic>.from(
                    item as Map,
                  ),
                ),
              )
              .toList();

      // Убираем записи, если физический файл
      // почему-то уже отсутствует.
      final List<RecentDocument> existing =
          <RecentDocument>[];

      for (final RecentDocument document
          in documents) {
        if (await File(document.path).exists()) {
          existing.add(document);
        }
      }

      existing.sort(
        (RecentDocument a, RecentDocument b) =>
            b.lastOpened.compareTo(a.lastOpened),
      );

      return existing;
    } catch (_) {
      return <RecentDocument>[];
    }
  }

  static Future<void> _saveIndex(
    List<RecentDocument> documents,
  ) async {
    final File file = await _indexFile();

    final String json = jsonEncode(
      documents
          .map(
            (RecentDocument document) =>
                document.toJson(),
          )
          .toList(),
    );

    await file.writeAsString(
      json,
      flush: true,
    );
  }

  static Future<void> add({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final Directory directory =
        await _recentDirectory();

    final List<RecentDocument> documents =
        await load();

    // Удаляем старую запись с таким же именем.
    final List<RecentDocument> sameName =
        documents
            .where(
              (RecentDocument d) =>
                  d.name == fileName,
            )
            .toList();

    for (final RecentDocument document
        in sameName) {
      final File oldFile = File(document.path);

      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    }

    documents.removeWhere(
      (RecentDocument d) =>
          d.name == fileName,
    );

    final String safeName = fileName.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '_',
    );

    final String storedName =
        '${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final String path =
        '${directory.path}${Platform.pathSeparator}$storedName';

    final File file = File(path);

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    documents.insert(
      0,
      RecentDocument(
        name: fileName,
        path: path,
        lastOpened: DateTime.now(),
        size: bytes.length,
      ),
    );

    // Максимум 20 документов.
    while (documents.length > _maxDocuments) {
      final RecentDocument old =
          documents.removeLast();

      final File oldFile = File(old.path);

      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    }

    await _saveIndex(documents);
  }

  static Future<Uint8List?> read(
    RecentDocument document,
  ) async {
    final File file = File(document.path);

    if (!await file.exists()) {
      return null;
    }

    final Uint8List bytes =
        await file.readAsBytes();

    // Обновляем дату последнего открытия.
    final List<RecentDocument> documents =
        await load();

    documents.removeWhere(
      (RecentDocument d) =>
          d.path == document.path,
    );

    documents.insert(
      0,
      RecentDocument(
        name: document.name,
        path: document.path,
        lastOpened: DateTime.now(),
        size: document.size,
      ),
    );

    await _saveIndex(documents);

    return bytes;
  }

  static Future<void> remove(
    RecentDocument document,
  ) async {
    final File file = File(document.path);

    if (await file.exists()) {
      await file.delete();
    }

    final List<RecentDocument> documents =
        await load();

    documents.removeWhere(
      (RecentDocument d) =>
          d.path == document.path,
    );

    await _saveIndex(documents);
  }

  static Future<void> clear() async {
    final List<RecentDocument> documents =
        await load();

    for (final RecentDocument document
        in documents) {
      final File file = File(document.path);

      if (await file.exists()) {
        await file.delete();
      }
    }

    await _saveIndex(
      <RecentDocument>[],
    );
  }
}