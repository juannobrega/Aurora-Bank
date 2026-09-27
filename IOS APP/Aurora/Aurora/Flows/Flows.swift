import Foundation

// MARK: - Pix

struct PixFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .pix }
    var title: String { "Enviar Pix" }
    var steps: [FlowStep] { [.recipient, .amount, .confirm, .pin, .done] }

    var contact: Contact?
    var scheduledFor: Date?

    var amountPrompt: String {
        let who = contact?.firstName ?? "o destinatário"
        return "Quanto enviar para \(who)?"
    }
    var confirmPrompt: String { scheduledFor == nil ? "Você está enviando" : "Você vai agendar" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { entered }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        var rows = [
            FlowRow(label: "Para", value: contact?.name ?? "—"),
            FlowRow(label: "Chave", value: contact?.key ?? "—"),
            FlowRow(label: "Instituição", value: contact?.bank ?? "—"),
        ]
        if let scheduledFor {
            rows.append(FlowRow(label: "Quando", value: Self.dateText(scheduledFor)))
        } else {
            rows.append(FlowRow(label: "Quando", value: "Agora"))
        }
        return rows
    }

    func validate(entered v: Money, context ctx: FlowContext) -> FlowValidation {
        if v.isZero { return .init(hint: "Saldo disponível \(ctx.balance.formatted)", isValid: false) }
        if v > ctx.balance { return .fail("Saldo insuficiente") }
        if ctx.nightLimitEnabled, ctx.isNightTime, v > ctx.nightLimit {
            return .fail("Acima do limite noturno de \(ctx.nightLimit.formatted)")
        }
        return .ok("Saldo disponível \(ctx.balance.formatted)")
    }

    @MainActor
    func commit(entered v: Money, model: AppModel) -> FlowResult {
        let name = contact?.name ?? "Destinatário"
        let tx = Transaction(
            date: scheduledFor ?? .now,
            title: scheduledFor == nil ? "Pix enviado" : "Pix agendado",
            counterparty: name,
            amount: -v,
            category: .transferencia,
            method: .pix
        )
        model.ledger.record(tx)
        if let contact { model.rememberContact(contact) }
        return FlowResult(
            transaction: tx,
            doneTitle: scheduledFor == nil ? "Pix enviado" : "Pix agendado",
            doneSubtitle: "\(v.formatted) para \(name)"
        )
    }

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Investir

struct InvestFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .invest }
    var title: String { "Investir" }
    var steps: [FlowStep] { [.amount, .confirm, .pin, .done] }

    var product: InvestmentProduct

    var amountPrompt: String { "Quanto investir em \(product.name)?" }
    var confirmPrompt: String { "Você está investindo" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { entered }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Produto", value: product.name),
            FlowRow(label: "Rentabilidade", value: product.rate),
            FlowRow(label: "Liquidez", value: product.liquidity),
        ]
    }

    func validate(entered v: Money, context ctx: FlowContext) -> FlowValidation {
        if v.isZero { return .init(hint: "Saldo disponível \(ctx.balance.formatted)", isValid: false) }
        if v > ctx.balance { return .fail("Saldo insuficiente") }
        return .ok("Saldo disponível \(ctx.balance.formatted)")
    }

    @MainActor
    func commit(entered v: Money, model: AppModel) -> FlowResult {
        model.invest(v, in: product)
        let tx = Transaction(
            title: "Aplicação",
            counterparty: product.name,
            amount: -v,
            category: .investimento,
            method: .aplicacao
        )
        model.ledger.record(tx)
        return FlowResult(
            transaction: tx,
            doneTitle: "Investimento feito",
            doneSubtitle: "\(v.formatted) aplicados em \(product.name)"
        )
    }
}

// MARK: - Resgate de investimento (não existia no protótipo)

