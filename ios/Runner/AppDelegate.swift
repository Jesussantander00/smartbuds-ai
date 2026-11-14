import AVFoundation
import Flutter
import MediaPlayer
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SmartBudsNative") {
      SmartBudsNative.register(with: registrar)
    }
  }
}

// MARK: - Puente nativo de SmartBuds para iPhone
//
// Usa los MISMOS canales que Android (smartbuds/media, smartbuds/voice…), así
// que la lógica en Dart (comandos, perfil, búsqueda) es la misma en las dos
// plataformas. Todo va en este archivo para no tener que tocar el proyecto
// de Xcode (los archivos nuevos hay que registrarlos a mano en él).
//
// Qué permite iOS (y qué no):
// - Apple Music: sí se controla (reproducir, pausa, siguiente, anterior y
//   poner una canción buscada) con el reproductor del sistema. Sigue sonando
//   con la pantalla apagada porque suena en la app Música.
// - Otras apps (YouTube Music, Spotify…): iOS no deja verlas ni controlarlas.
// - Volumen: iOS no deja que una app lo cambie; se usan los botones.

final class SmartBudsNative: NSObject, FlutterPlugin {
  private static var shared: SmartBudsNative?

  private let media: AppleMusicBridge
  private let voice: VoiceBridge
  private let actions: FlutterMethodChannel

  static func register(with registrar: FlutterPluginRegistrar) {
    shared = SmartBudsNative(messenger: registrar.messenger())
    for url in pendingLinks { shared?.send(url: url) }
    pendingLinks.removeAll()
  }

  /// Enlaces que llegan antes de que Flutter esté listo.
  private static var pendingLinks: [URL] = []
  private var ready = false
  private var queued: [String] = []

  static func handle(url: URL) {
    guard url.scheme == "smartbuds", url.absoluteString.count <= 200 else { return }
    if let s = shared { s.send(url: url) } else { pendingLinks.append(url) }
  }

  private func send(url: URL) {
    let action = "url:" + url.absoluteString
    if ready { actions.invokeMethod("action", arguments: action) } else { queued.append(action) }
  }

  private init(messenger: FlutterBinaryMessenger) {
    media = AppleMusicBridge(messenger: messenger)
    voice = VoiceBridge(messenger: messenger)
    // Accesos rápidos (en Android). En iPhone solo se contesta «listo».
    actions = FlutterMethodChannel(name: "smartbuds/actions", binaryMessenger: messenger)
    super.init()
    actions.setMethodCallHandler { [weak self] call, result in
      guard call.method == "ready", let self = self else { result(FlutterMethodNotImplemented); return }
      self.ready = true
      let pending = self.queued
      self.queued.removeAll()
      for a in pending { self.actions.invokeMethod("action", arguments: a) }
      result(true)
    }
  }
}

// MARK: - Apple Music (reproductor del sistema)

final class AppleMusicBridge: NSObject, FlutterStreamHandler {
  private static let package = "com.apple.Music"
  private static let appName = "Apple Music"

