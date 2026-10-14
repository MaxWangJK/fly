package com.flyproduct.fly

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import java.io.File

class MainActivity : FlutterActivity() {
    private var storageResult: MethodChannel.Result? = null
    private var returnSharedRoot = false
    private val storageRequest = 6021

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.flyproduct.fly/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sharedRoot" -> requestStorage(result, true)
                    "ensureAccess" -> {
                        val path = call.argument<String>("path") ?: ""
                        val shared = Environment.getExternalStorageDirectory().absolutePath
                        if (path == shared || path.startsWith("$shared/")) requestStorage(result, false)
                        else result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasStorageAccess(): Boolean = if (Build.VERSION.SDK_INT >= 30) {
        Environment.isExternalStorageManager()
    } else {
        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestStorage(result: MethodChannel.Result, sharedRoot: Boolean) {
        if (storageResult != null) {
            result.error("BUSY", "Storage permission request is already open", null)
            return
        }
        storageResult = result
        returnSharedRoot = sharedRoot
        if (hasStorageAccess()) {
            finishStorageRequest()
        } else if (Build.VERSION.SDK_INT >= 30) {
            try {
                startActivityForResult(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")), storageRequest)
            } catch (_: android.content.ActivityNotFoundException) {
                try {
                    startActivityForResult(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), storageRequest)
                } catch (_: android.content.ActivityNotFoundException) {
                    finishStorageRequest()
                }
            }
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE), storageRequest)
        }
    }

    private fun finishStorageRequest() {
        val result = storageResult ?: return
        storageResult = null
        val granted = hasStorageAccess()
        if (returnSharedRoot) {
            result.success(if (granted) File(Environment.getExternalStorageDirectory(), "fly").absolutePath else null)
        } else result.success(granted)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == storageRequest) finishStorageRequest()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == storageRequest) finishStorageRequest()
    }

    override fun onDestroy() {
        storageResult?.error("CANCELLED", "Activity closed during storage permission request", null)
        storageResult = null
        super.onDestroy()
    }
}
