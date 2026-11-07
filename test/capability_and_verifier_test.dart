import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/playback_verifier.dart';
import 'package:smartbuds_ai/core/models.dart';

import 'fakes.dart';

void main() {
  group('CapabilityManager', () {
    final manager = CapabilityManager();
    final full = Capabilities.fromCommands(MusicCommand.values.toSet());

    test('sin política: se respeta lo declarado', () {
      final caps = manager.applyPolicy(
          full, 'com.example.player', CommandSource.voice);
      expect(caps.level, ControlLevel.direct);
      expect(caps.allows(MusicCommand.next), isTrue);
    });

    test('Spotify por voz: control limitado, solo volumen del sistema', () {
      final caps =
          manager.applyPolicy(full, 'com.spotify.music', CommandSource.voice);
      expect(caps.level, ControlLevel.limited);
      expect(caps.allows(MusicCommand.next), isFalse);
      expect(caps.allows(MusicCommand.pause), isFalse);
      expect(caps.allows(MusicCommand.volumeUp), isTrue);
      expect(caps.reason, contains('Spotify'));
    });

    test('Spotify manual: la política de voz no aplica', () {
      final caps =
          manager.applyPolicy(full, 'com.spotify.music', CommandSource.manual);
      expect(caps.allows(MusicCommand.next), isTrue);
    });

    test('una política nunca añade acciones', () {
      final onlyPlay = Capabilities.fromCommands({MusicCommand.play});
      final caps = manager.applyPolicy(
          onlyPlay, 'com.example.player', CommandSource.manual);
      expect(caps.allows(MusicCommand.next), isFalse);
    });

    test('solo volumen → control limitado', () {
      final caps = Capabilities.fromCommands(
          {MusicCommand.volumeUp, MusicCommand.volumeDown});
      expect(caps.level, ControlLevel.limited);
    });
  });

  group('PlaybackVerifier.isConfirmed', () {
    final playing = status('A', state: PlaybackState.playing);
    final paused = status('A', state: PlaybackState.paused);

    test('pausa', () {
      expect(PlaybackVerifier.isConfirmed(MusicCommand.pause, playing, paused),
          isTrue);
      expect(PlaybackVerifier.isConfirmed(MusicCommand.pause, playing, playing),
          isFalse);
    });

    test('siguiente: cambia la pista', () {
      final other = status('A', state: PlaybackState.playing, title: 'Otra');
      expect(PlaybackVerifier.isConfirmed(MusicCommand.next, playing, other),
          isTrue);
      expect(PlaybackVerifier.isConfirmed(MusicCommand.next, playing, playing),
          isFalse);
    });

    test('anterior a mitad de canción: reinicio cuenta como confirmado', () {
      final mid = status('A', state: PlaybackState.playing, positionMs: 90000);
      final start = status('A', state: PlaybackState.playing, positionMs: 400);
      expect(PlaybackVerifier.isConfirmed(MusicCommand.previous, mid, start),
          isTrue);
    });
  });
}