  private let channel: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private let player = MPMusicPlayerController.systemMusicPlayer
  private var lastActiveAt = Date()
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "smartbuds/media", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "smartbuds/media/events", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    events.setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "hasNotificationAccess":
      result(true) // en iPhone no hace falta (no hay «acceso a notificaciones»)
    case "openNotificationAccessSettings", "bringToFront":
      result(nil)
    case "getSessions":
      result([session()])
    case "getSession":
      result((args["playerId"] as? String) == Self.package ? session() : nil)
    case "sendCommand":
      result(send(args["command"] as? String))
    case "playFromSearch":
      playFromSearch(args["query"] as? String ?? "", result)
    case "playUriInSession", "openUri", "adjustSystemVolume":
      result(false)
    case "setTapGestures":
      result(true)
    case "seek":
      result(seek(args))
    case "shareText":
      result(share(args["text"] as? String ?? ""))
    case "hasMusicAccess":
      result(MPMediaLibrary.authorizationStatus() == .authorized)
    case "requestMusicAccess":
      MPMediaLibrary.requestAuthorization { status in
        DispatchQueue.main.async { result(status == .authorized) }
      }
    case "filesDir":
      result(filesDir())
    case "getVolumePercent":
      result(Int(AVAudioSession.sharedInstance().outputVolume * 100))
    case "setVolumePercent", "setCallPause", "setPauseOnUnplug":
      // iOS no deja fijar el volumen ni vigilar llamadas desde una app;
      // Apple Music ya pausa sola al quitar los audífonos o al llamar.
      result(false)
    case "getOutputDevice":
      result(outputDevice() ?? NSNull())
    case "eqInfo":
      result(["available": false]) // iPhone no deja ecualizar el audio de otras apps
    case "eqApply", "eqRelease":
      result(false)
    case "openSystemEqualizer", "fadeVolume":
      // iOS no deja ecualizar ni cambiar el volumen de otras apps.
      result(false)
    case "audioOutputInfo":
      let session = AVAudioSession.sharedInstance()
      let out = session.currentRoute.outputs.first
      let info: [String: Any] = [
        "available": out != nil,
        "name": (out?.portName as Any?) ?? NSNull(),
        "type": (out?.portType.rawValue as Any?) ?? NSNull(),
        "nativeSampleRate": String(Int(session.sampleRate)),
        "framesPerBuffer": String(Int(session.ioBufferDuration * session.sampleRate)),
        "outputLatencyMs": Int(session.outputLatency * 1000),
        "channelCounts": [session.outputNumberOfChannels],
        "sampleRates": [Int(session.sampleRate)],
        "volumePercent": Int(session.outputVolume * 100),
      ]
      result(info)
    case "getBattery":
      UIDevice.current.isBatteryMonitoringEnabled = true
      let level = UIDevice.current.batteryLevel
      let st = UIDevice.current.batteryState
      result([
        "level": level < 0 ? 100 : Int(level * 100),
        "charging": st == .charging || st == .full,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func outputDevice() -> String? {
    let headphones: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones]
    let out = AVAudioSession.sharedInstance().currentRoute.outputs
      .first { headphones.contains($0.portType) }
    return out?.portName
  }

  private var artId: UInt64 = 0
  private var artData: FlutterStandardTypedData?

  /// Carátula de Apple Music reducida a 160 px (JPEG), cacheada por canción.
  private func artwork(_ item: MPMediaItem?) -> Any {
    guard let item = item else { return NSNull() }
    if item.persistentID != artId {
      artId = item.persistentID
      let image = item.artwork?.image(at: CGSize(width: 160, height: 160))
      artData = image?.jpegData(compressionQuality: 0.8).map { FlutterStandardTypedData(bytes: $0) }
    }
    return artData ?? NSNull()
  }

  /// Carpeta privada de la app para guardar ajustes y perfil (no se borra al cerrar).
  private func filesDir() -> String? {
    let fm = FileManager.default
    guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  private func send(_ command: String?) -> Bool {
    switch command {
    case "play": player.play()
    case "pause": player.pause()
    case "togglePlayPause":
      if player.playbackState == .playing { player.pause() } else { player.play() }
    case "next": player.skipToNextItem()
    case "previous": player.skipToPreviousItem()
    default: return false // volumen: iOS no lo permite
    }
    return true
  }

  private func seek(_ args: [String: Any]) -> Bool {
    guard player.nowPlayingItem != nil else { return false }
    let current = player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : 0
    var target: TimeInterval
    if let pos = args["positionMs"] as? NSNumber {
      target = pos.doubleValue / 1000
    } else {
      target = current + ((args["deltaMs"] as? NSNumber)?.doubleValue ?? 0) / 1000
    }
    if let duration = player.nowPlayingItem?.playbackDuration, duration > 2 {
      target = min(target, duration - 1)
    }
    player.currentPlaybackTime = max(0, target)
    return true
  }

  /// Menú «Compartir» de iPhone (WhatsApp, Mensajes…).
  private func share(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let key = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    guard let presenter = key?.rootViewController else { return false }
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = presenter.view
    presenter.present(sheet, animated: true)
    return true
  }

  /// Busca la canción en el catálogo de Apple (sin clave) y la pone en Música.
  /// Necesita permiso de «Apple Music» y una suscripción activa.
  private func playFromSearch(_ query: String, _ result: @escaping FlutterResult) {
    guard !query.isEmpty else { result(false); return }
    MPMediaLibrary.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { result(false) }
        return
      }
      let country = (Locale.current.regionCode ?? "US").lowercased()
      var comps = URLComponents(string: "https://itunes.apple.com/search")!
      comps.queryItems = [
        URLQueryItem(name: "term", value: query),
        URLQueryItem(name: "entity", value: "song"),
        URLQueryItem(name: "limit", value: "1"),
        URLQueryItem(name: "country", value: country),
      ]
      URLSession.shared.dataTask(with: comps.url!) { data, _, _ in
        var storeId: String?
        if let data = data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let first = (json["results"] as? [[String: Any]])?.first,
          let id = first["trackId"] as? Int
        {
          storeId = String(id)
        }
        DispatchQueue.main.async {
          guard let id = storeId else { result(false); return }
          self.player.setQueue(with: [id])
          // Preparar antes de reproducir: si falla (sin suscripción, canción no
          // disponible en el país…), se avisa a Dart en vez de decir que sonó.
          self.player.prepareToPlay { error in
            DispatchQueue.main.async {
              if error != nil { result(false); return }
              self.player.play()
              result(true)
            }
          }
        }
      }.resume()
    }
  }

