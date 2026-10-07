import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

/// A one-line, human-readable reason for [error], without the exception
/// class names `toString` would add.
String describeError(Object error) => switch (error) {
  FileSystemException(:final message, :final path, :final osError) => [
    message,
    if (osError != null && osError.message.isNotEmpty) osError.message,
    ?path,
  ].join(': '),
  PlatformException(:final message, :final code) => message ?? code,
  _ => '$error',
};

/// Replaces any visible snack bar with [message]; errors are red and stay
/// longer. A context without a [ScaffoldMessenger] shows nothing.
void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: Duration(seconds: error ? 6 : 3),
    ),
  );
}
