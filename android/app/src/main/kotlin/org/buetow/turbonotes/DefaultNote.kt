package org.buetow.turbonotes

import android.content.Context
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The default note as configured in the app's Preferences, for capturing
 * into it without starting Flutter: from the home-screen widget and from
 * other apps' share sheets.
 *
 * Reads the same settings the Dart side stores with shared_preferences (in
 * `FlutterSharedPreferences`, keys prefixed `flutter.`): the picked Android
 * folder, else the typed directory, else the app's default folder, and the
 * default note's path in it.
 */
internal class DefaultNote(private val context: Context) {
    private val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** The note's path relative to the notes folder, e.g. "TurboNotes.md". */
    val path: String =
        prefs.getString("flutter.DefaultNote", null)?.takeIf { it.isNotEmpty() } ?: "TurboNotes.md"

    private val treeUri: String? = prefs.getString("flutter.ScopedTreeUri", null)?.takeIf { it.isNotEmpty() }

    private val chosenDirectory: String? = prefs.getString("flutter.Directory", null)?.takeIf { it.isNotEmpty() }

    private val directory: String by lazy {
        chosenDirectory
            // What the Dart side's defaultNotesDirectory() picks.
            ?: context.getExternalFilesDir(null)?.path
            ?: context.getDir("flutter", Context.MODE_PRIVATE).path
    }

    private val saf by lazy { SafNotes(context.contentResolver) }

    init {
        val parts = path.split('/')
        require(parts.all { it.isNotEmpty() && it != "." && it != ".." && !it.startsWith(".") }) {
            "The default note path is invalid."
        }
    }

    /** Adds [text] to the end of the note as a paragraph of its own. */
    fun append(text: String) {
        val tree = treeUri
        if (tree != null) {
            val existing = try {
                saf.read(tree, path)
            } catch (e: FileNotFoundException) {
                saf.create(tree, path, withCapture("", text))
                return
            }
            saf.write(tree, path, withCapture(existing, text))
            return
        }
        val file = file(path)
        val existing = if (file.exists()) file.readText() else ""
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, ".${file.name}.${System.nanoTime()}.tmp")
        try {
            temp.writeText(withCapture(existing, text))
            if (!temp.renameTo(file)) throw IOException("Cannot write $path.")
        } finally {
            temp.delete()
        }
    }

    /**
     * Stores [bytes] next to the note, as the app does for pasted images,
     * and returns the markdown that shows it.
     */
    fun addImage(bytes: ByteArray, extension: String): String {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date())
        val stem = path.substringAfterLast('/').substringBeforeLast('.')
            .replace(Regex("[^\\p{L}\\p{N}_-]+"), "-").ifEmpty { "image" }
        val folder = path.substringBeforeLast('/', "")
        for (n in 0 until 100) {
            val suffix = if (n == 0) "" else "-$n"
            val link = "attachments/$stem-$stamp$suffix$extension"
            val target = if (folder.isEmpty()) link else "$folder/$link"
            try {
                val tree = treeUri
                if (tree != null) {
                    saf.createBytes(tree, target, bytes)
                } else {
                    val file = file(target)
                    file.parentFile?.mkdirs()
                    if (!file.createNewFile()) throw NoteExistsException(target)
                    file.writeBytes(bytes)
                }
                return "![]($link)"
            } catch (e: NoteExistsException) {
                // Several images in the same second: try the next name.
            }
        }
        throw IOException("Cannot name the image.")
    }

    private fun file(relative: String): File {
        val root = File(directory).canonicalFile
        // Like the app: the default folder is created on first use, a folder
        // the user chose never is (it may be an unmounted card).
        if (!root.isDirectory && (chosenDirectory != null || !root.mkdirs())) {
            throw FileNotFoundException("The notes folder $root does not exist.")
        }
        val file = File(root, relative).canonicalFile
        if (!file.path.startsWith(root.path + File.separator)) throw IOException("$relative is outside the notes folder.")
        return file
    }

    companion object {
        /** [existing] with [capture] added as a paragraph of its own. */
        fun withCapture(existing: String, capture: String): String {
            val text = capture.trim('\n', '\r')
            if (existing.isEmpty()) return "$text\n"
            val base = if (existing.endsWith("\n")) existing else "$existing\n"
            val gap = if (base.endsWith("\n\n")) "" else "\n"
            return "$base$gap$text\n"
        }
    }
}
