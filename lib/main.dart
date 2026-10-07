import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TurboNotesApp(preferences: PreferencesService()));
}

class TurboNotesApp extends StatelessWidget {
  const TurboNotesApp({super.key, required this.preferences});

  final PreferencesService preferences;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurboNotes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(preferences: preferences),
    );
  }
}
