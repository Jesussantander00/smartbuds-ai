import 'package:flutter/foundation.dart';

import '../../core/settings/app_settings.dart';
import '../brain/music_brain.dart';
import '../music_profile/music_profile.dart';

/// Una lista que mantiene el curador. Cada canción es «Título — Artista».
class CuratedList {
  CuratedList({required this.id, required this.name, required this.items, this.updatedAt});
  final String id;
  final String name;
  List<String> items;
  DateTime? updatedAt;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'items': items, 'at': updatedAt?.toIso8601String()};

  static CuratedList? fromJson(Map<dynamic, dynamic> j) {
    final id = j['id'], name = j['name'];
    if (id is! String || name is! String) return null;
    return CuratedList(
      id: id,
      name: name,
      items: [for (final i in (j['items'] as List?) ?? const []) if (i is String) i],
      updatedAt: DateTime.tryParse('${j['at'] ?? ''}'),
    );
  }
}

/// Cambios propuestos a una lista. Nada se aplica sin tu aprobación.
class CuratorProposal {
  CuratorProposal({required this.listId, required this.name, required this.add, required this.remove, required this.why});
  final String listId;
  final String name;
  final List<String> add;
  final List<String> remove;
  final String why;
  bool get isEmpty => add.isEmpty && remove.isEmpty;
}

/// Curador musical: arma listas con tus hábitos y propone actualizarlas.
/// Siempre te pide aprobar antes de cambiar algo.
class Curator extends ChangeNotifier {
  Curator({required this.settings, required this.profile, required this.brain});

  final AppSettings settings;
  final MusicProfile profile;
  final MusicBrain brain;

  static const maxItems = 20, maxRemove = 5;

  List<CuratedList> get lists => [
        for (final j in settings.curatedLists)
          if (CuratedList.fromJson(j) case final l?) l,
      ];

  static String label(TrackStats t) => t.artist == null || t.artist!.isEmpty ? t.title : '${t.title} — ${t.artist}';

  /// Lo que «debería» tener cada lista hoy, según tus datos.
  @visibleForTesting
  Map<String, ({String name, List<String> items, String why})> targets(DateTime now) {
    final out = <String, ({String name, List<String> items, String why})>{};
    final mix = brain.recommend(BrainContext(now: now), n: 15).map((r) => label(r.track)).toList();
    if (mix.isNotEmpty) {
      out['mix'] = (name: 'Tu mezcla', items: mix, why: 'Tus favoritas y las que hace rato no suenan, para esta semana.');
    }
    // El ambiente que más usas.
    final moods = profile.moodTracks.entries.where((e) => e.value.length >= 3).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (moods.isNotEmpty) {
      final m = moods.first;
      final items = [
        for (final k in m.value)
          if (profile.tracks[k] case final t? when t.score(profile.weights) > 0) t,
      ]..sort((a, b) => b.score(profile.weights).compareTo(a.score(profile.weights)));
      if (items.isNotEmpty) {
        out['mood:${m.key}'] = (
          name: 'Para ${m.key}',
          items: items.take(15).map(label).toList(),
          why: 'Lo que más te ha funcionado cuando pides «${m.key}».',
        );
      }
    }
    return out;
  }

  /// Propuestas de cambios para cada lista (sin aplicar nada).
  List<CuratorProposal> propose({DateTime? now, Map<String, List<String>> extra = const {}}) {
    final t = targets(now ?? DateTime.now());
    final current = {for (final l in lists) l.id: l};
    final out = <CuratorProposal>[];
    void diff(String id, String name, List<String> target, String why) {
      final have = current[id]?.items ?? const <String>[];
      final add = target.where((x) => !have.contains(x)).take(maxItems - have.length + maxRemove).toList();
      final remove = have.where((x) => !target.contains(x)).take(maxRemove).toList();
      final p = CuratorProposal(listId: id, name: name, add: add, remove: remove, why: why);
      if (!p.isEmpty) out.add(p);
    }

    t.forEach((id, v) => diff(id, v.name, v.items, v.why));
    extra.forEach((id, items) => diff(id, 'Descubrimientos', items, 'Artistas nuevos parecidos a los tuyos (Deezer).'));
    return out;
  }

  /// Descubrimientos: canciones de artistas que aún no escuchas (radar, por internet).
  Future<List<String>> discoveries() async {
    final r = await brain.radar(max: 8);
    return [for (final a in r) a.topTrack == null ? a.artist : '${a.topTrack} — ${a.artist}'];
  }

  /// Aplica solo lo que aprobaste.
  void approve(CuratorProposal p, {Set<String>? add, Set<String>? remove, DateTime? now}) {
    final all = lists;
    final l = all.where((x) => x.id == p.listId).firstOrNull ?? CuratedList(id: p.listId, name: p.name, items: []);
    final toAdd = add ?? p.add.toSet();
    final toRemove = remove ?? p.remove.toSet();
    l.items = [
      ...l.items.where((x) => !toRemove.contains(x)),
      ...p.add.where(toAdd.contains).where((x) => !l.items.contains(x)),
    ].take(maxItems).toList();
    l.updatedAt = now ?? DateTime.now();
    final next = [for (final x in all) if (x.id != l.id) x, l];
    settings.setCuratedLists([for (final x in next) x.toJson()]);
    notifyListeners();
  }

  void deleteList(String id) {
    settings.setCuratedLists([for (final x in lists) if (x.id != id) x.toJson()]);
    notifyListeners();
  }
}
