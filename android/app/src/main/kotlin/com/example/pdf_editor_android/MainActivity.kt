package com.example.pdf_editor_android

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "pdf_editor/open_file"

    private var methodChannel: MethodChannel? = null

    // Если PDF пришёл ещё до того, как Flutter успел создать канал
    private var pendingPdfBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPdf" -> {
                    val bytes = pendingPdfBytes

                    if (bytes != null) {
                        pendingPdfBytes = null
                        result.success(bytes)
                    } else {
                        val initialBytes = readPdfFromIntent(intent)
                        result.success(initialBytes)
                    }
                }

                else -> result.notImplemented()
            }
        }

        // Если файл уже был передан Android до создания Flutter Engine
        val bytes = pendingPdfBytes

        if (bytes != null) {
            pendingPdfBytes = null

            methodChannel?.invokeMethod(
                "openPdf",
                bytes
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        val bytes = readPdfFromIntent(intent)

        if (bytes != null) {
            if (methodChannel != null) {
                methodChannel?.invokeMethod(
                    "openPdf",
                    bytes
                )
            } else {
                pendingPdfBytes = bytes
            }
        }
    }

    private fun readPdfFromIntent(intent: Intent?): ByteArray? {
        if (intent == null) return null

        if (intent.action != Intent.ACTION_VIEW) {
            return null
        }

        val uri: Uri = intent.data ?: return null

        return try {
            contentResolver
                .openInputStream(uri)
                ?.use { input ->
                    input.readBytes()
                }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}