struct RedeemFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .invest }
    var title: String { "Resgatar" }
    var steps: [FlowStep] { [.amount, .confirm, .pin, .done] }

    var holding: Holding

    var amountPrompt: String { "Quanto resgatar de \(holding.product.name)?" }
    var confirmPrompt: String { "Você está resgatando" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { entered }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Produto", value: holding.product.name),
            FlowRow(label: "Disponível", value: holding.current.formatted),
            FlowRow(label: "Liquidez", value: holding.product.liquidity),
            FlowRow(label: "Restará", value: max(.zero, holding.current - entered).formatted),
        ]
    }

    func validate(entered v: Money, context ctx: FlowContext) -> FlowValidation {
        if v.isZero { return .init(hint: "Disponível \(holding.current.formatted)", isValid: false) }
        if v > holding.current { return .fail("Valor acima do disponível") }
        return .ok("Disponível \(holding.current.formatted)")
    }

    @MainActor
    func commit(entered v: Money, model: AppModel) -> FlowResult {
        model.redeem(v, from: holding.id)
        let tx = Transaction(
            title: "Resgate",
            counterparty: holding.product.name,
            amount: v,
            category: .investimento,
            method: .aplicacao
        )
        model.ledger.record(tx)
        return FlowResult(
            transaction: tx,
            doneTitle: "Resgate concluído",
            doneSubtitle: "\(v.formatted) de volta na sua conta"
        )
    }
}

// MARK: - Cofrinho: guardar

struct GoalDepositFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .goal }
    var title: String { "Guardar" }
    var steps: [FlowStep] { [.amount, .confirm, .pin, .done] }

    var goal: Goal

    var amountPrompt: String { "Quanto guardar em \(goal.name)?" }
    var confirmPrompt: String { "Você está guardando" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { entered }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Cofrinho", value: goal.name),
            FlowRow(label: "Novo total", value: (goal.saved + entered).formatted),
            FlowRow(label: "Meta", value: goal.target.formatted),
        ]
    }

    func validate(entered v: Money, context ctx: FlowContext) -> FlowValidation {
        if v.isZero { return .init(hint: "Saldo disponível \(ctx.balance.formatted)", isValid: false) }
        if v > ctx.balance { return .fail("Saldo insuficiente") }
        return .ok("Saldo disponível \(ctx.balance.formatted)")
    }

    @MainActor
    func commit(entered v: Money, model: AppModel) -> FlowResult {
        model.deposit(v, to: goal.id)
        let tx = Transaction(
            title: "Guardado no cofrinho",
            counterparty: goal.name,
            amount: -v,
            category: .investimento,
            method: .cofrinho
        )
        model.ledger.record(tx)
        return FlowResult(
            transaction: tx,
            doneTitle: "Dinheiro guardado",
            doneSubtitle: "\(v.formatted) em \(goal.name)"
        )
    }
}

// MARK: - Cofrinho: resgatar (não existia no protótipo)

struct GoalWithdrawFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .goal }
    var title: String { "Resgatar do cofrinho" }
    var steps: [FlowStep] { [.amount, .confirm, .pin, .done] }

    var goal: Goal

    var amountPrompt: String { "Quanto tirar de \(goal.name)?" }
    var confirmPrompt: String { "Você está resgatando" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { entered }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Cofrinho", value: goal.name),
            FlowRow(label: "Guardado", value: goal.saved.formatted),
            FlowRow(label: "Restará", value: max(.zero, goal.saved - entered).formatted),
        ]
    }

    func validate(entered v: Money, context ctx: FlowContext) -> FlowValidation {
        if v.isZero { return .init(hint: "Guardado \(goal.saved.formatted)", isValid: false) }
        if v > goal.saved { return .fail("Valor acima do que está guardado") }
        return .ok("Guardado \(goal.saved.formatted)")
    }

    @MainActor
    func commit(entered v: Money, model: AppModel) -> FlowResult {
        model.withdraw(v, from: goal.id)
        let tx = Transaction(
            title: "Resgate do cofrinho",
            counterparty: goal.name,
            amount: v,
            category: .investimento,
            method: .cofrinho
        )
        model.ledger.record(tx)
        return FlowResult(
            transaction: tx,
            doneTitle: "Dinheiro resgatado",
            doneSubtitle: "\(v.formatted) de volta na conta"
        )
    }
}

// MARK: - Empréstimo
//
// Diferente do protótipo: contratar agora gera parcelas reais (`Loan`),
// que aparecem em Crédito e podem ser pagas.

