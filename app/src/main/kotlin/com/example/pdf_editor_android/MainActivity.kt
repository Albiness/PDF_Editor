
package com.example.pdf_editor_android

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "pdf_editor/open_file"

    private var methodChannel: MethodChannel? = null

    // Store the PDF until Flutter is ready to receive it.
    private var pendingPdf: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPdf" -> {
                    val pdf = pendingPdf ?: readPdfFromIntent(intent)
                    pendingPdf = null
                    result.success(pdf)
                }

                "getInitialFileName" -> {
                    val uri = intent?.data
                    result.success(
                        if (uri != null) getFileName(uri) else null
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        val pdf = readPdfFromIntent(intent)

        if (pdf != null) {
            if (methodChannel != null) {
                methodChannel?.invokeMethod(
                    "openPdf",
                    pdf
                )
            } else {
                pendingPdf = pdf
            }
        }
    }

    private fun readPdfFromIntent(intent: Intent?): Map<String, Any>? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) {
            return null
        }

        val uri: Uri = intent.data ?: return null

        return try {
            val bytes = contentResolver
                .openInputStream(uri)
                ?.use { input ->
                    input.readBytes()
                } ?: return null

            val name = getFileName(uri)
                ?: "document_${System.currentTimeMillis()}.pdf"

            mapOf(
                "bytes" to bytes,
                "name" to name
            )
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getFileName(uri: Uri): String? {
        return try {
            var fileName: String? = null

            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(
                        OpenableColumns.DISPLAY_NAME
                    )

                    if (index >= 0) {
                        fileName = cursor.getString(index)
                    }
                }
            }

            fileName?.takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }
    }
}
