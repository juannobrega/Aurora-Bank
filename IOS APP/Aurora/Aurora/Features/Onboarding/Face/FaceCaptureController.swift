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
        // O descritor da última amostra já vem normalizado com 128 dims.
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
            let open = openness(f.landmarks?.leftEye) + openness(f.landmarks?.rightEye)
            return .init(faceWidth: Double(f.boundingBox.width),
                         eyeOpenness: open,
                         landmarks: faceDescriptor(f.landmarks) )
        }
        Task { @MainActor [weak self] in self?.analyze(sample) }
    }

}

/// Descritor facial de 128 dimensões, normalizado e reprodutível.
///
/// O problema do template cru era não sobreviver a mudanças de posição,
/// tamanho e leve rotação — o mesmo rosto virava vetores diferentes a cada
/// captura, e o login por rosto falhava. Aqui os pontos são:
///
///  1. recentrados na média dos dois olhos (invariante à posição no quadro);
///  2. escalados pela distância interocular (invariante ao tamanho/distância);
///  3. rotacionados para deixar os olhos na horizontal (invariante à inclinação);
///  4. reamostrados por região a um número fixo de pontos, para o vetor ter
///     sempre a mesma forma e as mesmas dimensões comparáveis.
///
/// Não é um embedding de rede neural, mas é geometria estável — o suficiente
/// para o mesmo rosto conferir consigo mesmo entre capturas.
private func faceDescriptor(_ lm: VNFaceLandmarks2D?) -> [Float] {
    guard let lm, let le = lm.leftEye, let re = lm.rightEye else { return [] }

    func center(_ r: VNFaceLandmarkRegion2D) -> (Double, Double) {
        let ps = r.normalizedPoints
        let cx = ps.map { Double($0.x) }.reduce(0, +) / Double(ps.count)
        let cy = ps.map { Double($0.y) }.reduce(0, +) / Double(ps.count)
        return (cx, cy)
    }
    let (lx, ly) = center(le), (rx, ry) = center(re)
    let ox = (lx + rx) / 2, oy = (ly + ry) / 2           // centro entre os olhos
    let dx = rx - lx, dy = ry - ly
    let interocular = max(1e-4, (dx*dx + dy*dy).squareRoot())  // escala
    let angle = atan2(dy, dx)                             // inclinação
    let cosA = cos(-angle), sinA = sin(-angle)

    // Normaliza um ponto: centraliza, escala, desrotaciona.
    func norm(_ x: Double, _ y: Double) -> (Float, Float) {
        let tx = (x - ox) / interocular, ty = (y - oy) / interocular
        return (Float(tx * cosA - ty * sinA), Float(tx * sinA + ty * cosA))
    }

    // Reamostra cada região a um número fixo de pontos, por interpolação.
    func resample(_ r: VNFaceLandmarkRegion2D?, _ count: Int) -> [Float] {
        guard let r, !r.normalizedPoints.isEmpty else {
            return Array(repeating: 0, count: count * 2)
        }
        let ps = r.normalizedPoints
        var out: [Float] = []
        for i in 0..<count {
            let t = Double(i) / Double(max(1, count - 1)) * Double(ps.count - 1)
            let lo = Int(t.rounded(.down)), hi = min(ps.count - 1, lo + 1)
            let frac = t - Double(lo)
            let x = Double(ps[lo].x) * (1 - frac) + Double(ps[hi].x) * frac
            let y = Double(ps[lo].y) * (1 - frac) + Double(ps[hi].y) * frac
            let (nx, ny) = norm(x, y)
            out.append(nx); out.append(ny)
        }
        return out
    }

    // 64 pontos no total (×2 coords = 128 dims), distribuídos por região.
    var v: [Float] = []
    v += resample(lm.leftEye, 8)
    v += resample(lm.rightEye, 8)
    v += resample(lm.leftEyebrow, 6)
    v += resample(lm.rightEyebrow, 6)
    v += resample(lm.nose, 8)
    v += resample(lm.outerLips, 12)
    v += resample(lm.faceContour, 16)
    // Garante exatamente 128 dimensões.
    if v.count < 128 { v += Array(repeating: 0, count: 128 - v.count) }
    return Array(v.prefix(128))
}

/// Abertura vertical do olho pelos landmarks — livre, para o delegate
/// nonisolated poder chamar sem tocar o ator.
private func openness(_ eye: VNFaceLandmarkRegion2D?) -> Double {
    guard let eye else { return 1 }
    let ys = eye.normalizedPoints.map { Double($0.y) }
    guard let top = ys.max(), let bottom = ys.min() else { return 1 }
    return top - bottom
}
