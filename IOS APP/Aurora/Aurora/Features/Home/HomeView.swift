import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(TabRouter.self) private var router
    @State private var activeFlow: FlowPresentation?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                greeting
                balanceCard
                sendReceive
                shortcuts
                if model.invoice > .zero { invoiceCard }
                if let loan = model.activeLoan, let next = loan.nextDue {
                    loanCard(loan, next)
                }
                recentTransactions
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.lg)
        }
        .refreshable { await model.load() }
        .auroraBackground(horizon: true)
        .auroraRoutes()
        .navigationBarHidden(true)
        .flowSheet($activeFlow)
    }

    // MARK: Saudação

    private var greeting: some View {
        HStack(spacing: 12) {
            Text(model.user.initials)
                .font(.display(15, .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.actionGradient, in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.timeGreeting())
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                Text(model.user.firstName)
                    .font(.display(18, .medium)).foregroundStyle(Theme.text)
            }
            Spacer()

            IconButton(symbol: model.hideBalance ? "eye.slash" : "eye",
                       label: model.hideBalance ? "Mostrar valores" : "Ocultar valores") {
                withAnimation(Theme.Motion.snap) { model.hideBalance.toggle() }
            }
            NavigationLink(value: Route.notifications) {
                Image(systemName: "bell")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface1, in: .circle)
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if model.unreadNotifications > 0 {
                            Circle().fill(Theme.cyan).frame(width: 9, height: 9).offset(x: -2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notificações, \(model.unreadNotifications) não lidas")
        }
        .padding(.top, Theme.Space.sm)
    }

    static func timeGreeting(_ date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Bom dia"
        case 12..<18: "Boa tarde"
        default: "Boa noite"
        }
    }

    // MARK: Saldo

    private var balanceCard: some View {
        AuroraCard(radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Saldo disponível").font(.auroraCaption).foregroundStyle(Theme.text2)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                        Text("100% do CDI").font(.display(12, .medium))
                    }
                    .foregroundStyle(Theme.cyan)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Theme.cyan.tinted, in: .capsule)
                }

                if model.isLoading && model.ledger.transactions.isEmpty {
                    SkeletonRows(count: 1).frame(height: 44)
                } else {
                    AnimatedMoney(value: model.balance, hidden: model.hideBalance)
                }

                Sparkline(values: balanceTrend)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saldo disponível \(model.balance.formatted(hidden: model.hideBalance))")
    }

    /// Evolução do saldo nos últimos 14 dias, para a sparkline.
    private var balanceTrend: [Double] {
        let cal = Calendar.current
        let days = (0..<14).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: .now)
        }
        var running = NSDecimalNumber(decimal: model.balance.amount).doubleValue
        var out: [Double] = []
        // Retrocede o saldo aplicando as transações de cada dia ao contrário.
        for day in days.reversed() {
            out.append(running)
            let sameDay = model.ledger.transactions.filter { cal.isDate($0.date, inSameDayAs: day) }
            let delta = sameDay.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount.amount).doubleValue }
            running -= delta
        }
        return out.reversed()
    }

    // MARK: Enviar / Receber

    private var sendReceive: some View {
        HStack(spacing: 10) {
            Button {
                activeFlow = .init(flow: PixFlow())
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill").font(.system(size: 15))
                    Text("Enviar Pix").font(.display(15, .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Theme.actionGradient, in: .rect(cornerRadius: Theme.Radius.icon))
            }
            .buttonStyle(PressStyle())

            NavigationLink(value: Route.pixReceive) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode").font(.system(size: 15))
                    Text("Receber").font(.display(15, .medium))
                }
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon)
                    .stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(PressStyle())
        }
    }

    // MARK: Atalhos — cada um com sua cor do espectro

    private var shortcuts: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                  spacing: Theme.Space.base) {
            NavigationLink(value: Route.payments) {
                shortcut("barcode.viewfinder", "Pagar", Theme.Spectrum.amber)
            }.buttonStyle(.plain)
            NavigationLink(value: Route.invest) {
                shortcut("chart.line.uptrend.xyaxis", "Investir", Theme.Spectrum.lime)
            }.buttonStyle(.plain)
            NavigationLink(value: Route.credit) {
                shortcut("hand.raised.fill", "Crédito", Theme.Spectrum.violet)
            }.buttonStyle(.plain)
            NavigationLink(value: Route.plan(.goals)) {
                shortcut("banknote.fill", "Cofrinhos", Theme.Spectrum.pink)
            }.buttonStyle(.plain)
            NavigationLink(value: Route.plan(.spending)) {
                shortcut("chart.pie.fill", "Gastos", Theme.Spectrum.coral)
            }.buttonStyle(.plain)
            Button { router.select(.statement) } label: {
                shortcut("list.bullet.rectangle", "Extrato", Theme.Spectrum.sky)
            }.buttonStyle(.plain)
            NavigationLink(value: Route.security) {
                shortcut("shield.fill", "Segurança", Theme.Spectrum.ice)
            }.buttonStyle(.plain)
            NavigationLink(value: Route.support) {
                shortcut("bubble.left.and.text.bubble.right.fill", "Ajuda", Theme.Spectrum.cyan)
            }.buttonStyle(.plain)
        }
    }

    private func shortcut(_ symbol: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.tile))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .stroke(Theme.line, lineWidth: 1))
            Text(label)
                .font(.auroraCaption).foregroundStyle(Theme.text2)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Fatura

    private var invoiceCard: some View {
        NavigationLink(value: Route.cardSettings) {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 14)).foregroundStyle(Theme.Spectrum.violet)
                            .frame(width: 34, height: 34)
                            .background(Theme.Spectrum.violet.tinted,
                                        in: .rect(cornerRadius: Theme.Radius.icon))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fatura atual").font(.auroraBody).foregroundStyle(Theme.text)
                            Text("Vence \(Self.dayMonth(model.card.invoiceDue))")
                                .font(.auroraCaption).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Text(model.invoice.formatted(hidden: model.hideBalance))
                            .font(.auroraAmount).foregroundStyle(Theme.text)
                    }
                    ProgressBar(value: invoiceProgress, height: 6)
                    Text("Limite disponível \(model.availableCardLimit.formatted(hidden: model.hideBalance))")
                        .font(.auroraCaption).foregroundStyle(Theme.text2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var invoiceProgress: Double {
        guard model.card.limit.amount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: model.invoice.amount / model.card.limit.amount).doubleValue)
    }

    // MARK: Empréstimo

    private func loanCard(_ loan: Loan, _ next: Installment) -> some View {
        NavigationLink(value: Route.loanDetail(loan.id)) {
            AuroraCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Empréstimo", systemImage: "hand.raised.fill")
                            .font(.auroraCaption).foregroundStyle(Theme.text2)
                        Spacer()
                        Text("\(loan.paidCount)/\(loan.installments.count) pagas")
                            .font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                    Text("Próxima parcela \(next.amount.formatted)")
                        .font(.auroraAmount).foregroundStyle(Theme.text)
                    Text("Vence \(Self.dayMonth(next.dueDate)) · saldo devedor \(loan.outstanding.formatted)")
                        .font(.auroraCaption)
                        .foregroundStyle(next.isOverdue ? Theme.danger : Theme.text2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Movimentações

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Movimentações").font(.auroraLabel).foregroundStyle(Theme.text2)
                Spacer()
                Button { router.select(.statement) } label: {
                    Text("Ver extrato").font(.auroraLabel).foregroundStyle(Theme.sky)
                }
                .buttonStyle(.plain)
            }

            AuroraCard(padding: Theme.Space.base) {
                if model.isLoading && model.ledger.transactions.isEmpty {
                    SkeletonRows()
                } else {
                    let recent = Array(model.ledger.sorted.prefix(5))
                    if recent.isEmpty {
                        EmptyStateView(symbol: "tray", title: "Nenhuma movimentação ainda")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { i, tx in
                                NavigationLink(value: Route.transaction(tx.id)) {
                                    TransactionRow(transaction: tx,
                                                   hidden: model.hideBalance,
                                                   showsDivider: i < recent.count - 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    static func dayMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

// MARK: - Linha de transação

struct TransactionRow: View {
    let transaction: Transaction
    var hidden: Bool
    var showsDivider = true

    /// Cada categoria tem seu tom do espectro, com fundo tingido a 10%.
    private var tint: Color { transaction.category.tint }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: transaction.category.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.tinted, in: .rect(cornerRadius: Theme.Radius.icon))
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.title)
                        .font(.auroraBody).foregroundStyle(Theme.text).lineLimit(1)
                    Text(transaction.counterparty)
                        .font(.auroraCaption).foregroundStyle(Theme.text2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(transaction.amount.signed(hidden: hidden))
                    .font(.auroraAmount)
                    .foregroundStyle(transaction.isCredit ? Theme.cyan : Theme.text)
            }
            .padding(.vertical, 10)
            if showsDivider { Divider().overlay(Theme.line) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(transaction.title), \(transaction.counterparty), \(transaction.amount.signed)"
        )
    }
}
