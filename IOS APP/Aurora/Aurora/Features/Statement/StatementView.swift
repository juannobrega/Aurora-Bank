import SwiftUI

/// Extrato com filtro por tipo, período e busca — e cada linha abre o
/// comprovante. No protótipo as datas eram strings e nada era tocável.
struct StatementView: View {
    @Environment(AppModel.self) private var model

    enum Kind: Hashable { case all, credits, debits }
    enum Period: Hashable, CaseIterable {
        case month, days30, days90, all
        var label: String {
            switch self {
            case .month: "Este mês"
            case .days30: "30 dias"
            case .days90: "90 dias"
            case .all: "Tudo"
            }
        }
        var interval: DateInterval {
            switch self {
            case .month: .currentMonth
            case .days30: .lastDays(30)
            case .days90: .lastDays(90)
            case .all: .allTime
            }
        }
    }

    @State private var kind: Kind = .all
    @State private var period: Period = .month
    @State private var search = ""
    @State private var showExport = false

    private var filtered: [Transaction] {
        model.ledger.transactions(in: period.interval)
            .filter {
                switch kind {
                case .all: true
                case .credits: $0.isCredit
                case .debits: !$0.isCredit
                }
            }
            .filter {
                search.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(search)
                    || $0.counterparty.localizedCaseInsensitiveContains(search)
            }
    }

    private var groups: [TransactionGroup] { model.ledger.grouped(filtered) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                totalsCard
                FilterChips(options: [(Kind.all, "Tudo"),
                                      (.credits, "Entradas"),
                                      (.debits, "Saídas")],
                            selection: $kind)
                    .frame(maxWidth: .infinity, alignment: .leading)
                periodPicker

                if groups.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "Nada encontrado",
                        message: search.isEmpty
                            ? "Não há movimentações neste período."
                            : "Tente outro termo de busca."
                    )
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.auroraLabel).foregroundStyle(Theme.text2)
                            AuroraCard(padding: 12) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { i, tx in
                                        NavigationLink(value: Route.transaction(tx.id)) {
                                            TransactionRow(transaction: tx,
                                                           hidden: model.hideBalance,
                                                           showsDivider: i < group.items.count - 1)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .searchable(text: $search, prompt: "Buscar no extrato")
        .refreshable { await model.load() }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Extrato").font(.auroraTitle).foregroundStyle(Theme.text)
                Spacer()
                ShareLink(item: exportCSV, preview: SharePreview("Extrato Aurora.csv")) {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                        .font(.auroraLabel)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.surface1, in: .capsule)
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 10)
            .background(Theme.navy)
        }
        .auroraBackground()
        .auroraRoutes()
        .navigationBarHidden(true)
    }

    // MARK: Totais

    private var totalsCard: some View {
        HStack(spacing: 10) {
            totalTile("Entradas", model.ledger.credits(in: period.interval), Theme.cyan)
            totalTile("Saídas", model.ledger.debits(in: period.interval), Theme.text)
        }
    }

    private func totalTile(_ label: String, _ value: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.auroraCaption).foregroundStyle(Theme.text2)
            Text(value.formatted(hidden: model.hideBalance))
                .font(.mono(17, .semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Period.allCases, id: \.self) { p in
                    let on = period == p
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { period = p }
                    } label: {
                        Text(p.label)
                            .font(.auroraCaption)
                            .foregroundStyle(on ? Theme.text : Theme.text2)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(on ? Theme.surface3 : .clear, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// CSV de verdade, compartilhável — o protótipo só mostrava um toast.
    private var exportCSV: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        let header = "Data;Descrição;Contraparte;Categoria;Meio;Valor;Autenticação"
        let rows = filtered.map { tx in
            [
                f.string(from: tx.date),
                tx.title,
                tx.counterparty,
                tx.category.title,
                tx.method.title,
                NSDecimalNumber(decimal: tx.amount.amount).stringValue.replacingOccurrences(of: ".", with: ","),
                tx.authCode,
            ].joined(separator: ";")
        }
        return ([header] + rows).joined(separator: "\n")
    }
}
