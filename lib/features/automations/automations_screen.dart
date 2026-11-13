import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/futuristic.dart';
import 'automation.dart';
import 'automation_engine.dart';

/// Automatizaciones y comandos personalizados: «cuando diga X», «al conectar
/// mis audífonos» o «a las 7:00», haz estos pasos.
class AutomationsScreen extends StatelessWidget {
  const AutomationsScreen({super.key, required this.engine});
  final AutomationEngine engine;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  static IconData _icon(TriggerKind k) => switch (k) {
        TriggerKind.phrase => Icons.record_voice_over_rounded,
        TriggerKind.headphones => Icons.headphones_rounded,
        TriggerKind.time => Icons.schedule_rounded,
      };

  static List<Color> _colors(TriggerKind k) => switch (k) {
        TriggerKind.phrase => AppColors.assistant,
        TriggerKind.headphones => AppColors.devices,
        TriggerKind.time => AppColors.home,
      };

  Future<void> _edit(BuildContext context, [Automation? a]) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => AutomationEditor(engine: engine, initial: a)),
      );

  Future<void> _templates(BuildContext context) async {
    final list = automationTemplates(headphones: engine.assistant.headphoneName ?? engine.settings.lastHeadphone);
    final chosen = await showModalBottomSheet<Automation>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Plantillas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final t in list)
            Card(
              child: ListTile(
                leading: AppIcon(_icon(t.kind), colors: _colors(t.kind), size: 36),
                title: Text(t.name),
                subtitle: Text('${t.triggerLabel}\n${t.steps.join(' → ')}'),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, t),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    final problem = engine.save(chosen);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem ?? '«${chosen.name}» agregada.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automatizaciones'),
        actions: [
          IconButton(
            tooltip: 'Plantillas',
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: () => _templates(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva'),
      ),
      body: ListenableBuilder(
        listenable: engine,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            NeonCard(
              child: Text(
                'Crea tus propios comandos: «vamos al gimnasio» pone el volumen al 80 y música para entrenar. '
                'También al conectar tus audífonos o a una hora. Funcionan mientras SmartBuds está abierto '
                'o escuchando.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (engine.automations.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Empieza con una plantilla'),
                  subtitle: const Text('Estudio, gimnasio, buenas noches…'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _templates(context),
                ),
              ),
            for (final a in engine.automations)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        secondary: AppIcon(_icon(a.kind), colors: _colors(a.kind), size: 38),
                        title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(a.triggerLabel),
                        value: a.enabled,
                        onChanged: (v) => engine.toggle(a.id, v),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final s in a.steps) Chip(label: Text(s), visualDensity: VisualDensity.compact)],
                        ),
                      ),
                      if (engine.lastError[a.id] case final err?)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                          child: Text(err, style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              engine.lastRun[a.id] == null ? 'Aún no se ha usado' : 'Última vez: ${_ago(engine.lastRun[a.id]!)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Probar ahora',
                            icon: const Icon(Icons.play_arrow_rounded),
                            onPressed: () => engine.runById(a.id),
                          ),
                          IconButton(
                            tooltip: 'Copiar enlace para Atajos',
                            icon: const Icon(Icons.link_rounded),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: 'smartbuds://automatizacion/${a.id}'));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(Platform.isIOS
                                      ? 'Enlace copiado. En Atajos: «Abrir URL» con este enlace.'
                                      : 'Enlace copiado. Úsalo en Tasker, MacroDroid o una etiqueta NFC.'),
                                ));
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, a),
                          ),
                          IconButton(
                            tooltip: 'Borrar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => engine.remove(a.id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Crear o editar una automatización.
class AutomationEditor extends StatefulWidget {
  const AutomationEditor({super.key, required this.engine, this.initial});
  final AutomationEngine engine;
  final Automation? initial;

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  late final Automation a = widget.initial == null
      ? Automation(id: Automation.newId(), name: '', kind: TriggerKind.phrase, steps: [])
      : Automation.fromJson(widget.initial!.toJson())!;
  late final _name = TextEditingController(text: a.name);
  late final _phrase = TextEditingController(text: a.phrase ?? '');
  final _step = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phrase.dispose();
    _step.dispose();
    super.dispose();
  }

  void _addStep(String s) {
    final step = s.trim();
    if (step.isEmpty) return;
    final problem = Automation.stepProblem(step, parser: widget.engine.parser);
    setState(() {
      _error = problem;
      if (problem == null && a.steps.length < Automation.maxSteps) {
        a.steps = [...a.steps, step];
        _step.clear();
      }
    });
  }

  void _save() {
    a.name = _name.text.trim();
    a.phrase = _phrase.text.trim();
    final problem = widget.engine.save(a);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context);
  }

  List<String> get _devices => <String>{
        if (widget.engine.assistant.headphoneName != null) widget.engine.assistant.headphoneName!,
        if (widget.engine.settings.lastHeadphone != null) widget.engine.settings.lastHeadphone!,
        ...widget.engine.settings.headphoneVolumes.keys,
        ...widget.engine.settings.carDevices,
        if (a.device != null) a.device!,
      }.toList()
        ..sort();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const dayNames = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Nueva automatización' : 'Editar'),
        actions: [TextButton(onPressed: _save, child: const Text('Guardar'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Gimnasio'),
          ),
          const SizedBox(height: 8),
          Text('Cuándo', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<TriggerKind>(
            segments: const [
              ButtonSegment(value: TriggerKind.phrase, icon: Icon(Icons.record_voice_over_rounded), label: Text('Frase')),
              ButtonSegment(value: TriggerKind.headphones, icon: Icon(Icons.headphones_rounded), label: Text('Audífonos')),
              ButtonSegment(value: TriggerKind.time, icon: Icon(Icons.schedule_rounded), label: Text('Hora')),
            ],
            selected: {a.kind},
            onSelectionChanged: (s) => setState(() => a.kind = s.first),
          ),
          const SizedBox(height: 12),
          if (a.kind == TriggerKind.phrase)
            TextField(
              controller: _phrase,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Cuando diga…',
                hintText: 'vamos al gimnasio',
                helperText: 'Tus frases tienen prioridad sobre las órdenes de SmartBuds.',
              ),
            ),
          if (a.kind == TriggerKind.headphones)
            _devices.isEmpty
                ? const Text('Conecta tus audífonos una vez para poder elegirlos.')
                : DropdownButtonFormField<String>(
                    initialValue: _devices.contains(a.device) ? a.device : null,
                    decoration: const InputDecoration(labelText: 'Al conectar'),
                    items: [for (final d in _devices) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: (v) => setState(() => a.device = v),
                  ),
          if (a.kind == TriggerKind.time) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(a.minuteOfDay == null ? 'Elegir hora' : Automation.clock(a.minuteOfDay!)),
              onTap: () async {
                final m = a.minuteOfDay ?? 7 * 60;
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
                if (t != null) setState(() => a.minuteOfDay = t.hour * 60 + t.minute);
              },
            ),
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(dayNames[d - 1]),
                    selected: a.days.contains(d),
                    onSelected: (on) => setState(() => a.days = on ? ({...a.days, d}) : ({...a.days}..remove(d))),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Corre con SmartBuds abierto o escuchando en segundo plano.', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Text('Haz esto (en orden)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          if (a.steps.isEmpty) const Text('Aún no hay pasos.'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (from, to) => setState(() {
              final list = [...a.steps];
              final s = list.removeAt(from);
              list.insert(to > from ? to - 1 : to, s);
              a.steps = list;
            }),
            children: [
              for (var i = 0; i < a.steps.length; i++)
                ListTile(
                  key: ValueKey('$i-${a.steps[i]}'),
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(a.steps[i]),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => a.steps = [...a.steps]..removeAt(i)),
                  ),
                ),
            ],
          ),
          if (a.steps.length < Automation.maxSteps) ...[
            TextField(
              controller: _step,
              decoration: InputDecoration(
                labelText: 'Agregar paso',
                hintText: 'volumen al 40',
                suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _addStep(_step.text)),
              ),
              onSubmitted: _addStep,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in suggestedSteps)
                  ActionChip(label: Text(s), onPressed: () => _addStep(s)),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
