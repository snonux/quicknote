import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(QuicknoteApp(preferences: PreferencesService()));
}

class QuicknoteApp extends StatelessWidget {
  const QuicknoteApp({super.key, required this.preferences});

  final PreferencesService preferences;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quicknote',
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
