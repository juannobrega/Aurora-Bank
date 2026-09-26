import SwiftUI

/// Hub de pagamentos — categoria inteira ausente no protótipo, apesar de
/// ser o segundo fluxo mais usado de um banco depois do Pix.
struct PaymentsView: View {
    @Environment(AppModel.self) private var model
    @State private var activeFlow: FlowPresentation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                AuroraCard(padding: 12) {
                    VStack(spacing: 0) {
                        option("barcode.viewfinder", "Boleto",
                               "Conta de consumo, carnê ou fatura",
                               tint: Theme.Spectrum.amber) {
                            activeFlow = .init(flow: BoletoFlow())
                        }
                        option("antenna.radiowaves.left.and.right", "Recarga de celular",
                               "Crédito na hora para qualquer operadora",
                               tint: Theme.Spectrum.violet) {
                            activeFlow = .init(flow: RecargaFlow())
                        }
                        option("bolt.fill", "Contas de consumo",
                               "Luz, água, gás e telefone",
                               tint: Theme.Spectrum.cyan) {
                            activeFlow = .init(flow: BoletoFlow())
                        }
                        option("building.columns.fill", "Tributos",
                               "IPVA, IPTU e DARF",
                               tint: Theme.Spectrum.ice, showsDivider: false) {
                            model.showToast("Pagamento de tributos em breve")
                        }
                    }
                }

                Text("Pagamentos feitos até 20h caem no mesmo dia útil.")
                    .font(.auroraCaption).foregroundStyle(Theme.text3)

                if !recentPayments.isEmpty {
                    Text("Pagamentos recentes").font(.auroraLabel).foregroundStyle(Theme.text2)
                    AuroraCard(padding: 12) {
                        VStack(spacing: 0) {
                            ForEach(Array(recentPayments.enumerated()), id: \.element.id) { i, tx in
                                NavigationLink(value: Route.transaction(tx.id)) {
                                    TransactionRow(transaction: tx, hidden: model.hideBalance,
                                                   showsDivider: i < recentPayments.count - 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Pagar") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .flowSheet($activeFlow)
    }

    private var recentPayments: [Transaction] {
        Array(model.ledger.sorted.filter {
            $0.method == .boleto || $0.method == .recarga
        }.prefix(5))
    }

    private func option(_ symbol: String, _ title: String, _ subtitle: String,
                        tint: Color = Theme.Spectrum.sky, showsDivider: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ActionRowLabel(symbol: symbol, title: title, subtitle: subtitle,
                           tint: tint, showsDivider: showsDivider)
        }
        .buttonStyle(.plain)
    }
}

/// Atendimento — categoria inteira ausente no protótipo.
struct SupportView: View {
    @Environment(AppModel.self) private var model
    @State private var expandedFAQ: String?

    private let faqs: [(String, String)] = [
        ("Como aumentar meu limite do Pix?",
         "Em Pix › Limites você ajusta os valores. Aumentos passam por análise e valem a partir do dia seguinte, conforme regra do Banco Central."),
        ("Recebi um Pix por engano. E agora?",
         "Abra a transação no extrato e toque em Devolver. Se houver suspeita de fraude, use o Mecanismo Especial de Devolução (MED) pelo atendimento."),
        ("Como funciona a fatura do cartão?",
         "Todas as compras no crédito somam na fatura em aberto. Você pode pagar com saldo ou parcelar a qualquer momento antes do vencimento."),
        ("Perdi meu celular. Como bloquear?",
         "Ligue para a central 24h ou entre por outro aparelho e use Segurança › Encerrar outras sessões."),
        ("O rendimento é automático?",
         "Sim. O saldo em conta rende 100% do CDI desde o primeiro dia, sem precisar aplicar."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                AuroraCard(padding: 12) {
                    VStack(spacing: 0) {
                        channel("bubble.left.fill", "Chat com atendente",
                                "Seg a sex, 8h às 20h") {
                            model.showToast("Abrindo chat com atendente…")
                        }
                        channel("phone.fill", "Central 24 horas",
                                "0800 000 0000") {
                            if let url = URL(string: "tel://08000000000") {
                                UIApplication.shared.open(url)
                            }
                        }
                        channel("envelope.fill", "Ouvidoria",
                                "Prazo de resposta de 10 dias úteis",
                                showsDivider: false) {
                            model.showToast("Chamado de ouvidoria aberto")
                        }
                    }
                }

                Text("Perguntas frequentes").font(.auroraLabel).foregroundStyle(Theme.text2)
                AuroraCard(padding: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(faqs.enumerated()), id: \.offset) { i, faq in
                            faqRow(faq.0, faq.1, divider: i < faqs.count - 1)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Ajuda") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
    }

    private func channel(_ symbol: String, _ title: String, _ subtitle: String,
                         showsDivider: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ActionRowLabel(symbol: symbol, title: title, subtitle: subtitle,
                           showsDivider: showsDivider)
        }
        .buttonStyle(.plain)
    }

    private func faqRow(_ question: String, _ answer: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    expandedFAQ = expandedFAQ == question ? nil : question
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(question)
                        .font(.auroraBody).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(expandedFAQ == question ? 180 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expandedFAQ == question {
                Text(answer)
                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if divider { Divider().overlay(Theme.line) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toque para \(expandedFAQ == question ? "fechar" : "abrir") a resposta")
    }
}
