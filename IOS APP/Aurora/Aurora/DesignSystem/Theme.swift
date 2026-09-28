import SwiftUI

/// Tokens do Aurora Bank Design System.
///
/// Base navy com gradiente azul → ciano da marca, mais um espectro de cores
/// usado **apenas em dados** (categorias, metas, gráficos). Os nomes espelham
/// os tokens `--au-*` do design system para que a conversa entre design e
/// código use o mesmo vocabulário.
enum Theme {

    // MARK: Marca — azul para ação, ciano só para positivo e foco

    /// Fundo da aplicação — quase preto azulado, sóbrio.
    static let navy    = Color(hex: 0x0B0E14)
    /// Cor de ação primária — azul institucional, não vibrante.
    static let blue    = Color(hex: 0x2D5BD6)
    /// Azul de apoio (links, foco).
    static let sky     = Color(hex: 0x4B7BE5)
    /// Acento pontual (positivo, destaque) — verde-azulado discreto.
    static let cyan    = Color(hex: 0x3BA88F)

    // MARK: Neutros — superfícies em camadas e texto

    /// Cartões e barra — cinza-azulado escuro, pouca saturação.
    static let surface1 = Color(hex: 0x141821)
    /// Superfície elevada.
    static let surface2 = Color(hex: 0x1C212C)
    /// Controles e segmentos ativos.
    static let surface3 = Color(hex: 0x2A303D)
    /// Linha divisória e bordas — sutil.
    static let line     = Color(hex: 0x252A36)

    /// Texto primário — branco levemente quente, não puro.
    static let text  = Color(hex: 0xEDEFF3)
    /// Texto secundário — cinza neutro.
    static let text2 = Color(hex: 0x9BA1AD)
    /// Texto terciário e placeholders.
    static let text3 = Color(hex: 0x616773)

    // MARK: Semânticas — cores de estado, sóbrias

    static let positive = Color(hex: 0x4CAF82)
    static let danger   = Color(hex: 0xE05260)
    static let warning  = Color(hex: 0xD9A03C)
    static let info     = sky

    // MARK: Espectro — SÓ em dados: categorias, metas e gráficos

    enum Spectrum {
        static let cyan   = Color(hex: 0x3BA88F)
        static let sky    = Color(hex: 0x4B7BE5)
        static let violet = Color(hex: 0x7C74C4)
        static let pink   = Color(hex: 0xC07A9C)
        static let amber  = Color(hex: 0xC79A45)
        static let lime   = Color(hex: 0x6FA85E)
        static let coral  = Color(hex: 0xC77A64)
        static let ice    = Color(hex: 0x7E8BA6)

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

    // MARK: Superfícies de destaque
    //
    // Sem gradiente vibrante — bancos sérios usam cor chapada. O "gradiente"
    // da marca é só o azul institucional sólido; o cartão ganha um degradê
    // discreto para dar profundidade sem parecer demo.

    static let brandGradient = LinearGradient(colors: [blue, blue],
        startPoint: .leading, endPoint: .trailing)

    static let actionGradient = LinearGradient(colors: [blue, blue],
        startPoint: .leading, endPoint: .trailing)

    /// Face do cartão: degradê sóbrio, tons de grafite/azul profundo.
    static let cardGradient = LinearGradient(
        colors: [Color(hex: 0x232A3A), Color(hex: 0x14181F)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Raios

    enum Radius {
        static let icon: CGFloat = 10
        static let tile: CGFloat = 12
        static let card: CGFloat = 14
        static let hero: CGFloat = 16
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
