import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/ui/futuristic.dart';
import 'package:smartbuds_ai/core/ui/live_visuals.dart';

void main() {
  testWidgets('sin audio real, el visualizador usa la animación normal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: LiveVisualizer(playing: true)))));
    expect(find.byType(NeonEqualizer), findsOneWidget);
  });

  testWidgets('con bandas, dibuja 16 barras', (tester) async {
    AudioBands.instance.bands.value = List.filled(16, .5);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: LiveVisualizer(playing: true, height: 40)))));
    expect(find.byType(AnimatedContainer), findsNWidgets(16));
    AudioBands.instance.bands.value = null;
  });

  testWidgets('carátula viva se apaga si el teléfono pide menos movimiento', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: LiveArt(playing: true, child: SizedBox(width: 10, height: 10, key: Key('art'))),
      ),
    ));
    expect(find.ancestor(of: find.byKey(const Key('art')), matching: find.byType(AnimatedBuilder)), findsNothing);
  });
}
