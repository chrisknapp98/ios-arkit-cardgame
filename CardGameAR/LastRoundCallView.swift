//
//  LastRoundCallView.swift
//  CardGameAR
//
//  Created by Christopher Knapp on 18.07.23.
//

import Foundation
import SwiftUI
import Combine

struct LastRoundCallView: View {
    let gameState: AnyPublisher<GameState, Never>
    let callLastRoundAction: (Int) -> Void
    @State private var buttonAction: (() -> Void)?
    
    var body: some View {
        Button {
            buttonAction?()
        } label: {
            Text("CABO")
        }
        .buttonStyle(.glassProminent)
        .onReceive(gameState) { gameState in
            if case let .inGame(state) = gameState {
                if case let .selectedInteractionType(playerId, _, _) = state {
                    buttonAction = { [callLastRoundAction] in
                        callLastRoundAction(playerId)
                    }
                }
            }
        }
    }
}

