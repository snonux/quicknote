package org.buetow.quicknote

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves the files the app hands to other apps when a note is shared as a
 * PDF or image. They are written to `cache/share/` (by the Dart side) and
 * readable only by the app the user picked, through a one-off URI grant.
 */
class ShareProvider : ContentProvider() {
    companion object {
        const val AUTHORITY = "org.buetow.quicknote.share"

        fun uriFor(name: String): Uri =
            Uri.Builder().scheme("content").authority(AUTHORITY).appendPath(name).build()
    }

    override fun onCreate(): Boolean = true

    private fun file(uri: Uri): File {
        val name = uri.lastPathSegment
        if (name.isNullOrEmpty() || name.contains('/') || name == "." || name == ".." ||
            uri.pathSegments.size != 1
        ) {
            throw FileNotFoundException("No such shared file.")
        }
        val file = File(File(context!!.cacheDir, "share"), name)
        if (!file.isFile) throw FileNotFoundException("No such shared file.")
        return file
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Shared notes are read-only.")
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = file(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = columns.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns, 1).apply { addRow(row) }
    }

    override fun getType(uri: Uri): String = when (uri.lastPathSegment?.substringAfterLast('.')?.lowercase()) {
        "pdf" -> "application/pdf"
        "png" -> "image/png"
        "md", "txt" -> "text/plain"
        else -> "application/octet-stream"
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
}
