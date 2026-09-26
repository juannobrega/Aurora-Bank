import SwiftUI

/// Tokens do Aurora Bank Design System.
///
/// Base navy com gradiente azul → ciano da marca, mais um espectro de cores
/// usado **apenas em dados** (categorias, metas, gráficos). Os nomes espelham
/// os tokens `--au-*` do design system para que a conversa entre design e
/// código use o mesmo vocabulário.
enum Theme {

    // MARK: Marca — azul para ação, ciano só para positivo e foco

    /// `--au-navy` — fundo da aplicação.
    static let navy    = Color(hex: 0x070B1E)
    /// `--au-blue` — cor de ação primária.
    static let blue    = Color(hex: 0x2447F5)
    /// `--au-sky` — meio do gradiente da marca; também `--au-info`.
    static let sky     = Color(hex: 0x2E8BFF)
    /// `--au-cyan` — fim do gradiente; também `--au-positive`.
    static let cyan    = Color(hex: 0x25E2D6)

    // MARK: Neutros — superfícies em camadas e texto

    /// `--au-surface-1` — cartões e barra flutuante.
    static let surface1 = Color(hex: 0x0F1530)
    /// `--au-surface-2` — superfície elevada, base do shimmer.
    static let surface2 = Color(hex: 0x161E42)
    /// `--au-surface-3` — controles e segmentos ativos.
    static let surface3 = Color(hex: 0x222B5A)
    /// Linha divisória e bordas de cartão.
    static let line     = Color(hex: 0x1A2250)

    /// `--au-text` — texto primário.
    static let text  = Color(hex: 0xF2F4FF)
    /// `--au-text-2` — texto secundário.
    static let text2 = Color(hex: 0x9AA3DB)
    /// `--au-text-3` — texto terciário e placeholders.
    static let text3 = Color(hex: 0x5C66A3)

    // MARK: Semânticas

    static let positive = cyan
    static let danger   = Color(hex: 0xFF6B81)
    static let warning  = Color(hex: 0xFFB547)
    static let info     = sky

    // MARK: Espectro — SÓ em dados: categorias, metas e gráficos

    enum Spectrum {
        static let cyan   = Color(hex: 0x3CCFC4)
        static let sky    = Color(hex: 0x4C8DF6)
        static let violet = Color(hex: 0x8C86E8)
        static let pink   = Color(hex: 0xD98AB0)
        static let amber  = Color(hex: 0xE3AE5B)
        static let lime   = Color(hex: 0x8CCB7A)
        static let coral  = Color(hex: 0xE08A72)
        static let ice    = Color(hex: 0x8FA7E0)

        static let all: [Color] = [cyan, sky, violet, pink, amber, lime, coral, ice]

        static func named(_ name: String) -> Color {
            switch name {
            case "cyan": cyan
            case "sky": sky
            case "violet": violet
            case "pink": pink
            case "amber": amber
            case "lime": lime
            case "coral": coral
            default: ice
            }
        }
    }

    // MARK: Gradientes

    /// Gradiente da marca: azul → céu → ciano.
    static let brandGradient = LinearGradient(
        stops: [
            .init(color: blue, location: 0),
            .init(color: sky, location: 0.55),
            .init(color: cyan, location: 1),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    /// `--au-grad-card` — face do cartão.
    static let cardGradient = LinearGradient(
        colors: [Color(hex: 0x1F3BD6), Color(hex: 0x13206E)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Gradiente de ação para botões primários.
    static let actionGradient = LinearGradient(
        colors: [blue, Color(hex: 0x1F3BD6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Raios

    enum Radius {
        static let icon: CGFloat = 14
        static let tile: CGFloat = 20
        static let card: CGFloat = 24
        static let hero: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: Espaçamento

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let gutter: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    // MARK: Motion

    enum Motion {
        /// Entrada de elementos e transições de tela.
        static let enter = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42)
        /// Mudança de estado em controles.
        static let snap = Animation.timingCurve(0.3, 0.8, 0.2, 1, duration: 0.26)
        /// Microinteração de toque.
        static let tap = Animation.easeOut(duration: 0.14)
    }
}

// MARK: - Cor por hex

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Fundo tingido a 10%, como o design system prescreve para o espectro.
    var tinted: Color { opacity(0.10) }
}

// MARK: - Tipografia
//
// Escala do design system: Display XL 46/500 · Valor 40/400 · Título 32/500 ·
// Headline 20/400 · Corpo 15/400 · Legenda 13/400 · Mono 20/400.
// Usamos as fontes do sistema (`.rounded` aproxima a Outfit) para que o
// Dynamic Type continue funcionando — algo que o protótipo web não tinha.

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let auroraDisplayXL = display(46, .medium)
    static let auroraTitle     = display(32, .medium)
    static let auroraHeadline  = display(20, .regular)
    static let auroraBody      = display(15, .regular)
    static let auroraCaption   = display(13, .regular)
    static let auroraLabel     = display(13, .medium)

    /// Valores monetários grandes (saldo, patrimônio).
    static let auroraValue  = mono(40, .regular)
    /// Valores em linhas de lista e comprovantes.
    static let auroraAmount = mono(17, .regular)
    /// Número de cartão e códigos.
    static let auroraMono   = mono(20, .regular)
}
