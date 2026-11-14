/// Un perfil de sonido: 5 bandas en dB (graves → agudos).
class SoundPreset {
  const SoundPreset(this.id, this.name, this.db, this.hint);
  final String id;
  final String name;

  /// Ganancia en dB a 60 Hz, 230 Hz, 910 Hz, 3,6 kHz y 14 kHz.
  final List<double> db;
  final String hint;

  static const freqs = [60, 230, 910, 3600, 14000];
}

const soundPresets = <SoundPreset>[
  SoundPreset('flat', 'Plano', [0, 0, 0, 0, 0], 'Como lo grabó el artista.'),
  SoundPreset('bass', 'Graves+', [6, 4, 0, 0, 1], 'Reguetón, trap, electrónica, para entrenar o la fiesta.'),
  SoundPreset('vocal', 'Voces', [-2, 0, 3, 4, 1], 'Baladas, pódcast y para concentrarte.'),
  SoundPreset('bright', 'Brillante', [0, -1, 0, 3, 5], 'Audífonos opacos o música acústica.'),
  SoundPreset('night', 'Noche suave', [-3, -1, 1, 0, -3], 'Volumen bajo, para relajarte o dormir.'),
];

SoundPreset presetById(String? id) => soundPresets.firstWhere((p) => p.id == id, orElse: () => soundPresets.first);

/// Perfil recomendado para un tipo de música (ambiente) — una sugerencia, no un dato del audio.
String recommendedPresetFor(String? mood) {
  final m = (mood ?? '').toLowerCase();
  if (RegExp(r'entrenar|gimnasio|fiesta|bailar|energ|perrear|correr').hasMatch(m)) return 'bass';
  if (RegExp(r'concentr|estudi|trabaj|leer').hasMatch(m)) return 'vocal';
  if (RegExp(r'dormir|tranquil|relaj|calma|noche|triste').hasMatch(m)) return 'night';
  return 'flat';
}

/// Lleva un perfil de 5 bandas a las bandas reales del teléfono (por la
/// frecuencia más cercana) en milibelios, dentro de su rango.
List<int> mapToDevice(List<double> db, List<int> deviceHz, int minMb, int maxMb) {
  int nearest(int hz) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < SoundPreset.freqs.length; i++) {
      final d = (hz.toDouble() / SoundPreset.freqs[i]).abs();
      final ratio = d >= 1 ? d : 1 / d; // distancia en octavas (multiplicativa)
      if (ratio < bestD) {
        bestD = ratio;
        best = i;
      }
    }
    return best;
  }

  return [
    for (final hz in deviceHz) (db[nearest(hz)] * 100).round().clamp(minMb, maxMb),
  ];
}
