import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: PlanTab
    @State private var showNewGoal = false
    @State private var activeFlow: FlowPresentation?

    init(initialTab: PlanTab = .goals) { _tab = State(initialValue: initialTab) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                SegmentedPicker(
                    options: [(PlanTab.goals, "Cofrinhos"), (.spending, "Gastos")],
                    selection: $tab
                )
                if tab == .goals { goalsTab } else { spendingTab }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Planejar") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showNewGoal) { NewGoalSheet() }
        .flowSheet($activeFlow)
        .animation(.snappy(duration: 0.22), value: tab)
    }

    // MARK: Cofrinhos

    private var goalsTab: some View {
        VStack(spacing: Theme.Space.base) {
            AuroraCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total guardado").font(.auroraLabel).foregroundStyle(Theme.text2)
                    AnimatedMoney(value: model.savedTotal, hidden: model.hideBalance)
                }
            }
            .accessibilityElement(children: .combine)

            if model.goals.isEmpty {
                EmptyStateView(symbol: "banknote", title: "Nenhum cofrinho ainda",
                               message: "Crie um objetivo e comece a guardar.")
            } else {
                ForEach(model.goals) { goal in
                    NavigationLink(value: Route.goalDetail(goal.id)) {
                        goalCard(goal)
                    }
                    .buttonStyle(.plain)
                }
            }

            SecondaryButton(title: "Criar cofrinho") { showNewGoal = true }
        }
    }

    private func goalCard(_ goal: Goal) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: goal.symbol)
                        .font(.system(size: 15)).foregroundStyle(Theme.cyan)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface2, in: .circle)
                    Text(goal.name).font(.auroraBody).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(goal.percentText)
                        .font(.auroraLabel)
                        .foregroundStyle(goal.isComplete ? Theme.cyan : Theme.text2)
                }
                ProgressBar(value: goal.progress)
                HStack {
                    Text("\(goal.saved.formatted(hidden: model.hideBalance)) de \(goal.target.formatted)")
                        .font(.auroraCaption).foregroundStyle(Theme.text2)
                    Spacer()
                    if let deadline = goal.deadline {
                        Text("até \(HomeView.dayMonth(deadline))")
                            .font(.auroraCaption).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.name), \(goal.percentText) de \(goal.target.formatted)")
    }

    // MARK: Gastos
    //
    // Deriva do ledger: um Pix feito agora muda este gráfico na hora — o
    // protótipo tinha uma lista fixa que nunca mudava.

    private var spendingTab: some View {
        let spend = model.ledger.spending(in: .currentMonth)
        return VStack(spacing: Theme.Space.base) {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Gasto em \(Self.monthName())")
                        .font(.auroraLabel).foregroundStyle(Theme.text2)
                    AnimatedMoney(value: model.monthSpending, hidden: model.hideBalance)
                    // Acima de 90% do orçamento a barra vira alerta; abaixo
                    // disso usa o gradiente da marca.
                    if model.budgetProgress > 0.9 {
                        ProgressBar(value: model.budgetProgress, color: Theme.danger)
                    } else {
                        ProgressBar(value: model.budgetProgress)
                    }
                    Text("Orçamento de \(model.monthlyBudget.formatted) · faltam \(model.budgetRemaining.formatted)")
                        .font(.auroraCaption).foregroundStyle(Theme.text2)
                }
            }
            .accessibilityElement(children: .combine)

            if spend.isEmpty {
                EmptyStateView(symbol: "chart.pie", title: "Sem gastos neste mês")
            } else {
                AuroraCard(padding: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(spend.enumerated()), id: \.element.id) { i, item in
                            categoryRow(item, divider: i < spend.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(_ item: CategorySpend, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: item.category.symbol)
                    .font(.system(size: 14)).foregroundStyle(item.category.tint)
                    .frame(width: 36, height: 36)
                    .background(item.category.tint.tinted,
                                in: .rect(cornerRadius: Theme.Radius.icon))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.category.title).font(.auroraBody).foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        Text(item.total.formatted(hidden: model.hideBalance))
                            .font(.auroraAmount).foregroundStyle(Theme.text)
                    }
                    ProgressBar(value: item.ratio, color: item.category.tint, height: 5)
                }
            }
            .padding(.vertical, 10)
            if divider { Divider().overlay(Theme.line) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.category.title), \(item.total.formatted)")
    }

    static func monthName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMMM"
        return f.string(from: .now)
    }
}

