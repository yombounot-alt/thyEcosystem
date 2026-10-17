import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_widgetbook/main.dart';

void main() {
  testWidgets('la galerie démarre et liste les familles de composants', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ThyWidgetbook());
    await tester.pumpAndSettle();
    for (final folder in ['Statuts', 'Messages', 'Saisie']) {
      expect(find.text(folder), findsWidgets, reason: folder);
    }
  });
}
