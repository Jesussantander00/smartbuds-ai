import '../../connectors/deezer/similar_artists.dart';

/// Por qué SmartBuds conecta un artista nuevo con tu música.
enum LinkKind { collaborationMine, collaboration, style }

class ArtistLink {
  const ArtistLink(this.kind, this.seed, {this.song});
  final LinkKind kind;

  /// Tu artista con el que se conecta.
  final String seed;
  final String? song;
}

/// Un artista para descubrir, con todas sus conexiones con tu música.
class ArtistDiscovery {
  ArtistDiscovery(this.name);
  final String name;
  final List<ArtistLink> links = [];
  double score = 0;
  int? fans;
  String? topSong;

  /// Tus artistas con los que se conecta (sin repetir).
  Set<String> get seeds => {for (final l in links) l.seed};

  /// Razón principal, en palabras simples.
  String get reason {
    final mine = links.where((l) => l.kind == LinkKind.collaborationMine).firstOrNull;
    if (mine != null) return 'Aparece con ${mine.seed} en canciones que ya escuchas';
    final collab = links.where((l) => l.kind == LinkKind.collaboration).firstOrNull;
    final style = links.where((l) => l.kind == LinkKind.style).map((l) => l.seed).toSet().toList();
    final parts = <String>[
      if (collab != null) 'Colaboró con ${collab.seed}${collab.song == null ? '' : ' en «${collab.song}»'}',
      if (style.isNotEmpty) 'Estilo parecido a ${_list(style.take(2).toList())}',
    ];
    return parts.join(' · ');
  }

  /// Para buscarlo en tu app de música.
  String get query => topSong == null ? name : '$topSong $name';

  static String _list(List<String> l) => l.length == 1 ? l.first : '${l.first} y ${l[1]}';
}

/// Descubrimiento por conexiones: artistas que NO escuchas todavía pero que
/// colaboraron con tus artistas o comparten su estilo (artistas relacionados
/// de Deezer). Los que se conectan con varios de tus artistas suben.
///
/// Límite honesto: productores y compositores no están disponibles en fuentes
/// gratuitas confiables para todas las canciones, así que no se usan.
class ConnectionGraph {
  static const _w = {LinkKind.collaborationMine: 4.0, LinkKind.collaboration: 3.0, LinkKind.style: 2.0};

  /// [seeds]: tus artistas con su peso (0–1). [known]: artistas que ya escuchas
  /// (en minúsculas). [blocked]: los que bloqueaste.
  static List<ArtistDiscovery> build({
    required Map<String, double> seeds,
    required Set<String> known,
    Set<String> blocked = const {},
    Map<String, List<String>> mineCollabs = const {},
    Map<String, List<Collaboration>> collabs = const {},
    Map<String, List<SimilarArtist>> similar = const {},
    int n = 10,
  }) {
    final out = <String, ArtistDiscovery>{};
    bool skip(String name) {
      final k = name.toLowerCase().trim();
      return k.isEmpty || known.contains(k) || blocked.contains(k) || seeds.keys.any((s) => s.toLowerCase() == k);
    }

    void add(String name, ArtistLink link, {int? fans, String? song}) {
      if (skip(name)) return;
      final d = out.putIfAbsent(name.toLowerCase(), () => ArtistDiscovery(name));
      final dup = d.links.any((l) => l.kind == link.kind && l.seed == link.seed);
      if (!dup) {
        d.links.add(link);
        d.score += _w[link.kind]! * (0.5 + (seeds[link.seed] ?? 0.5));
      }
      d.fans ??= fans;
      d.topSong ??= song;
    }

    for (final e in mineCollabs.entries) {
      for (final name in e.value) {
        add(name, ArtistLink(LinkKind.collaborationMine, e.key));
      }
    }
    for (final e in collabs.entries) {
      for (final c in e.value) {
        add(c.name, ArtistLink(LinkKind.collaboration, e.key, song: c.song), fans: c.fans);
      }
    }
    for (final e in similar.entries) {
      for (final a in e.value) {
        add(a.name, ArtistLink(LinkKind.style, e.key), fans: a.fans,
            song: a.topTracks.isEmpty ? null : a.topTracks.first);
      }
    }
    // Conecta varios de tus artistas: un puente entre tus gustos.
    for (final d in out.values) {
      final k = d.seeds.length;
      if (k >= 2) d.score *= 1 + 0.35 * (k - 1);
    }
    final list = out.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.take(n).toList();
  }
}