/// Detalhe do cofrinho: guardar, resgatar e excluir — no protótipo só dava
/// para guardar, e não havia como criar ou apagar um cofrinho.
struct GoalDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var activeFlow: FlowPresentation?
    @State private var confirmDelete = false

    private var current: Goal { model.goals.first { $0.id == goal.id } ?? goal }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 11) {
                            Image(systemName: current.symbol)
                                .font(.system(size: 17)).foregroundStyle(Theme.cyan)
                                .frame(width: 42, height: 42)
                                .background(Theme.surface2, in: .circle)
                            Text(current.name).font(.auroraHeadline).foregroundStyle(Theme.text)
                        }
                        AnimatedMoney(value: current.saved, hidden: model.hideBalance)
                        ProgressBar(value: current.progress)
                        Text(current.isComplete
                             ? "Meta alcançada 🎉"
                             : "Faltam \(current.remaining.formatted) para \(current.target.formatted)")
                            .font(.auroraCaption)
                            .foregroundStyle(current.isComplete ? Theme.cyan : Theme.text2)
                    }
                }
                .accessibilityElement(children: .combine)

                if let deadline = current.deadline {
                    AuroraCard {
                        VStack(spacing: 0) {
                            DetailRow(label: "Prazo", value: PixFlow.dateText(deadline))
                            DetailRow(label: "Sugestão mensal",
                                      value: monthlySuggestion(deadline).formatted,
                                      showsDivider: false)
                        }
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Guardar") {
                        activeFlow = .init(flow: GoalDepositFlow(goal: current))
                    }
                    SecondaryButton(title: "Resgatar") {
                        activeFlow = .init(flow: GoalWithdrawFlow(goal: current))
                    }
                }

                Button { confirmDelete = true } label: {
                    Text("Excluir cofrinho")
                        .font(.auroraLabel).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { ScreenHeader("Cofrinho") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
        .flowSheet($activeFlow)
        .confirmationDialog("Excluir \(current.name)?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Excluir e resgatar", role: .destructive) {
                model.deleteGoal(current.id)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(current.saved.isZero
                 ? "Este cofrinho será removido."
                 : "O valor de \(current.saved.formatted) volta para a sua conta.")
        }
    }

    /// Quanto guardar por mês para bater a meta no prazo.
    private func monthlySuggestion(_ deadline: Date) -> Money {
        let months = Calendar.current.dateComponents([.month], from: .now, to: deadline).month ?? 1
        return current.remaining / Decimal(max(1, months))
    }
}

struct NewGoalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var targetCents = ""
    @State private var symbol = "banknote.fill"
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: .now)!

    private let symbols = ["banknote.fill", "airplane", "house.fill", "car.fill",
                           "laptopcomputer", "gift.fill", "shield.fill", "graduationcap.fill"]

    private var target: Money { Money(cents: Int(targetCents) ?? 0) }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && target > .zero
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Objetivo").font(.auroraLabel).foregroundStyle(Theme.text2)
                        TextField("Ex.: viagem, reserva, notebook", text: $name)
                            .font(.auroraBody).foregroundStyle(Theme.text)
                            .padding(16)
                            .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon)
                                .stroke(Theme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meta").font(.auroraLabel).foregroundStyle(Theme.text2)
                        Text(target.formatted)
                            .font(.mono(24, .semibold))
                            .foregroundStyle(target.isZero ? Theme.text3 : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon)
                                .stroke(Theme.line, lineWidth: 1))
                        Keypad { key in
                            switch key {
                            case .digit(let d):
                                guard targetCents.count < 9 else { return }
                                let next = targetCents + d
                                targetCents = String(next.drop { $0 == "0" })
                            case .delete: _ = targetCents.popLast()
                            default: break
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ícone").font(.auroraLabel).foregroundStyle(Theme.text2)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                 count: 4), spacing: 8) {
                            ForEach(symbols, id: \.self) { s in
                                Button {
                                    withAnimation(.snappy(duration: 0.15)) { symbol = s }
                                } label: {
                                    Image(systemName: s)
                                        .font(.system(size: 17))
                                        .foregroundStyle(symbol == s ? .white : Theme.cyan)
                                        .frame(maxWidth: .infinity).frame(height: 50)
                                        .background(symbol == s ? Theme.cyan : Theme.surface1,
                                                    in: .rect(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .stroke(symbol == s ? .clear : Theme.line, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Toggle(isOn: $hasDeadline) {
                        Text("Definir prazo").font(.auroraBody).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.cyan)

                    if hasDeadline {
                        DatePicker("Prazo", selection: $deadline, in: Date.now...,
                                   displayedComponents: .date)
                            .tint(Theme.cyan)
                            .foregroundStyle(Theme.text)
                    }

                    PrimaryButton(title: "Criar cofrinho", enabled: isValid) {
                        model.addGoal(Goal(
                            name: name.trimmingCharacters(in: .whitespaces),
                            saved: .zero,
                            target: target,
                            symbol: symbol,
                            deadline: hasDeadline ? deadline : nil
                        ))
                        model.showToast("Cofrinho criado")
                        dismiss()
                    }
                }
                .padding(Theme.Space.gutter)
            }
            .navigationTitle("Novo cofrinho")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.tint(Theme.text2)
                }
            }
        }
    }
}
