import 'dart:io';
import 'dart:ui' as ui;
import 'package:bank_app/core/widgets/bank_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the in-app logo is bundled and decodes', () async {
    final data = await rootBundle.load(BankMark.asset);
    final image = await decode(data.buffer.asUint8List());
    expect(image.width, greaterThan(200));
    expect(image.height, greaterThan(200));
  });

  test('the launcher icon is square, large and fully opaque (iOS rejects transparency)', () async {
    final image = await decode(File('assets/brand/app_icon.png').readAsBytesSync());
    expect(image.width, 1024);
    expect(image.height, 1024);
    final px = (await image.toByteData())!.buffer.asUint8List();
    var minAlpha = 255;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] < minAlpha) minAlpha = px[i];
    }
    expect(minAlpha, 255);
  });

  test('the Android foreground keeps a transparent margin so it can sit inside the adaptive mask', () async {
    final image = await decode(File('assets/brand/app_icon_foreground.png').readAsBytesSync());
    final px = (await image.toByteData())!.buffer.asUint8List();
    int alphaAt(int x, int y) => px[(y * image.width + x) * 4 + 3];
    expect(alphaAt(2, 2), 0, reason: 'corner is empty');
    expect(alphaAt(image.width ~/ 2, image.height ~/ 2), 255, reason: 'centre is artwork');
  });

  testWidgets('BankMark shows the logo image and can be tinted', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: Center(child: BankMark(size: 40, color: Colors.white))));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.color, Colors.white);
    expect(image.colorBlendMode, BlendMode.srcIn);
    expect(tester.getSize(find.byType(BankMark)), const Size(40, 40));
  });
}
