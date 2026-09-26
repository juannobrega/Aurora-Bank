import SwiftUI

/// Teclado numérico reutilizado pelo PIN e pela digitação de valores.
struct Keypad: View {
    enum Key: Hashable {
        case digit(String), delete, biometry, blank
    }

    var showsBiometry = false
    var onKey: (Key) -> Void

    private var keys: [Key] {
        [.digit("1"), .digit("2"), .digit("3"),
         .digit("4"), .digit("5"), .digit("6"),
         .digit("7"), .digit("8"), .digit("9"),
         showsBiometry ? .biometry : .blank, .digit("0"), .delete]
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                keyButton(key)
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        switch key {
        case .blank:
            Color.clear.frame(height: 58)
        case .digit(let d):
            Button {
                Haptics.tap()
                onKey(key)
            } label: {
                Text(d)
                    .font(.mono(24, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel(d)
        case .delete:
            Button {
                Haptics.tap()
                onKey(key)
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel("Apagar")
        case .biometry:
            Button {
                Haptics.tap()
                onKey(key)
            } label: {
                Image(systemName: "faceid")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.cyan)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel("Entrar com Face ID")
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Os 4 pontos do PIN, com animação de erro (shake).
struct PinDots: View {
    let filled: Int
    var total = 4
    var isError = false

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < filled ? (isError ? Theme.danger : Theme.cyan) : .clear)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(
                            i < filled ? (isError ? Theme.danger : Theme.cyan) : Theme.line,
                            lineWidth: 1.5
                        )
                    )
                    .animation(.snappy(duration: 0.15), value: filled)
            }
        }
        .modifier(ShakeEffect(shakes: isError ? 1 : 0))
        .animation(.linear(duration: 0.4), value: isError)
        .accessibilityLabel("\(filled) de \(total) dígitos informados")
    }
}

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 9 * sin(shakes * .pi * 4), y: 0)
        )
    }
}

// MARK: - Háptica

enum Haptics {
    @MainActor static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    @MainActor static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    @MainActor static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
