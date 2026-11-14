import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import 'curator.dart';

/// Curador musical: tus listas y los cambios que propone (tú apruebas).
class CuratorScreen extends StatefulWidget {
  const CuratorScreen({super.key, required this.assistant});
  final Assistant assistant;

  @override
  State<CuratorScreen> createState() => _CuratorScreenState();
}

class _CuratorScreenState extends State<CuratorScreen> {
  late final Curator curator = Curator(
    settings: widget.assistant.settings!,
    profile: widget.assistant.profile,
    brain: widget.assistant.brain,
  );
  List<CuratorProposal> _proposals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    List<String> disc = const [];
    try {
      disc = await curator.discoveries();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _proposals = curator.propose(extra: disc.isEmpty ? const {} : {'discover': disc});
      _loading = false;
    });
  }

  Future<void> _play(CuratedList l) async {
    if (l.items.isEmpty) return;
    final a = widget.assistant;
    await a.handleSearch(SearchRequest(l.items.first.replaceAll(' — ', ' ')));
    final n = a.addToQueue(l.items.skip(1).map((x) => x.replaceAll(' — ', ' ')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('«${l.name}»: suena la primera y $n en la cola.')));
    }
  }

  Future<void> _review(CuratorProposal p) async {
    final add = {...p.add}, remove = {...p.remove};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .75,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                Text(p.why, style: Theme.of(context).textTheme.bodySmall),
                if (p.add.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Agregar (${add.length})', style: Theme.of(context).textTheme.titleSmall),
                  for (final x in p.add)
                    CheckboxListTile(
                      dense: true,
                      value: add.contains(x),
                      title: Text(x),
                      secondary: const Icon(Icons.add_rounded, color: Color(0xFF1FA889)),
                      onChanged: (v) => set(() => v == true ? add.add(x) : add.remove(x)),
                    ),
                ],
                if (p.remove.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Quitar (${remove.length})', style: Theme.of(context).textTheme.titleSmall),
                  for (final x in p.remove)
                    CheckboxListTile(
                      dense: true,
                      value: remove.contains(x),
                      title: Text(x),
                      secondary: Icon(Icons.remove_rounded, color: Theme.of(context).colorScheme.error),
                      onChanged: (v) => set(() => v == true ? remove.add(x) : remove.remove(x)),
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aprobar')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    curator.approve(p, add: add, remove: remove);
    setState(() => _proposals.remove(p));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lists = curator.lists;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curador musical'),
        actions: [IconButton(tooltip: 'Buscar cambios', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          NeonCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppIcon(Icons.library_music_rounded, colors: AppColors.music, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Armo listas con tus hábitos y busco canciones nuevas. Nada cambia sin que lo apruebes. '
                    'Las listas viven en SmartBuds y se reproducen en tu app de música.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_proposals.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('Cambios propuestos', style: theme.textTheme.titleMedium),
            ),
            for (final p in _proposals)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: Text(p.name),
                  subtitle: Text('${p.add.isEmpty ? '' : '+${p.add.length} '}${p.remove.isEmpty ? '' : '−${p.remove.length}'} · ${p.why}'),
                  trailing: FilledButton.tonal(onPressed: () => _review(p), child: const Text('Revisar')),
                ),
              ),
          ] else if (!_loading)
            const Card(child: ListTile(leading: Icon(Icons.check_rounded), title: Text('Tus listas están al día.'))),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text('Tus listas', style: theme.textTheme.titleMedium),
          ),
          if (lists.isEmpty)
            const Card(child: ListTile(title: Text('Aprueba una propuesta para crear tu primera lista.')))
          else
            for (final l in lists)
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(l.name),
                  subtitle: Text('${l.items.length} canciones'),
                  trailing: IconButton.filled(
                    tooltip: 'Reproducir',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => _play(l),
                  ),
                  children: [
                    for (final x in l.items) ListTile(dense: true, title: Text(x)),
                    TextButton.icon(
                      onPressed: () {
                        curator.deleteList(l.id);
                        setState(() {});
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Borrar lista'),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
