import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/settings/app_settings.dart';

/// Cuenta con correo y contraseña (Supabase Auth). La sesión se guarda en el
/// teléfono (AppSettings) y se renueva sola, así que solo se entra una vez.
class SupabaseAuth extends ChangeNotifier {
  SupabaseAuth({
    required this.url,
    required this.anonKey,
    required this.settings,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String url;
  final String anonKey;
  final AppSettings settings;
  final HttpClient _client;

  bool busy = false;
  String? error;

  /// Se llama después de entrar (para traer tu perfil de la nube).
  Future<void> Function()? onSignedIn;

  bool get signedIn => settings.signedIn;
  String? get email => settings.authEmail;
  String? get userId => settings.authUserId;

  /// Crea la cuenta y entra.
  Future<bool> signUp(String email, String password) => _run(() async {
        final json = await _request('/auth/v1/signup', {
          'email': email.trim(),
          'password': password,
        });
        if (json['access_token'] == null) {
          // El proyecto pide confirmar el correo antes de entrar.
          throw _AuthException(
              200, 'Te enviamos un correo: confírmalo y luego toca «Entrar».');
        }
        _saveSession(json);
        await onSignedIn?.call();
      });

  /// Entra con una cuenta que ya existe.
  Future<bool> signIn(String email, String password) => _run(() async {
        final json = await _request('/auth/v1/token?grant_type=password', {
          'email': email.trim(),
          'password': password,
        });
        _saveSession(json);
        await onSignedIn?.call();
      });

  void signOut() {
    settings.setSession();
    notifyListeners();
  }

  /// Token válido para hablar con la base de datos; lo renueva si va a vencer.
  /// Null si no hay sesión o no se pudo renovar.
  Future<String?> validToken() async {
    if (!signedIn) return null;
    final exp = settings.authExpiresAt;
    final fresh = exp != null &&
        exp.isAfter(DateTime.now().add(const Duration(minutes: 2)));
    if (fresh && settings.authAccessToken != null) return settings.authAccessToken;
    try {
      final json = await _request('/auth/v1/token?grant_type=refresh_token', {
        'refresh_token': settings.authRefreshToken,
      });
      _saveSession(json);
      return settings.authAccessToken;
    } on _AuthException catch (e) {
      // Sesión revocada o vencida: hay que entrar otra vez.
      if (e.status == 400 || e.status == 401) signOut();
      return null;
    } catch (_) {
      return null; // sin internet: se intenta más tarde
    }
  }

  void _saveSession(Map<String, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    settings.setSession(
      email: (user['email'] as String?) ?? settings.authEmail,
      userId: (user['id'] as String?) ?? settings.authUserId,
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on _AuthException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'No hay conexión. Revisa el internet e inténtalo otra vez.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _request(String path, Map<String, dynamic> body) async {
    final req = await _client
        .postUrl(Uri.parse('$url$path'))
        .timeout(const Duration(seconds: 10));
    req.headers
      ..set('apikey', anonKey)
      ..set('Content-Type', 'application/json');
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    final json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    final map = json is Map<String, dynamic> ? json : <String, dynamic>{};
    if (res.statusCode >= 300) {
      throw _AuthException(res.statusCode, friendlyError(res.statusCode, map));
    }
    return map;
  }

  /// Mensajes de error de Supabase en palabras sencillas.
  @visibleForTesting
  static String friendlyError(int status, Map<String, dynamic> body) {
    final raw = '${body['msg'] ?? body['error_description'] ?? body['message'] ?? ''}'
        .toLowerCase();
    if (status == 429 || raw.contains('rate limit')) {
      return 'Demasiados intentos. Espera un momento.';
    }
    if (raw.contains('already registered') || raw.contains('already exists')) {
      return 'Ese correo ya tiene cuenta. Toca «Entrar».';
    }
    if (raw.contains('invalid login') || raw.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (raw.contains('not confirmed')) return 'Primero confirma tu correo.';
    if (raw.contains('password')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (raw.contains('email')) return 'Revisa que el correo esté bien escrito.';
    return 'No se pudo completar ($status). Inténtalo otra vez.';
  }
}

class _AuthException implements Exception {
  _AuthException(this.status, this.message);
  final int status;
  final String message;
}
