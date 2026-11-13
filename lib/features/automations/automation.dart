import 'dart:math';

import '../../core/voice_engine/command_parser.dart';

/// Qué dispara una automatización.
enum TriggerKind {
  /// Una frase tuya: «vamos al gimnasio».
  phrase,

  /// Al conectar unos audífonos o el Bluetooth del carro.
  headphones,

  /// A una hora, los días que elijas (con SmartBuds abierto o escuchando).
  time,
}

/// Una automatización o comando personalizado: un disparador y una lista de
/// pasos. Cada paso es una orden que SmartBuds ya entiende («volumen al 40»,
/// «pon algo para entrenar»), así no hay una inteligencia aparte: lo ejecuta
/// el mismo asistente que responde a tu voz.
class Automation {
  Automation({
    required this.id,
    required this.name,
    required this.kind,
    this.phrase,
    this.device,
    this.minuteOfDay,
    Set<int>? days,
    required this.steps,
    this.enabled = true,
  }) : days = days ?? {1, 2, 3, 4, 5, 6, 7};

  final String id;
  String name;
  TriggerKind kind;

  /// Para [TriggerKind.phrase].
  String? phrase;

  /// Para [TriggerKind.headphones]: nombre del dispositivo Bluetooth.
  String? device;

  /// Para [TriggerKind.time]: minutos desde la medianoche (7:30 → 450).
  int? minuteOfDay;

  /// Días de la semana (1 = lunes … 7 = domingo).
  Set<int> days;

  List<String> steps;
  bool enabled;

  static const maxSteps = 6;
  static const maxAutomations = 20;

  static String newId([Random? r]) {
    final rnd = r ?? Random.secure();
    return List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// Descripción corta del disparador para la lista.
  String get triggerLabel => switch (kind) {
        TriggerKind.phrase => 'Cuando digas «$phrase»',
        TriggerKind.headphones => 'Al conectar $device',
        TriggerKind.time => 'A las ${clock(minuteOfDay ?? 0)} · ${daysLabel(days)}',
      };

  static String clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static String daysLabel(Set<int> d) {
    if (d.length == 7) return 'todos los días';
    if (d.length == 5 && d.containsAll({1, 2, 3, 4, 5})) return 'entre semana';
    if (d.length == 2 && d.containsAll({6, 7})) return 'fines de semana';
    const n = ['', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return (d.toList()..sort()).map((i) => n[i]).join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'phrase': phrase,
        'device': device,
        'minute': minuteOfDay,
        'days': days.toList()..sort(),
        'steps': steps,
        'enabled': enabled,
      };

  static Automation? fromJson(Map<dynamic, dynamic> j) {
    final kind = TriggerKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final id = j['id'];
    if (kind == null || id is! String) return null;
    return Automation(
      id: id,
      name: (j['name'] as String?) ?? 'Automatización',
      kind: kind,
      phrase: j['phrase'] as String?,
      device: j['device'] as String?,
      minuteOfDay: (j['minute'] as num?)?.toInt(),
      days: {for (final d in (j['days'] as List?) ?? const [1, 2, 3, 4, 5, 6, 7]) (d as num).toInt()},
      steps: ((j['steps'] as List?) ?? const []).cast<String>(),
      enabled: j['enabled'] != false,
    );
  }

  /// Revisa que la automatización se pueda ejecutar. Devuelve el problema
  /// (para mostrarlo) o null si está bien.
  String? validate({CommandParser parser = const CommandParser()}) {
    if (name.trim().isEmpty) return 'Ponle un nombre.';
    switch (kind) {
      case TriggerKind.phrase:
        final p = CommandParser.normalize(phrase ?? '').trim();
        if (p.split(' ').where((w) => w.isNotEmpty).length < 2) {
          return 'La frase debe tener al menos dos palabras (así no se dispara por error).';
        }
      case TriggerKind.headphones:
        if ((device ?? '').trim().isEmpty) return 'Elige los audífonos.';
      case TriggerKind.time:
        final m = minuteOfDay;
        if (m == null || m < 0 || m >= 24 * 60) return 'Elige la hora.';
        if (days.isEmpty) return 'Elige al menos un día.';
    }
    if (steps.isEmpty) return 'Agrega al menos un paso.';
    if (steps.length > maxSteps) return 'Máximo $maxSteps pasos.';
    for (final s in steps) {
      if (stepProblem(s, parser: parser) case final problem?) return problem;
    }
    return null;
  }

  /// Un paso es válido si es una orden que SmartBuds entiende (y no otra
  /// automatización ni la palabra de activación).
  static String? stepProblem(String step, {CommandParser parser = const CommandParser()}) {
    final intent = parser.parseIntent(step);
    if (intent == null || intent is WakeIntent || intent is MacroIntent) {
      return 'No entiendo el paso «$step». Escríbelo como se lo dirías a SmartBuds.';
    }
    return null;
  }
}

/// Pasos sugeridos (todos son órdenes que SmartBuds ya entiende).
const suggestedSteps = <String>[
  'pon algo que me guste',
  'pon algo nuevo',
  'pon algo para entrenar',
  'pon algo para concentrarme',
  'pon algo tranquilo',
  'pon algo para dormir',
  'pon algo de fiesta',
  'volumen al 30',
  'volumen al 60',
  'volumen al 80',
  'modo estudio',
  'modo viaje',
  'modo diario',
  'modo privado',
  'sal del modo privado',
  'apaga en 30 minutos',
  'sube la energía poco a poco',
  'modo carro',
];

/// Plantillas listas para agregar con un toque.
List<Automation> automationTemplates({String? headphones}) => [
      Automation(
        id: Automation.newId(),
        name: 'Sesión de estudio',
        kind: TriggerKind.phrase,
        phrase: 'empiezo a estudiar',
        steps: ['modo estudio', 'volumen al 35', 'pon algo para concentrarme'],
      ),
      Automation(
        id: Automation.newId(),
        name: 'Gimnasio',
        kind: TriggerKind.phrase,
        phrase: 'vamos al gimnasio',
        steps: ['volumen al 80', 'pon algo para entrenar'],
      ),
      Automation(
        id: Automation.newId(),
        name: 'Buenas noches',
        kind: TriggerKind.phrase,
        phrase: 'buenas noches',
        steps: ['volumen al 25', 'pon algo para dormir', 'apaga en 30 minutos'],
      ),
      if (headphones != null)
        Automation(
          id: Automation.newId(),
          name: 'Al ponerme los audífonos',
          kind: TriggerKind.headphones,
          device: headphones,
          steps: ['pon algo que me guste'],
        ),
      Automation(
        id: Automation.newId(),
        name: 'Mañanas con energía',
        kind: TriggerKind.time,
        minuteOfDay: 7 * 60,
        days: {1, 2, 3, 4, 5},
        steps: ['pon algo con energía'],
      ),
    ];
