import 'dart:typed_data';


import 'package:share_plus/share_plus.dart';

class ShareService {
  static Future<void> sharePdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
          ),
        ],
        fileNameOverrides: <String>[fileName],
      ),
    );
  }
}