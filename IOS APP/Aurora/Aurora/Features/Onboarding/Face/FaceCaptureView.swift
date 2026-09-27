import SwiftUI
import AVFoundation

/// Tela de prova de vida: câmera frontal num círculo, com um anel que se
/// fecha conforme o rosto se aproxima e a orientação em texto. Ao concluir,
/// entrega o template ao chamador.
struct FaceCaptureView: View {
    var onCaptured: ([Float]) -> Void
    var onCancel: () -> Void

    @State private var controller = FaceCaptureController()

    var body: some View {
        VStack(spacing: 20) {
            Text("Prova de vida")
                .font(.auroraTitle).foregroundStyle(Theme.text)
            Text(guidance)
                .font(.auroraBody).foregroundStyle(guidanceColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)

            ZStack {
                // A câmera dentro de um círculo.
                Group {
                    if controller.stage == .denied {
                        deniedPlaceholder
                    } else {
                        CameraPreview(session: controller.session)
                    }
                }
                .frame(width: 260, height: 260)
                .clipShape(.circle)
                .overlay(Circle().stroke(Theme.line, lineWidth: 2))

                // Anel de progresso: fecha com a aproximação; fica verde ao concluir.
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(ringStyle, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 274, height: 274)
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy(duration: 0.3), value: ringProgress)

                if controller.stage == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 290)

            // Passos, para o usuário saber o que esperar.
            HStack(spacing: 20) {
                stepDot("Aproxime", reached: proximityReached)
                stepDot("Segure", reached: controller.stage == .holding
                        || controller.stage == .livenessCheck || controller.stage == .done)
                stepDot("Pisque", reached: controller.stage == .done)
            }
            .padding(.top, 4)

            Spacer()

            if controller.stage == .denied {
                PrimaryButton(title: "Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
            }
            Button("Cancelar", action: onCancel)
                .font(.auroraLabel).foregroundStyle(Theme.text2)
                .padding(.bottom, 8)
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.stage) { _, stage in
            if stage == .done, let t = controller.template { onCaptured(t) }
        }
        .animation(.snappy(duration: 0.3), value: controller.stage)
    }

    // MARK: Estado visual

    private var proximityReached: Bool {
        controller.stage == .holding || controller.stage == .livenessCheck
            || controller.stage == .done
    }

    private var ringProgress: CGFloat {
        switch controller.stage {
        case .done: return 1
        case .livenessCheck: return 0.85
        case .holding: return 0.6 + controller.proximity * 0.2
        default: return controller.proximity * 0.5
        }
    }

    private var ringStyle: Color {
        controller.stage == .done ? Theme.cyan
            : proximityReached ? Theme.cyan.opacity(0.8) : Theme.blue
    }

    private var guidance: String {
        switch controller.stage {
        case .starting: "Preparando a câmera…"
        case .searching: "Posicione seu rosto no círculo"
        case .tooFar: "Aproxime um pouco mais"
        case .holding: "Perfeito, segure assim…"
        case .livenessCheck: "Agora pisque os olhos"
        case .done: "Rosto confirmado!"
        case .denied: "Precisamos da câmera para validar seu rosto"
        }
    }
    private var guidanceColor: Color {
        controller.stage == .done ? Theme.cyan
            : controller.stage == .denied ? Theme.danger : Theme.text2
    }

    private func stepDot(_ label: String, reached: Bool) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(reached ? Theme.cyan : Theme.surface2)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(reached ? Theme.cyan : Theme.line, lineWidth: 1))
            Text(label)
                .font(.auroraCaption)
                .foregroundStyle(reached ? Theme.text : Theme.text3)
        }
    }

    private var deniedPlaceholder: some View {
        ZStack {
            Theme.surface1
            Image(systemName: "video.slash")
                .font(.system(size: 40)).foregroundStyle(Theme.text3)
        }
    }
}

/// Ponte para a AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoLayer.session = session
        v.videoLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
