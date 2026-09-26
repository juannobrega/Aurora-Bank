import SwiftUI

// MARK: - Sparkline

/// Linha de tendência sob o saldo, com área tingida e ponto na ponta.
struct Sparkline: View {
    var values: [Double]
    var animated = true

    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack(alignment: .topLeading) {
                // Área sob a curva.
                path(pts, closedIn: geo.size)
                    .fill(
                        LinearGradient(
                            colors: [Theme.cyan.opacity(0.10), Theme.cyan.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                // A curva.
                path(pts, closedIn: nil)
                    .trim(from: 0, to: animated ? progress : 1)
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // Ponto na extremidade.
                if let last = pts.last {
                    Circle()
                        .fill(Theme.cyan)
                        .frame(width: 8, height: 8)
                        .position(last)
                        .opacity(animated ? Double(progress) : 1)
                }
            }
        }
        .frame(height: 56)
        .accessibilityHidden(true)
        .onAppear {
            guard animated else { return }
            withAnimation(.timingCurve(0.3, 0.8, 0.2, 1, duration: 1.4)) { progress = 1 }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = hi - lo == 0 ? 1 : hi - lo
        return values.enumerated().map { i, v in
            CGPoint(
                x: CGFloat(i) / CGFloat(values.count - 1) * size.width,
                y: size.height - CGFloat((v - lo) / span) * (size.height - 10) - 5
            )
        }
    }

    /// Curva suavizada por Catmull-Rom convertida em cúbicas.
    private func path(_ pts: [CGPoint], closedIn size: CGSize?) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for i in 1..<pts.count {
            let prev = pts[i - 1], cur = pts[i]
            let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
            p.addQuadCurve(to: mid, control: prev)
            p.addQuadCurve(to: cur, control: CGPoint(x: (mid.x + cur.x) / 2, y: cur.y))
        }
        if let size, let last = pts.last {
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.addLine(to: CGPoint(x: first.x, y: size.height))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Skeleton

/// Placeholder de lista com brilho deslizante, para o carregamento inicial.
struct SkeletonRows: View {
    var count = 3
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    shimmer.frame(width: 40, height: 40)
                        .clipShape(.rect(cornerRadius: Theme.Radius.icon))
                    VStack(alignment: .leading, spacing: 7) {
                        shimmer.frame(height: 10).frame(maxWidth: .infinity, alignment: .leading)
                            .clipShape(.capsule)
                        shimmer.frame(width: 110, height: 9).clipShape(.capsule)
                    }
                    Spacer(minLength: 12)
                    shimmer.frame(width: 64, height: 12).clipShape(.capsule)
                }
                .padding(.vertical, 9)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
        .accessibilityLabel("Carregando")
    }

    private var shimmer: some View {
        Theme.surface2.overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Theme.surface3.opacity(0.9), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.4)
                .offset(x: phase * geo.size.width)
            }
        }
        .clipped()
    }
}

// MARK: - Contador

/// Valor monetário que sobe do zero ao abrir a tela.
struct AnimatedMoney: View {
    let value: Money
    var font: Font = .auroraValue
    var hidden = false

    @State private var shown: Decimal = 0

    var body: some View {
        Text(hidden ? "••••" : Money(shown).formatted)
            .font(font)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear { animate(to: value.amount) }
            .onChange(of: value) { _, new in animate(to: new.amount) }
            .onChange(of: hidden) { _, _ in shown = value.amount }
    }

    private func animate(to target: Decimal) {
        guard !hidden else { shown = target; return }
        shown = 0
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.1)) { shown = target }
    }
}

// MARK: - Sucesso

/// Selo de confirmação: círculo com gradiente e um "check" que se desenha.
struct SuccessMark: View {
    var size: CGFloat = 76
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: ring)
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.42, height: size * 0.32)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)) { ring = 1 }
            withAnimation(.timingCurve(0.3, 0.8, 0.2, 1, duration: 0.4).delay(0.32)) { check = 1 }
        }
        .accessibilityHidden(true)
    }

    private struct CheckShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: r.height * 0.55))
            p.addLine(to: CGPoint(x: r.width * 0.38, y: r.height))
            p.addLine(to: CGPoint(x: r.width, y: 0))
            return p
        }
    }
}

// MARK: - Loader

/// Órbita de processamento, usada enquanto a transação é autorizada.
struct OrbitLoader: View {
    var size: CGFloat = 54
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
        .accessibilityLabel("Processando")
    }
}

/// Três pontos pulsando, para carregamento inline.
struct DotsLoader: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.text2)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.32)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(.easeInOut(duration: 0.24)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("Carregando")
    }
}