  private func session() -> [String: Any] {
    let item = player.nowPlayingItem
    let state: String
    switch player.playbackState {
    case .playing: state = "playing"
    case .paused, .interrupted: state = "paused"
    case .stopped: state = "stopped"
    case .seekingForward, .seekingBackward: state = "buffering"
    @unknown default: state = "unknown"
    }
    let position = player.currentPlaybackTime
    // Flutter necesita NSNull (no nil de Swift) para los valores vacíos.
    func orNull(_ v: Any?) -> Any { v ?? NSNull() }
    let positionMs: Int? = position.isFinite ? Int(position * 1000) : nil
    return [
      "playerId": Self.package,
      "packageName": Self.package,
      "appName": Self.appName,
      "state": state,
      "title": orNull(item?.title),
      "artist": orNull(item?.artist ?? item?.albumArtist),
      "positionMs": orNull(positionMs),
      "lastActiveAtMs": Int(lastActiveAt.timeIntervalSince1970 * 1000),
      "actions": ["play", "pause", "togglePlayPause", "next", "previous"],
      "durationMs": orNull(item.map { Int($0.playbackDuration * 1000) }),
      "album": orNull(item?.albumTitle),
      "art": artwork(item),
    ]
  }

  private func emit() {
    guard let sink = sink else { return }
    let list = [session()]
    DispatchQueue.main.async { sink(list) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    player.beginGeneratingPlaybackNotifications()
    let center = NotificationCenter.default
    for name in [
      Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange,
      Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
    ] {
      observers.append(
        center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
          self?.lastActiveAt = Date()
          self?.emit()
        })
    }
    emit()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
    player.endGeneratingPlaybackNotifications()
    sink = nil
    return nil
  }
}

// MARK: - Voz (reconocimiento de Apple, dentro del teléfono cuando se puede)

