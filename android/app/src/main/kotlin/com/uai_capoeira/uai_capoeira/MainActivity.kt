package com.uai_capoeira.uai_capoeira

import android.content.Intent
import android.app.DownloadManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.view.WindowManager
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
    private var inscricoesAbertas = 0
    private var capturaEraProtegida = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        UpdateWifiManager.cleanStale(applicationContext)
        UpdateWifiManager.resumeMonitoring(applicationContext)
        if (intent?.action == UpdateWifiManager.ACTION_INSTALL) {
            UpdateWifiReleaseChecker.installAfterFreshCheck(this) { }
            intent?.action = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == UpdateWifiManager.ACTION_INSTALL) {
            UpdateWifiReleaseChecker.installAfterFreshCheck(this) { }
            intent.action = null
        }
    }

    override fun onResume() {
        super.onResume()
        if (inscricoesAbertas > 0) window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    private val CHANNEL = "com.example.uai_capoeira/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UpdateWifiManager.CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    val uid = call.argument<String>("uid") ?: ""
                    val version = call.argument<String>("version") ?: ""
                    when (call.method) {
                        "openRecoveryDownloads" -> {
                            try {
                                startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
                                result.success(true)
                            } catch (_: Exception) { result.success(false) }
                        }
                        "recoveryState" -> result.success(UpdateRecoveryExporter.state())
                        "exportRecoveryApk" -> UpdateRecoveryExporter.export(this, version) { response ->
                            result.success(response)
                        }
                        "checkNow" -> {
                            val accepted = uid.isNotBlank() && UpdateWifiManager.enabled(applicationContext, uid)
                            if (accepted) UpdateWifiReleaseChecker.scheduleImmediateCheck(applicationContext)
                            result.success(accepted)
                        }
                        "getState" -> {
                            UpdateWifiManager.resumeMonitoring(applicationContext)
                            result.success(UpdateWifiManager.state(applicationContext, uid, version))
                        }
                        "setEnabled" -> result.success(UpdateWifiManager.setEnabled(applicationContext, uid,
                            call.argument<Boolean>("enabled") == true))
                        "cancelInstallReady" -> result.success(UpdateWifiReleaseChecker.cancelInstallReady(
                            call.argument<String>("requestId") ?: ""))
                        "installReady" -> UpdateWifiReleaseChecker.installAfterFreshCheck(this,
                            requestId = call.argument<String>("requestId") ?: "") { status ->
                            result.success(status)
                        }
                        "validateLatest" -> UpdateWifiReleaseChecker.validateLatest(this, uid, version,
                            scheduleDownload = call.argument<Boolean>("scheduleDownload") == true) { status ->
                            result.success(status)
                        }
                        "beginManualDownload" -> UpdateWifiReleaseChecker.beginManualDownload(this, uid, version) { response ->
                            result.success(response)
                        }
                        "endManualDownload" -> UpdateWifiReleaseChecker.endManualDownload(this, uid, version,
                            call.argument<String>("token") ?: "") { released ->
                            result.success(released)
                        }
                        "verifyManualApk" -> UpdateWifiReleaseChecker.verifyManualApk(this, uid, version,
                            call.argument<String>("path") ?: "") { status ->
                            result.success(status)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("UPDATE_WIFI", e.message ?: "Erro interno", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uai/inscricao_captura")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "entrar" -> {
                        if (inscricoesAbertas == 0) capturaEraProtegida =
                            (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                        inscricoesAbertas++
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "sair" -> {
                        if (inscricoesAbertas > 0) {
                            inscricoesAbertas--
                            if (inscricoesAbertas == 0 && capturaEraProtegida)
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

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
