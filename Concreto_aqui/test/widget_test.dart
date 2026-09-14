// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:concreto_aqui/main.dart';

void main() {
  testWidgets('exibe o login e trata credenciais invalidas',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ConcretoAquiApp());

    expect(find.text('Concreto Aqui'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), 'invalido');
    await tester.enterText(find.byType(TextField).at(1), 'invalida');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Usuário ou senha inválidos.'), findsOneWidget);
  });
}
