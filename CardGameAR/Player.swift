//
//  Player.swift
//  CardGameAR
//
//  Created by Christopher Knapp on 25.06.23.
//

import Foundation
import RealityKit
import UIKit

class Player: Entity, HasModel, HasCollision {
    
    let identity: Int
    
    let avatarWidth: Float = 0.05
    static let avatarHeight: Float = 0.0001
    let avatarDepth: Float = 0.05
    
    private var avatar: ModelEntity
    private var currentlyDrawnCard: Entity?
    private var cardsToDiscard: [Entity] = []
    
    var hasCards: Bool {
        !children.filter { $0.name.contains(PlayingCard.prefix) }.isEmpty
    }
    
    var points: Int {
        children.filter { $0.name.contains(PlayingCard.prefix) }.reduce(0, { (currentSum, playingCardEntity) in
            currentSum + playingCardEntity.name.getPlayingCardValue()
        })
    }
    
    init(identity: Int) {
        self.identity = identity
        // Create a separate entity for the avatar
        avatar = ModelEntity()
        super.init()
        
        self.addChild(avatar)
        
        self.components[CollisionComponent.self] = CollisionComponent(shapes: [.generateBox(width: avatarWidth, height: Self.avatarHeight, depth: avatarDepth)])
        
        let mesh: MeshResource = .generatePlane(width: avatarWidth, depth: avatarDepth, cornerRadius: 8)
        
        var material = SimpleMaterial()
        if let image = UIImage(systemName: "person.circle.fill"),
           let cgImage = image.cgImage,
           let baseResource = try? TextureResource.generate(
            from: cgImage,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
           ) {
            material.color = SimpleMaterial.BaseColor(
                tint: .white.withAlphaComponent(0.999),
                texture: .init(baseResource)
            )
        }
        material.metallic = .float(1.0)
        material.roughness = .float(0.0)
        
        avatar.components[ModelComponent.self] = ModelComponent(mesh: mesh, materials: [material]) // Set the model on the avatar
        self.name = "Player-\(identity)"
        generateCollisionShapes(recursive: true)
    }
    
    @MainActor required init() {
        fatalError("init() has not been implemented")
    }
    
    @MainActor
    func arrangeDealtCardsInGrid() async {
        let cards = Array(self.children).filter { $0.name.contains(PlayingCard.prefix) }
        let gridWidth = 2
        let gridHeight = cards.count / gridWidth
        let cardSpacingW: Float = 0.07  // adjust this to set the spacing between the cards
        let cardSpacingH: Float = 0.1
        
        
        // Compute the total width and height of the grid
        let totalWidth = cardSpacingW * Float(gridWidth - 1)
        let totalHeight = cardSpacingH * Float(gridHeight - 1)
        
        // Define an offset for the grid
        let gridOffset = SIMD3<Float>(-totalWidth / 2, 0, -totalHeight)
        
        for (index, card) in cards.enumerated() {
            let row = index / gridWidth
            let column = index % gridWidth
            let offsetPosition = SIMD3<Float>(cardSpacingW * Float(column), 0, -cardSpacingH * Float(row))
            // Your existing quaternion, which is a 180 degree rotation around the x-axis
            let xAxisAlignment = simd_quatf(angle: Float.pi, axis: SIMD3(x: 1, y: 0, z: 0))
            
            // Get the player's rotation matrix and extract the y-axis vector
            let playerRotationMatrix = simd_float3x3(self.transform.rotation)
            let playerYAxisDirection = playerRotationMatrix.columns.1
            
            // Create a quaternion for the player's y-axis direction
            let playerYRotation = simd_quatf(from: SIMD3(x: 0, y: 1, z: 0), to: playerYAxisDirection)
            
            // Combine the two rotations by multiplying the quaternions
            let combineAlignment = xAxisAlignment * playerYRotation
            
            let alignedCardRotation = combineAlignment // card front facing to the plane
            let animationDefinition1 = FromToByAnimation(
                to: Transform(
                    rotation: alignedCardRotation,
                    translation: card.position(relativeTo: self) + offsetPosition + gridOffset
                ),
                bindTarget: .transform
            )
            let animationResource = try! AnimationResource.generate(with: animationDefinition1)
            
            await card.playAnimationAsync(animationResource, transitionDuration: 1, startsPaused: false)
        }
        
    }
    
    func showAvatar() {
        avatar.isEnabled = true
    }
    
    func hideAvatar() {
        avatar.isEnabled = false
    }
    
    func setDrawnCard(_ card: Entity) {
        currentlyDrawnCard = card
    }
    
    func didDiscardDrawnCardOnCardSelection(_ card: Entity, discardPile: DiscardPile) async -> Bool {
        if card != currentlyDrawnCard {
            cardsToDiscard.append(card)
            await turnCard(card)
            return false
        } else {
            if allMemorizedCardsMatchDrawnCard() {
                await discardMemorizedCards(to: discardPile)
            } else {
                for wronglyGuessedCard in cardsToDiscard {
                    await turnCard(wronglyGuessedCard)
                }
            }
            await discardDrawnCard(to: discardPile)
            cardsToDiscard = []
            return true
        }
    }
    
