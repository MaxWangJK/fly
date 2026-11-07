import AVFoundation
import AudioToolbox
import Flutter
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Local conversion at the source. Never modifies a selected file or Photos asset.
@MainActor
final class FlyMediaImport: NSObject, FlutterPlugin, PHPickerViewControllerDelegate {
  private var registrar: FlutterPluginRegistrar?
  private var picking: FlutterResult?
  private var activePick: String?
  private weak var pickerController: PHPickerViewController?
  private var pickProgress: Progress?
  private var exports: [String: AVAssetExportSession] = [:]
  private var requests = Set<String>()
  private var cancelled = Set<String>()
  private var picks: [String: URL] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlyMediaImport()
    instance.registrar = registrar
    let channel = FlutterMethodChannel(name: "com.flyproduct.fly/media", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pick":
      guard picking == nil, let host = registrar?.viewController() else {
        result(FlutterError(code: "BUSY", message: "媒体选择器暂时不可用，请稍后重试", details: nil)); return
      }
      picking = result
      var config = PHPickerConfiguration(photoLibrary: .shared())
      config.selectionLimit = 0
      config.filter = .any(of: [.images, .videos])
      config.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = self
      pickerController = picker
      host.present(picker, animated: true)
    case "normalize":
      guard let id = args["id"] as? String, let source = args["source"] as? String,
            let output = args["output"] as? String, let name = args["name"] as? String else {
        result(FlutterError(code: "ARGUMENT", message: "缺少媒体转换参数", details: nil)); return
      }
      requests.insert(id)
      Task {
        defer { exports.removeValue(forKey: id); cancelled.remove(id); requests.remove(id) }
        do {
          let item = try await normalize(id: id, source: URL(fileURLWithPath: source),
                                         name: name, output: URL(fileURLWithPath: output))
          try check(id)
          result(item)
        } catch {
          result(FlutterError(code: cancelled.contains(id) ? "CANCELLED" : "CONVERSION",
                              message: error.localizedDescription, details: nil))
        }
      }
    case "cancel":
      if let id = args["id"] as? String, requests.contains(id) { cancelled.insert(id); exports[id]?.cancelExport() }
      result(nil)
    case "progress":
      result(Double(exports[args["id"] as? String ?? ""]?.progress ?? 0))
    case "releasePick":
      if let token = args["token"] as? String, let dir = picks.removeValue(forKey: token) {
        do { try FileManager.default.removeItem(at: dir); result(nil) }
        catch { result(FlutterError(code: "CLEANUP", message: error.localizedDescription, details: nil)) }
      } else { result(nil) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func check(_ id: String) throws {
    if cancelled.contains(id) { throw failure("已取消媒体转换") }
  }

  nonisolated private func failure(_ message: String) -> NSError {
    NSError(domain: "FlyMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func normalize(id: String, source: URL, name: String, output: URL) async throws -> [String: String] {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"
    guard output.resolvingSymlinksInPath().path.hasPrefix(root),
          output.lastPathComponent.hasPrefix("fly-media-") else { throw failure("无效转换目录") }
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    try check(id)
    let safeName = (name as NSString).lastPathComponent
    let ext = source.pathExtension.lowercased()
    let image = CGImageSourceCreateWithURL(source as CFURL, nil)
    if let image = image, let type = CGImageSourceGetType(image) {
      let actual = type as String
      if actual == UTType.jpeg.identifier || actual == UTType.png.identifier {
        let suffix = actual == UTType.png.identifier ? "png" : "jpg"
        return ["path": source.path, "name": (safeName as NSString).deletingPathExtension + "." + suffix]
      }
      let target = output.appendingPathComponent((safeName as NSString).deletingPathExtension + ".jpg")
      let converted = try await Task.detached(priority: .userInitiated) { () -> (Data, Bool) in
        guard let sourceImage = UIImage(contentsOfFile: source.path), let cg = sourceImage.cgImage else {
          throw NSError(domain: "FlyMedia", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取图片"])
        }
        let alpha = [.first, .last, .premultipliedFirst, .premultipliedLast].contains(cg.alphaInfo)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !alpha
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: sourceImage.size, format: format)
        let upright = renderer.image { _ in sourceImage.draw(in: CGRect(origin: .zero, size: sourceImage.size)) }
        guard let data = alpha ? upright.pngData() : upright.jpegData(compressionQuality: 0.94) else {
          throw NSError(domain: "FlyMedia", code: 3, userInfo: [NSLocalizedDescriptionKey: "图片转换失败"])
        }
        return (data, alpha)
      }.value
      try check(id)
      let url = converted.1 ? target.deletingPathExtension().appendingPathExtension("png") : target
      try converted.0.write(to: url, options: .atomic)
      return ["path": url.path, "name": url.lastPathComponent]
    }
    guard ["mov", "mp4", "m4v", "3gp"].contains(ext) else { throw failure("无法识别图片或视频格式") }
    let asset = AVURLAsset(url: source)
    let videos = try await asset.loadTracks(withMediaType: .video)
    guard !videos.isEmpty else { throw failure("视频没有可播放的画面轨道") }
    let audios = try await asset.loadTracks(withMediaType: .audio)
    var compatible = true
    for track in videos {
      let descriptions = try await track.load(.formatDescriptions)
      if descriptions.isEmpty { compatible = false }
      for desc in descriptions {
        if CMFormatDescriptionGetMediaSubType(desc) != kCMVideoCodecType_H264 { compatible = false }
        let attrs = (CMFormatDescriptionGetExtensions(desc) as? [String: Any]) ?? [:]
        let transfer = attrs[kCMFormatDescriptionExtension_TransferFunction as String] as? String ?? ""
        if transfer.contains("2084") || transfer.contains("HLG") { compatible = false }
      }
    }
    for track in audios {
      let descriptions = try await track.load(.formatDescriptions)
      if descriptions.isEmpty { compatible = false }
      for desc in descriptions {
        if CMFormatDescriptionGetMediaSubType(desc) != kAudioFormatMPEG4AAC { compatible = false }
      }
    }
    try check(id)
    if compatible && ext == "mp4" { return ["path": source.path, "name": (safeName as NSString).deletingPathExtension + ".mp4"] }
    // The H.264 size preset also produces AAC and converts HDR to SDR.
    let preset = compatible ? AVAssetExportPresetPassthrough : AVAssetExportPreset1920x1080
    guard let export = AVAssetExportSession(asset: asset, presetName: preset),
          export.supportedFileTypes.contains(.mp4) else { throw failure("此视频无法生成兼容副本") }
    let target = output.appendingPathComponent((safeName as NSString).deletingPathExtension + ".mp4")
    export.outputURL = target
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    exports[id] = export
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      export.exportAsynchronously { continuation.resume() }
    }
    try check(id)
    guard export.status == .completed else { throw export.error ?? failure("视频转换失败，请重试") }
    // Verify actual output tracks before Dart hashes and commits the file.
    let converted = AVURLAsset(url: target)
    let finalTracks = try await converted.loadTracks(withMediaType: .video)
    guard !finalTracks.isEmpty else { throw failure("转换后视频没有画面") }
    for track in finalTracks {
      for desc in try await track.load(.formatDescriptions) {
        guard CMFormatDescriptionGetMediaSubType(desc) == kCMVideoCodecType_H264 else { throw failure("视频编码不兼容") }
      }
    }
    for track in try await converted.loadTracks(withMediaType: .audio) {
      for desc in try await track.load(.formatDescriptions) {
        guard CMFormatDescriptionGetMediaSubType(desc) == kAudioFormatMPEG4AAC else { throw failure("音频编码不兼容") }
      }
    }
    return ["path": target.path, "name": target.lastPathComponent]
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard let callback = picking else { return }
    if results.isEmpty && activePick != nil { cancelPreparing(); return }
    guard activePick == nil else { return }
    if results.isEmpty { picking = nil; picker.dismiss(animated: true); callback(nil); return }
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.center = picker.view.center
    spinner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    spinner.startAnimating()
    picker.view.addSubview(spinner)
    let cancel = UIButton(type: .system)
    cancel.setTitle("Cancel preparing", for: .normal)
    cancel.frame = CGRect(x: picker.view.bounds.midX - 90, y: picker.view.bounds.midY + 45, width: 180, height: 48)
    cancel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cancel.addTarget(self, action: #selector(cancelPreparing), for: .touchUpInside)
    picker.view.addSubview(cancel)
    let token = UUID().uuidString
    activePick = token
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("fly-picked-" + token)
    Task {
      do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var files: [String] = []
        for (index, selection) in results.enumerated() {
          guard activePick == token else { throw failure("已取消媒体选择") }
          let dir = root.appendingPathComponent(String(index))
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          let provider = selection.itemProvider
          if provider.canLoadObject(ofClass: PHLivePhoto.self) {
            let photo: PHLivePhoto = try await withCheckedThrowingContinuation { continuation in
              pickProgress = provider.loadObject(ofClass: PHLivePhoto.self) { object, error in
                if let photo = object as? PHLivePhoto { continuation.resume(returning: photo) }
                else { continuation.resume(throwing: error ?? self.failure("无法读取Live Photo")) }
              }
            }
            let resources = PHAssetResource.assetResources(for: photo)
            guard activePick == token else { throw failure("已取消媒体选择") }
            guard let still = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }),
                  let motion = resources.first(where: { $0.type == .fullSizePairedVideo }) ?? resources.first(where: { $0.type == .pairedVideo }) else {
              throw failure("Live Photo缺少照片或动态资源")
            }
            let stem = ((still.originalFilename as NSString).lastPathComponent as NSString).deletingPathExtension
            for (resource, name) in [(still, still.originalFilename), (motion, stem + " (Live).mov")] {
              guard activePick == token else { throw failure("已取消媒体选择") }
              let url = dir.appendingPathComponent((name as NSString).lastPathComponent)
              let options = PHAssetResourceRequestOptions()
              options.isNetworkAccessAllowed = true
              try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                  if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
              }
              files.append(url.path)
            }
          } else {
            let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie.identifier : UTType.image.identifier
            let path: String = try await withCheckedThrowingContinuation { continuation in
              pickProgress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url = url else { continuation.resume(throwing: error ?? self.failure("无法准备媒体")); return }
                do {
                  let target = dir.appendingPathComponent(url.lastPathComponent)
                  try FileManager.default.copyItem(at: url, to: target)
                  continuation.resume(returning: target.path)
                } catch { continuation.resume(throwing: error) }
              }
            }
            files.append(path)
          }
        }
        guard activePick == token else { throw failure("已取消媒体选择") }
        picks[token] = root
        picking = nil
        activePick = nil
        pickProgress = nil
        picker.dismiss(animated: true)
        callback(["token": token, "files": files])
      } catch {
        try? FileManager.default.removeItem(at: root)
        if activePick == token {
          picking = nil
          activePick = nil
          pickProgress = nil
          picker.dismiss(animated: true)
          callback(FlutterError(code: "PICK", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  @objc private func cancelPreparing() {
    let callback = picking
    picking = nil
    activePick = nil
    pickProgress?.cancel()
    pickProgress = nil
    pickerController?.dismiss(animated: true)
    callback?(nil)
    // The pending resource callback owns and eventually cleans its own directory.
  }
}
