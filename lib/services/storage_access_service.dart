import 'package:flutter/services.dart';

class StorageAccessService {
  static const _channel = MethodChannel('org.buetow.quicknote/storage');

  static Future<int?> storageApiLevel() async {
    try {
      return await _channel.invokeMethod<int>('storageApiLevel');
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether [path] is a shared folder that Android 11+ only fully exposes
  /// with All files access, which is not held. Writing there can still work,
  /// so a write probe alone misses this: other apps' notes stay invisible.
  static Future<bool> needsAllFilesAccess(String path) async {
    try {
      return await _channel.invokeMethod<bool>('needsAllFilesAccess', {
            'path': path,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> requestStorageAccess() async {
    try {
      await _channel.invokeMethod<void>('requestStorageAccess');
    } on MissingPluginException {
      // No-op: channel not registered (e.g. running on a non-Android target).
    }
  }
}

String storageAccessWarning(int? androidApiLevel) {
  if (androidApiLevel != null && androidApiLevel < 30) {
    return 'Quicknote needs Storage permission for this folder on Android 7–10. '
        'Tap to request it. If no dialog appears, enable Storage in '
        'Settings → Apps → Quicknote → Permissions. Check the folder path if '
        'access still fails.';
  }
  if (androidApiLevel != null) {
    return 'Quicknote needs All files access for this folder on Android 11+. '
        'Tap to grant it in Settings. Check the folder path if access still fails.';
  }
  return 'Quicknote cannot write to this folder. Check its path and permissions.';
}
