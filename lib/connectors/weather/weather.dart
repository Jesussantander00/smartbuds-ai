import 'dart:convert';
import 'dart:io';

/// Sugerencia de música según el clima de donde estás.
class WeatherMood {
  const WeatherMood(this.description, this.mood, this.query);

  /// «Está lloviendo en Medellín».
  final String description;

  /// Ambiente para la lista automática («tranquila»…).
  final String mood;
  final String query;
}

/// Clima actual con Open-Meteo (gratis, sin clave). La ubicación es
/// aproximada (por la conexión a internet), así que no pide permiso de GPS.
class WeatherService {
  WeatherService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  WeatherMood? _cached;
  DateTime? _cachedAt;

  Future<WeatherMood?> current() async {
    final at = _cachedAt;
    if (at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return _cached;
    }
    try {
      final where = await _get('https://ipwho.is/?fields=latitude,longitude,city');
      final lat = (where['latitude'] as num?)?.toDouble();
      final lon = (where['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      final city = (where['city'] as String?) ?? '';
      final w = await _get('https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code');
      final cur = w['current'] as Map?;
      final code = (cur?['weather_code'] as num?)?.toInt();
      final temp = (cur?['temperature_2m'] as num?)?.toDouble();
      if (code == null || temp == null) return null;
      _cached = moodFor(code, temp, city);
      _cachedAt = DateTime.now();
      return _cached;
    } catch (_) {
      return null;
    }
  }

  /// Público para probarlo sin internet.
  static WeatherMood moodFor(int code, double temp, String city) {
    final en = city.isEmpty ? '' : ' en $city';
    final rainy = (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;
    if (rainy) {
      return WeatherMood('Está lloviendo$en', 'tranquila', 'musica tranquila para dias de lluvia');
    }
    if (temp >= 26 && code <= 3) {
      return WeatherMood('Hace calor$en (${temp.round()} °C)', 'alegre', 'musica alegre de verano');
    }
    if (temp <= 14) {
      return WeatherMood('Hace frío$en (${temp.round()} °C)', 'tranquila', 'musica acustica tranquila');
    }
    if (code <= 1) {
      return WeatherMood('Está soleado$en', 'alegre', 'musica alegre');
    }
    return WeatherMood('Está nublado$en', 'tranquila', 'musica chill');
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final req = await _client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) return const {};
    final json = jsonDecode(text);
    return json is Map<String, dynamic> ? json : const {};
  }
}
