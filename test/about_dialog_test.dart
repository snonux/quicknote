import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quicknote/screens/home_screen.dart';
import 'package:quicknote/services/app_version.dart';
import 'package:quicknote/services/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_note_store.dart';

void main() {
  test('parsePubspecVersion drops the build counter', () {
    expect(parsePubspecVersion('name: x\nversion: 1.2.3+45\n'), '1.2.3');
    expect(
      () => parsePubspecVersion('name: x\n'),
      throwsA(isA<FormatException>()),
    );
  });

  // Drift guard: About must show the version: line of pubspec.yaml, which
  // is bundled as an asset, never a literal in the source.
  testWidgets('About shows the version from pubspec.yaml', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final expected = parsePubspecVersion(
      File('pubspec.yaml').readAsStringSync(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          preferences: PreferencesService(),
          storeFactory: () async => MemoryNoteStore({}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<AboutDialog>(find.byType(AboutDialog));
    expect(dialog.applicationVersion, expected);
  });
}
