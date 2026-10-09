import 'package:flutter/material.dart';

import '../editor/markdown_controller.dart';

/// Formatting buttons for the WYSIWYG editor. Each one edits the markdown
/// source through [MarkdownEditingController], so what it inserts is plain,
/// portable markdown.
class FormatToolbar extends StatelessWidget {
  const FormatToolbar({
    super.key,
    required this.controller,
    required this.focus,
  });

  final MarkdownEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    Widget button(String tooltip, Widget icon, VoidCallback action) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: icon,
        onPressed: () {
          action();
          focus.requestFocus();
        },
      );
    }

    Widget heading(int level) => button(
      'Heading $level',
      Text('H$level', style: const TextStyle(fontWeight: FontWeight.bold)),
      () => controller.toggleHeading(level),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          heading(1),
          heading(2),
          heading(3),
          const _Separator(),
          button(
            'Bold (Ctrl+B)',
            const Icon(Icons.format_bold),
            () => controller.toggleWrap('**'),
          ),
          button(
            'Italic (Ctrl+I)',
            const Icon(Icons.format_italic),
            () => controller.toggleWrap('*'),
          ),
          button(
            'Strikethrough',
            const Icon(Icons.format_strikethrough),
            () => controller.toggleWrap('~~'),
          ),
          button(
            'Inline code',
            const Icon(Icons.code),
            () => controller.toggleWrap('`'),
          ),
          button('Link', const Icon(Icons.link), controller.insertLink),
          const _Separator(),
          button(
            'Bulleted list',
            const Icon(Icons.format_list_bulleted),
            () => controller.toggleLinePrefix('- '),
          ),
          button(
            'Numbered list',
            const Icon(Icons.format_list_numbered),
            () => controller.toggleLinePrefix('1. '),
          ),
          button(
            'Task (toggle done)',
            const Icon(Icons.check_box_outlined),
            controller.toggleTask,
          ),
          button(
            'Quote',
            const Icon(Icons.format_quote),
            () => controller.toggleLinePrefix('> '),
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).dividerColor,
  );
}
