import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'recent_documents_service.dart';

class RecentDocumentResult {
  final Uint8List bytes;
  final String fileName;

  const RecentDocumentResult({
    required this.bytes,
    required this.fileName,
  });
}

class RecentDocumentsScreen
    extends StatefulWidget {
  const RecentDocumentsScreen({
    super.key,
  });

  @override
  State<RecentDocumentsScreen>
      createState() =>
          _RecentDocumentsScreenState();
}

class _RecentDocumentsScreenState
    extends State<RecentDocumentsScreen> {
  bool _loading = true;

  List<RecentDocument> _documents =
      <RecentDocument>[];

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    final List<RecentDocument> documents =
        await RecentDocumentsService.load();

    if (!mounted) return;

    setState(() {
      _documents = documents;
      _loading = false;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final DateTime now = DateTime.now();

    final DateTime today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final DateTime value = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final Duration difference =
        today.difference(value);

    final String time =
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    if (difference.inDays == 0) {
      return 'Сегодня, $time';
    }

    if (difference.inDays == 1) {
      return 'Вчера, $time';
    }

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year} $time';
  }

  Future<void> _open(
    RecentDocument document,
  ) async {
    final Uint8List? bytes =
        await RecentDocumentsService.read(
      document,
    );

    if (!mounted) return;

    if (bytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Файл больше не существует',
          ),
        ),
      );

      await _load();

      return;
    }

    Navigator.of(context).pop(
      RecentDocumentResult(
        bytes: bytes,
        fileName: document.name,
      ),
    );
  }

  Future<void> _delete(
    RecentDocument document,
  ) async {
    await RecentDocumentsService.remove(
      document,
    );

    await _load();
  }

  Future<void> _clearAll() async {
    if (_documents.isEmpty) return;

    final bool? result =
        await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Очистить историю?',
          ),
          content: const Text(
            'Все документы будут удалены '
            'из списка недавно открытых.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child: const Text(
                'Отмена',
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child: const Text(
                'Очистить',
              ),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    await RecentDocumentsService.clear();

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Недавние документы',
        ),
        actions: <Widget>[
          if (_documents.isNotEmpty)
            IconButton(
              tooltip: 'Очистить историю',
              icon: const Icon(
                Icons.delete_sweep_rounded,
              ),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : _documents.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.history_rounded,
                        size: 72,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Недавних документов пока нет',
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  itemCount:
                      _documents.length,
                  separatorBuilder: (
                    BuildContext context,
                    int index,
                  ) =>
                      const Divider(
                    height: 1,
                  ),
                  itemBuilder: (
                    BuildContext context,
                    int index,
                  ) {
                    final RecentDocument
                        document =
                        _documents[index];

                    return ListTile(
                      leading: Container(
                        width: 46,
                        height: 46,
                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                          color: Theme.of(
                            context,
                          )
                              .colorScheme
                              .primaryContainer,
                        ),
                        child: Icon(
                          Icons
                              .picture_as_pdf_rounded,
                          color: Theme.of(
                            context,
                          )
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        document.name,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                      subtitle: Text(
                        '${_formatDate(document.lastOpened)}'
                        ' • ${_formatSize(document.size)}',
                      ),
                      onTap: () =>
                          _open(document),
                      trailing:
                          PopupMenuButton<String>(
                        onSelected:
                            (String value) {
                          if (value ==
                              'delete') {
                            _delete(
                              document,
                            );
                          }
                        },
                        itemBuilder:
                            (BuildContext
                                context) {
                          return const <
                              PopupMenuEntry<
                                  String>>[
                            PopupMenuItem<
                                String>(
                              value:
                                  'delete',
                              child: Row(
                                children: <
                                    Widget>[
                                  Icon(
                                    Icons
                                        .delete_outline_rounded,
                                  ),
                                  SizedBox(
                                    width: 12,
                                  ),
                                  Text(
                                    'Удалить из истории',
                                  ),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    );
                  },
                ),
    );
  }
}