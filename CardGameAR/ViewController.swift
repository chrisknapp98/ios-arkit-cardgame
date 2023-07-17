//
//  ViewController.swift
//  CardGameAR
//
//  Created by Christopher Knapp on 23.04.23.
//

import UIKit
import ARKit
import RealityKit
import Combine
import SwiftUI

class ViewController: UIViewController {
    
    private var arView: ARView = ARView(frame: .zero)
    private var playingCardModels: [PlayingCard: ModelEntity] = [:]
    private let currentGameState = CurrentValueSubject<GameState, Never>(.preGame(.loadingAssets))
//    private let currentGameState = CurrentValueSubject<GameState, Never>(.inGame(.selectedInteractionType(0, .discard)))
    private var drawPile: DrawPile?
    private var discardPile: DiscardPile?
    private var players: [Player] = []
    private var cancellables = Set<AnyCancellable>()
    private var callToActionView: UIView?
    private var undoView: UIView?
    
    private let cardsPerPlayer: Int = 4
    
    // MARK: - Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
        arView.session.delegate = self
        //        arView.debugOptions = [.showAnchorOrigins, .showPhysics]
        //        arView.debugOptions = [.showPhysics]
        arView.addCoaching()
        arView.environment.sceneUnderstanding.options.insert(.receivesLighting)
        runOcclusionConfiguration()
        addCallToActionView()
        addUndoView()
        Task {
            await preloadAllModelEntities()
            arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:))))
            updateGameState(.preGame(.placeDrawPile))
        }
        subscribeToGameStateChanges()
    }
    
    private func subscribeToGameStateChanges() {
        currentGameState.sink { [weak self] gameState in
            switch gameState {
            case .inGame(let state):
                switch state {
                case .waitForInteractionTypeSelection:
                    self?.callToActionView?.isUserInteractionEnabled = true
                    self?.undoView?.isHidden = true
                    break
                case .selectedInteractionType:
                    self?.callToActionView?.isUserInteractionEnabled = false
                    self?.undoView?.isHidden = false
                    break
                default:
                    self?.undoView?.isHidden = true
                    break
                }
                break
            default:
                break
            }
        }
        .store(in: &cancellables)
    }
    
    private func runOcclusionConfiguration() {
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth) // crashes on iPhone 11
        }
        // disabled because it's not applied although it seems to be available on iPhone 11
        //        if ARConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
        configuration.frameSemantics.insert(.personSegmentationWithDepth)
        //        }
        arView.session.run(configuration)
    }
    
    private func addCallToActionView() {
        let hostingController = UIHostingController(rootView: CallToActionView(
            gameState: currentGameState.eraseToAnyPublisher(),
            updateGameStateAction: { gameState in
                self.updateGameState(gameState)
            })
        )
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = false
        callToActionView = hostingController.view
        arView.addSubview(hostingController.view)
        hostingController.view?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: arView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
    }
    
    private func addUndoView() {
        let hostingController = UIHostingController(rootView: UndoView(
            gameState: currentGameState.eraseToAnyPublisher(),
            updateGameStateAction: { gameState in
                self.updateGameState(gameState)
            }
        ))
        hostingController.view.backgroundColor = .clear
        hostingController.view.isHidden = true
        undoView = hostingController.view
        arView.addSubview(hostingController.view)
        hostingController.view?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: arView.topAnchor, constant: 130),
            hostingController.view.leadingAnchor.constraint(equalTo: arView.trailingAnchor, constant: -100),
            hostingController.view.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: arView.topAnchor, constant: 180)
        ])
    }
    
    @MainActor
    private func updateGameState(_ gameState: GameState) {
        if case let .inGame(state) = currentGameState.value {
            if case let .currentTurn(playerId) = state {
                players.first(where: { $0.identity == playerId })?.hideAvatar()
            }
        }
        if case let .inGame(state) = gameState {
            if case let .currentTurn(playerId) = state {
                players.first(where: { $0.identity == playerId })?.showAvatar()
            }
        }
        currentGameState.send(gameState)
    }
    
    private func preloadAllModelEntities() async {
        let loadedModels: [PlayingCard: ModelEntity]? = try? await PlayingCard.allBlueCards()
            .reduceAsync([PlayingCard: ModelEntity]()) { partialResult, card in
                var partialResult = partialResult
                guard let modelEntity: ModelEntity = try? await loadModelAsync(named: card.assetName) else {
                    print("Failed to load model for Card")
                    throw CardGameError.failedToLoadModel
                }
                partialResult[card] = modelEntity
                return partialResult
            }
        guard let loadedModels else { return }
        self.playingCardModels = loadedModels
    }
    
    private func loadModelAsync(named entityName: String) async throws -> ModelEntity {
        return try await withCheckedThrowingContinuation { continuation in
            ModelEntity.loadModelAsync(named: entityName)
                .subscribe(
                    Subscribers.Sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .failure(let error):
                                print("Couldn't load model for entity name \(entityName)")
                                continuation.resume(throwing: error)
                                break
                            case .finished:
                                break
                            }
                        }, receiveValue: { modelEntity in
                            continuation.resume(returning: modelEntity)
                        }
                    )
                )
        }
    }
    
    // MARK: - Object Placement
    
    private func placeDrawPile(cards: [PlayingCard], for anchor: ARAnchor) async {
        let drawPile = DrawPile(with: cards, from: playingCardModels)
        arView.installGestures([.rotation, .translation], for: drawPile.entity)
        let parentAnchor = AnchorEntity(anchor: anchor)
        parentAnchor.addChild(drawPile.entity)
        arView.scene.addAnchor(parentAnchor)
        self.drawPile = drawPile
    }
    
    private func placeDiscardPile(for anchor: ARAnchor) {
        let discardPile = DiscardPile()
        discardPile.entity.generateCollisionShapes(recursive: true)
        let discardPileAnchor = AnchorEntity(anchor: anchor)
        discardPileAnchor.addChild(discardPile.entity)
        arView.installGestures([.rotation, .translation], for: discardPile.entity)
        arView.scene.addAnchor(discardPileAnchor)
        self.discardPile = discardPile
    }
    
    private func transformForDiscardPile(drawPileTransform: simd_float4x4) -> simd_float4x4 {
        var drawPileTransform = drawPileTransform
        // maybe choose x or/and z axis based on device orientation whatsoever
        drawPileTransform.columns.3.x += 0.1
        return drawPileTransform
    }
    
    // MARK: - Touch Interaction
    
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: arView)
        // TODO: switch case
        if case let .preGame(state) = currentGameState.value {
            if state == .setPlayerPositions {
                let hits = arView.hitTest(location, query: .nearest, mask: .all)
                if let playerEntity = hits.first?.entity as? Player {
                    playerEntity.removeFromParent()
                    players.remove(at: playerEntity.identity)
                    return
                } else if let cardEntity = hits.first?.entity, cardEntity.name.contains("Playing_Card") {
                    Task {
                        await dealCards()
                        startGame()
                    }
                    return
                }
            }
        }
        
        if case let .inGame(state) = currentGameState.value {
            let hits = arView.hitTest(location, query: .nearest, mask: .all)
            let modelEntity = hits.first?.entity as? ModelEntity
            if let parentEntity = modelEntity?.parent, parentEntity.name == DrawPile.identifier || parentEntity.name == DiscardPile.identifier {
                if case let .currentTurn(playerid) = state,
                   let player = players.first(where:{ $0.identity == playerid}),
                   let cardValue = modelEntity?.name.getPlayingCardValue() {
                    Task {
                        await parentEntity.moveCardToPlayerWithOffset(player: player)
                        updateGameState(.inGame(.waitForInteractionTypeSelection(playerid, cardValue: cardValue)))
                    }
                }
            }
            if case let .selectedInteractionType(playerId, interactionType, _) = state,
               let player = players.first(where:{ $0.identity == playerId}),
               let modelEntity, let discardPile,
               let anyPlayer = modelEntity.parent as? Player {
                switch interactionType {
                case .discard:
                    Task {
                        if anyPlayer.identity == playerId {
                            let didEndTurn = await player.didDiscardDrawnCardOnCardSelection(modelEntity, discardPile: discardPile)
                            if didEndTurn {
                                endTurn(currentPlayerId: playerId)
                            }
                        }
                    }
                    break
                case .swapDrawnWithOwnCard:
                    Task {
                        if anyPlayer.identity == playerId {
                            await player.swapDrawnCardWithOwnCoveredCard(card: modelEntity, discardPile: discardPile)
                            endTurn(currentPlayerId: playerId)
                        }
                    }
                    break
                case .performAction(let cardAction):
                    switch cardAction {
                    case .peek:
                        Task {
                            if anyPlayer.identity == playerId {
                                await player.peekCard(card: modelEntity, discardPile: discardPile)
                                endTurn(currentPlayerId: playerId)
                            }
                        }
                        break
                    case .spy:
                        break
                    case .swap:
                        break
                    case .anyAction:
                        break
                    }
                    break
                }
            }
            return
        }
        
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
        if let firstResult = results.first {
            if case let .preGame(state) = currentGameState.value {
                if state == .placeDrawPile {
                    let drawPileAnchor = ARAnchor(name: DrawPile.identifier, transform: firstResult.worldTransform)
                    arView.session.add(anchor: drawPileAnchor)
                    let discardPileAnchor = ARAnchor(
                        name: DiscardPile.identifier,
                        transform: transformForDiscardPile(drawPileTransform: firstResult.worldTransform)
                    )
                    arView.session.add(anchor: discardPileAnchor)
                } else if state == .setPlayerPositions {
                    let anchor = ARAnchor(name: "player_positions", transform: firstResult.worldTransform)
                    arView.session.add(anchor: anchor)
                }
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } else {
            print("Object placement failed. Couldn't find a surface.")
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    
    private func dealCards() async {
        updateGameState(.inGame(.dealingCards))
        await drawPile?.dealCards(cardsPerPlayer: cardsPerPlayer, players: players)
        if let discardPile {
            await drawPile?.moveLastCardToDiscardPile(discardPile)
        }
        for player in players {
            rotatePlayerFacingTowardsDrawPile(player)
            await player.arrangeCardsInGridForPlayer(player: player)
        }
    }
    
    func rotatePlayerFacingTowardsDrawPile(_ player: Player)  {
        if let drawPile {
            let playerPosition = player.position(relativeTo: nil)
            let drawPilePosition = drawPile.entity.position(relativeTo: nil)
            
            player.look(at: drawPilePosition,
                        from: playerPosition,
                        relativeTo: nil)
            
            print("dealCards: after animation \(player.transform.translation)")
        }
    }
    
    private func startGame() {
        let randomPlayerIndex = Int.random(in: 0..<players.count)
        updateGameState(.inGame(.currentTurn(randomPlayerIndex)))
        for player in players {
            if player.identity != randomPlayerIndex {
                player.hideAvatar()
            }
        }
    }
    
    private func nextPlayerIdentityInOrder(currentPlayerId: Int) -> Int? {
        guard let currentPlayer = players.first(where: { $0.identity == currentPlayerId }),
              let playersIndexInArray = players.firstIndex(of: currentPlayer)
        else { return nil }
        
        if playersIndexInArray == players.count - 1 {
            return 0
        } else {
            return playersIndexInArray + 1
        }
    }
    
    private func endTurn(currentPlayerId: Int) {
        guard let nextPlayerId = nextPlayerIdentityInOrder(currentPlayerId: currentPlayerId) else { return }
        updateGameState(.inGame(.currentTurn(nextPlayerId)))
    }
    
}

// MARK: - ARView Coaching Overlay

extension ARView: ARCoachingOverlayViewDelegate {
    func addCoaching() {
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.delegate = self
        coachingOverlay.session = self.session
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.layer.position = CGPoint(x: self.bounds.size.width/2, y: self.bounds.size.height/2)
        coachingOverlay.goal = .horizontalPlane
        self.addSubview(coachingOverlay)
    }
    
    public func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        // Ready to add entities next?
        // Maybe automatically add the card deck in the middle of the table after a surface has been identified
    }
}

// MARK: - ARSessionDelegate

extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            // TODO: introduce some sort of game state to match the expected anchorName
            if let anchorName = anchor.name, anchorName == DrawPile.identifier {
                Task {
                    await placeDrawPile(cards: PlayingCard.allBlueCards(), for: anchor)
                    updateGameState(.preGame(.setPlayerPositions))
                }
            } else if let anchorName = anchor.name, anchorName == DiscardPile.identifier {
                placeDiscardPile(for: anchor)
            } else if let anchorName = anchor.name, anchorName == "player_positions" {
                setPlayerPosition(for: anchor)
            }
        }
    }
    
    private func setPlayerPosition(for anchor: ARAnchor) {
        let entity = Player(identity: players.count)
        arView.installGestures([.translation], for: entity)
        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)
        players.append(entity)
    }
}
