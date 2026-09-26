import Foundation

/// Snapshot inicial da conta. Trocar `MockAccountService` por uma
/// implementação de rede não exige mudar nenhuma view.
struct AccountSnapshot: Sendable {
    var user: User
    var ledger: Ledger
    var card: Card
    var holdings: [Holding]
    var goals: [Goal]
    var loans: [Loan]
    var pixKeys: [PixKey]
    var contacts: [Contact]
    var monthlyBudget: Money
    var creditScore: Int
}

protocol AccountServicing: Sendable {
    func loadAccount() async throws -> AccountSnapshot
}

/// Dados mockados. A latência artificial existe de propósito: obriga as
/// telas a terem estado de carregamento desde já.
struct MockAccountService: AccountServicing {
    var latency: Duration = .milliseconds(450)

    func loadAccount() async throws -> AccountSnapshot {
        try await Task.sleep(for: latency)
        return MockData.snapshot()
    }
}

enum MockData {
    static func snapshot() -> AccountSnapshot {
        AccountSnapshot(
            user: User(
                name: "Marina Costa",
                cpf: "482.917.330-12",
                email: "marina.costa@email.com",
                phone: "(11) 99873-3120"
            ),
            ledger: Ledger(openingBalance: 1_950.31, transactions: transactions()),
            card: Card(invoiceDue: nextTenth()),
            holdings: [
                Holding(id: "cdb", invested: 7_800, current: 8_200),
                Holding(id: "selic", invested: 5_150, current: 5_350),
                Holding(id: "lci", invested: 2_900, current: 3_000),
                Holding(id: "fii", invested: 1_500, current: 1_480),
            ],
            goals: [
                Goal(name: "Viagem para o Chile", saved: 3_200, target: 8_000,
                     symbol: "airplane", deadline: months(from: .now, 8)),
                Goal(name: "Reserva de emergência", saved: 9_400, target: 12_000,
                     symbol: "shield.fill"),
                Goal(name: "Notebook novo", saved: 1_150, target: 6_500,
                     symbol: "laptopcomputer", deadline: months(from: .now, 5)),
            ],
            loans: [],
            pixKeys: [
                PixKey(kind: .cpf, value: "482.917.330-12", masked: "***.917.330-**"),
                PixKey(kind: .celular, value: "(11) 99873-3120", masked: "(11) 9****-3120"),
            ],
            contacts: [
                Contact(name: "Ana Luiza Prado", key: "ana.prado@email.com"),
                Contact(name: "João Pedro Lima", key: "(11) 98820-4471", bank: "Banco Aurora"),
                Contact(name: "Bruna Takeda", key: "bruna@takeda.dev"),
                Contact(name: "Rafael Souza", key: "123.456.789-10", bank: "Caixa Vermelha"),
            ],
            monthlyBudget: 4_000,
            creditScore: 742
        )
    }

