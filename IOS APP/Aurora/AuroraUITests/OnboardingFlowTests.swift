import XCTest

/// Percorre o app de ponta a ponta na simulação, do onboarding ao Pix.
/// Serve como verificação de que os fluxos realmente completam — no
/// protótipo HTML não havia como testar isso.
@MainActor
final class OnboardingFlowTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-auroraResetState"]   // sempre do zero
        app.launch()
    }

    /// Abre conta, cria PIN, entra e confirma que a home carregou.
    func testOnboardingCreatesPinAndReachesHome() {
        app.buttons["Abrir minha conta"].firstMatch.tap()

        fillIdentity()
        tapCTA()

        // Passo 2: prova de vida (capturar → aguarda análise → continuar)
        XCTAssertTrue(waitForLiveness(), "passo de prova de vida não apareceu")
        tapCTA()                                  // "Capturar"
        XCTAssertTrue(
            element("livenessOK").waitForExistence(timeout: 10),
            "análise da prova de vida não concluiu"
        )
        tapCTA()                                  // "Continuar"

        // Passo 3: conta e termos
        XCTAssertTrue(app.staticTexts["Escolha sua conta"].waitForExistence(timeout: 5))
        app.buttons["Aceitar os termos de uso"].tap()
        tapCTA()

        // Passo 4: criar PIN (novo — não existia no protótipo)
        XCTAssertTrue(app.staticTexts["Crie seu PIN"].waitForExistence(timeout: 5),
                      "passo de criação de PIN não apareceu")
        typePin("2846")
        XCTAssertTrue(app.staticTexts["Confirme seu PIN"].waitForExistence(timeout: 3),
                      "não avançou para confirmação do PIN")
        typePin("2846")
        tapCTA()

        // Tela de bloqueio: entrar com o PIN recém-criado
        XCTAssertTrue(app.staticTexts["Digite seu PIN de 4 dígitos"].waitForExistence(timeout: 6),
                      "não chegou na tela de PIN")
        typePin("2846")

        // Home carregada com dados do mock
        XCTAssertTrue(app.staticTexts["Saldo disponível"].waitForExistence(timeout: 10),
                      "home não carregou")
        XCTAssertTrue(app.staticTexts["Movimentações"].waitForExistence(timeout: 10),
                      "extrato recente não carregou")
    }

    /// PIN fraco deve ser recusado — o protótipo aceitava qualquer coisa.
    func testWeakPinIsRejected() {
        app.buttons["Abrir minha conta"].firstMatch.tap()
        fillIdentity()
        tapCTA()

        XCTAssertTrue(waitForLiveness())
        tapCTA()
        XCTAssertTrue(element("livenessOK").waitForExistence(timeout: 10))
        tapCTA()

        XCTAssertTrue(app.staticTexts["Escolha sua conta"].waitForExistence(timeout: 5))
        app.buttons["Aceitar os termos de uso"].tap()
        tapCTA()

        XCTAssertTrue(app.staticTexts["Crie seu PIN"].waitForExistence(timeout: 5))
        typePin("1234")   // sequência — deve ser recusada
        XCTAssertTrue(
            app.staticTexts["PIN muito fácil de adivinhar. Escolha outro."]
                .waitForExistence(timeout: 3),
            "PIN sequencial 1234 foi aceito"
        )
    }

    /// Preenche nome, CPF e e-mail, fechando o teclado entre os campos para
    /// que o próximo não fique coberto.
    private func fillIdentity() {
        let nome = app.textFields["campoNome"]
        XCTAssertTrue(nome.waitForExistence(timeout: 5), "campo de nome não apareceu")
        nome.tap(); nome.typeText("Marina Costa")

        let cpf = app.textFields["campoCPF"]
        cpf.tap(); cpf.typeText("52998224725")   // CPF com dígitos verificadores válidos

        let email = app.textFields["campoEmail"]
        email.tap(); email.typeText("marina@email.com")

        // Dispensa o teclado de forma determinística. `swipeDown` na app
        // inteira às vezes rolava a ScrollView em vez de fechar o teclado,
        // deixando o CTA fora de alcance de maneira intermitente.
        if app.keyboards.element.waitForExistence(timeout: 2) {
            app.buttons["fecharTeclado"].firstMatch.tap()
        }
    }

    /// O passo de prova de vida agrupa seus filhos num único elemento de
    /// acessibilidade, então esperamos pelo container, não por um texto.
    private func waitForLiveness() -> Bool {
        // Espera pelo container da prova de vida em si. Um fallback pelo
        // indicador "Passo 2 de 4" casaria cedo demais, antes de a view
        // montar, e dessincronizaria os toques seguintes.
        element("livenessPendente").waitForExistence(timeout: 15)
    }

    /// O container combinado do passo de prova de vida é exposto como
    /// StaticText (confirmado na árvore de acessibilidade).
    private func element(_ id: String) -> XCUIElement {
        app.staticTexts[id]
    }

    private func tapCTA() {
        let cta = app.buttons["onboardingCTA"]
        XCTAssertTrue(cta.waitForExistence(timeout: 8), "botão de avançar não apareceu")
        // Só toca quando o botão está de fato alcançável — se o teclado
        // ainda estiver subindo, o toque cairia sobre ele.
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: cta)
        waitForExpectations(timeout: 8)
        cta.tap()
    }

    private func typePin(_ pin: String) {
        for digit in pin {
            let key = app.buttons[String(digit)]
            XCTAssertTrue(key.waitForExistence(timeout: 3), "tecla \(digit) não encontrada")
            key.tap()
        }
    }
}
