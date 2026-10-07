package org.buetow.turbonotes

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.FileNotFoundException
import java.io.IOException

class NoteExistsException(message: String) : IOException(message)

/**
 * Markdown notes inside a document tree the user picked, addressed by
 * relative POSIX paths ("projects/todo.md") just like the Dart
 * DirectoryNoteStore. Paths arrive already normalized by the Dart side, but
 * every segment is checked again: a provider must never be asked for "..".
 */
internal class SafNotes(private val resolver: ContentResolver) {
    private data class Doc(val id: String, val name: String, val isDir: Boolean)

    private fun tree(raw: String, write: Boolean): Uri {
        val tree = Uri.parse(raw)
        require(tree.scheme == ContentResolver.SCHEME_CONTENT && DocumentsContract.isTreeUri(tree)) {
            "A document tree URI is required."
        }
        val granted = resolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission && (!write || it.isWritePermission)
        }
        if (!granted) throw SecurityException("Access to the selected folder has expired. Select it again.")
        return tree
    }

    private fun segments(path: String): List<String> {
        val parts = path.split('/')
        require(parts.isNotEmpty() && parts.all { it.isNotEmpty() && it != "." && it != ".." && !it.startsWith(".") }) {
            "Invalid note path."
        }
        return parts
    }

    private fun children(tree: Uri, parentId: String): List<Doc> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE)
        val cursor = resolver.query(uri, columns, null, null, null)
            ?: throw IOException("Cannot list the selected folder.")
        cursor.use {
            val extras = it.extras
            if (extras.getBoolean(DocumentsContract.EXTRA_LOADING, false)) {
                throw IOException("The document provider is still loading this folder. Try again.")
            }
            extras.getString(DocumentsContract.EXTRA_ERROR)?.let { e -> throw IOException(e) }
            val result = mutableListOf<Doc>()
            while (it.moveToNext()) {
                val id = it.getString(0) ?: continue
                val name = it.getString(1) ?: continue
                result.add(Doc(id, name, it.getString(2) == Document.MIME_TYPE_DIR))
            }
            return result
        }
    }

    private fun rootId(tree: Uri): String = DocumentsContract.getTreeDocumentId(tree)

    private fun find(tree: Uri, path: String): Doc? {
        var current = Doc(rootId(tree), "", true)
        for (segment in segments(path)) {
            if (!current.isDir) return null
            current = children(tree, current.id).firstOrNull { it.name == segment } ?: return null
        }
        return current
    }

    private fun requireNote(tree: Uri, path: String): Doc {
        val doc = find(tree, path)
        if (doc == null || doc.isDir) throw FileNotFoundException("$path not found.")
        return doc
    }

    private fun uri(tree: Uri, doc: Doc): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, doc.id)

    fun list(raw: String): List<String> {
        val tree = tree(raw, write = false)
        val out = mutableListOf<String>()
        val pending = ArrayDeque<Pair<String, String>>()
        pending.add(rootId(tree) to "")
        while (pending.isNotEmpty()) {
            val (id, prefix) = pending.removeFirst()
            for (child in children(tree, id)) {
                if (child.name.startsWith(".")) continue
                val rel = if (prefix.isEmpty()) child.name else "$prefix/${child.name}"
                if (child.isDir) {
                    pending.add(child.id to rel)
                } else if (isNote(child.name)) {
                    out.add(rel)
                }
            }
        }
        out.sort()
        return out
    }

    fun read(raw: String, path: String): String {
        val tree = tree(raw, write = false)
        val input = resolver.openInputStream(uri(tree, requireNote(tree, path)))
            ?: throw IOException("Cannot read $path.")
        return input.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    fun write(raw: String, path: String, text: String) {
        val tree = tree(raw, write = true)
        writeDoc(uri(tree, requireNote(tree, path)), text)
    }

    private fun writeDoc(uri: Uri, text: String) {
        // "wt" truncates. Plain "w" does not truncate on every provider, which
        // would leave the tail of a longer old note behind a shorter new one.
        val output = resolver.openOutputStream(uri, "wt")
            ?: throw IOException("Cannot write the note.")
        output.use { it.write(text.toByteArray(Charsets.UTF_8)) }
    }

    fun create(raw: String, path: String, text: String) {
        if (!isNote(path)) throw IllegalArgumentException("Notes must end in .md or .markdown.")
        createDocument(raw, path) { writeDoc(it, text) }
    }

    /** Reads an image next to the notes (pasted or shared into a note). */
    fun readBytes(raw: String, path: String): ByteArray {
        if (!isImage(path)) throw IllegalArgumentException("Not an image: $path")
        val tree = tree(raw, write = false)
        val input = resolver.openInputStream(uri(tree, requireNote(tree, path)))
            ?: throw IOException("Cannot read $path.")
        return input.use { it.readBytes() }
    }

    /** Stores a new image next to the notes; never overwrites. */
    fun createBytes(raw: String, path: String, bytes: ByteArray) {
        if (!isImage(path)) throw IllegalArgumentException("Not an image: $path")
        createDocument(raw, path) { uri ->
            val output = resolver.openOutputStream(uri, "wt") ?: throw IOException("Cannot write $path.")
            output.use { it.write(bytes) }
        }
    }

    /**
     * Creates the document at [path] (and any missing folders) and fills it
     * with [fill]. Throws [NoteExistsException] rather than overwrite.
     */
    private fun createDocument(raw: String, path: String, fill: (Uri) -> Unit) {
        val tree = tree(raw, write = true)
        val parts = segments(path)
        var parent = Doc(rootId(tree), "", true)
        for (segment in parts.dropLast(1)) {
            val existing = children(tree, parent.id).firstOrNull { it.name == segment }
            parent = when {
                existing == null -> {
                    val created = DocumentsContract.createDocument(
                        resolver, uri(tree, parent), Document.MIME_TYPE_DIR, segment,
                    ) ?: throw IOException("Cannot create folder $segment.")
                    Doc(DocumentsContract.getDocumentId(created), segment, true)
                }
                existing.isDir -> existing
                else -> throw IOException("$segment is a file, not a folder.")
            }
        }
        val name = parts.last()
        if (children(tree, parent.id).any { it.name == name }) throw NoteExistsException("$path already exists.")
        // octet-stream so the provider keeps the name verbatim instead of
        // appending an extension it derives from the MIME type.
        val created = DocumentsContract.createDocument(
            resolver, uri(tree, parent), "application/octet-stream", name,
        ) ?: throw IOException("Cannot create $path.")
        try {
            val actual = displayName(created)
            if (actual != name) throw IOException("The folder's provider named the file $actual instead of $name.")
            fill(created)
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(resolver, created)
            } catch (_: Exception) {
                // Leave the empty document; the error below is what matters.
            }
            throw e
        }
    }

    fun delete(raw: String, path: String) {
        val tree = tree(raw, write = true)
        if (!DocumentsContract.deleteDocument(resolver, uri(tree, requireNote(tree, path)))) {
            throw IOException("Cannot delete $path.")
        }
    }

    /**
     * Copy, then delete. Providers differ in whether they support rename and
     * move at all, while create/write/delete work everywhere notes can be
     * edited. The target is written completely before the source goes.
     */
    fun rename(raw: String, from: String, to: String) {
        val text = read(raw, from)
        create(raw, to, text)
        delete(raw, from)
    }

    private fun displayName(uri: Uri): String {
        resolver.query(uri, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0) ?: ""
        }
        throw IOException("The document provider returned no file name.")
    }

    private fun isImage(name: String): Boolean {
        val lower = name.lowercase()
        return listOf(".png", ".jpg", ".jpeg", ".gif", ".webp").any { lower.endsWith(it) }
    }

    private fun isNote(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".md") || lower.endsWith(".markdown")
    }
}
