import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Guarda y lee un JSON. Se usa para los ajustes y el perfil musical.
abstract class JsonStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> data);
}

/// Para pruebas y plataformas sin almacenamiento.
class MemoryJsonStore implements JsonStore {
  MemoryJsonStore([this.data]);
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> load() async => data;

  @override
  Future<void> save(Map<String, dynamic> d) async => data = d;
}

/// Archivo en la memoria interna de la app (no requiere permisos).
/// La carpeta la entrega el lado nativo (Context.filesDir).
class FileJsonStore implements JsonStore {
  FileJsonStore(this.fileName, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('smartbuds/media');

  final String fileName;
  final MethodChannel _channel;
  File? _file;

  Future<File?> _resolve() async {
    if (_file != null) return _file;
    try {
      final dir = await _channel.invokeMethod<String>('filesDir');
      if (dir == null) return null;
      return _file = File('$dir${Platform.pathSeparator}$fileName');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    final f = await _resolve();
    if (f == null || !await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null; // archivo dañado: se empieza de cero
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final f = await _resolve();
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path); // escritura atómica
  }
}
