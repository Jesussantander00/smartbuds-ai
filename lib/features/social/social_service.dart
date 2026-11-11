import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/settings/app_settings.dart';
import '../account/supabase_auth.dart';

/// Una lista compartida.
class SharedPlaylist {
  const SharedPlaylist(this.id, this.name, this.inviteCode, this.isMine);
  final String id;
  final String name;
  final String inviteCode;
  final bool isMine;
}

/// Una canción de una lista compartida.
class PlaylistItem {
  const PlaylistItem(this.id, this.title, this.artist, this.addedBy, this.mine);
  final int id;
  final String title;
  final String? artist;
  final String? addedBy;
  final bool mine;
}

/// Una canción que te enviaron.
class InboxSong {
  const InboxSong(this.id, this.fromName, this.title, this.artist, this.message, this.seen, this.at);
  final int id;

  /// Null = anónima.
  final String? fromName;
  final String title;
  final String? artist;
  final String? message;
  final bool seen;
  final DateTime at;
}

/// Un amigo agregado por código.
class Contact {
  const Contact(this.userId, this.name, this.code, this.topArtists, this.mutual);
  final String userId;
  final String name;
  final String code;

  /// Solo llegan cuando la amistad es mutua.
  final List<String> topArtists;

  /// Los dos se agregaron: ya pueden enviarse canciones.
  final bool mutual;
}

/// Mi perfil social.
class SocialProfile {
  const SocialProfile(this.name, this.friendCode, this.isPublic);
  final String name;
  final String friendCode;
  final bool isPublic;
}

