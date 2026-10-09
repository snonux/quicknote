package org.buetow.turbonotes

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/** The image formats notes keep as they are; anything else becomes JPEG. */
private val keptImageTypes = setOf("image/png", "image/jpeg", "image/gif", "image/webp")

/** Most images one gallery pick adds at once. */
internal const val maxPickedImages = 20

/** An image for the Dart side: its bytes and MIME type. */
internal fun imageResult(bytes: ByteArray, mime: String): Map<String, Any> {
    if (mime.lowercase() in keptImageTypes) return mapOf("bytes" to bytes, "mime" to mime.lowercase())
    // HEIC from a phone camera, BMP...: only decodable formats get this far.
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        ?: throw IOException("This image format is not supported.")
    try {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        return mapOf("bytes" to out.toByteArray(), "mime" to "image/jpeg")
    } finally {
        bitmap.recycle()
    }
}

/** Reads a picked image (a gallery or document URI). */
internal fun readImage(resolver: ContentResolver, uri: Uri): Map<String, Any> {
    val bytes = resolver.openInputStream(uri)?.use { readLimited(it) }
        ?: throw IOException("The image could not be read.")
    return imageResult(bytes, resolver.getType(uri) ?: sniffImageType(bytes))
}

/** Reads the photo the camera app wrote, or null when it wrote none. */
internal fun readPhoto(file: File): Map<String, Any>? {
    try {
        if (!file.isFile || file.length() == 0L) return null
        val bytes = file.inputStream().use { readLimited(it) }
        return imageResult(bytes, sniffImageType(bytes))
    } finally {
        file.delete()
    }
}

/** The MIME type from the first bytes, for sources that do not say. */
internal fun sniffImageType(bytes: ByteArray): String {
    fun startsWith(vararg prefix: Int) =
        bytes.size >= prefix.size && prefix.indices.all { bytes[it].toInt() and 0xff == prefix[it] }
    return when {
        startsWith(0x89, 0x50, 0x4e, 0x47) -> "image/png"
        startsWith(0xff, 0xd8, 0xff) -> "image/jpeg"
        startsWith(0x47, 0x49, 0x46) -> "image/gif"
        bytes.size >= 12 && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP" -> "image/webp"
        else -> "application/octet-stream"
    }
}
