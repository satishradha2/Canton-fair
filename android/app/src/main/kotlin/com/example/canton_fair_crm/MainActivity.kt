package com.example.canton_fair_crm

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val backupChannel = "canton_fair_crm/backup"
    private val backupPickerRequestCode = 7231
    private val documentPickerRequestCode = 7232
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPrefix = "backup"
    private var cameraToken: Int? = null
    private var cameraStartedAt = 0L
    private var cameraScreenOff = true
    private var screenReceiverRegistered = false
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) cameraScreenOff = true
        }
    }

    override fun onDestroy() {
        if (screenReceiverRegistered) unregisterReceiver(screenReceiver)
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != backupPickerRequestCode && requestCode != documentPickerRequestCode) return
        val result = pendingResult ?: return
        pendingResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val extension = when (contentResolver.getType(uri)) {
                "application/pdf" -> ".pdf"
                "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> ".xlsx"
                else -> ""
            }
            val target = File(cacheDir, "${pendingPrefix}_${System.currentTimeMillis()}$extension")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: throw IllegalStateException("Unable to read the selected backup")
            result.success(target.absolutePath)
        } catch (error: Exception) {
            result.error("backup_read_failed", error.message, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!screenReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(screenReceiver, filter)
            }
            screenReceiverRegistered = true
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "canton_fair_crm/camera_lock")
            .setMethodCallHandler { call, result ->
                val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                when (call.method) {
                    "begin" -> {
                        cameraToken = call.arguments as? Int
                        cameraStartedAt = SystemClock.elapsedRealtime()
                        cameraScreenOff = !power.isInteractive || keyguard.isKeyguardLocked
                        result.success(null)
                    }
                    "finish" -> {
                        val allowed = cameraToken != null && cameraToken == (call.arguments as? Int) &&
                            !cameraScreenOff && power.isInteractive && !keyguard.isKeyguardLocked &&
                            SystemClock.elapsedRealtime() - cameraStartedAt < 60_000L
                        cameraToken = null
                        result.success(allowed)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickBackup" && call.method != "pickDocument") {
                    result.notImplemented()
                } else if (pendingResult != null) {
                    result.error("picker_busy", "A file picker is already open.", null)
                } else {
                    pendingResult = result
                    pendingPrefix = if (call.method == "pickBackup") "restore_backup" else "attachment"
                    startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (call.method == "pickBackup") "application/json" else "*/*"
                        },
                        if (call.method == "pickBackup") backupPickerRequestCode else documentPickerRequestCode,
                    )
                }
            }
    }
}
