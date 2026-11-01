import 'package:flutter/painting.dart';

class AppShadows {
  const AppShadows._();

  static const soft = [
    BoxShadow(color: Color(0x1F020A22), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static const elevated = [
    BoxShadow(color: Color(0x33020A22), blurRadius: 36, offset: Offset(0, 18)),
  ];

  static List<BoxShadow> glow(Color color) => [
    BoxShadow(color: color.withAlpha(90), blurRadius: 22, spreadRadius: -2),
  ];
}
