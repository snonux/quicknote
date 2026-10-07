# TurboNotes

<img src="logo-small.png" alt="TurboNotes logo" width="120">

TurboNotes is a small Android app for browsing and editing a folder of
Markdown notes. Point it at a folder, for example one Syncthing keeps in sync
with your laptop, and every `.md` file in it is one tap away. It is a sibling
of [Quicklog](https://github.com/snonux/quicklog): Quicklog jots down new
notes; TurboNotes edits the ones you already have.

| Tree, pins and tags | A note with an image |
|---------------------|----------------------|
| ![The file tree with pinned and recent notes and tags](docs/images/phone-sidebar.png) | ![A note in the WYSIWYG editor with an inline image](docs/images/phone-note-image.png) |

## Features

- **File tree** of the notes folder, with **pinned** and **recent** notes on
  top and a **tag tree** (`#tag`) that filters it.
- **Fuzzy finder** for note names and **full-text search** across all notes
  that forgives typos.
- **Raw and WYSIWYG editors** on the same Markdown text. WYSIWYG never
  rewrites a note and shows **pasted images** inline.
- **Share** a note to other apps as text, PDF or image.
- **Quick capture** from the home-screen widget or the Android share sheet,
  without opening the app.
- **Autosave**, and a note changed on disk meanwhile is never overwritten
  silently.
- **No network**: no accounts, no telemetry, not even the `INTERNET`
  permission.

**[Read the usage guide](docs/usage.md)** for a full tour with screenshots.

## Install

Install it from the [snonux F-Droid repository](https://github.com/snonux/fdroid):
add the repository to F-Droid as described there, then install TurboNotes like
any other app. F-Droid keeps it up to date.

APKs by hand, the Linux desktop build and building from source:
[docs/install.md](docs/install.md).

## License

MIT; see [LICENSE](LICENSE).
