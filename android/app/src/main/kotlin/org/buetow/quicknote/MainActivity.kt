package org.buetow.quicknote

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val storageChannelName = "org.buetow.quicknote/storage"
    private val safChannelName = "org.buetow.quicknote/saf"
    private val safNotesChannelName = "org.buetow.quicknote/saf-notes"
    private val requestLegacyStorage = 4203
    private val requestNoteTree = 4204
    private var pendingStorageResult: MethodChannel.Result? = null
    private var pendingTreeResult: MethodChannel.Result? = null

    // Document providers can be slow (cloud-backed ones especially), so all
    // note I/O runs off the main thread, one request at a time and in order.
    private var safExecutor: ExecutorService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, storageChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "storageApiLevel" -> result.success(Build.VERSION.SDK_INT)
                "requestStorageAccess" -> requestStorageAccess(result)
                "needsAllFilesAccess" -> result.success(needsAllFilesAccess(call.requireString("path")))
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, safChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTree" -> pickTree(result)
                "releaseTree" -> releaseTree(call, result)
                else -> result.notImplemented()
            }
        }
        val notes = SafNotes(contentResolver)
        val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "quicknote-saf") }
        safExecutor = executor
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, safNotesChannelName).setMethodCallHandler { call, result ->
            if (call.method !in setOf("list", "read", "write", "create", "delete", "rename")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            executor.execute {
                try {
                    val tree = call.requireString("treeUri")
                    val value: Any? = when (call.method) {
                        "list" -> notes.list(tree)
                        "read" -> notes.read(tree, call.requireString("path"))
                        "write" -> notes.write(tree, call.requireString("path"), call.requireString("text"))
                        "create" -> notes.create(tree, call.requireString("path"), call.requireString("text"))
                        "delete" -> notes.delete(tree, call.requireString("path"))
                        else -> notes.rename(tree, call.requireString("from"), call.requireString("to"))
                    }
                    main.post { result.success(if (value is Unit) null else value) }
                } catch (e: IllegalArgumentException) {
                    main.post { result.error("bad_args", e.message, null) }
                } catch (e: SecurityException) {
                    main.post { result.error("access_denied", e.message, null) }
                } catch (e: NoteExistsException) {
                    main.post { result.error("exists", e.message, null) }
                } catch (e: FileNotFoundException) {
                    main.post { result.error("not_found", e.message, null) }
                } catch (e: Exception) {
                    main.post { result.error("io", e.message ?: e.toString(), null) }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Let writes already handed to the provider finish.
        safExecutor?.shutdown()
        safExecutor = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingTreeResult != null) {
            result.error("busy", "Another folder dialog is already open.", null)
            return
        }
        pendingTreeResult = result
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }, requestNoteTree)
        } catch (e: ActivityNotFoundException) {
            pendingTreeResult = null
            result.error("no_picker", "No folder picker is available.", null)
        }
    }

    private fun releaseTree(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("uri")
        if (raw == null) {
            result.error("bad_args", "A folder URI is required.", null)
            return
        }
        try {
            val uri = Uri.parse(raw)
            val grant = contentResolver.persistedUriPermissions.firstOrNull { it.uri == uri }
            if (grant != null) {
                val flags = (if (grant.isReadPermission) Intent.FLAG_GRANT_READ_URI_PERMISSION else 0) or
                    (if (grant.isWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
                contentResolver.releasePersistableUriPermission(uri, flags)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("access_denied", e.message ?: e.toString(), null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestNoteTree) return
        val result = pendingTreeResult ?: return
        pendingTreeResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (flags != (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) {
                throw SecurityException("The selected folder needs read and write access.")
            }
            val alreadyGranted = contentResolver.persistedUriPermissions.any {
                it.uri == uri && it.isReadPermission && it.isWritePermission
            }
            contentResolver.takePersistableUriPermission(uri, flags)
            try {
                val treeDocument = DocumentsContract.buildDocumentUriUsingTree(
                    uri, DocumentsContract.getTreeDocumentId(uri))
                result.success(mapOf("uri" to uri.toString(), "name" to displayName(treeDocument)))
            } catch (e: Exception) {
                if (!alreadyGranted) contentResolver.releasePersistableUriPermission(uri, flags)
                throw e
            }
        } catch (e: Exception) {
            result.error("access_denied", e.message ?: e.toString(), null)
        }
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val name = cursor.getString(0)
                        if (!name.isNullOrEmpty()) return name
                    }
                }
        } catch (e: Exception) {
            // Fall through to the URI: the name is only a label.
        }
        return uri.lastPathSegment ?: uri.toString()
    }

    // Android 7-10 uses a runtime permission for direct paths in shared storage.
    private fun hasLegacyStoragePermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    /**
     * On Android 11+ an app without All files access can still create its own
     * files in shared folders such as Documents, so a write probe succeeds,
     * but every note another app or a sync tool put there stays invisible.
     * Only the app's own directories work without the permission.
     */
    private fun needsAllFilesAccess(path: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()) {
            return false
        }
        val target = File(path).canonicalFile
        if (!target.path.startsWith("/storage/")) return false
        val own = (getExternalFilesDirs(null) + externalCacheDirs + obbDirs)
            .filterNotNull()
            .mapNotNull { it.parentFile?.canonicalFile }
        return own.none { target.startsWith(it) }
    }

    private fun requestStorageAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            if (hasLegacyStoragePermission()) {
                result.success(null)
            } else if (pendingStorageResult != null) {
                result.error("busy", "A storage permission request is already open.", null)
            } else {
                pendingStorageResult = result
                requestPermissions(
                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    requestLegacyStorage,
                )
            }
            return
        }
        // Android has no runtime dialog for MANAGE_EXTERNAL_STORAGE.
        try {
            startActivity(Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            ))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_settings", "Storage settings are unavailable.", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == requestLegacyStorage) {
            pendingStorageResult?.success(null)
            pendingStorageResult = null
        }
    }
}

private fun MethodCall.requireString(key: String): String =
    argument<String>(key) ?: throw IllegalArgumentException("$key is required.")
