import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // Enlaces smartbuds://… (Atajos de iPhone, etiquetas NFC…) con la app cerrada.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      SmartBudsNative.handle(url: context.url)
    }
  }

  // …y con la app ya abierta.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
      SmartBudsNative.handle(url: context.url)
    }
  }
}
