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
  }

  private init(messenger: FlutterBinaryMessenger) {
    media = AppleMusicBridge(messenger: messenger)
    voice = VoiceBridge(messenger: messenger)
    // Accesos rápidos (en Android). En iPhone solo se contesta «listo».
    actions = FlutterMethodChannel(name: "smartbuds/actions", binaryMessenger: messenger)
    actions.setMethodCallHandler { call, result in
      if call.method == "ready" { result(true) } else { result(FlutterMethodNotImplemented) }
    }
    super.init()
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
    default:
      result(FlutterMethodNotImplemented)
    }
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
      self, selector: #selector(routeChanged),
      name: AVAudioSession.routeChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(interrupted(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isAvailable":
      result(recognizer?.isAvailable ?? false)
    case "hasPermission":
      result(hasPermission())
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
      stopListening()
      emit("state", ["listening": false])
      result(true)
    case "setPaused":
      paused = (args["paused"] as? Bool) ?? false
      if paused { stopListening() } else { startListening() }
      emit("state", ["listening": wanted && !paused, "paused": paused])
      result(true)
    case "speak":
      speak(args["text"] as? String ?? "")
      result(true)
    case "listenOnce":
      listenOnce(result)
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
      let audio = AVAudioSession.sharedInstance()
      // Mezclar con otras apps: la música de Apple Music sigue sonando.
      try audio.setCategory(
        .playAndRecord, mode: .default,
        options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
      try audio.setActive(true, options: .notifyOthersOnDeactivation)

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

      task = recognizer.recognitionTask(with: req) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if let result = result {
            self.lastText = result.bestTranscription.formattedString
            if result.isFinal { self.finishUtterance() } else { self.armSilenceTimer() }
          } else if error != nil {
            self.restart(after: 0.6)
          }
        }
      }
      emit("state", ["listening": true])
    } catch {
      emit("error", ["message": "No se pudo abrir el micrófono: \(error.localizedDescription)"])
      stopListening()
    }
  }

  private func stopListening() {
    silenceTimer?.invalidate()
    silenceTimer = nil
    if audioEngine.isRunning { audioEngine.stop() }
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
  }

  private func restart(after seconds: Double) {
    stopListening()
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      self?.startListening()
    }
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

  private func speak(_ text: String) {
    guard !text.isEmpty else { return }
    let u = AVSpeechUtterance(string: text)
    u.voice = AVSpeechSynthesisVoice(language: "es-CO") ?? AVSpeechSynthesisVoice(language: "es-ES")
    speaking = true
    stopListening() // que SmartBuds no se escuche a sí mismo
    synth.speak(u)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    speaking = false
    restart(after: 0.3)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    speaking = false
    restart(after: 0.3)
  }

  // MARK: Audífonos e interrupciones

  private func headphonesConnected() -> Bool {
    let kinds: Set<AVAudioSession.Port> = [
      .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio,
    ]
    return AVAudioSession.sharedInstance().currentRoute.outputs.contains { kinds.contains($0.portType) }
  }

  @objc private func routeChanged() {
    emit("headphones", ["connected": headphonesConnected()])
  }

  @objc private func interrupted(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    if type == .began { stopListening() } else { restart(after: 0.5) } // p. ej. una llamada
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
