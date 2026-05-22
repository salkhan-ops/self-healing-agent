// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class BrowserStorage {
  static bool getBool(String key) => html.window.localStorage[key] == 'true';

  static void setBool(String key, bool value) {
    html.window.localStorage[key] = value.toString();
  }

  static int getInt(String key) {
    return int.tryParse(html.window.localStorage[key] ?? '') ?? 0;
  }

  static void setInt(String key, int value) {
    html.window.localStorage[key] = value.toString();
  }
}
