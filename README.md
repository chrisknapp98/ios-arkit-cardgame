# 🃏 CABO – AR Card Game

## Overview

CABO is a digital adaptation of the card game **CABO**, implemented in **Swift** using **ARKit** and **RealityKit**.  
It provides an immersive _Pass & Play_ augmented reality experience on iPhone and iPad, following the official CABO rules.

The project demonstrates how ARKit can be used to represent a card game in 3D space, handle gesture-based interactions, and manage animated game states with physical realism.

---

## Gameplay Concept

CABO is a memory-based card game where players aim to achieve the lowest total card value at the end of each round.  
This version supports **Pass & Play** mode, allowing players to take turns on the same device. Only one player interacts with the device at a time. Don't fool your friends and play honest!

## Game Flow

### PreGame

- Initializes draw and discard piles
- Positions players and distributes cards into a **2×2 grid**

### InGame

- Implements official rules from CABO game, but with playing classic cards
- Displays the active player using a black pofile object in front of the cards

### PostGame

- Evaluates end-of-game conditions
- Calculates total scores and determines the winner
- Provides a “Play Again” option that resets the scene efficiently

---

## 📹 Demo Video

**5-Minute Showcase**

> Recorded on an iPhone 11 (without LiDAR sensor).

![](docs/showcase.mp4)

---

## Possible Future Work

- Online multiplayer support across devices
- Optimized model position, fixing overlapping models
- Dedicated Game Manager for cleaner logic separation as currently, ViewController is a god class.
