import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showOnboarding = false
    @State private var showSignIn = false
    @State private var showIntro = !ProcessInfo.processInfo
        .arguments.contains("-auroraSkipIntro")

    var body: some View {
        ZStack {
            content
            if showIntro {
                BrandIntro { withAnimation(Theme.Motion.enter) { showIntro = false } }
                    .transition(.opacity)
            }
        }
        .auroraBackground()
        .fullScreenCover(isPresented: $showOnboarding) { OnboardingView() }
        .fullScreenCover(isPresented: $showSignIn) {
            NavigationStack { SignInView() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 26) {
                AuroraMark(width: 132)
                AuroraWordmark(size: 30)
            }
            Spacer()

            VStack(spacing: 14) {
                AuroraBadge(text: "Conta digital sem tarifa")
                Text("Seu dinheiro, sem ruído.")
                    .font(.auroraTitle).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("Conta, Pix, cartão e investimentos em um só lugar.")
                    .font(.auroraBody).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                PrimaryButton(title: "Abrir minha conta") { showOnboarding = true }
                SecondaryButton(title: "Já tenho conta") {
                    // Aparelho com PIN local: vai direto ao desbloqueio.
                    // Aparelho novo/reinstalado: pede CPF + PIN para logar na API.
                    if model.security.hasPIN() { model.phase = .locked }
                    else { showSignIn = true }
                }
            }
            .padding(Theme.Space.gutter)
            .padding(.top, Theme.Space.xl)
        }
    }
}

/// Abertura da marca: arco se desenha, onda entra, logotipo aparece.
/// Some sozinha depois de 2,6s, ou ao toque.
struct BrandIntro: View {
    var onFinish: () -> Void

    @State private var glow = false
    @State private var rings = false

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            // Horizonte que cresce por baixo.
            RadialGradient(
                colors: [Theme.blue.opacity(0.16), Theme.navy.opacity(0)],
                center: .bottom, startRadius: 0, endRadius: glow ? 520 : 200
            )
            .ignoresSafeArea()
            .animation(Theme.Motion.enter, value: glow)

            // Anéis concêntricos que se expandem.
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Theme.text2.opacity(0.22), lineWidth: 1)
                    .frame(width: 200, height: 200)
                    .scaleEffect(rings ? 2.6 : 0.6)
                    .opacity(rings ? 0 : 0.9)
                    .animation(
                        .timingCurve(0.2, 0.8, 0.2, 1, duration: 2.6)
                            .delay(0.9 + Double(i) * 0.5),
                        value: rings
                    )
            }

            VStack(spacing: 28) {
                AuroraMark(width: 140, animated: true)
                AuroraWordmark(size: 32)
                    .opacity(rings ? 1 : 0)
                    .animation(Theme.Motion.enter.delay(1.35), value: rings)
            }
            .offset(y: -30)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onFinish)
        .task {
            glow = true
            rings = true
            try? await Task.sleep(for: .milliseconds(2600))
            onFinish()
        }
        .accessibilityLabel("Aurora Bank")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Toque para pular a abertura")
    }
}
