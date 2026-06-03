import 'package:flutter/material.dart';

class Responsive {
  static bool isHandset(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      return const EdgeInsets.fromLTRB(14, 14, 14, 20);
    }
    if (width < 1024) {
      return const EdgeInsets.all(18);
    }
    return const EdgeInsets.all(24);
  }
}