    /// Histórico com datas reais, espalhado pelos últimos ~45 dias, para que
    /// filtro por período e gráfico de categorias tenham o que mostrar.
    private static func transactions() -> [Transaction] {
        let seeds: [(days: Int, hour: Int, title: String, who: String,
                     amount: Decimal, cat: Category, method: PaymentMethod)] = [
            (0,  9,  "Pix recebido", "João Pedro Lima",        150,     .transferencia, .pix),
            (0,  12, "Mercado Pão Fresco", "Compra no crédito", -87.40,  .mercado,       .credito),
            (0,  19, "Padaria Aurora", "Compra no débito",      -18.50,  .restaurantes,  .debito),
            (1,  8,  "Salário", "Studio Nuvem Ltda",            6_200,   .salario,       .ted),
            (1,  14, "Assinatura de música", "Compra no crédito", -21.90, .assinaturas,  .credito),
            (1,  18, "Corrida por app", "Compra no débito",     -18.70,  .transporte,    .debito),
            (2,  11, "Pix enviado", "Ana Luiza Prado",          -60,     .transferencia, .pix),
            (2,  16, "Rendimento", "CDB Aurora",                 12.34,  .rendimento,    .aplicacao),
            (2,  20, "Café Moinho", "Compra no crédito",        -45.90,  .restaurantes,  .credito),
            (4,  10, "Aluguel", "Imobiliária Vega",           -1_200,    .moradia,       .boleto),
            (5,  13, "Supermercado Vila", "Compra no crédito", -312.80,  .mercado,       .credito),
            (6,  9,  "Academia Pulse", "Compra no crédito",     -119,    .saude,         .credito),
            (7,  21, "Cinema Lumière", "Compra no débito",       -68,    .lazer,         .debito),
            (9,  15, "Posto Sol", "Compra no crédito",          -210.40, .transporte,    .credito),
            (11, 12, "Restaurante Sal", "Compra no crédito",    -142.30, .restaurantes,  .credito),
            (13, 17, "Farmácia Bem", "Compra no débito",         -76.20, .saude,         .debito),
            (15, 10, "Curso de inglês", "Escola Falo",          -389,    .educacao,      .boleto),
            (18, 14, "Internet fibra", "NetVia Telecom",        -129.90, .moradia,       .boleto),
            (21, 11, "Supermercado Vila", "Compra no crédito",  -284.60, .mercado,       .credito),
            (24, 16, "Streaming de vídeo", "Compra no crédito",  -39.90, .assinaturas,   .credito),
            (28, 9,  "Pix recebido", "Bruna Takeda",             320,    .transferencia, .pix),
            (32, 8,  "Salário", "Studio Nuvem Ltda",           6_200,    .salario,       .ted),
            (33, 10, "Aluguel", "Imobiliária Vega",           -1_200,    .moradia,       .boleto),
            (38, 19, "Jantar aniversário", "Compra no crédito", -256.70, .restaurantes,  .credito),
            (42, 15, "Conta de luz", "Enel Distribuição",       -187.40, .moradia,       .boleto),
        ]

        let cal = Calendar.current
        return seeds.compactMap { s in
            guard let day = cal.date(byAdding: .day, value: -s.days, to: .now),
                  let date = cal.date(bySettingHour: s.hour, minute: Int.random(in: 0...59),
                                      second: 0, of: day) else { return nil }
            return Transaction(
                date: date,
                title: s.title,
                counterparty: s.who,
                amount: Money(s.amount),
                category: s.cat,
                method: s.method
            )
        }
    }

    /// Dia 10 do próximo vencimento de fatura.
    static func nextTenth() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: .now)
        comps.day = 10
        let thisMonth = cal.date(from: comps) ?? .now
        return thisMonth > .now ? thisMonth : (cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth)
    }

    static func months(from date: Date, _ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: n, to: date) ?? date
    }

    /// Boletos reconhecidos pelo "scanner" mockado.
    static func boleto(for code: String) -> BoletoFlow {
        let digits = code.filter(\.isNumber)
        let presets: [(String, Decimal, Category, Int)] = [
            ("Enel Distribuição", 187.40, .moradia, 6),
            ("Sabesp", 94.20, .moradia, 9),
            ("NetVia Telecom", 129.90, .moradia, 12),
            ("Imobiliária Vega", 1_200, .moradia, 4),
        ]
        let pick = presets[abs(digits.hashValue) % presets.count]
        return BoletoFlow(
            barcode: code,
            payee: pick.0,
            amount: Money(pick.1),
            dueDate: Calendar.current.date(byAdding: .day, value: pick.3, to: .now) ?? .now,
            category: pick.2
        )
    }

    static func carrier(for phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        let carriers = ["Vivo", "Claro", "TIM", "Oi"]
        guard digits.count >= 3 else { return "Operadora" }
        return carriers[abs(digits.hashValue) % carriers.count]
    }
}