struct LoanFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .loan }
    var title: String { product.name }
    var steps: [FlowStep] { [.confirm, .pin, .done] }

    var product: CreditProduct = .find("pessoal")
    var principal: Money
    var months: Int
    var monthlyRate: Decimal { product.monthlyRate }

    var amountPrompt: String { "" }
    var confirmPrompt: String { "Você vai receber" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    var payment: Money {
        Loan.payment(principal: principal, monthlyRate: monthlyRate, months: months)
    }

    func displayAmount(entered: Money) -> Money { principal }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Produto", value: product.name),
            FlowRow(label: "Parcelas", value: "\(months)x de \(payment.formatted)"),
            FlowRow(label: "Taxa", value: product.rateLabel),
            FlowRow(label: "Total a pagar", value: (payment * Decimal(months)).formatted),
            FlowRow(label: "1ª parcela", value: PixFlow.dateText(Self.firstDueDate())),
        ]
    }

    func validate(entered: Money, context: FlowContext) -> FlowValidation {
        .ok("")
    }

    @MainActor
    func commit(entered: Money, model: AppModel) -> FlowResult {
        let loan = model.contractLoan(principal: principal, months: months, monthlyRate: monthlyRate)
        let tx = Transaction(
            title: product.name,
            counterparty: "\(months)x de \(payment.formatted)",
            amount: principal,
            category: .credito,
            method: .emprestimo
        )
        model.ledger.record(tx)
        _ = loan
        return FlowResult(
            transaction: tx,
            doneTitle: "Crédito em análise",
            doneSubtitle: "Seu pedido de \(principal.formatted) foi enviado para análise."
        )
    }

    static func firstDueDate() -> Date {
        Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    }
}

// MARK: - Boleto (ausente por completo no protótipo)

struct BoletoFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .boleto }
    var title: String { "Pagar boleto" }
    var steps: [FlowStep] { [.recipient, .confirm, .pin, .done] }

    var barcode: String = ""
    var payee: String = ""
    var amount: Money = .zero
    var dueDate: Date = .now
    var category: Category = .outros

    var amountPrompt: String { "Valor do boleto" }
    var confirmPrompt: String { "Você está pagando" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { amount }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Beneficiário", value: payee),
            FlowRow(label: "Vencimento", value: PixFlow.dateText(dueDate)),
            FlowRow(label: "Código", value: Self.shortCode(barcode)),
            FlowRow(label: "Quando", value: "Agora"),
        ]
    }

    func validate(entered: Money, context ctx: FlowContext) -> FlowValidation {
        amount > ctx.balance
            ? .fail("Saldo insuficiente")
            : .ok("Saldo disponível \(ctx.balance.formatted)")
    }

    @MainActor
    func commit(entered: Money, model: AppModel) -> FlowResult {
        let tx = Transaction(
            title: "Pagamento de boleto",
            counterparty: payee,
            amount: -amount,
            category: category,
            method: .boleto
        )
        model.ledger.record(tx)
        return FlowResult(
            transaction: tx,
            doneTitle: "Boleto pago",
            doneSubtitle: "\(amount.formatted) para \(payee)"
        )
    }

    static func shortCode(_ code: String) -> String {
        let digits = code.filter(\.isNumber)
        guard digits.count > 12 else { return code }
        return "\(digits.prefix(5))…\(digits.suffix(6))"
    }
}

// MARK: - Recarga de celular (ausente no protótipo)

struct RecargaFlow: TransactionFlow {
    let id = UUID()
    var kind: FlowKind { .recarga }
    var title: String { "Recarga de celular" }
    var steps: [FlowStep] { [.recipient, .amount, .confirm, .pin, .done] }

    var phone: String = ""
    var carrier: String = ""

    var amountPrompt: String { "Quanto recarregar?" }
    var confirmPrompt: String { "Você está recarregando" }
    var confirmCallToAction: String { "Confirmar com PIN" }

    func displayAmount(entered: Money) -> Money { entered }

    func rows(entered: Money, context: FlowContext) -> [FlowRow] {
        [
            FlowRow(label: "Número", value: phone),
            FlowRow(label: "Operadora", value: carrier),
            FlowRow(label: "Quando", value: "Agora"),
        ]
    }

    func validate(entered v: Money, context ctx: FlowContext) -> FlowValidation {
        if v.isZero { return .init(hint: "Escolha um valor", isValid: false) }
        if v > ctx.balance { return .fail("Saldo insuficiente") }
        return .ok("Saldo disponível \(ctx.balance.formatted)")
    }

    @MainActor
    func commit(entered v: Money, model: AppModel) -> FlowResult {
        let tx = Transaction(
            title: "Recarga de celular",
            counterparty: "\(carrier) · \(phone)",
            amount: -v,
            category: .outros,
            method: .recarga
        )
        model.ledger.record(tx)
        return FlowResult(
            transaction: tx,
            doneTitle: "Recarga feita",
            doneSubtitle: "\(v.formatted) para \(phone)"
        )
    }
}
