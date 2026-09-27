import AVFoundation
import Vision
import SwiftUI

/// Captura facial com câmera frontal e detecção de rosto via Vision.
///
/// Guia o usuário: detecta o rosto, mede a aproximação (fração da tela que o
/// rosto ocupa) e a prova de vida por um movimento simples (piscar / virar).
/// Ao concluir, gera um template de 128 dimensões — o mesmo formato que a API
/// espera. O template é derivado de landmarks; num app real viria de um modelo
/// de embedding, mas a estrutura de captura, proximidade e vivacidade é real.
@MainActor
@Observable
final class FaceCaptureController: NSObject {

    enum Stage: Equatable {
        case starting           // preparando a câmera
        case searching          // procurando um rosto
        case tooFar             // rosto detectado, longe
        case holding            // na distância certa, estabilizando
        case livenessCheck      // pedindo o movimento de vivacidade
        case done               // capturado
        case denied             // sem permissão de câmera
    }

    var stage: Stage = .starting
    /// 0…1: o quanto o rosto preenche o quadro. Alimenta a bolinha.
    var proximity: Double = 0
    /// Template gerado ao concluir.
    private(set) var template: [Float]?

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "face.capture")
    private var holdFrames = 0
    private var blinkSeen = false
    private var lastLandmarks: [Float] = []

    /// Distância ideal: o rosto ocupa entre 32% e 62% da largura do quadro.
    private let nearEnough = 0.32
    private let tooClose = 0.72
    private let framesToHold = 12

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in granted ? self?.configure() : (self?.stage = .denied) }
            }
        default: stage = .denied
        }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    private func configure() {
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  session.canAddInput(input) else {
                Task { @MainActor in self.stage = .denied }
                return
            }
            session.addInput(input)
            output.setSampleBufferDelegate(self, queue: queue)
            output.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor in self.stage = .searching }
        }
    }

    // MARK: - Análise de cada frame

    /// Amostra Sendable de um frame — só números, cruza a fronteira do ator
    /// com segurança (o VNFaceObservation não é Sendable).
    struct FaceSample: Sendable {
        var faceWidth: Double
        var eyeOpenness: Double
        var landmarks: [Float]
    }

    private func analyze(_ sample: FaceSample?) {
        guard let sample else {
            proximity = 0
            if stage == .tooFar || stage == .holding { stage = .searching }
            holdFrames = 0
            return
        }

        let fill = sample.faceWidth
        proximity = min(1, fill / tooClose)
        if !sample.landmarks.isEmpty { lastLandmarks = sample.landmarks }
        if sample.eyeOpenness < 0.06 { blinkSeen = true }

        switch stage {
        case .searching, .tooFar:
            stage = fill >= nearEnough ? .holding : .tooFar
            holdFrames = 0
        case .holding:
            if fill < nearEnough { stage = .tooFar; holdFrames = 0; break }
            holdFrames += 1
            if holdFrames >= framesToHold { stage = .livenessCheck }
        case .livenessCheck:
            if blinkSeen {
                finish()
            }
        default: break
        }
    }

    private func finish() {
        // Template de 128 dims a partir dos landmarks normalizados. Determinístico
        // para o mesmo rosto, com pequena variação natural entre capturas.
        var t = lastLandmarks
        if t.count < 128 { t += Array(repeating: 0, count: 128 - t.count) }
        template = Array(t.prefix(128))
        stage = .done
        stop()
        Haptics.success()
    }

}

extension FaceCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
        let face = (request.results as? [VNFaceObservation])?
            .max(by: { $0.boundingBox.width < $1.boundingBox.width })

        let sample: FaceCaptureController.FaceSample? = face.map { f in
            var pts: [Float] = []
            if let lm = f.landmarks {
                for region in [lm.leftEye, lm.rightEye, lm.nose, lm.outerLips,
                               lm.leftEyebrow, lm.rightEyebrow, lm.faceContour] {
                    guard let region else { continue }
                    for p in region.normalizedPoints {
                        pts.append(Float(p.x)); pts.append(Float(p.y))
                    }
                }
            }
            let open = openness(f.landmarks?.leftEye) + openness(f.landmarks?.rightEye)
            return .init(faceWidth: Double(f.boundingBox.width),
                         eyeOpenness: open, landmarks: pts.count >= 64 ? pts : [])
        }
        Task { @MainActor [weak self] in self?.analyze(sample) }
    }

}

/// Abertura vertical do olho pelos landmarks — livre, para o delegate
/// nonisolated poder chamar sem tocar o ator.
private func openness(_ eye: VNFaceLandmarkRegion2D?) -> Double {
    guard let eye else { return 1 }
    let ys = eye.normalizedPoints.map { Double($0.y) }
    guard let top = ys.max(), let bottom = ys.min() else { return 1 }
    return top - bottom
}
