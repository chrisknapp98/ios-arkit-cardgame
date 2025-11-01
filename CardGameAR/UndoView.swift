//
//  UndoView.swift
//  CardGameAR
//
//  Created by Christopher Knapp on 17.07.23.
//

import Foundation
import SwiftUI
import Combine

struct UndoView: View {
    let gameState: AnyPublisher<GameState, Never>
    let updateGameStateAction: (GameState) -> Void
    @State private var undoAction: (() -> Void)?
    
    var body: some View {
        Button {
            undoAction?()
        } label: {
            Text("Undo")
        }
        .buttonStyle(.glassProminent)
        .onReceive(gameState) { gameState in
            if case let .inGame(state) = gameState {
                if case let .selectedInteractionType(playerId, _, cardValue) = state {
                    undoAction = { [updateGameStateAction] in
                        updateGameStateAction(.inGame(.waitForInteractionTypeSelection(playerId, cardValue: cardValue)))
                    }
                }
            }
        }
    }
}
