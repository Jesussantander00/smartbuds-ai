import 'dart:async';
import 'dart:io';

/// ¿Hay internet? Busca la dirección de un sitio conocido (sin enviar datos).
/// Null si no se pudo saber (p. ej. tardó demasiado).
Future<bool?> checkOnline({Duration timeout = const Duration(seconds: 3)}) async {
  try {
    final r = await InternetAddress.lookup('smartbuds-ai-web.vercel.app').timeout(timeout);
    return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}
