import SwiftUI
import CoreImage.CIFilterBuiltins

/// Cobrança Pix com QR **gerado de verdade** a partir do payload EMV,
/// com valor e descrição opcionais. No protótipo era uma imagem estática
/// e "copiar" era só um toast.
struct PixReceiveView: View {
    @Environment(AppModel.self) private var model

    @State private var amountCents = ""
    @State private var note = ""
    @State private var selectedKey: PixKey?
    @FocusState private var noteFocused: Bool

    private var amount: Money { Money(cents: Int(amountCents) ?? 0) }
    private var key: PixKey? { selectedKey ?? model.pixKeys.first }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.base) {
                qrCard
                if model.pixKeys.count > 1 { keyPicker }
                amountField
                noteField
                actions
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top) { ScreenHeader("Receber") }
        .auroraBackground()
        .navigationBarBackButtonHidden()
    }

    // MARK: QR

    private var qrCard: some View {
        AuroraCard {
            VStack(spacing: 14) {
                Text(amount.isZero ? "QR code estático" : "QR code dinâmico")
                    .font(.auroraLabel).foregroundStyle(Theme.text2)

                if let image = QRGenerator.image(from: payload) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 210, height: 210)
                        .padding(12)
                        .background(.white, in: .rect(cornerRadius: 12))
                        .accessibilityLabel("QR code Pix para receber \(amount.isZero ? "qualquer valor" : amount.formatted)")
                } else {
                    EmptyStateView(symbol: "qrcode", title: "Não foi possível gerar o QR")
                }

                VStack(spacing: 3) {
                    Text(model.user.name).font(.auroraBody).foregroundStyle(Theme.text)
                    if let key {
                        Text("\(key.kind.title) · \(key.masked)")
                            .font(.auroraCaption).foregroundStyle(Theme.text2)
                    }
                    if !amount.isZero {
                        Text(amount.formatted)
                            .font(.mono(20, .semibold)).foregroundStyle(Theme.cyan)
                            .padding(.top, 4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Chave

    private var keyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receber na chave").font(.auroraLabel).foregroundStyle(Theme.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.pixKeys) { k in
                        let on = (key?.id == k.id)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { selectedKey = k }
                        } label: {
                            Text(k.kind.title)
                                .font(.auroraCaption)
                                .foregroundStyle(on ? .white : Theme.text)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(on ? Theme.cyan : .clear, in: .capsule)
                                .overlay(Capsule().stroke(on ? Theme.cyan : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Valor

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Valor (opcional)").font(.auroraLabel).foregroundStyle(Theme.text2)
            HStack {
                Text(amount.formatted)
                    .font(.mono(22, .semibold))
                    .foregroundStyle(amount.isZero ? Theme.text3 : Theme.text)
                Spacer()
                if !amountCents.isEmpty {
                    Button { amountCents = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Limpar valor")
                }
            }
            .padding(16)
            .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.icon).stroke(Theme.line, lineWidth: 1))

            HStack(spacing: 8) {
                ForEach([20, 50, 100, 200], id: \.self) { v in
                    Button {
                        amountCents = String(v * 100)
                        Haptics.tap()
                    } label: {
                        Text("R$ \(v)")
                            .font(.auroraCaption).foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(Theme.surface1, in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Descrição (opcional)").font(.auroraLabel).foregroundStyle(Theme.text2)
            TextField("Ex.: racha do jantar", text: $note)
                .font(.auroraBody).foregroundStyle(Theme.text)
                .focused($noteFocused)
                .padding(16)
                .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.icon)
                        .stroke(noteFocused ? Theme.cyan : Theme.line, lineWidth: 1)
                )
        }
    }

    // MARK: Ações

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = payload
                Haptics.success()
                model.showToast("Código Pix copiado")
            } label: {
                Text("Copiar código Pix")
                    .font(.display(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Theme.cyan, in: .rect(cornerRadius: Theme.Radius.icon))
            }
            .buttonStyle(.plain)

            ShareLink(item: payload) {
                Text("Compartilhar cobrança")
                    .font(.display(16, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Theme.surface1, in: .rect(cornerRadius: Theme.Radius.icon))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.icon)
                            .stroke(Theme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// Payload EMV do Pix (BR Code), montado conforme o padrão do Bacen.
    private var payload: String {
        PixPayload.build(
            key: key?.value ?? model.user.cpf,
            name: model.user.name,
            city: "SAO PAULO",
            amount: amount.isZero ? nil : amount,
            txid: note.isEmpty ? "***" : String(note.prefix(25))
        )
    }
}

// MARK: - BR Code

enum PixPayload {
    /// Monta o payload no formato EMV TLV e acrescenta o CRC16-CCITT.
    static func build(key: String, name: String, city: String,
                      amount: Money?, txid: String) -> String {
        func tlv(_ id: String, _ value: String) -> String {
            id + String(format: "%02d", value.count) + value
        }
        let gui = tlv("00", "br.gov.bcb.pix")
        let keyField = tlv("01", key)
        let merchant = tlv("26", gui + keyField)

        var out = tlv("00", "01")                     // payload format
        out += amount == nil ? tlv("01", "11") : tlv("01", "12") // estático/dinâmico
        out += merchant
        out += tlv("52", "0000")                      // categoria
        out += tlv("53", "986")                       // BRL
        if let amount {
            let v = NSDecimalNumber(decimal: amount.amount.rounded(2))
            out += tlv("54", String(format: "%.2f", v.doubleValue))
        }
        out += tlv("58", "BR")
        out += tlv("59", String(sanitize(name).prefix(25)))
        out += tlv("60", String(sanitize(city).prefix(15)))
        out += tlv("62", tlv("05", sanitize(txid)))
        out += "6304"
        return out + crc16(out)
    }

    private static func sanitize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .init(identifier: "pt_BR"))
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "*" }
    }

    /// CRC16-CCITT (polinômio 0x1021, valor inicial 0xFFFF).
    static func crc16(_ s: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in Array(s.utf8) {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return String(format: "%04X", crc)
    }
}

// MARK: - Gerador de QR

enum QRGenerator {
    private static let context = CIContext()

    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
