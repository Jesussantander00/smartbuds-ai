import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/settings/app_settings.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import 'automation.dart';
import 'automation_runner.dart';

/// Motor de automatizaciones: guarda tus reglas, las dispara (frase,
/// audífonos u hora) y ejecuta sus pasos con el mismo asistente de la voz.
///
/// Límite honesto: funciona mientras SmartBuds está abierto o escuchando en
/// segundo plano. Con la app cerrada del todo, el sistema no la despierta a
/// una hora fija sin permisos especiales.
class AutomationEngine extends ChangeNotifier implements AutomationRunner {
  AutomationEngine({
    required this.assistant,
    required this.settings,
    this.parser = const CommandParser(),
    DateTime Function()? clock,
    this.stepDelay = const Duration(milliseconds: 1500),
    bool startTimer = true,
  }) : _clock = clock ?? DateTime.now {
    _load();
    _lastHeadphone = assistant.headphoneName;
    assistant.addListener(_onAssistant);
    if (startTimer) _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
  }

  final Assistant assistant;
  final AppSettings settings;
  final CommandParser parser;
  final DateTime Function() _clock;
  final Duration stepDelay;
  Timer? _timer;
  String? _lastHeadphone;
  bool _running = false;

  List<Automation> automations = [];

  /// Última vez que corrió cada una (id → hora), para mostrarlo y no repetir.
  final Map<String, DateTime> lastRun = {};

  /// Pasos que fallaron en la última ejecución (id → mensaje).
  final Map<String, String> lastError = {};

  void _load() {
    automations = [
      for (final j in settings.automations)
        if (Automation.fromJson(j) case final a?) a,
    ];
  }

  void _save() {
    settings.setAutomations([for (final a in automations) a.toJson()]);
    notifyListeners();
  }

  /// Guarda una nueva o editada. Devuelve el problema si no es válida.
  String? save(Automation a) {
    final problem = a.validate(parser: parser);
    if (problem != null) return problem;
    if (a.kind == TriggerKind.phrase) {
      final p = CommandParser.normalize(a.phrase!);
      final dup = automations.any((o) =>
          o.id != a.id && o.kind == TriggerKind.phrase && CommandParser.normalize(o.phrase ?? '') == p);
      if (dup) return 'Ya tienes otra automatización con esa frase.';
    }
    final i = automations.indexWhere((o) => o.id == a.id);
    if (i >= 0) {
      automations[i] = a;
    } else {
      if (automations.length >= Automation.maxAutomations) {
        return 'Máximo ${Automation.maxAutomations} automatizaciones.';
      }
      automations.add(a);
    }
    _save();
    return null;
  }

  void remove(String id) {
    automations.removeWhere((a) => a.id == id);
    _save();
  }

  void toggle(String id, bool on) {
    for (final a in automations) {
      if (a.id == id) a.enabled = on;
    }
    _save();
  }

  /// ¿La frase dicha es uno de tus comandos? (se revisa antes que los de SmartBuds).
  VoiceIntent? match(String heard) {
    final text = CommandParser.normalize(heard).trim();
    if (text.isEmpty) return null;
    for (final a in automations) {
      if (a.enabled && a.kind == TriggerKind.phrase && CommandParser.normalize(a.phrase ?? '').trim() == text) {
        return MacroIntent(a.id, a.name);
      }
    }
    return null;
  }

  /// Ejecuta sus pasos, uno tras otro. No se anidan ni se cruzan.
  @override
  Future<bool> runById(String id) async {
    final a = automations.where((x) => x.id == id).firstOrNull;
    if (a == null || _running) return false;
    _running = true;
    lastError.remove(id);
    try {
      var first = true;
      for (final step in a.steps) {
        final intent = parser.parseIntent(step);
        if (intent == null || intent is MacroIntent || intent is WakeIntent) {
          lastError[id] = 'No entendí «$step».';
          continue;
        }
        if (!first) await Future<void>.delayed(stepDelay);
        first = false;
        await assistant.handleIntent(intent);
      }
      lastRun[id] = _clock();
      return true;
    } catch (e) {
      lastError[id] = 'Algo falló: $e';
      return false;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Al conectar unos audífonos: corre las automatizaciones de ese dispositivo.
  void _onAssistant() {
    final name = assistant.headphoneName;
    if (name == _lastHeadphone) return;
    _lastHeadphone = name;
    if (name == null) return;
    for (final a in automations) {
      if (a.enabled && a.kind == TriggerKind.headphones && a.device == name) {
        unawaited(runById(a.id));
      }
    }
  }

  /// Revisa las de hora (cada 30 s). Cada una corre una vez por día.
  @visibleForTesting
  Future<void> tick() async {
    final now = _clock();
    final minute = now.hour * 60 + now.minute;
    for (final a in automations) {
      if (!a.enabled || a.kind != TriggerKind.time || a.minuteOfDay != minute) continue;
      if (!a.days.contains(now.weekday)) continue;
      final last = lastRun[a.id];
      if (last != null && last.year == now.year && last.month == now.month && last.day == now.day) continue;
      await runById(a.id);
    }
  }

  /// Enlaces para atajos (Atajos de iPhone, Tasker, MacroDroid, una etiqueta NFC…):
  /// smartbuds://automatizacion/<id> corre una automatización;
  /// smartbuds://accion/<siguiente|favorita|nuevo|megusta|escuchar> devuelve la acción.
  /// Solo hacen cosas que ya podrías hacer tocando la app.
  static String? actionForLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'smartbuds') return null;
    final segs = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty).toList();
    if (segs.length != 2) return null;
    final value = segs[1].toLowerCase();
    switch (segs[0].toLowerCase()) {
      case 'automatizacion':
        return RegExp(r'^[0-9a-f]{8}$').hasMatch(value) ? 'run:$value' : null;
      case 'accion':
        return const {
          'siguiente': 'next',
          'favorita': 'favorite',
          'favoritas': 'favorite',
          'nuevo': 'discover',
          'megusta': 'like',
          'escuchar': 'listen',
        }[value];
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    assistant.removeListener(_onAssistant);
    super.dispose();
  }
}
