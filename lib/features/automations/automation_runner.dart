/// Lo que el asistente necesita para ejecutar una automatización por su id
/// (así el asistente no depende del motor completo).
abstract class AutomationRunner {
  Future<bool> runById(String id);
}
