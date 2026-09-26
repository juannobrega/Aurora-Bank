import SwiftUI

@main
struct AuroraApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
        }
        .onChange(of: scenePhase) { _, phase in
            // Bloqueia ao sair do app — o protótipo não tinha logout por
            // inatividade, item listado no documento de funcionalidades.
            if phase == .background, model.phase == .ready {
                model.lock()
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            switch model.phase {
            case .welcome, .onboarding:
                WelcomeView().transition(.opacity)
            case .locked:
                LockScreenView().transition(.opacity)
            case .ready:
                MainTabView().transition(.opacity)
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    ToastView(message: toast).padding(.bottom, 100)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.3), value: model.phase)
        .animation(.snappy(duration: 0.25), value: model.toast)
        .task(id: model.phase) {
            if model.phase == .ready, model.ledger.transactions.isEmpty {
                await model.load()
            }
        }
    }
}
