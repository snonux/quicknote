package org.buetow.turbonotes

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import java.util.concurrent.Executors

/**
 * A small dialog over whatever is on screen that adds a quick note to the
 * default note, without starting the full app. Opened by the home-screen
 * widget, and by other apps' share sheets with the shared text or images
 * filled in.
 */
class CaptureActivity : Activity() {
    private val io = Executors.newSingleThreadExecutor()
    private var images: List<Uri> = emptyList()
    private lateinit var input: EditText
    private lateinit var add: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.capture)
        window.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
        )
        val note = try {
            DefaultNote(this)
        } catch (e: IllegalArgumentException) {
            fail(e.message ?: e.toString())
            return
        }
        findViewById<TextView>(R.id.capture_title).text = getString(R.string.capture_title, note.path)
        input = findViewById(R.id.capture_text)
        add = findViewById(R.id.capture_add)
        findViewById<Button>(R.id.capture_cancel).setOnClickListener { finish() }
        findViewById<Button>(R.id.capture_open).setOnClickListener {
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
        }
        add.setOnClickListener { save(note) }
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) = updateAdd()
        })
        // The text survives recreation in the field; the images are read
        // from the intent again.
        readShare(intent, withText = savedInstanceState == null)
        updateAdd()
        input.requestFocus()
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    /** Fills in what another app shared: text, and images to attach. */
    private fun readShare(intent: Intent, withText: Boolean) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                if (withText) {
                    val text = listOfNotNull(
                        intent.getStringExtra(Intent.EXTRA_SUBJECT)?.takeIf { it.isNotBlank() },
                        intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.takeIf { it.isNotBlank() },
                    ).distinct().joinToString("\n")
                    input.setText(text)
                    input.setSelection(input.text.length)
                }
                streamExtra(intent)?.let { images = listOf(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> images = streamListExtra(intent)
        }
        images = images.filter { contentResolver.getType(it)?.startsWith("image/") == true }
        val label = findViewById<TextView>(R.id.capture_images)
        if (images.isNotEmpty()) {
            label.text = resources.getQuantityString(R.plurals.capture_images, images.size, images.size)
            label.visibility = View.VISIBLE
        }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }) ?: emptyList()

    private fun updateAdd() {
        add.isEnabled = input.text.isNotBlank() || images.isNotEmpty()
    }

    private fun save(note: DefaultNote) {
        add.isEnabled = false
        val text = input.text.toString()
        val shared = images
        io.execute {
            try {
                val links = shared.map { uri ->
                    val mime = contentResolver.getType(uri) ?: ""
                    val extension = when (mime.lowercase()) {
                        "image/png" -> ".png"
                        "image/jpeg", "image/jpg" -> ".jpg"
                        "image/gif" -> ".gif"
                        "image/webp" -> ".webp"
                        else -> throw IllegalArgumentException("Unsupported image type $mime.")
                    }
                    val bytes = contentResolver.openInputStream(uri)?.use { readLimited(it) }
                        ?: throw java.io.IOException("Cannot read the shared image.")
                    note.addImage(bytes, extension)
                }
                val capture = (listOf(text.trim()).filter { it.isNotEmpty() } + links).joinToString("\n\n")
                note.append(capture)
                runOnUiThread {
                    Toast.makeText(this, getString(R.string.capture_added, note.path), Toast.LENGTH_SHORT).show()
                    finish()
                }
            } catch (e: Exception) {
                runOnUiThread {
                    Toast.makeText(this, getString(R.string.capture_failed, e.message ?: e.toString()), Toast.LENGTH_LONG).show()
                    updateAdd()
                }
            }
        }
    }

    private fun fail(message: String) {
        Toast.makeText(this, getString(R.string.capture_failed, message), Toast.LENGTH_LONG).show()
        finish()
    }
}
