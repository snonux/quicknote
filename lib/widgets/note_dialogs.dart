import 'package:flutter/material.dart';

import '../services/note_store.dart';

/// Asks for a note path relative to the notes folder. Returns it normalized
/// (see [normalizeNotePath]), or null when cancelled. [exists] rejects paths
/// already taken, except [initial] itself.
Future<String?> askNotePath(
  BuildContext context, {
  required String title,
  required String action,
  required String initial,
  required bool Function(String path) exists,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PathDialog(
      title: title,
      action: action,
      initial: initial,
      exists: exists,
    ),
  );
}

/// Asks before deleting [path] for good; true means delete.
Future<bool> confirmDeleteNote(BuildContext context, String path) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          '$path will be deleted from the notes folder for good. '
          'There is no trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return answer ?? false;
}

/// How a note is handed to another app.
enum ShareFormat { text, pdf, image }

/// Asks how to share [path]; null when cancelled. [desktop] words the
/// choices for a desktop without a share sheet.
Future<ShareFormat?> askShareFormat(
  BuildContext context,
  String path, {
  required bool desktop,
}) {
  Widget option(
    BuildContext ctx,
    ShareFormat format,
    IconData icon,
    String title,
    String subtitle,
  ) => ListTile(
    key: ValueKey('share:${format.name}'),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    onTap: () => Navigator.of(ctx).pop(format),
  );

  return showDialog<ShareFormat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Share $path'),
      children: [
        option(
          ctx,
          ShareFormat.text,
          Icons.notes,
          'As text',
          desktop
              ? 'Copy the markdown to the clipboard'
              : 'The markdown, as plain text',
        ),
        option(
          ctx,
          ShareFormat.pdf,
          Icons.picture_as_pdf_outlined,
          'As PDF',
          desktop
              ? 'Save formatted A4 pages to Downloads'
              : 'Formatted A4 pages, with images',
        ),
        option(
          ctx,
          ShareFormat.image,
          Icons.image_outlined,
          'As image',
          desktop
              ? 'Save the formatted note as a PNG to Downloads'
              : 'The formatted note as one PNG',
        ),
      ],
    ),
  );
}

class _PathDialog extends StatefulWidget {
  const _PathDialog({
    required this.title,
    required this.action,
    required this.initial,
    required this.exists,
  });

  final String title;
  final String action;
  final String initial;
  final bool Function(String path) exists;

  @override
  State<_PathDialog> createState() => _PathDialogState();
}

class _PathDialogState extends State<_PathDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select the file name, not the folder, so typing replaces just that.
    final text = widget.initial;
    final start = text.lastIndexOf('/') + 1;
    var end = text.lastIndexOf('.');
    if (end < start) end = text.length;
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final path = normalizeNotePath(_controller.text);
      if (path != widget.initial && widget.exists(path)) {
        setState(() => _error = '$path already exists.');
        return;
      }
      Navigator.of(context).pop(path);
    } on InvalidNotePathException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('path-field'),
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'folder/name.md',
            helperText:
                'Relative to the notes folder. Folders are created '
                'as needed; .md is added if missing.',
            helperMaxLines: 2,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
