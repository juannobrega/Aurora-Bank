import XCTest

/// Percorre **todas** as telas e confirma que cada uma abre de verdade.
/// Substitui a inspeção visual: se uma rota não estiver registrada na pilha,
/// o `NavigationLink` não faz nada e o teste falha aqui.
@MainActor
final class NavigationTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-auroraResetState", "-auroraSkipIntro", "-auroraAutoLogin"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Saldo disponível"].waitForExistence(timeout: 20),
                      "home não carregou")
    }

    // MARK: Atalhos da home

    func testHomeShortcutsOpenEveryScreen() {
        let destinos: [(atalho: String, marcador: String)] = [
            ("Pagar",      "Pagar"),
            ("Investir",   "Investimentos"),
            ("Crédito",    "Crédito"),
            ("Cofrinhos",  "Planejar"),
            ("Gastos",     "Planejar"),
            ("Extrato",    "Extrato"),
            ("Segurança",  "Central de segurança"),
            ("Ajuda",      "Ajuda"),
        ]
        for d in destinos {
            // "Extrato" nomeia tanto a aba quanto o atalho. A aba tem
            // identifier (vem do systemImage); o atalho não — filtrar por
            // identifier vazio pega o atalho certo.
            let atalho = app.buttons
                .matching(NSPredicate(format: "label == %@ AND identifier == ''", d.atalho))
                .firstMatch
            XCTAssertTrue(atalho.waitForExistence(timeout: 5),
                          "atalho \(d.atalho) não existe na home")
            atalho.tap()
            XCTAssertTrue(
                app.staticTexts[d.marcador].waitForExistence(timeout: 6),
                "atalho \(d.atalho) não abriu \(d.marcador)"
            )
            // Atalhos que apontam para uma aba trocam de aba; os demais
            // empurram na pilha. Voltar para a home cobre os dois casos.
            voltar()
            if !app.staticTexts["Saldo disponível"].waitForExistence(timeout: 2) {
                app.buttons["Início"].firstMatch.tap()
            }
            // Garante que voltamos mesmo para a home antes do próximo atalho;
            // caso contrário a falha aparece no atalho seguinte, escondendo
            // a causa real.
            XCTAssertTrue(
                app.staticTexts["Saldo disponível"].waitForExistence(timeout: 6),
                "não voltou para a home depois de abrir \(d.marcador)"
            )
        }
    }

    /// Telas empilhadas que abrem a partir de outra tela empilhada — é onde
    /// uma rota não registrada passa despercebida.
    func testNestedScreensOpen() {
        // Investimentos → detalhe da posição
        app.buttons["Investir"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Investimentos"].waitForExistence(timeout: 6))
        app.staticTexts["CDB Aurora"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Posição"].waitForExistence(timeout: 6),
                      "detalhe da posição não abriu a partir de Investimentos")
        voltar(); voltar()

        // Cofrinhos → detalhe da meta
        app.buttons["Cofrinhos"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Planejar"].waitForExistence(timeout: 6))
        app.staticTexts["Viagem para o Chile"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Cofrinho"].waitForExistence(timeout: 6),
                      "detalhe do cofrinho não abriu")
        voltar(); voltar()

        // Extrato → comprovante da transação
        app.buttons["Extrato"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Extrato"].waitForExistence(timeout: 6))
        app.staticTexts["Salário"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Comprovante"].waitForExistence(timeout: 6),
                      "comprovante não abriu a partir do extrato")
        voltar(); voltar()
    }

    // MARK: Abas

    func testEveryTabOpens() {
        for (aba, marcador) in [("Extrato", "Extrato"), ("Pix", "Pix"),
                                ("Cartões", "Cartões"), ("Perfil", "Perfil"),
                                ("Início", "Saldo disponível")] {
            app.buttons[aba].firstMatch.tap()
            XCTAssertTrue(app.staticTexts[marcador].waitForExistence(timeout: 6),
                          "aba \(aba) não abriu")
        }
    }

    /// Telas que só existem dentro da aba Pix.
    func testPixSubscreens() {
        app.buttons["Pix"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pix"].waitForExistence(timeout: 6))

        for (acao, marcador) in [("Receber", "Receber"), ("Chaves", "Minhas chaves"),
                                 ("Limites", "Limites do Pix")] {
            app.buttons[acao].firstMatch.tap()
            XCTAssertTrue(app.staticTexts[marcador].waitForExistence(timeout: 6),
                          "\(acao) não abriu \(marcador)")
            voltar()
        }
    }

    private func voltar() {
        let back = app.buttons["Voltar"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
    }
}
