import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uai_capoeira/app/bootstrap/uai_native_bootstrap.dart';

void main() {
  testWidgets('native bootstrap fallback shows initialization failure', (tester) async {
    const message = 'Falha de inicializacao controlada';
    await tester.pumpWidget(ErrorApp(
      error: StateError(message),
      stack: StackTrace.fromString('bootstrap-test-stack'),
    ));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Erro ao inicializar o app'), findsOneWidget);
    expect(find.textContaining(message), findsOneWidget);
    expect(find.textContaining('bootstrap-test-stack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