    func turnCard(_ card: Entity) async {
        let animationDefinition1 = FromToByAnimation(
            to: Transform(
                rotation: card.transform.rotation * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1)),
                translation: card.transform.translation
            ),
            bindTarget: .transform
        )
        let animationResource = try! AnimationResource.generate(with: animationDefinition1)
        
        await card.playAnimationAsync(animationResource, transitionDuration: 1, startsPaused: false)
    }
    
    private func allMemorizedCardsMatchDrawnCard() -> Bool {
        cardsToDiscard.allSatisfy { cardsToDiscard in
            cardsToDiscard.name.getPlayingCardValue() == currentlyDrawnCard?.name.getPlayingCardValue()
        }
    }
    
    private func discardMemorizedCards(to discardPile: DiscardPile) async {
        for card in cardsToDiscard {
            let transform = Transform(
                rotation: card.transform.rotation,
                translation: discardPile.entity.position(relativeTo: self)
            )
            await discardCard(card, with: transform, to: discardPile)
        }
    }
    
    private func discardDrawnCard(to discardPile: DiscardPile) async {
        guard let currentlyDrawnCard else { return }
        let transform = Transform(
            rotation: currentlyDrawnCard.transform.rotation,
            translation: discardPile.entity.position(relativeTo: self)
        )
        await discardCard(currentlyDrawnCard, with: transform, to: discardPile)
        self.currentlyDrawnCard = nil
    }
    
    private func discardCard(_ card: Entity, with transform: Transform, to discardPile: DiscardPile) async {
        var transform = transform
        let numberOfCardsInPile = discardPile.numberOfCardsInPile
        let yOffset = Float(numberOfCardsInPile) * (PlayingCard.thickness * 2)
        transform.translation += SIMD3<Float>(0, yOffset, 0)
        let animationDefinition1 = FromToByAnimation(to: transform, bindTarget: .transform)
        let animationResource = try! AnimationResource.generate(with: animationDefinition1)
        
        await card.playAnimationAsync(animationResource, transitionDuration: 1, startsPaused: false)
        removeChild(card, preservingWorldTransform: true)
        discardPile.entity.addChild(card, preservingWorldTransform: true)
    }
    
    func swapDrawnCardWithOwnCoveredCard(card: Entity, discardPile: DiscardPile) async {
        guard let currentlyDrawnCard else {
            print("Currently no card drawn")
            return
        }
        let animationDefinition1 = FromToByAnimation(
            to: Transform(
                rotation: card.transform.rotation * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1)),
                translation: currentlyDrawnCard.position(relativeTo: self)
            ),
            bindTarget: .transform
        )
        let animationDefinition2 = FromToByAnimation(
            to: Transform(
                rotation: currentlyDrawnCard.transform.rotation * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1)),
                translation: card.position(relativeTo: self)
            ),
            bindTarget: .transform
        )
        let animationResource1 = try! AnimationResource.generate(with: animationDefinition1)
        let animationResource2 = try! AnimationResource.generate(with: animationDefinition2)
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await card.playAnimationAsync(animationResource1, transitionDuration: 1, startsPaused: false)
            }
            group.addTask {
                await currentlyDrawnCard.playAnimationAsync(animationResource2, transitionDuration: 1, startsPaused: false)
            }
        }
        self.currentlyDrawnCard = card
        await discardDrawnCard(to: discardPile)
    }
    
    // MARK: - Card Actions
    
    func peekCard(card: Entity, discardPile: DiscardPile) async {
        await turnCard(card)
        try? await Task.sleep(for: .seconds(2))
        await turnCard(card)
        await discardDrawnCard(to: discardPile)
    }
    
    func swapCards(card1: Entity, card2: Entity, discardPile: DiscardPile) async {
        let ownCard = card1.parent == self ? card1 : card2
        let opponentsCard = card1.parent != self ? card1 : card2
        let opponentsPlayer = card1.parent != self ? card1.parent : card2.parent
        
        if ownCard == currentlyDrawnCard {
            currentlyDrawnCard = opponentsCard
        }
        
        // Get the global positions and rotations of the cards
        let ownCardGlobalTransform = ownCard.transformMatrix(relativeTo: nil)
        let opponentsCardGlobalTransform = opponentsCard.transformMatrix(relativeTo: nil)
        
        // Compute the transforms of the cards in the other players' local coordinate systems
        let ownCardInOpponentsCoordinates = opponentsPlayer!.transformMatrix(relativeTo: nil).inverse * ownCardGlobalTransform
        let opponentsCardInOwnCoordinates = self.transformMatrix(relativeTo: nil).inverse * opponentsCardGlobalTransform
        
        // Create the animation definitions
        let animationDefinition1 = FromToByAnimation(
            to: Transform(matrix: opponentsCardInOwnCoordinates),
            bindTarget: .transform
        )
        let animationDefinition2 = FromToByAnimation(
            to: Transform(matrix: ownCardInOpponentsCoordinates),
            bindTarget: .transform
        )
        let animationResource1 = try! AnimationResource.generate(with: animationDefinition1)
        let animationResource2 = try! AnimationResource.generate(with: animationDefinition2)
        
        // Play the animations
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await ownCard.playAnimationAsync(animationResource1, transitionDuration: 1, startsPaused: false)
            }
            group.addTask {
                await opponentsCard.playAnimationAsync(animationResource2, transitionDuration: 1, startsPaused: false)
            }
        }
        
        // Swap the parents of the cards
        let ownCardParent = ownCard.parent
        let opponentsCardParent = opponentsCard.parent
        ownCardParent?.removeChild(ownCard, preservingWorldTransform: true)
        opponentsCardParent?.removeChild(opponentsCard, preservingWorldTransform: true)
        ownCardParent?.addChild(opponentsCard, preservingWorldTransform: true)
        opponentsCardParent?.addChild(ownCard, preservingWorldTransform: true)
        
        await discardDrawnCard(to: discardPile)
    }
    
}

extension String {
    func getPlayingCardValue() -> Int {
        let numberString = String(split(separator: "_").last ?? "")
        if numberString == "J" {
            return 11
        } else if numberString == "Q" {
            return 12
        } else if numberString == "K" {
            return 13
        } else if numberString == "A" {
            return 0
        }
        return Int(numberString) ?? 0
    }
}
