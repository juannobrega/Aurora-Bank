import SwiftUI

/// A marca Aurora: um arco com gradiente azul → ciano, recortado por uma
/// onda. Portado do SVG do design system (viewBox 120×84).
struct AuroraMark: View {
    enum Mode { case color, mono, onLight }

    var width: CGFloat = 120
    var mode: Mode = .color
    /// Cor do "corte" entre arco e onda — deve casar com o fundo.
    var cutColor: Color = Theme.navy
    var animated = false

    @State private var arcProgress: CGFloat = 0
    @State private var waveProgress: CGFloat = 0

    private var height: CGFloat { width * 0.7 }
    private var scale: CGFloat { width / 120 }

    private var fill: AnyShapeStyle {
        switch mode {
        case .color:   AnyShapeStyle(Theme.brandGradient)
        case .mono:    AnyShapeStyle(Color.white)
        case .onLight: AnyShapeStyle(Theme.brandGradient)
        }
    }

    var body: some View {
        ZStack {
            // Arco superior, traçado de 14pt no viewBox original.
            ArcShape()
                .trim(from: 0, to: animated ? arcProgress : 1)
                .stroke(style: StrokeStyle(lineWidth: 14 * scale, lineCap: .butt))
                .fill(fill)
                // A onda recorta o arco, deixando o vão do design original.
                .overlay {
                    WaveShape()
                        .stroke(style: StrokeStyle(lineWidth: 7 * scale, lineJoin: .round))
                        .fill(cutColor)
                        .overlay { WaveShape().fill(cutColor) }
                }

            // Onda, desenhada por cima do vão.
            WaveShape()
                .fill(fill)
                .scaleEffect(animated ? waveProgress : 1, anchor: .center)
                .opacity(animated ? Double(waveProgress) : 1)
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Aurora Bank")
        .onAppear {
            guard animated else { return }
            withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 1.1)) { arcProgress = 1 }
            withAnimation(Theme.Motion.enter.delay(0.6)) { waveProgress = 1 }
        }
    }

    /// `M30 60 A31 31 0 1 1 92 60`
    private struct ArcShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 120
            var p = Path()
            p.addArc(
                center: CGPoint(x: 61 * s, y: 60 * s),
                radius: 31 * s,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            return p
        }
    }

    /// A onda do design system, convertida das curvas cúbicas do SVG.
    private struct WaveShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 120
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var p = Path()
            p.move(to: pt(3, 72))
            p.addCurve(to: pt(66, 57), control1: pt(22, 56), control2: pt(46, 50))
            p.addCurve(to: pt(116, 59), control1: pt(82, 63), control2: pt(98, 66))
            p.addCurve(to: pt(67, 69), control1: pt(104, 71), control2: pt(86, 75))
            p.addCurve(to: pt(3, 72), control1: pt(48, 63), control2: pt(27, 62))
            p.closeSubpath()
            return p
        }
    }
}

/// O logotipo "AURORA BANK", com o A desenhado como triângulo aberto.
struct AuroraWordmark: View {
    var size: CGFloat = 56
    var color: Color = .white
    var bankColor: Color = Color(hex: 0x8C9BFF)
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: size * 0.3) {
            HStack(alignment: .bottom, spacing: size * 0.1) {
                ForEach(Array("AURORA".enumerated()), id: \.offset) { _, ch in
                    if ch == "A" {
                        LetterA(color: color)
                            .frame(width: size * 0.74, height: size * 0.72)
                    } else {
                        Text(String(ch))
                            .font(.display(size, .medium))
                            .foregroundStyle(color)
                            .frame(height: size * 0.72)
                    }
                }
            }
            Text("BANK")
                .font(.display(size * 0.42, .medium))
                .tracking(size * 0.42 * 0.62)
                .foregroundStyle(bankColor)
                // Compensa o tracking do último caractere, como no CSS original.
                .padding(.trailing, -size * 0.42 * 0.62)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aurora Bank")
    }

    /// `polyline 5,70 37,4 69,70` — um "A" sem a barra horizontal.
    private struct LetterA: View {
        let color: Color
        var body: some View {
            GeometryReader { geo in
                let w = geo.size.width, hgt = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: 5 / 74 * w, y: 70 / 72 * hgt))
                    p.addLine(to: CGPoint(x: 37 / 74 * w, y: 4 / 72 * hgt))
                    p.addLine(to: CGPoint(x: 69 / 74 * w, y: 70 / 72 * hgt))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 9.5 / 74 * w, lineJoin: .miter))
            }
        }
    }
}

/// Lockup horizontal: marca + logotipo lado a lado.
struct AuroraLockup: View {
    var markWidth: CGFloat = 56
    var wordSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 14) {
            AuroraMark(width: markWidth)
            AuroraWordmark(size: wordSize, alignment: .leading)
        }
    }
}
