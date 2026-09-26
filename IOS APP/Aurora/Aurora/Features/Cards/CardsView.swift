import SwiftUI

struct CardsView: View {
    @Environment(AppModel.self) private var model
    @State private var revealVirtual = false
    @State private var showInstallments = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                SegmentedPicker(
                    options: [(Card.Kind.fisico, "Físico"), (.virtual, "Virtual")],
                    selection: $model.card.kind
                )
                cardFace
                actions
                invoiceCard
                limitCard
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Cartões").font(.auroraTitle).foregroundStyle(Theme.text)
                Spacer()
                NavigationLink(value: Route.cardSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16)).foregroundStyle(Theme.text)
                        .frame(width: 38, height: 38)
                        .background(Theme.surface1, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes do cartão")
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 10)
            .background(Theme.navy)
        }
        .auroraBackground()
        .auroraRoutes()
        .navigationBarHidden(true)
        .sheet(isPresented: $showInstallments) { InstallmentSheet() }
    }

    // MARK: Face do cartão

    private var cardFace: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.hero)
                .fill(
                    model.card.kind == .virtual
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Theme.Spectrum.violet.opacity(0.55), Color(hex: 0x13206E)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Theme.cardGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.hero)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        AuroraMark(width: 34, mode: .mono, cutColor: Color(hex: 0x1B2B84))
                        AuroraWordmark(size: 11, bankColor: Color(hex: 0xC9D2FF))
                    }
                    Spacer()
                    Text(model.card.kind == .virtual ? "Virtual · crédito" : "Débito e crédito")
                        .font(.auroraCaption).foregroundStyle(Theme.text2)
                }
                Spacer()
                Text(model.card.displayNumber(revealed: revealVirtual))
                    .font(.mono(19, .medium)).foregroundStyle(Theme.text)
                Spacer()
                HStack(alignment: .bottom) {
                    Text(model.user.name.uppercased())
                        .font(.mono(11)).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Text(model.card.kind == .virtual && revealVirtual
                         ? "CVV \(model.card.cvv) · \(model.card.expiry)"
                         : model.card.expiry)
                        .font(.mono(11)).foregroundStyle(Theme.text2)
                }
            }
            .padding(20)
        }
        .frame(height: 206)
        .opacity(model.card.isBlocked ? 0.45 : 1)
        .overlay {
            if model.card.isBlocked {
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 22))
                    Text("Bloqueado").font(.auroraLabel)
                }
                .foregroundStyle(Theme.text)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.card.isBlocked)
        .animation(.snappy(duration: 0.25), value: model.card.kind)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Cartão \(model.card.kind.title)\(model.card.isBlocked ? ", bloqueado" : "")"
        )
    }

    // MARK: Ações

    private var actions: some View {
        HStack(spacing: 10) {
            actionTile(model.card.isBlocked ? "lock.open.fill" : "lock.fill",
                       model.card.isBlocked ? "Desbloquear" : "Bloquear") {
                model.card.isBlocked.toggle()
                Haptics.tap()
                model.showToast(model.card.isBlocked ? "Cartão bloqueado" : "Cartão desbloqueado")
            }
            if model.card.kind == .virtual {
                actionTile(revealVirtual ? "eye.slash.fill" : "eye.fill",
                           revealVirtual ? "Ocultar" : "Mostrar") {
                    withAnimation(.snappy(duration: 0.2)) { revealVirtual.toggle() }
                }
                actionTile("doc.on.doc.fill", "Copiar") {
                    UIPasteboard.general.string = model.card.number.filter(\.isNumber)
                    model.showToast("Número do cartão virtual copiado")
                }
            } else {
                actionTile("creditcard.fill", "Virtual") {
                    withAnimation(.snappy(duration: 0.25)) { model.card.kind = .virtual }
                }
                actionTile("calendar", "Parcelar") { showInstallments = true }
            }
        }
    }

    private func actionTile(_ symbol: String, _ label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 16)).foregroundStyle(Theme.cyan)
                Text(label)
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon)
                .stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    // MARK: Fatura

    private var invoiceCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Fatura atual · vence \(HomeView.dayMonth(model.card.invoiceDue))")
                        .font(.auroraLabel).foregroundStyle(Theme.text2)
                    Spacer()
                    Text("Cashback \(model.card.cashback.formatted)")
                        .font(.auroraCaption).foregroundStyle(Theme.cyan)
                }
                Text(model.invoice.formatted(hidden: model.hideBalance))
                    .font(.mono(28, .semibold)).foregroundStyle(Theme.text)
                    .contentTransition(.numericText())

                HStack(spacing: 10) {
                    Button { _ = model.payInvoice() } label: {
                        Text("Pagar com saldo")
                            .font(.display(15, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Theme.cyan, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .opacity(model.invoice > .zero ? 1 : 0.4)
                    .disabled(model.invoice.isZero)

                    Button { showInstallments = true } label: {
                        Text("Parcelar")
                            .font(.display(15, .medium)).foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Theme.surface2, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .opacity(model.invoice > .zero ? 1 : 0.4)
                    .disabled(model.invoice.isZero)
                }

                if !invoiceItems.isEmpty {
                    Divider().overlay(Theme.line)
                    Text("Compras nesta fatura").font(.auroraLabel).foregroundStyle(Theme.text2)
                    VStack(spacing: 0) {
                        ForEach(Array(invoiceItems.prefix(4).enumerated()), id: \.element.id) { i, tx in
                            NavigationLink(value: Route.transaction(tx.id)) {
                                TransactionRow(transaction: tx, hidden: model.hideBalance,
                                               showsDivider: i < min(4, invoiceItems.count) - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Compras que compõem a fatura em aberto.
    private var invoiceItems: [Transaction] {
        var out: [Transaction] = []
        for tx in model.ledger.sorted {
            if tx.title == Ledger.invoicePaymentTitle { break }
            if tx.method == .credito, !tx.isCredit { out.append(tx) }
        }
        return out
    }

    // MARK: Limite

    private var limitCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Limite total").font(.auroraLabel).foregroundStyle(Theme.text2)
                Text(model.card.limit.formatted)
                    .font(.mono(22, .semibold)).foregroundStyle(Theme.text)
                ProgressBar(value: usedRatio)
                Text("Disponível \(model.availableCardLimit.formatted) · usado \(model.invoice.formatted)")
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                NavigationLink(value: Route.cardSettings) {
                    Text("Ajustar limite")
                        .font(.auroraLabel).foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var usedRatio: Double {
        guard model.card.limit.amount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: model.invoice.amount / model.card.limit.amount).doubleValue)
    }
}

/// Parcelamento de fatura — o protótipo mostrava o valor num toast e não parcelava.
struct InstallmentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var months = 3
    private let options = [2, 3, 6, 10, 12]
    private let rate: Decimal = 0.0199

    private var payment: Money {
        Loan.payment(principal: model.invoice, monthlyRate: rate, months: months)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fatura de \(model.invoice.formatted)")
                        .font(.auroraHeadline).foregroundStyle(Theme.text)
                    Text("Escolha em quantas vezes quer dividir.")
                        .font(.auroraCaption).foregroundStyle(Theme.text2)
                }

                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { n in
                        let on = months == n
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { months = n }
                        } label: {
                            Text("\(n)x")
                                .font(.auroraLabel)
                                .foregroundStyle(on ? .white : Theme.text)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(on ? Theme.cyan : .clear, in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(on ? Theme.cyan : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                AuroraCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Parcela", value: payment.formatted)
                        DetailRow(label: "Taxa", value: "1,99% a.m.")
                        DetailRow(label: "Total", value: (payment * Decimal(months)).formatted,
                                  showsDivider: false)
                    }
                }

                Spacer()
                PrimaryButton(title: "Parcelar fatura") {
                    model.installInvoice(months: months)
                    dismiss()
                }
            }
            .padding(Theme.Space.gutter)
            .navigationTitle("Parcelar fatura")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.tint(Theme.text2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Ajustes do cartão: limite, contactless, compras internacionais.
struct CardSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var limitValue: Double = 5_000
    @State private var contactless = true
    @State private var international = false
    @State private var onlinePurchases = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Limite do cartão").font(.auroraLabel).foregroundStyle(Theme.text2)
                        Text(Money(Decimal(limitValue)).formatted)
                            .font(.mono(24, .semibold)).foregroundStyle(Theme.text)
                        Slider(value: $limitValue, in: minLimit...20_000, step: 500)
                            .tint(Theme.cyan)
                            .onChange(of: limitValue) { _, new in
                                model.card.limit = Money(Decimal(new))
                            }
                        Text("Não é possível reduzir abaixo da fatura em aberto (\(model.invoice.formatted)).")
                            .font(.auroraCaption).foregroundStyle(Theme.text3)
                    }
                }

                AuroraCard {
                    VStack(spacing: 4) {
                        toggle("Pagamento por aproximação", "Contactless e Apple Pay", $contactless)
                        Divider().overlay(Theme.line)
                        toggle("Compras online", "Autorizar transações na internet", $onlinePurchases)
                        Divider().overlay(Theme.line)
                        toggle("Compras internacionais", "Sujeitas a IOF e variação cambial", $international)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Ajustes do cartão") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .onAppear {
            limitValue = NSDecimalNumber(decimal: model.card.limit.amount).doubleValue
        }
    }

    /// Nunca abaixo da fatura já usada, arredondado para cima em 500.
    private var minLimit: Double {
        let used = NSDecimalNumber(decimal: model.invoice.amount).doubleValue
        return max(500, (used / 500).rounded(.up) * 500)
    }

    private func toggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.auroraBody).foregroundStyle(Theme.text)
                Text(subtitle).font(.auroraCaption).foregroundStyle(Theme.text2)
            }
        }
        .tint(Theme.cyan)
        .padding(.vertical, 8)
    }
}
