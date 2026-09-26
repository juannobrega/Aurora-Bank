import SwiftUI

/// Envelope identificável para apresentar um fluxo em folha modal.
struct FlowPresentation: Identifiable {
    let id = UUID()
    let flow: any TransactionFlow
    var startAt: FlowStep?
}

extension View {
    /// Apresenta o motor de fluxo em tela cheia, do jeito que apps de banco
    /// fazem: o fluxo transacional não divide espaço com a navegação.
    func flowSheet(_ presentation: Binding<FlowPresentation?>) -> some View {
        fullScreenCover(item: presentation) { p in
            NavigationStack {
                FlowView(flow: p.flow, startAt: p.startAt)
            }
        }
    }
}
