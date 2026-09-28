import SwiftUI

struct CreditView: View {
    @Environment(AppModel.self) private var model
    @State private var product: CreditProduct = .find("pessoal")
    @State private var principal: Double = 5_000
    @State private var months = 12
    @State private var activeFlow: FlowPresentation?

    private var rate: Decimal { product.monthlyRate }
    private var payment: Money {
        Loan.payment(principal: Money(Decimal(principal)), monthlyRate: rate, months: months)
    }
    private var minAmt: Double { NSDecimalNumber(decimal: product.minAmount.amount).doubleValue }
    private var maxAmt: Double { NSDecimalNumber(decimal: product.maxAmount.amount).doubleValue }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                scoreCard
                if !model.loans.isEmpty { contractsSection }
                productList
                simulator
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Crédito") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .flowSheet($activeFlow)
    }

    // MARK: Produtos de crédito

    private var productList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Produtos de crédito").font(.auroraLabel).foregroundStyle(Theme.text2)
            ForEach(CreditProduct.all) { p in
                Button {
                    withAnimation(Theme.Motion.snap) {
                        product = p
                        // Reenquadra valor e prazo nos limites do produto.
                        principal = min(max(principal, minAmtOf(p)), maxAmtOf(p))
                        months = min(months, p.maxMonths)
                    }
                } label: { productRow(p) }
                .buttonStyle(.plain)
            }
        }
    }

    private func productRow(_ p: CreditProduct) -> some View {
        let selected = p.id == product.id
        return HStack(spacing: 13) {
            Image(systemName: p.symbol)
                .font(.system(size: 16)).foregroundStyle(Theme.text2)
                .frame(width: 44, height: 44)
                .background(Theme.surface2, in: .rect(cornerRadius: Theme.Radius.icon))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.auroraBody).foregroundStyle(Theme.text)
                Text(p.rateLabel + " · até " + String(p.maxMonths) + "x")
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected ? Theme.blue : Theme.text3)
        }
        .padding(14)
        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
            .stroke(selected ? Theme.blue : Theme.line, lineWidth: selected ? 1.5 : 1))
    }

    /// Opções de prazo até o máximo do produto.
    private var termOptions: [Int] {
        [6, 12, 24, 36, 48, 60].filter { $0 <= product.maxMonths }
    }

    private func minAmtOf(_ p: CreditProduct) -> Double {
        NSDecimalNumber(decimal: p.minAmount.amount).doubleValue
    }
    private func maxAmtOf(_ p: CreditProduct) -> Double {
        NSDecimalNumber(decimal: p.maxAmount.amount).doubleValue
    }

    // MARK: Score

    private var scoreCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Seu score").font(.auroraLabel).foregroundStyle(Theme.text2)
                    Spacer()
                    AuroraBadge(text: scoreLabel, color: scoreColor)
                }
                Text("\(model.creditScore)")
                    .font(.mono(38, .regular)).foregroundStyle(Theme.text)
                ProgressBar(value: Double(model.creditScore) / 1000)
                Text("Nenhuma pendência no seu CPF.")
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score de crédito \(model.creditScore), \(scoreLabel)")
    }

    private var scoreColor: Color {
        switch model.creditScore {
        case 700...: Theme.cyan
        case 500..<700: Theme.warning
        default: Theme.danger
        }
    }

    private var scoreLabel: String {
        switch model.creditScore {
        case 800...: "Excelente"
        case 700..<800: "Bom"
        case 500..<700: "Regular"
        default: "Baixo"
        }
    }

    // MARK: Contratos ativos

    private var contractsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Seus contratos").font(.auroraLabel).foregroundStyle(Theme.text2)
            ForEach(model.loans) { loan in
                NavigationLink(value: Route.loanDetail(loan.id)) {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Empréstimo pessoal")
                                    .font(.auroraBody).foregroundStyle(Theme.text)
                                Spacer()
                                Text(loan.isSettled ? "Quitado" : "\(loan.paidCount)/\(loan.installments.count)")
                                    .font(.auroraCaption)
                                    .foregroundStyle(loan.isSettled ? Theme.cyan : Theme.text2)
                            }
                            Text("Saldo devedor \(loan.outstanding.formatted)")
                                .font(.auroraAmount).foregroundStyle(Theme.text)
                            ProgressBar(
                                value: Double(loan.paidCount) / Double(max(1, loan.installments.count))
                            )
                            if let next = loan.nextDue {
                                Text("Próxima em \(HomeView.dayMonth(next.dueDate)) · \(next.amount.formatted)")
                                    .font(.auroraCaption)
                                    .foregroundStyle(next.isOverdue ? Theme.danger : Theme.text2)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Simulador

    private var simulator: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(product.name)
                    .font(.auroraHeadline).foregroundStyle(Theme.text)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quanto você precisa?").font(.auroraLabel).foregroundStyle(Theme.text2)
                    Text(Money(Decimal(principal)).formatted)
                        .font(.mono(26, .semibold)).foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Slider(value: $principal, in: minAmt...maxAmt,
                           step: minAmt >= 1000 ? 1000 : 500).tint(Theme.blue)
                    Text("De \(product.minAmount.formatted) a \(product.maxAmount.formatted)")
                        .font(.auroraCaption).foregroundStyle(Theme.text3)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Em quantas parcelas?").font(.auroraLabel).foregroundStyle(Theme.text2)
                    HStack(spacing: 8) {
                        ForEach(termOptions, id: \.self) { n in
                            let on = months == n
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { months = n }
                            } label: {
                                Text("\(n)x")
                                    .font(.auroraLabel)
                                    .foregroundStyle(on ? .white : Theme.text)
                                    .frame(maxWidth: .infinity).frame(height: 40)
                                    .background(on ? Theme.blue : .clear, in: .rect(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(on ? Theme.blue : Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 0) {
                    DetailRow(label: "Parcela", value: payment.formatted)
                    DetailRow(label: "Taxa", value: product.rateLabel)
                    DetailRow(label: "Total", value: (payment * Decimal(months)).formatted,
                              showsDivider: false)
                }

                PrimaryButton(title: "Pedir análise") {
                    activeFlow = .init(flow: LoanFlow(
                        product: product,
                        principal: Money(Decimal(principal)),
                        months: months
                    ))
                }
            }
        }
    }
}

/// Detalhe do contrato com as parcelas — inexistente no protótipo, que
/// creditava o dinheiro sem nunca gerar dívida.
struct LoanDetailView: View {
    @Environment(AppModel.self) private var model
    let loan: Loan

    /// Relê do modelo para refletir parcelas pagas durante a sessão.
    private var current: Loan {
        model.loans.first { $0.id == loan.id } ?? loan
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Saldo devedor").font(.auroraLabel).foregroundStyle(Theme.text2)
                        AnimatedMoney(value: current.outstanding, font: .mono(30, .regular))
                        ProgressBar(
                            value: Double(current.paidCount) / Double(max(1, current.installments.count))
                        )
                        Text("\(current.paidCount) de \(current.installments.count) parcelas pagas")
                            .font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                }

                AuroraCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Valor contratado", value: current.principal.formatted)
                        DetailRow(label: "Taxa", value: "2,49% a.m.")
                        DetailRow(label: "Contratado em",
                                  value: PixFlow.dateText(current.contractedAt),
                                  showsDivider: false)
                    }
                }

                if let next = current.nextDue {
                    PrimaryButton(title: "Pagar parcela \(next.number) · \(next.amount.formatted)") {
                        _ = model.payNextInstallment(of: current.id)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.cyan)
                        Text("Contrato quitado").font(.auroraBody).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Parcelas").font(.auroraLabel).foregroundStyle(Theme.text2)
                    AuroraCard(padding: 12) {
                        VStack(spacing: 0) {
                            ForEach(Array(current.installments.enumerated()), id: \.element.id) { i, inst in
                                installmentRow(inst, divider: i < current.installments.count - 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Contrato") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
    }

    private func installmentRow(_ inst: Installment, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: inst.isPaid ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(inst.isPaid ? Theme.cyan
                                     : (inst.isOverdue ? Theme.danger : Theme.text3))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parcela \(inst.number)")
                        .font(.auroraBody).foregroundStyle(Theme.text)
                    Text(inst.isPaid
                         ? "Paga em \(HomeView.dayMonth(inst.paidAt ?? .now))"
                         : "Vence \(HomeView.dayMonth(inst.dueDate))")
                        .font(.auroraCaption)
                        .foregroundStyle(inst.isOverdue && !inst.isPaid ? Theme.danger : Theme.text2)
                }
                Spacer(minLength: 8)
                Text(inst.amount.formatted)
                    .font(.auroraAmount)
                    .foregroundStyle(inst.isPaid ? Theme.text2 : Theme.text)
                    .strikethrough(inst.isPaid)
            }
            .padding(.vertical, 10)
            if divider { Divider().overlay(Theme.line) }
        }
        .accessibilityElement(children: .combine)
    }
}
