import SwiftUI

// MARK: - Superfícies

struct AuroraCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.gutter
    var radius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface1, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius).stroke(Theme.line, lineWidth: 1)
            )
    }
}

// MARK: - Botões

struct PrimaryButton: View {
    let title: String
    var icon: String?
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                Text(title).font(.display(16, .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.actionGradient, in: .rect(cornerRadius: Theme.Radius.icon))
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0.38)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16)) }
                Text(title).font(.display(16, .regular))
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.surface2, in: .rect(cornerRadius: Theme.Radius.icon))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.icon)
                    .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressStyle())
    }
}

struct DestructiveButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.display(16, .regular))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.danger.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.icon))
        }
        .buttonStyle(PressStyle())
    }
}

/// Botão circular de ícone usado nos cabeçalhos.
struct IconButton: View {
    let symbol: String
    var label: String
    var badge = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(Theme.surface1, in: .circle)
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Theme.cyan)
                            .frame(width: 9, height: 9)
                            .offset(x: -2, y: 2)
                    }
                }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Theme.Motion.tap, value: configuration.isPressed)
    }
}

// MARK: - Cabeçalho

struct ScreenHeader: View {
    let title: String
    var trailing: AnyView?
    @Environment(\.dismiss) private var dismiss

    init(_ title: String) { self.title = title; self.trailing = nil }

    init<T: View>(_ title: String, @ViewBuilder trailing: () -> T) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "chevron.left", label: "Voltar") { dismiss() }
            Text(title).font(.auroraHeadline).foregroundStyle(Theme.text)
            Spacer()
            trailing
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 12)
        .background(Theme.navy)
    }
}

// MARK: - Chips e segmentos

struct SegmentedPicker<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let on = selection == opt.value
                Button {
                    withAnimation(Theme.Motion.snap) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(.auroraLabel)
                        .foregroundStyle(on ? Theme.text : Theme.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(on ? Theme.surface3 : .clear, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.icon).stroke(Theme.line, lineWidth: 1)
        )
    }
}

struct FilterChips<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { opt in
                let on = selection == opt.value
                Button {
                    withAnimation(Theme.Motion.snap) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(.auroraLabel)
                        .foregroundStyle(on ? .white : Theme.text2)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if on {
                                Capsule().fill(Theme.blue)
                            } else {
                                Capsule().stroke(Theme.line, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Etiqueta de estado: "Conta digital", "Vence amanhã", "Bloqueado".
struct AuroraBadge: View {
    let text: String
    var color: Color = Theme.cyan

    var body: some View {
        Text(text)
            .font(.display(12, .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(color.tinted, in: .capsule)
    }
}

// MARK: - Linhas

struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.text
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.auroraBody).foregroundStyle(Theme.text2)
                Spacer(minLength: 16)
                Text(value).font(.auroraBody).foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 13)
            if showsDivider { Divider().overlay(Theme.line) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Conteúdo de linha navegável — o ícone ganha o tom da sua categoria.
struct ActionRowLabel: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = Theme.text2
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.tinted, in: .rect(cornerRadius: Theme.Radius.icon))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.auroraBody).foregroundStyle(Theme.text)
                    if let subtitle {
                        Text(subtitle).font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.vertical, 11)
            if showsDivider { Divider().overlay(Theme.line) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct ActionRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = Theme.text2
    var showsDivider = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionRowLabel(symbol: symbol, title: title, subtitle: subtitle,
                           tint: tint, showsDivider: showsDivider)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progresso

struct ProgressBar: View {
    var value: Double
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.brandGradient)
    var height: CGFloat = 8

    init(value: Double, height: CGFloat = 8) {
        self.value = value
        self.height = height
    }

    init(value: Double, color: Color, height: CGFloat = 8) {
        self.value = value
        self.tint = AnyShapeStyle(color)
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface3)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(Theme.Motion.snap, value: value)
    }
}

// MARK: - Estado vazio

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(Theme.text3)
            Text(title).font(.auroraBody).foregroundStyle(Theme.text)
            if let message {
                Text(message)
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.auroraLabel)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Theme.surface2, in: .capsule)
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Fundo

/// Fundo navy com o "horizonte" da marca: um brilho radial azul embaixo.
struct AuroraBackground: ViewModifier {
    var showsHorizon = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Theme.navy
                    if showsHorizon {
                        RadialGradient(
                            colors: [Theme.blue.opacity(0.16), Theme.navy.opacity(0)],
                            center: .bottom, startRadius: 0, endRadius: 420
                        )
                        .allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func auroraBackground(horizon: Bool = false) -> some View {
        modifier(AuroraBackground(showsHorizon: horizon))
    }
}
