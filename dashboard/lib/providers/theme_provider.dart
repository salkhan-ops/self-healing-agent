import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode mode = ThemeMode.light;

  bool get isDark => mode == ThemeMode.dark;

  void toggleTheme() {
    mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
