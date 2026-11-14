import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/connectors/knowledge/music_knowledge.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/modules/extensions_screen.dart';
import 'package:smartbuds_ai/features/modules/modules.dart';

void main() {
  const parser = CommandParser();

  test('«cuéntame de…» y «quién es este artista»', () {
    final a = parser.parseIntent('Cuéntame de Feid');
    expect(a, isA<ArtistInfoIntent>());
    expect((a as ArtistInfoIntent).artist, 'feid');
    expect((parser.parseIntent('háblame sobre Karol G') as ArtistInfoIntent).artist, 'karol g');
    expect((parser.parseIntent('¿quién es este artista?') as ArtistInfoIntent).artist, isNull);
    expect(parser.parseIntent('cuéntame de'), isNot(isA<ArtistInfoIntent>()));
  });

  test('solo usa artículos que hablan de música', () {
    expect(MusicKnowledge.looksMusical('Salomón Villada Hoyos, conocido como Feid, es un cantante colombiano.'), isTrue);
    expect(MusicKnowledge.looksMusical('Fue una agrupación de reguetón de Puerto Rico.'), isTrue);
    expect(MusicKnowledge.looksMusical('Es un municipio de Antioquia, Colombia.'), isFalse);
  });

  test('resumen corto para decir en voz alta', () {
    const info = ArtistInfo(name: 'X', summary: 'Primera oración. Segunda oración. Tercera oración.');
    expect(info.shortSummary(1), 'Primera oración.');
    expect(info.shortSummary(2), 'Primera oración. Segunda oración.');
  });

  test('colaboraciones en tu música (ft., feat., comas y &)', () {
    final songs = [
      (title: 'Classy 101', artist: 'Feid, Young Miko'),
      (title: 'Normal (feat. Karol G)', artist: 'Feid'),
      (title: 'Hey Mor', artist: 'Ozuna & Feid'),
      (title: 'Otra (ft. Young Miko)', artist: 'Feid'),
      (title: 'Sola', artist: 'Karol G'),
    ];
    final c = collaborationsIn(songs, 'Feid');
    expect(c.first, 'Young Miko'); // aparece dos veces
    expect(c, containsAll(['Karol G', 'Ozuna']));
    expect(collaborationsIn(songs, 'Nadie'), isEmpty);
  });

  test('módulos: ids únicos y se encienden o apagan', () {
    final ids = smartBudsModules.map((m) => m.id).toSet();
    expect(ids.length, smartBudsModules.length);
    expect(smartBudsModules.where((m) => m.premium), isEmpty, reason: 'hoy todo es gratis');
    final s = AppSettings();
    expect(s.moduleOn('social'), isTrue);
    s.setModule('social', false);
    expect(s.moduleOn('social'), isFalse);
    expect(s.toMap()['disabledModules'], ['social']);
    s.setModule('social', true);
    expect(s.moduleOn('social'), isTrue);
  });

  testWidgets('pantalla de extensiones apaga un módulo', (tester) async {
    final s = AppSettings();
    await tester.pumpWidget(MaterialApp(home: ExtensionsScreen(settings: s)));
    expect(find.text('Conocimiento musical'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(s.moduleOn('knowledge'), isFalse);
    final soon = find.textContaining('próximamente');
    await tester.scrollUntilVisible(soon, 300, scrollable: find.byType(Scrollable).first);
    expect(soon, findsOneWidget);
  });
}
