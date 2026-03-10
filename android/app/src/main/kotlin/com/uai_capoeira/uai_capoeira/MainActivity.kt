package com.uai_capoeira.uai_capoeira

import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.uai_capoeira/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            scanFile(path)
                            result.success(true)
                        } else {
                            result.error("INVALID_PATH", "Path is null", null)
                        }
                    }
                    "refreshGallery" -> {
                        refreshGallery()
                        result.success(true)
                    }
                    "openGallery" -> {
                        openGallery()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun scanFile(path: String) {
        // Método 1: MediaScannerConnection
        MediaScannerConnection.scanFile(
            this,
            arrayOf(path),
            arrayOf("image/png"),
            null
        )

        // Método 2: Broadcast para forçar atualização
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            try {
                val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                val file = File(path)
                mediaScanIntent.data = Uri.fromFile(file)
                sendBroadcast(mediaScanIntent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun refreshGallery() {
        // Forçar atualização do MediaStore (Android 10+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val resolver = contentResolver
                val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                resolver.query(uri, null, null, null, null)?.close()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun openGallery() {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.type = "image/*"
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(Intent.createChooser(intent, "Abrir galeria"))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}