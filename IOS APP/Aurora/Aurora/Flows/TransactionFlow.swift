import Foundation

/// Passos possíveis de um fluxo transacional.
enum FlowStep: String, Hashable, Sendable {
    case recipient   // escolher destinatário / digitar chave ou código
    case amount      // digitar valor
    case confirm     // revisar
    case pin         // autorizar
    case done        // comprovante
}

/// Linha de revisão exibida na confirmação e no comprovante.
struct FlowRow: Identifiable, Hashable, Sendable {
    var id: String { label }
    let label: String
    let value: String
}

/// Resultado do commit: a transação registrada mais efeitos colaterais
/// já aplicados pelo fluxo no `AppModel`.
struct FlowResult: Sendable {
    var transaction: Transaction
    var doneTitle: String
    var doneSubtitle: String
}

/// Generaliza o motor `STEPS` do protótipo React.
///
/// Cada fluxo — Pix, investir, guardar, empréstimo, boleto, recarga —
/// declara seus passos e sua validação, e ganha toda a UI de graça:
/// teclado de valor, tela de revisão, PIN e comprovante.
protocol TransactionFlow: Identifiable, Sendable {
    var id: UUID { get }
    var kind: FlowKind { get }
    var title: String { get }
    var steps: [FlowStep] { get }

    /// Rótulo acima do teclado de valor ("Quanto enviar para Ana?").
    var amountPrompt: String { get }
    /// Rótulo na tela de revisão ("Você está enviando").
    var confirmPrompt: String { get }
    /// Texto do botão de confirmação.
    var confirmCallToAction: String { get }
    /// Valor exibido na revisão (para o empréstimo é o principal, não o digitado).
    func displayAmount(entered: Money) -> Money
    /// Linhas de revisão.
    func rows(entered: Money, context: FlowContext) -> [FlowRow]
    /// Valida o valor digitado. Devolve dica a exibir e se pode avançar.
    func validate(entered: Money, context: FlowContext) -> FlowValidation
    /// Aplica a transação. Muta o modelo (cofrinho, posição, parcelas...).
    @MainActor func commit(entered: Money, model: AppModel) -> FlowResult
}

enum FlowKind: String, Sendable {
    case pix, invest, goal, loan, boleto, recarga

    var symbol: String {
        switch self {
        case .pix: "arrow.left.arrow.right.circle.fill"
        case .invest: "chart.line.uptrend.xyaxis"
        case .goal: "banknote.fill"
        case .loan: "hand.raised.fill"
        case .boleto: "barcode"
        case .recarga: "antenna.radiowaves.left.and.right"
        }
    }
}

struct FlowValidation: Sendable {
    var hint: String
    var isValid: Bool
    var isWarning: Bool = false

    static func ok(_ hint: String) -> Self { .init(hint: hint, isValid: true) }
    static func fail(_ hint: String) -> Self { .init(hint: hint, isValid: false, isWarning: true) }
}

/// Contexto somente-leitura que os fluxos consultam para validar.
struct FlowContext: Sendable {
    var balance: Money
    var nightLimitEnabled: Bool
    var nightLimit: Money
    var isNightTime: Bool

    /// 20h–6h, mesma regra do protótipo.
    static func isNight(_ date: Date = .now) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return h >= 20 || h < 6
    }
}

// MARK: - Estado corrente de um fluxo em execução

@Observable
@MainActor
final class FlowSession {
    /// Mutável: passos como "escolher destinatário" e "ler boleto"
    /// substituem o fluxo por uma versão já preenchida.
    private(set) var flow: any TransactionFlow
    var step: FlowStep
    var centsText: String = ""
    var result: FlowResult?

    /// Destinatário resolvido (Pix) ou código lido (boleto).
    var recipientName: String = ""
    var recipientKey: String = ""

    init(flow: any TransactionFlow, startAt: FlowStep? = nil) {
        self.flow = flow
        self.step = startAt ?? flow.steps.first ?? .amount
    }

    var entered: Money { Money(cents: Int(centsText) ?? 0) }

    /// Substitui o fluxo pela versão com os dados coletados no passo atual
    /// (destinatário do Pix, boleto lido, número da recarga).
    func replaceFlow(_ new: any TransactionFlow) { flow = new }

    var canGoBack: Bool { step != .done }

    func appendDigit(_ d: String) {
        guard centsText.count < 9 else { return }
        let next = centsText + d
        centsText = next.drop { $0 == "0" }.isEmpty ? "" : String(next.drop { $0 == "0" })
    }

    func deleteDigit() { _ = centsText.popLast() }

    func advance() {
        guard let i = flow.steps.firstIndex(of: step), i + 1 < flow.steps.count else { return }
        step = flow.steps[i + 1]
    }

    /// Devolve `false` quando não há passo anterior — o chamador fecha o fluxo.
    func retreat() -> Bool {
        guard let i = flow.steps.firstIndex(of: step), i > 0 else { return false }
        step = flow.steps[i - 1]
        return true
    }
}
