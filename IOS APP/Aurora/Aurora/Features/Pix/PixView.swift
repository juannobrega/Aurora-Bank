import SwiftUI

struct PixView: View {
    @Environment(AppModel.self) private var model
    @State private var activeFlow: FlowPresentation?
    @State private var showSchedule = false
    @State private var scheduledDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                actions
                if !model.contacts.isEmpty { recentContacts }
                if model.settings.nightLimitEnabled { nightNotice }
                scheduledPix
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Pix").font(.auroraTitle).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 10)
            .background(Theme.navy)
        }
        .auroraBackground()
        .auroraRoutes()
        .navigationBarHidden(true)
        .flowSheet($activeFlow)
        .sheet(isPresented: $showSchedule) { scheduleSheet }
    }

    // MARK: Ações

    private var actions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            actionTile("paperplane.fill", "Enviar", primary: true) {
                activeFlow = .init(flow: PixFlow())
            }
            NavigationLink(value: Route.pixReceive) { actionLabel("qrcode", "Receber", primary: false) }
                .buttonStyle(.plain)
            NavigationLink(value: Route.pixKeys) { actionLabel("key.fill", "Chaves", primary: false) }
                .buttonStyle(.plain)
            NavigationLink(value: Route.pixLimits) { actionLabel("slider.horizontal.3", "Limites", primary: false) }
                .buttonStyle(.plain)
            actionTile("calendar.badge.clock", "Agendar", primary: false) { showSchedule = true }
            actionTile("qrcode.viewfinder", "Ler QR", primary: false) {
                model.showToast("Aponte para um QR code Pix")
            }
            actionTile("arrow.uturn.left", "Devolver", primary: false) {
                model.showToast("Selecione um Pix recebido no extrato para devolver")
            }
            NavigationLink(value: Route.support) { actionLabel("questionmark.circle.fill", "Ajuda", primary: false) }
                .buttonStyle(.plain)
        }
    }

    private func actionTile(_ symbol: String, _ label: String, primary: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(symbol, label, primary: primary) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ symbol: String, _ label: String, primary: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(primary ? .white : Theme.cyan)
                .frame(width: 54, height: 54)
                .background(primary ? Theme.cyan : Theme.surface1, in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(primary ? .clear : Theme.line, lineWidth: 1)
                )
            Text(label)
                .font(.auroraCaption).foregroundStyle(Theme.text2)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Contatos

    private var recentContacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contatos recentes").font(.auroraLabel).foregroundStyle(Theme.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(model.contacts) { c in
                        Button {
                            activeFlow = .init(flow: PixFlow(contact: c), startAt: .amount)
                        } label: {
                            VStack(spacing: 7) {
                                Text(c.initials)
                                    .font(.display(15, .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Theme.cyan, in: .circle)
                                Text(c.firstName)
                                    .font(.auroraCaption).foregroundStyle(Theme.text2)
                                    .lineLimit(1)
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Enviar Pix para \(c.name)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Aviso de limite noturno

    private var nightNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill").foregroundStyle(Theme.cyan)
            Text("Limite noturno de \(model.settings.nightLimit.formatted) ativo entre 20h e 6h.")
                .font(.auroraCaption).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Pix agendados

    private var scheduledPix: some View {
        let upcoming = model.ledger.sorted.filter {
            $0.method == .pix && $0.date > .now
        }
        return Group {
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Agendados").font(.auroraLabel).foregroundStyle(Theme.text2)
                    AuroraCard(padding: 12) {
                        VStack(spacing: 0) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { i, tx in
                                NavigationLink(value: Route.transaction(tx.id)) {
                                    TransactionRow(transaction: tx, hidden: model.hideBalance,
                                                   showsDivider: i < upcoming.count - 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Agendamento

    private var scheduleSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Data do envio", selection: $scheduledDate,
                           in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.cyan)
                    .padding(.horizontal, 8)
                Spacer()
                PrimaryButton(title: "Escolher destinatário") {
                    showSchedule = false
                    activeFlow = .init(flow: PixFlow(scheduledFor: scheduledDate))
                }
                .padding(Theme.Space.gutter)
            }
            .padding(.top, 8)
            .navigationTitle("Agendar Pix")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showSchedule = false }.tint(Theme.text2)
                }
            }
        }
        .presentationDetents([.large])
    }
}
