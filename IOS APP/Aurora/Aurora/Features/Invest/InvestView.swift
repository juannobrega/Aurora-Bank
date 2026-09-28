import SwiftUI

struct InvestView: View {
    @Environment(AppModel.self) private var model
    @State private var activeFlow: FlowPresentation?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                portfolioCard
                if !model.holdings.isEmpty { holdingsSection }
                offersSection
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Investimentos") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .flowSheet($activeFlow)
    }

    // MARK: Patrimônio

    private var portfolioCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Patrimônio investido").font(.auroraLabel).foregroundStyle(Theme.text2)
                AnimatedMoney(value: model.investedTotal, hidden: model.hideBalance)
                if model.investedEarnings.amount != 0 {
                    HStack(spacing: 5) {
                        Image(systemName: model.investedEarnings.isPositive
                              ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(model.investedEarnings.signed(hidden: model.hideBalance)) desde o início")
                    }
                    .font(.auroraCaption)
                    .foregroundStyle(model.investedEarnings.isPositive ? Theme.cyan : Theme.danger)
                }
                if !model.holdings.isEmpty { allocationBar.padding(.top, 6) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Barra de alocação por produto.
    private var allocationBar: some View {
        let total = model.investedTotal.amount
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(model.holdings) { h in
                    let share = total > 0
                        ? NSDecimalNumber(decimal: h.current.amount / total).doubleValue : 0
                    Rectangle()
                        .fill(Theme.Spectrum.named( h.product.accent))
                        .frame(width: max(2, geo.size.width * share))
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: Posições

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suas posições").font(.auroraLabel).foregroundStyle(Theme.text2)
            AuroraCard(padding: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(model.holdings.enumerated()), id: \.element.id) { i, h in
                        NavigationLink(value: Route.holding(h.id)) {
                            holdingRow(h, divider: i < model.holdings.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func holdingRow(_ h: Holding, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Circle()
                    .fill(Theme.text3)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.product.name).font(.auroraBody).foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(h.product.rate).font(.auroraCaption).foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(h.current.formatted(hidden: model.hideBalance))
                        .font(.auroraAmount).foregroundStyle(Theme.text)
                    Text(percentText(h))
                        .font(.auroraCaption)
                        .foregroundStyle(h.earnings.isPositive ? Theme.cyan : Theme.danger)
                }
            }
            .padding(.vertical, 11)
            if divider { Divider().overlay(Theme.line) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func percentText(_ h: Holding) -> String {
        let pct = NSDecimalNumber(decimal: h.earningsPercent).doubleValue
        return String(format: "%@%.2f%%", pct >= 0 ? "+" : "", pct)
    }

    // MARK: Ofertas

    private var offersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Para investir").font(.auroraLabel).foregroundStyle(Theme.text2)
            AuroraCard(padding: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(InvestmentProduct.all.enumerated()), id: \.element.id) { i, p in
                        Button {
                            activeFlow = .init(flow: InvestFlow(product: p))
                        } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 13) {
                                    Circle()
                                        .fill(Theme.text3)
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.auroraBody).foregroundStyle(Theme.text)
                                        Text("\(p.rate) · liquidez \(p.liquidity)")
                                            .font(.auroraCaption).foregroundStyle(Theme.text2)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.text3)
                                }
                                .padding(.vertical, 11)
                                if i < InvestmentProduct.all.count - 1 {
                                    Divider().overlay(Theme.line)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Detalhe da posição, com resgate — o protótipo só permitia aplicar.
struct HoldingDetailView: View {
    @Environment(AppModel.self) private var model
    let holding: Holding
    @State private var activeFlow: FlowPresentation?

    private var current: Holding {
        model.holdings.first { $0.id == holding.id } ?? holding
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.product.name)
                            .font(.auroraHeadline).foregroundStyle(Theme.text)
                        AnimatedMoney(value: current.current, hidden: model.hideBalance)
                        HStack(spacing: 5) {
                            Image(systemName: current.earnings.isPositive
                                  ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                            Text(current.earnings.signed(hidden: model.hideBalance))
                        }
                        .font(.auroraCaption)
                        .foregroundStyle(current.earnings.isPositive ? Theme.cyan : Theme.danger)
                    }
                }
                .accessibilityElement(children: .combine)

                AuroraCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Total aportado", value: current.invested.formatted)
                        DetailRow(label: "Rendimento", value: current.earnings.signed)
                        DetailRow(label: "Rentabilidade", value: current.product.rate)
                        DetailRow(label: "Liquidez", value: current.product.liquidity,
                                  showsDivider: false)
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Investir mais") {
                        activeFlow = .init(flow: InvestFlow(product: current.product))
                    }
                    SecondaryButton(title: "Resgatar") {
                        activeFlow = .init(flow: RedeemFlow(holding: current))
                    }
                }

                Text("Resgates em produtos com liquidez \(current.product.liquidity) podem levar até o prazo indicado para cair na conta.")
                    .font(.auroraCaption).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Posição") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .flowSheet($activeFlow)
    }
}
