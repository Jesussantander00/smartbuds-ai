import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/settings/app_settings.dart';
import '../account/supabase_auth.dart';
import '../music_profile/music_profile.dart';

/// Datos de la copia guardada en la nube.
typedef CloudBackupInfo = ({DateTime at, String? device, int songs, int automations});

/// Copia de seguridad inteligente: tus preferencias, perfiles de uso,
/// automatizaciones, audífonos y gustos en un solo paquete, para recuperar
/// todo al cambiar de teléfono. Sin datos de sesión ni tu huella de voz.
class BackupService extends ChangeNotifier {
  BackupService({
    required this.settings,
    required this.profile,
    this.auth,
    this.url,
    this.anonKey,
    HttpClient? client,
    DateTime Function()? clock,
  })  : _client = client ?? HttpClient(),
        _clock = clock ?? DateTime.now;

  final AppSettings settings;
  final MusicProfile profile;
  final SupabaseAuth? auth;
  final String? url;
  final String? anonKey;
  final HttpClient _client;
  final DateTime Function() _clock;

  CloudBackupInfo? cloud;
  String? error;
  bool busy = false;

  static const maxBytes = 1800000;

  bool get cloudAvailable => auth != null && url != null && anonKey != null && settings.signedIn;

  /// Arma la copia. Si es muy grande, deja fuera las canciones que sonaron una sola vez.
  Map<String, dynamic> build({String? device}) {
    final prof = jsonDecode(profile.exportJson()) as Map<String, dynamic>;
    final data = <String, dynamic>{
      'app': 'smartbuds',
      'kind': 'backup',
      'v': 2,
      'at': _clock().toUtc().toIso8601String(),
      'device': device,
      'prefs': settings.backupPreferences(),
      'profile': prof,
    };
    if (utf8.encode(jsonEncode(data)).length > maxBytes) {
      prof['tracks'] = [
        for (final t in prof['tracks'] as List)
          if (((t as Map)['plays'] as num? ?? 0) > 1) t,
      ];
    }
    return data;
  }

  String exportText({String? device}) => jsonEncode(build(device: device));

  /// Restaura una copia (completa o solo de gustos). Devuelve qué trajo, o null si no es válida.
  Future<({int songs, int automations})?> restore(Object? raw) async {
    try {
      final d = raw is String ? jsonDecode(raw.trim()) : raw;
      if (d is! Map || (d['app'] != null && d['app'] != 'smartbuds')) return null;
      // Copia vieja: solo gustos.
      if (d['tracks'] is List) {
        final n = profile.importJson(jsonEncode(d));
        return n < 0 ? null : (songs: n, automations: 0);
      }
      if (d['kind'] != 'backup') return null;
      final prefs = d['prefs'];
      if (prefs is Map) await settings.restorePreferences(prefs.cast<String, dynamic>());
      var songs = 0;
      if (d['profile'] is Map) songs = profile.importJson(jsonEncode(d['profile']));
      return (songs: songs < 0 ? 0 : songs, automations: settings.automations.length);
    } catch (_) {
      return null;
    }
  }

  /// Lee qué copia hay en la nube (fecha, teléfono y contenido).
  Future<void> refreshCloud() async {
    if (!cloudAvailable) return;
    await _run(() async {
      final rows = await _call('GET', '/rest/v1/user_backups?select=updated_at,device,data') as List?;
      if (rows == null || rows.isEmpty) {
        cloud = null;
        return;
      }
      final r = (rows.first as Map).cast<String, dynamic>();
      final data = (r['data'] as Map?) ?? const {};
      cloud = (
        at: DateTime.tryParse('${r['updated_at']}')?.toLocal() ?? _clock(),
        device: r['device'] as String?,
        songs: (((data['profile'] as Map?)?['tracks'] as List?) ?? const []).length,
        automations: ((((data['prefs'] as Map?)?['automations']) as List?) ?? const []).length,
      );
    });
  }

  /// Guarda la copia en la nube (sobrescribe la anterior).
  Future<bool> saveToCloud({required String device}) async {
    if (!cloudAvailable) return false;
    final ok = await _run(() async {
      await _call('POST', '/rest/v1/user_backups?on_conflict=user_id', {
        'user_id': settings.authUserId,
        'device': device.length > 40 ? device.substring(0, 40) : device,
        'data': build(device: device),
      }, prefer: 'resolution=merge-duplicates,return=minimal');
      settings.markBackup(_clock());
    });
    if (ok) await refreshCloud();
    return ok;
  }

  /// Trae la copia de la nube y la aplica.
  Future<({int songs, int automations})?> restoreFromCloud() async {
    if (!cloudAvailable) return null;
    ({int songs, int automations})? result;
    await _run(() async {
      final rows = await _call('GET', '/rest/v1/user_backups?select=data') as List?;
      if (rows == null || rows.isEmpty) throw const _BackupException('Aún no hay copia en la nube.');
      result = await restore((rows.first as Map)['data']);
      if (result == null) throw const _BackupException('La copia de la nube no es válida.');
    });
    return result;
  }

  /// Copia automática: una vez al día, si hay cuenta y está activada.
  Future<void> autoBackup({required String device}) async {
    if (!settings.autoBackup || !cloudAvailable) return;
    final last = settings.lastBackupAt;
    if (last != null && _clock().difference(last) < const Duration(hours: 24)) return;
    await saveToCloud(device: device);
  }

  /// Teléfono nuevo (sin gustos ni automatizaciones) y hay copia en la nube:
  /// conviene ofrecer restaurarla.
  Future<bool> shouldOfferRestore() async {
    if (!cloudAvailable || profile.tracks.isNotEmpty || settings.automations.isNotEmpty) return false;
    await refreshCloud();
    return cloud != null;
  }

  Future<bool> _run(Future<void> Function() body) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on _BackupException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Sin conexión. Intenta otra vez.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<dynamic> _call(String method, String path, [Object? body, String? prefer]) async {
    final token = await auth!.validToken();
    if (token == null) throw const _BackupException('Entra con tu cuenta.');
    final req = await _client.openUrl(method, Uri.parse('$url$path')).timeout(const Duration(seconds: 12));
    req.headers
      ..set('apikey', anonKey!)
      ..set('Authorization', 'Bearer $token')
      ..set('Content-Type', 'application/json');
    if (prefer != null) req.headers.set('Prefer', prefer);
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      if (res.statusCode == 404 || text.contains('does not exist') || text.contains('Could not find')) {
        throw const _BackupException('Falta activar la copia en la nube (supabase/respaldo.sql).');
      }
      if (text.contains('check constraint')) throw const _BackupException('La copia es demasiado grande.');
      throw _BackupException('No se pudo guardar (${res.statusCode}).');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}

class _BackupException implements Exception {
  const _BackupException(this.message);
  final String message;
}