/// Funciones sociales con Supabase (tablas de supabase/social.sql).
/// Todo requiere cuenta; nadie ve el historial de nadie.
class SocialService extends ChangeNotifier {
  SocialService({
    required this.url,
    required this.anonKey,
    required this.auth,
    required this.settings,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String url;
  final String anonKey;
  final SupabaseAuth auth;
  final AppSettings settings;
  final HttpClient _client;

  SocialProfile? profile;
  List<InboxSong> inbox = [];
  List<SharedPlaylist> playlists = [];
  List<Contact> contacts = [];
  bool loading = false;
  String? error;

  int get unseen => inbox.where((s) => !s.seen).length;
  String? get _uid => settings.authUserId;

  /// Código de amigo de 6 letras y números fáciles de dictar (sin 0/O ni 1/I).
  static String newFriendCode([Random? random]) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = random ?? Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    final token = await auth.validToken();
    if (token == null) throw const SocialException('Entra con tu cuenta para usar Amigos.');
    final req = await _client
        .openUrl(method, Uri.parse('$url$path'))
        .timeout(const Duration(seconds: 8));
    req.headers
      ..set('apikey', anonKey)
      ..set('Authorization', 'Bearer $token')
      ..set('Content-Type', 'application/json');
    if (method == 'POST' && path.startsWith('/rest/v1/') && !path.startsWith('/rest/v1/rpc/')) {
      req.headers.set('Prefer', 'return=representation,resolution=merge-duplicates');
    }
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 8));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      String msg = text;
      try {
        final j = jsonDecode(text);
        if (j is Map && j['message'] is String) msg = j['message'] as String;
      } catch (_) {}
      if (res.statusCode == 404 || msg.contains('does not exist') || msg.contains('Could not find')) {
        throw const SocialException('Falta activar Amigos en la base de datos (supabase/social.sql).');
      }
      throw SocialException(msg.length > 140 ? msg.substring(0, 140) : msg);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<T?> _guard<T>(Future<T> Function() f) async {
    try {
      error = null;
      return await f();
    } on SocialException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Sin conexión. Intenta otra vez.';
    } finally {
      notifyListeners();
    }
    return null;
  }

  /// Trae perfil, bandeja y listas.
  Future<void> refresh() async {
    if (!settings.signedIn) return;
    loading = true;
    notifyListeners();
    await _guard(() async {
      final p = await _call('GET', '/rest/v1/social_profiles?select=*&user_id=eq.$_uid');
      final row = p is List && p.isNotEmpty ? p.first as Map : null;
      profile = row == null
          ? null
          : SocialProfile(row['display_name'] as String, row['friend_code'] as String, row['is_public'] == true);
      await _loadInbox();
      await _loadPlaylists();
      await _loadContacts();
    });
    loading = false;
    notifyListeners();
  }

  // ----------------------------------------------------------- Perfil

  /// Crea o actualiza tu perfil; [topArtists] son tus favoritos (no el historial).
  Future<bool> saveProfile(String name, {required bool isPublic, required List<String> topArtists}) async {
    final ok = await _guard(() async {
      final code = profile?.friendCode ?? newFriendCode();
      await _call('POST', '/rest/v1/social_profiles', {
        'user_id': _uid,
        'display_name': name.trim(),
        'friend_code': code,
        'top_artists': topArtists.take(15).toList(),
        'is_public': isPublic,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      profile = SocialProfile(name.trim(), code, isPublic);
      return true;
    });
    return ok ?? false;
  }

  // ---------------------------------------------------------- Amigos

  Future<void> _loadContacts() async {
    final r = await _call('POST', '/rest/v1/rpc/my_contacts', const {});
    contacts = [
      for (final m in (r as List? ?? const []).cast<Map>())
        Contact(
          m['user_id'] as String,
          m['display_name'] as String,
          (m['friend_code'] as String?) ?? '',
          ((m['top_artists'] as List?) ?? const []).cast<String>(),
          m['mutual'] == true,
        ),
    ];
  }

  /// Agrega a alguien por su código. Devuelve su nombre y si ya es mutuo.
  Future<({String name, bool mutual})?> addContact(String code) => _guard(() async {
        final r = await _call('POST', '/rest/v1/rpc/add_contact', {'code': code.trim().toUpperCase()});
        if (r is! List || r.isEmpty) throw const SocialException('No encontré ese código.');
        final m = r.first as Map;
        await _loadContacts();
        return (name: m['display_name'] as String, mutual: m['mutual'] == true);
      });

  Future<void> removeContact(String userId) => _guard(() async {
        await _call('DELETE', '/rest/v1/contacts?user_id=eq.$_uid&contact_id=eq.$userId');
        await _loadContacts();
      });

  // ------------------------------------------------- Canciones enviadas

  Future<void> _loadInbox() async {
    final r = await _call('POST', '/rest/v1/rpc/my_inbox', const {});
    inbox = [
      for (final m in (r as List? ?? const []).cast<Map>())
        InboxSong(
          (m['id'] as num).toInt(),
          m['from_name'] as String?,
          m['title'] as String,
          m['artist'] as String?,
          m['message'] as String?,
          m['seen'] == true,
          DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
        ),
    ];
  }

  Future<void> markInboxSeen() async {
    if (unseen == 0) return;
    await _guard(() async {
      await _call('POST', '/rest/v1/rpc/mark_inbox_seen', const {});
      await _loadInbox();
    });
  }

  /// Envía una canción a un amigo (con tu nombre o anónima).
  Future<bool> sendSong({
    required String toUserId,
    required String title,
    String? artist,
    String? message,
    bool anonymous = false,
  }) async {
    final ok = await _guard(() async {
      await _call('POST', '/rest/v1/rpc/send_song', {
        'to_id': toUserId,
        'song_title': title,
        'song_artist': artist,
        'note': (message ?? '').trim().isEmpty ? null : message!.trim(),
        'is_anonymous': anonymous,
      });
      return true;
    });
    return ok ?? false;
  }

  // ------------------------------------------------- Listas compartidas

  Future<void> _loadPlaylists() async {
    final r = await _call('GET', '/rest/v1/shared_playlists?select=*&order=created_at.desc');
    playlists = [
      for (final m in (r as List? ?? const []).cast<Map>())
        SharedPlaylist(m['id'] as String, m['name'] as String, m['invite_code'] as String, m['owner'] == _uid),
    ];
  }

  Future<SharedPlaylist?> createPlaylist(String name) => _guard(() async {
        final m = await _call('POST', '/rest/v1/rpc/create_playlist', {'list_name': name.trim()}) as Map;
        await _loadPlaylists();
        return SharedPlaylist(m['id'] as String, m['name'] as String, m['invite_code'] as String, true);
      });

  Future<SharedPlaylist?> joinPlaylist(String code) => _guard(() async {
        final m = await _call('POST', '/rest/v1/rpc/join_playlist', {'code': code.trim().toUpperCase()}) as Map;
        await _loadPlaylists();
        return SharedPlaylist(m['id'] as String, m['name'] as String, m['invite_code'] as String, m['owner'] == _uid);
      });

  Future<void> leavePlaylist(SharedPlaylist p) => _guard(() async {
        if (p.isMine) {
          await _call('DELETE', '/rest/v1/shared_playlists?id=eq.${p.id}');
        } else {
          await _call('DELETE', '/rest/v1/playlist_members?playlist_id=eq.${p.id}&user_id=eq.$_uid');
        }
        await _loadPlaylists();
      });

  Future<List<PlaylistItem>> items(String playlistId) async =>
      await _guard(() async {
        final r = await _call(
            'GET', '/rest/v1/playlist_items?select=*&playlist_id=eq.$playlistId&order=created_at.desc&limit=200');
        return [
          for (final m in (r as List? ?? const []).cast<Map>())
            PlaylistItem((m['id'] as num).toInt(), m['title'] as String, m['artist'] as String?,
                m['added_by_name'] as String?, m['added_by'] == _uid),
        ];
      }) ??
      const [];

  Future<bool> addItem(String playlistId, String title, String? artist) async =>
      await _guard(() async {
        await _call('POST', '/rest/v1/rpc/add_playlist_item', {
          'pid': playlistId,
          'song_title': title,
          'song_artist': artist,
        });
        return true;
      }) ??
      false;

  /// Cambia el código de invitación (si se compartió con quien no debía).
  Future<String?> rotateInvite(SharedPlaylist p) => _guard(() async {
        final r = await _call('POST', '/rest/v1/rpc/rotate_invite', {'pid': p.id});
        await _loadPlaylists();
        return r as String?;
      });

  Future<void> removeItem(int id) => _guard(() => _call('DELETE', '/rest/v1/playlist_items?id=eq.$id'));

  // ----------------------------------------------------- Resumen del grupo

  /// Artistas y canciones más agregados en todas tus listas compartidas.
  Future<({List<(String, int)> artists, List<(String, int)> songs})> groupSummary() async {
    final artists = <String, int>{}, songs = <String, int>{};
    for (final p in playlists) {
      for (final i in await items(p.id)) {
        if ((i.artist ?? '').isNotEmpty) artists[i.artist!] = (artists[i.artist!] ?? 0) + 1;
        final s = [i.title, if ((i.artist ?? '').isNotEmpty) i.artist].join(' — ');
        songs[s] = (songs[s] ?? 0) + 1;
      }
    }
    for (final s in inbox) {
      if ((s.artist ?? '').isNotEmpty) artists[s.artist!] = (artists[s.artist!] ?? 0) + 1;
    }
    List<(String, int)> top(Map<String, int> m) =>
        (m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2))).take(5).toList();
    return (artists: top(artists), songs: top(songs));
  }
}

class SocialException implements Exception {
  const SocialException(this.message);
  final String message;
  @override
  String toString() => message;
}
