import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Liens de profil zamu://profil/<id> (même contrat que MainActivity.kt) :
  // « initial » rend le lien de lancement une seule fois, puis les liens
  // reçus app ouverte sont envoyés à Dart par « lien ».
  private var canalLiens: FlutterMethodChannel?
  private var lienEnAttente: String?
  private var dartEcoute = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let url = launchOptions?[.url] as? URL, url.scheme == "zamu" {
      lienEnAttente = url.absoluteString
    }
    if let controleur = window?.rootViewController as? FlutterViewController {
      let messager = controleur.binaryMessenger

      let liens = FlutterMethodChannel(name: "zamu/liens", binaryMessenger: messager)
      liens.setMethodCallHandler { [weak self] appel, resultat in
        guard let self = self else { return }
        if appel.method == "initial" {
          self.dartEcoute = true
          resultat(self.lienEnAttente)
          self.lienEnAttente = nil  // une seule fois
        } else {
          resultat(FlutterMethodNotImplemented)
        }
      }
      canalLiens = liens

      // Découpe de vidéo pour les stories, sans réencodage (comme Android)
      FlutterMethodChannel(name: "zamu/video", binaryMessenger: messager)
        .setMethodCallHandler { appel, resultat in
          guard appel.method == "decouper" else {
            resultat(FlutterMethodNotImplemented)
            return
          }
          let args = appel.arguments as? [String: Any]
          guard let chemin = args?["chemin"] as? String,
            let debutMs = args?["debutMs"] as? Int,
            let finMs = args?["finMs"] as? Int, finMs > debutMs
          else {
            resultat(FlutterError(code: "arguments", message: "Arguments invalides", details: nil))
            return
          }
          AppDelegate.decouper(chemin: chemin, debutMs: debutMs, finMs: finMs, resultat: resultat)
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // App déjà ouverte (ou lancement) : un lien zamu:// arrive ici
  override func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "zamu" {
      if dartEcoute {
        canalLiens?.invokeMethod("lien", arguments: url.absoluteString)
      } else {
        lienEnAttente = url.absoluteString
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// Copie le passage [debutMs, finMs] de la vidéo (préréglage « passthrough »).
  private static func decouper(
    chemin: String, debutMs: Int, finMs: Int, resultat: @escaping FlutterResult
  ) {
    let source = AVURLAsset(url: URL(fileURLWithPath: chemin))
    guard
      let export = AVAssetExportSession(asset: source, presetName: AVAssetExportPresetPassthrough)
    else {
      resultat(FlutterError(code: "decoupe", message: "Export impossible", details: nil))
      return
    }
    let mp4 = export.supportedFileTypes.contains(.mp4)
    let sortie = FileManager.default.temporaryDirectory.appendingPathComponent(
      "story_\(Int(Date().timeIntervalSince1970 * 1000)).\(mp4 ? "mp4" : "mov")")
    export.outputURL = sortie
    export.outputFileType = mp4 ? .mp4 : .mov
    export.timeRange = CMTimeRange(
      start: CMTime(value: CMTimeValue(debutMs), timescale: 1000),
      end: CMTime(value: CMTimeValue(finMs), timescale: 1000))
    export.exportAsynchronously {
      DispatchQueue.main.async {
        if export.status == .completed {
          resultat(sortie.path)
        } else {
          try? FileManager.default.removeItem(at: sortie)
          resultat(
            FlutterError(
              code: "decoupe", message: export.error?.localizedDescription, details: nil))
        }
      }
    }
  }
}
