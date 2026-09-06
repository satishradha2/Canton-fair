package com.example.canton_fair_crm

import android.app.Activity
import android.os.Handler
import android.os.Looper
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Imports only the JPEG accepted in the scanner, never its raw camera image. */
class LiveCardScanner(private val activity: FlutterFragmentActivity) {
    private val preferences get() = activity.getSharedPreferences("card_scanner_recovery", 0)
    private var pending: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        val token = preferences.getString("active", null)
        val reply = pending
        pending = null
        if (token == null) {
            reply?.error("scan_interrupted", "Scan interrupted. Please scan again.", null)
        } else if (result.resultCode != Activity.RESULT_OK) {
            preferences.edit().remove("active").commit()
            reply?.success(null)
        } else {
            val uri = GmsDocumentScanningResult.fromActivityResultIntent(result.data)
                ?.pages?.singleOrNull()?.imageUri
            if (uri == null) {
                preferences.edit().remove("active").commit()
                reply?.error("scan_empty", "No accepted card image was returned.", null)
            } else worker.execute {
                try {
                    val target = output(token)
                    val temporary = File(target.parentFile, "$token.part")
                    try {
                        activity.contentResolver.openInputStream(uri)?.use { input ->
                            temporary.outputStream().use { input.copyTo(it) }
                        } ?: error("Cannot open scan")
                        check(temporary.length() > 0 && temporary.renameTo(target))
                    } finally { temporary.delete() }
                    preferences.edit().remove("active").commit()
                    handler.post { reply?.success(target.path) }
                } catch (_: Exception) {
                    preferences.edit().remove("active").commit()
                    handler.post { reply?.error("scan_save_failed", "Could not retain the accepted scan. Please retry.", null) }
                }
            }
        }
    }

    private fun output(token: String): File {
        require(Regex("card_[0-9]+_(front|back)").matches(token))
        val directory = File(activity.cacheDir, "accepted_card_scans")
        check(directory.isDirectory || directory.mkdirs())
        return File(directory, "$token.jpg")
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "canton_fair_crm/card_scanner")
            .setMethodCallHandler { call, result ->
                try {
                    val token = call.argument<String>("token") ?: error("Missing scan token")
                    val target = output(token)
                    when (call.method) {
                        "recover" -> result.success(if (target.isFile) target.path else null)
                        "discard" -> { target.delete(); result.success(null) }
                        "scan" -> {
                            if (pending != null) {
                                result.error("scan_busy", "A card scanner is already open.", null)
                            } else {
                                pending = result
                                target.delete()
                                preferences.edit().putString("active", token).commit()
                                val options = GmsDocumentScannerOptions.Builder()
                                    .setGalleryImportAllowed(false)
                                    .setPageLimit(1)
                                    .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                                    .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_BASE)
                                    .build()
                                // Bound component download/startup, not the user's review time.
                                val timeout = Runnable {
                                    if (pending === result) {
                                        pending = null
                                        preferences.edit().remove("active").commit()
                                        result.error("scanner_not_ready", "Scanner setup timed out. Connect to the internet and check Google Play services, then retry.", null)
                                    }
                                }
                                handler.postDelayed(timeout, 30_000)
                                GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                                    .addOnSuccessListener { sender ->
                                        handler.removeCallbacks(timeout)
                                        if (pending === result) {
                                            try {
                                                launcher.launch(IntentSenderRequest.Builder(sender).build())
                                            } catch (_: Exception) {
                                                pending = null
                                                preferences.edit().remove("active").commit()
                                                result.error("scanner_unavailable", "Could not open the card scanner. Check Google Play services.", null)
                                            }
                                        }
                                    }.addOnFailureListener {
                                        handler.removeCallbacks(timeout)
                                        if (pending === result) {
                                            pending = null
                                            preferences.edit().remove("active").commit()
                                            result.error("scanner_unavailable", "Live scanning is unavailable. Check Google Play services and internet access for first-time setup.", null)
                                        }
                                    }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    if (pending === result) pending = null
                    result.error("scanner_failed", "Could not start card scanning. Your existing records are unchanged.", null)
                }
            }
    }
}
