import SwiftUI

/// Comprovante ao fim de um fluxo. No protótipo isto era um toast
/// ("Comprovante pronto para compartilhar") que não gerava nada.
struct ReceiptView: View {
    @Environment(AppModel.self) private var model
    let result: FlowResult
    let rows: [FlowRow]
    let amount: Money
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    SuccessMark(size: 84).padding(.top, 24)

                    VStack(spacing: 6) {
                        Text(result.doneTitle)
                            .font(.auroraTitle).foregroundStyle(Theme.text)
                        Text(result.doneSubtitle)
                            .font(.auroraBody).foregroundStyle(Theme.text2)
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)

                    AuroraCard {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                DetailRow(label: row.label, value: row.value)
                            }
                            DetailRow(label: "Data", value: Self.fullDate(result.transaction.date))
                            DetailRow(label: "Autenticação",
                                      value: result.transaction.authCode,
                                      showsDivider: false)
                        }
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                }
            }

            VStack(spacing: 10) {
                ShareLink(item: receiptText) {
                    Text("Compartilhar comprovante")
                        .font(.display(16, .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.icon)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                PrimaryButton(title: "Concluir", action: onFinish)
            }
            .padding(Theme.Space.gutter)
        }
    }

    /// Texto do comprovante, compartilhável pela folha nativa do iOS.
    private var receiptText: String {
        var lines = [
            "Comprovante Aurora",
            result.doneTitle,
            "Valor: \(amount.formatted)",
        ]
        lines += rows.map { "\($0.label): \($0.value)" }
        lines.append("Data: \(Self.fullDate(result.transaction.date))")
        lines.append("Autenticação: \(result.transaction.authCode)")
        lines.append("\(model.user.name) · Ag \(model.user.agency) · Conta \(model.user.account)")
        return lines.joined(separator: "\n")
    }

    static func fullDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMMM 'de' yyyy 'às' HH:mm"
        return f.string(from: d)
    }
}

/// Comprovante de uma transação já registrada, aberto pelo extrato.
struct TransactionDetailView: View {
    @Environment(AppModel.self) private var model
    let transaction: Transaction

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: transaction.method.symbol)
                            .font(.system(size: 26))
                            .foregroundStyle(transaction.category.tint)
                            .frame(width: 66, height: 66)
                            .background(transaction.category.tint.tinted, in: .circle)
                        Text(transaction.amount.signed)
                            .font(.mono(32, .semibold))
                            .foregroundStyle(transaction.isCredit ? Theme.cyan : Theme.text)
                        Text(transaction.title)
                            .font(.auroraBody).foregroundStyle(Theme.text2)
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)

                    AuroraCard {
                        VStack(spacing: 0) {
                            DetailRow(label: transaction.isCredit ? "De" : "Para",
                                      value: transaction.counterparty)
                            DetailRow(label: "Meio", value: transaction.method.title)
                            DetailRow(label: "Categoria", value: transaction.category.title)
                            DetailRow(label: "Data",
                                      value: ReceiptView.fullDate(transaction.date))
                            DetailRow(label: "Autenticação", value: transaction.authCode,
                                      showsDivider: false)
                        }
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                }
            }

            ShareLink(item: shareText) {
                Text("Compartilhar comprovante")
                    .font(.display(16, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.icon)
                            .stroke(Theme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(Theme.Space.gutter)
        }
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .top) { ScreenHeader("Comprovante") }
        .auroraBackground()
    }

    private var shareText: String {
        """
        Comprovante Aurora
        \(transaction.title)
        Valor: \(transaction.amount.signed)
        \(transaction.isCredit ? "De" : "Para"): \(transaction.counterparty)
        Meio: \(transaction.method.title)
        Data: \(ReceiptView.fullDate(transaction.date))
        Autenticação: \(transaction.authCode)
        \(model.user.name) · Ag \(model.user.agency) · Conta \(model.user.account)
        """
    }
}