final class VoiceBridge: NSObject, FlutterStreamHandler, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?

  private let recognizer =
    SFSpeechRecognizer(locale: Locale(identifier: "es-CO"))
    ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private let synth = AVSpeechSynthesizer()

  private var wanted = false
  private var paused = false
  private var speaking = false
  private var session = 0
  private var lastText = ""
  private var silenceTimer: Timer?
  private var phrases: [String] = []

  /// Cada tarea de reconocimiento tiene su número: las respuestas de una tarea
  /// vieja (cancelada) se ignoran. Antes, al cancelar una tarea, su aviso de
  /// error llegaba tarde y reiniciaba —y mataba— la tarea nueva, en bucle:
  /// Jarvis dejaba de oír hasta tocar el micrófono.
  private var generation = 0

  /// Un solo reinicio pendiente a la vez.
  private var pendingRestart: DispatchWorkItem?

  /// Errores seguidos (pausas crecientes; sin reintentos infinitos).
  private var errorStreak = 0
  private static let maxRetries = 5

  /// «¿Qué canción?» → la siguiente frase va a quien la pidió (listenOnce).
  private var once: FlutterResult?
  private var onceFrom = Date.distantPast
  private var onceTimer: Timer?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "smartbuds/voice", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "smartbuds/voice/events", binaryMessenger: messenger)
    super.init()
    synth.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    events.setStreamHandler(self)
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(routeChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(interrupted(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    // Al conectar o quitar audífonos el motor de audio se detiene solo: hay que reabrirlo.
    center.addObserver(
      self, selector: #selector(engineChanged),
      name: .AVAudioEngineConfigurationChange, object: audioEngine)
    // Al volver a la app (desbloquear, cambiar de app) se comprueba que siga escuchando.
    center.addObserver(
      self, selector: #selector(becameActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  @objc private func engineChanged() {
    emit("audio", ["event": "engine_change", "running": audioEngine.isRunning])
    // Solo si el motor realmente se detuvo (un cambio de configuración no siempre lo detiene).
    guard wanted, !paused, !speaking, !audioEngine.isRunning, allowAutoRestart("engine") else { return }
    restart(after: 0.3, recovering: true)
  }

  @objc private func becameActive() { ensure() }

  /// Reabre la escucha si debería estar activa y no lo está. Devuelve si escucha.
  @discardableResult
  private func ensure() -> Bool {
    errorStreak = 0
    if wanted && !paused && !speaking && (task == nil || !audioEngine.isRunning) {
      restart(after: 0.1, recovering: true)
    }
    return task != nil && audioEngine.isRunning
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isAvailable":
      result(recognizer?.isAvailable ?? false)
    case "hasPermission":
      result(hasPermission())
    case "openAppSettings":
      // Ajustes de SmartBuds en el sistema (permiso de micrófono y voz).
      if let url = URL(string: UIApplication.openSettingsURLString) {
        DispatchQueue.main.async { UIApplication.shared.open(url) }
        result(true)
      } else {
        result(false)
      }
    case "requestPermission":
      SFSpeechRecognizer.requestAuthorization { status in
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async { result(status == .authorized && granted) }
        }
      }
    case "start":
      phrases = (args["grammar"] as? [String] ?? []).filter { !$0.hasPrefix("[") }
      wanted = true
      paused = false
      startListening()
      result(true)
    case "stop":
      wanted = false
      pendingRestart?.cancel()
      pendingRestart = nil
      stopListening()
      emit("state", ["listening": false])
      result(true)
    case "setPaused":
      paused = (args["paused"] as? Bool) ?? false
      if paused { stopListening() } else { startListening() }
      emit("state", ["listening": wanted && !paused, "paused": paused])
      result(true)
    case "speak":
      duckOnReply = args["duck"] as? Bool ?? false
      speak(
        args["text"] as? String ?? "",
        rate: (args["rate"] as? NSNumber)?.floatValue ?? 1,
        pitch: (args["pitch"] as? NSNumber)?.floatValue ?? 1
      )
      result(true)
    case "listenOnce":
      listenOnce(result)
    case "ensure":
      result(ensure())
    case "headphonesConnected":
      result(headphonesConnected())
    case "speakerAvailable":
      result(false) // «Solo mi voz» usa el modelo de Vosk (solo Android por ahora)
    case "setGrammar":
      phrases = (args["grammar"] as? [String] ?? []).filter { !$0.hasPrefix("[") }
      result(true)
    case "setGrammarEnabled":
      result(true) // el reconocedor de Apple siempre escucha libre
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func hasPermission() -> Bool {
    SFSpeechRecognizer.authorizationStatus() == .authorized
      && AVAudioSession.sharedInstance().recordPermission == .granted
  }

  // MARK: Escucha

  private func startListening() {
    guard wanted, !paused, !speaking, task == nil else { return }
    guard let recognizer = recognizer, recognizer.isAvailable else {
      emit("error", ["message": "El reconocimiento de voz no está disponible ahora."])
      return
    }
    guard hasPermission() else {
      emit("error", ["message": "Falta el permiso de micrófono o de reconocimiento de voz."])
      return
    }
    do {
      try configureSession()

      let req = SFSpeechAudioBufferRecognitionRequest()
      req.shouldReportPartialResults = true
      req.taskHint = .search
      req.contextualStrings = phrases // las órdenes se reconocen mejor
      if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
      request = req

      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
        self?.request?.append(buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()

      generation += 1
      let gen = generation
      task = recognizer.recognitionTask(with: req) { [weak self] result, error in
        DispatchQueue.main.async {
          // Respuesta de una tarea vieja (ya cancelada): no tocar la actual.
          guard let self = self, gen == self.generation else { return }
          if let result = result {
            self.errorStreak = 0
            self.lastText = result.bestTranscription.formattedString
            if result.isFinal { self.finishUtterance() } else { self.armSilenceTimer() }
          } else if let error = error {
            self.recognitionFailed(error)
          }
        }
      }
      emit("state", ["listening": true, "recovering": false])
    } catch {
      stopListening()
      recognitionFailed(error)
    }
  }

  /// Error de reconocimiento: reintenta con pausas crecientes (0,6 s, 1,2 s,
  /// 2,4 s… hasta 10 s) y, si sigue fallando, avisa a Dart en vez de insistir.
  private func recognitionFailed(_ error: Error) {
    let ns = error as NSError
    // 1110 = no se oyó nada; 216/301 = cancelada. No cuentan como fallo del micrófono.
    let benign = [1110, 216, 301, 203].contains(ns.code)
    if !benign { errorStreak += 1 }
    if errorStreak > Self.maxRetries {
      stopListening()
      emit("state", ["listening": false, "recovering": false])
      emit("error", ["message": "El reconocimiento de voz no responde: \(ns.localizedDescription)", "fatal": true])
      return
    }
    let delay = benign ? 0.3 : min(0.6 * pow(2.0, Double(max(errorStreak - 1, 0))), 10)
    restart(after: delay, recovering: !benign)
  }

  // MARK: Sesión de audio (volumen estable)

  /// Opciones para ESCUCHAR: mezclar con la música de otras apps y nunca
  /// atenuarla (sin .duckOthers). Antes se volvía a fijar la categoría y a
  /// activar la sesión en CADA frase; eso disparaba un cambio de ruta, el
  /// cambio de ruta reiniciaba la escucha, y así en bucle: la música subía y
  /// bajaba mientras hablabas o cantabas. Ahora se configura una sola vez.
  private let listenOptions: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
  private var sessionActive = false
  /// Atenuar la música solo mientras Jarvis responde (ajuste; apagado por defecto).
  private var duckOnReply = false
  private var ducking = false
  private var autoRestarts: [Date] = []

  private func configureSession() throws {
    let audio = AVAudioSession.sharedInstance()
    if audio.category != .playAndRecord || audio.mode != .default || audio.categoryOptions != listenOptions {
      try audio.setCategory(.playAndRecord, mode: .default, options: listenOptions)
      emit("audio", ["event": "category", "duck": false])
    }
    if !sessionActive {
      try audio.setActive(true)
      sessionActive = true
      emit("audio", ["event": "active"])
    }
  }

  /// Atenúa la música de otras apps mientras Jarvis habla (solo con el ajuste).
  private func beginReplyDuck() {
    guard duckOnReply, !ducking else { return }
    let audio = AVAudioSession.sharedInstance()
    do {
      try audio.setCategory(.playAndRecord, mode: .default, options: listenOptions.union(.duckOthers))
      try audio.setActive(true)
      sessionActive = true
      ducking = true
      emit("audio", ["event": "duck_on"])
    } catch {
      emit("audio", ["event": "duck_failed"])
    }
  }

  /// Quita la atenuación: iOS solo devuelve el volumen a las otras apps al
  /// desactivar la sesión, así que se desactiva una vez y se vuelve a escuchar.
  private func endReplyDuck() {
    guard ducking else { return }
    ducking = false
    let audio = AVAudioSession.sharedInstance()
    try? audio.setActive(false, options: .notifyOthersOnDeactivation)
    sessionActive = false
    try? audio.setCategory(.playAndRecord, mode: .default, options: listenOptions)
    emit("audio", ["event": "duck_off"])
  }

  /// Freno: si el sistema pide reiniciar la escucha más de 4 veces en 15 s
  /// (cambios de ruta o del motor de audio en cadena), se ignora para no
  /// entrar en un ciclo. El vigilante de Dart la reabre si queda caída.
  private func allowAutoRestart(_ why: String) -> Bool {
    let now = Date()
    autoRestarts = autoRestarts.filter { now.timeIntervalSince($0) < 15 } + [now]
    if autoRestarts.count > 4 {
      emit("audio", ["event": "restart_blocked", "why": why])
      return false
    }
    return true
  }

  private func stopListening() {
    generation += 1 // lo que llegue de la tarea anterior se ignora
    silenceTimer?.invalidate()
    silenceTimer = nil
    if audioEngine.isRunning { audioEngine.stop() }
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
  }

  private func restart(after seconds: Double, recovering: Bool = false) {
    stopListening()
    if recovering { emit("state", ["listening": false, "recovering": true]) }
    pendingRestart?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.pendingRestart = nil
      self?.startListening()
    }
    pendingRestart = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  /// Un segundo sin palabras nuevas = terminaste la frase.
  private func armSilenceTimer() {
    silenceTimer?.invalidate()
    silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
      self?.finishUtterance()
    }
  }

  private func finishUtterance() {
    silenceTimer?.invalidate()
    let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
    lastText = ""
    if !text.isEmpty {
      if let once = once, Date() >= onceFrom {
        self.once = nil
        onceTimer?.invalidate()
        once(text)
      } else if once == nil {
        emit("final", ["texts": [text]])
      }
      session += 1
    }
    restart(after: 0.2) // frase nueva desde cero
  }

  private func listenOnce(_ result: @escaping FlutterResult) {
    once?(nil)
    once = result
    onceFrom = Date().addingTimeInterval(1.2) // que termine de sonar la pregunta
    onceTimer?.invalidate()
    onceTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
      self?.once?(nil)
      self?.once = nil
    }
    if task == nil { startListening() }
  }

  // MARK: Respuesta hablada

  private func speak(_ text: String, rate: Float = 1, pitch: Float = 1) {
    guard !text.isEmpty else { return }
    let u = AVSpeechUtterance(string: text)
    // Voz personalizada: velocidad (sobre la normal) y tono.
    let r = AVSpeechUtteranceDefaultSpeechRate * min(max(rate, 0.5), 2)
    u.rate = min(max(r, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    u.pitchMultiplier = min(max(pitch, 0.5), 2)
    u.voice = AVSpeechSynthesisVoice(language: "es-CO") ?? AVSpeechSynthesisVoice(language: "es-ES")
    speaking = true
    stopListening() // que SmartBuds no se escuche a sí mismo
    beginReplyDuck()
    emit("speaking", ["on": true])
    synth.speak(u)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    speaking = false
    endReplyDuck()
    emit("speaking", ["on": false])
    restart(after: 0.3)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    speaking = false
    endReplyDuck()
    emit("speaking", ["on": false])
    restart(after: 0.3)
  }

  // MARK: Audífonos e interrupciones

  private func headphonesConnected() -> Bool {
    let kinds: Set<AVAudioSession.Port> = [
      .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio,
    ]
    return AVAudioSession.sharedInstance().currentRoute.outputs.contains { kinds.contains($0.portType) }
  }

  @objc private func routeChanged(_ note: Notification) {
    let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
    let reason = AVAudioSession.RouteChangeReason(rawValue: raw) ?? .unknown
    emit("headphones", ["connected": headphonesConnected()])
    emit("audio", ["event": "route", "reason": raw])
    // Solo reabrir la escucha si cambió el aparato (audífonos conectados o
    // quitados). Un cambio de categoría (.categoryChange) lo provoca la propia
    // sesión: reiniciar ahí era el bucle que hacía subir y bajar la música.
    guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
    if wanted && !paused && !speaking && allowAutoRestart("route") { restart(after: 0.4, recovering: true) }
  }

  @objc private func interrupted(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    emit("audio", ["event": "interruption", "began": type == .began])
    if type == .began {
      sessionActive = false // el sistema desactivó la sesión (llamada, Siri, alarma)
      stopListening()
    } else {
      restart(after: 0.5)
    }
  }

  // MARK: Eventos hacia Dart

  private func emit(_ type: String, _ data: [String: Any]) {
    var payload = data
    payload["type"] = type
    payload["session"] = session
    DispatchQueue.main.async { [weak self] in self?.sink?(payload) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    emit("headphones", ["connected": headphonesConnected()])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
