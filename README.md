# Marriage Card Game — Godot 4
> The classic Nepali card game. Built with Godot 4, GDScript, ENet multiplayer.

---

## Quick Start

### 1. Install Godot 4
Download **Godot 4.2+** (Standard version, NOT .NET unless you want C#):
→ https://godotengine.org/download

No installer needed. Extract and run the executable.

### 2. Open the project
- Launch Godot
- Click **Import** → navigate to this folder → select `project.godot`
- Hit **Import & Edit**

### 3. Run the game
Press **F5** or the Play button. The game starts from `MainMenu.tscn`.

---

## Project Structure

```
marriage_card_game/
├── project.godot               ← Godot project config + autoloads
│
├── scripts/
│   ├── core/
│   │   ├── GameState.gd        ← Autoload: all game logic & state
│   │   ├── CardManager.gd      ← Autoload: deck building + meld validation
│   │   ├── CardData.gd         ← Resource: one card's data
│   │   ├── PlayerData.gd       ← Resource: one player's state
│   │   ├── MeldData.gd         ← Resource: a validated meld group
│   │   ├── Card.gd             ← Visual card node (draw, drag, flip)
│   │   ├── HandManager.gd      ← Manages player's hand layout
│   │   └── CPUPlayer.gd        ← AI opponent (Easy/Medium/Hard)
│   ├── ui/
│   │   ├── GameScene.gd        ← Main game scene controller
│   │   ├── MainMenu.gd         ← Main menu screen
│   │   └── AudioManager.gd     ← Autoload: SFX + music
│   └── network/
│       └── NetworkManager.gd   ← Autoload: ENet multiplayer
│
├── scenes/
│   ├── screens/
│   │   ├── MainMenu.tscn       ← Main menu (create in editor)
│   │   ├── GameScene.tscn      ← Main game table (create in editor)
│   │   ├── LobbyScreen.tscn    ← Online lobby
│   │   └── RulesScreen.tscn    ← How to play
│   └── components/
│       ├── Card.tscn           ← Visual card component
│       └── MeldGroup.tscn      ← Visual meld display
│
├── assets/
│   ├── cards/                  ← Card textures (optional, we draw with code)
│   ├── fonts/                  ← .ttf fonts (grab from Google Fonts)
│   ├── sounds/                 ← .ogg sound files
│   └── shaders/                ← .gdshader files
│
└── resources/                  ← Saved .tres resource files
```

---

## Creating Scenes in Godot Editor

### Card.tscn
```
Node2D (Card.gd)
└── Area2D
    └── CollisionShape2D  (RectangleShape2D, 80×112)
```

### GameScene.tscn
```
Node2D (GameScene.gd)
├── Table (Node2D)
│   ├── DeckPile (Area2D)
│   │   └── CollisionShape2D
│   └── DiscardPile (Area2D)
│       ├── CollisionShape2D
│       └── TopCard (Node2D)
├── PlayerHand (HandManager.gd)
└── UI (CanvasLayer)
    ├── TurnLabel (Label)
    ├── ScoreLabel (Label)
    ├── StatusLabel (Label)
    ├── PhaseLabel (Label)
    ├── DeckCount (Label)
    ├── MeldsPanel (PanelContainer)
    │   └── MeldsContainer (HBoxContainer)
    └── ActionBar (HBoxContainer)
        ├── BtnLayMeld (Button)
        ├── BtnDiscard (Button)
        └── BtnHint (Button)
```

### MainMenu.tscn
```
Control (MainMenu.gd)
├── VBox (VBoxContainer)
│   ├── TitleLabel (Label) — "Marriage"
│   ├── BtnPlay2P (Button) — "2 Players"
│   ├── BtnPlay3P (Button) — "3 Players"
│   ├── BtnPlay4P (Button) — "4 Players"
│   ├── DifficultyOption (OptionButton) — Easy/Medium/Hard
│   ├── BtnOnline (Button) — "Play Online"
│   └── BtnRules (Button) — "How to Play"
└── VersionLabel (Label)
```

---

## Game Rules (Marriage — Nepali style)

- **3 decks** = 162 cards total (52×3 + 6 jokers)
- **21 cards** dealt to each player
- **Goal**: empty your hand by forming melds

### Melds
| Type | Definition | Example |
|------|-----------|---------|
| **Sequence** | 3+ same-suit, consecutive ranks | 5♠ 6♠ 7♠ 8♠ |
| **Dublee** | 2 identical cards from different decks | A♥ (deck 0) + A♥ (deck 1) |
| **Tunnala** | 3 identical cards, one from each deck | K♣×3 |

### Turn structure
1. **Draw** — from deck or top of discard pile
2. **Play** — optionally lay melds or add to existing ones
3. **Discard** — exactly 1 card to end your turn

### Jokers
- Wild in any meld
- Can fill gaps in sequences

---

## Multiplayer Setup (Local Network)

### Host
```
NetworkManager.host_game("YourName")
# Listens on port 7777
```

### Join
```
NetworkManager.join_game("192.168.x.x", "YourName")
```

For internet play, the host needs to port-forward **7777 UDP** or use a relay.

### Future: relay server
To avoid port forwarding, integrate **Nakama** (free, open-source):
→ https://heroiclabs.com/nakama/

---

## Free Tools & Resources

| Tool | Purpose | Link |
|------|---------|------|
| Godot 4 | Game engine | godotengine.org |
| VS Code + godot-tools | IDE | marketplace.visualstudio.com |
| Inkscape | Vector art | inkscape.org |
| Aseprite (compile from source) | Pixel art | github.com/aseprite/aseprite |
| BFXR | Sound effects | sfxr.me |
| Audacity | Audio editing | audacityteam.org |
| itch.io | Publish & distribute | itch.io |
| Freesound.org | Free SFX | freesound.org |
| Google Fonts | Free fonts | fonts.google.com |

---

## Roadmap

- [x] Core card data model
- [x] 3-deck builder + shuffle
- [x] Full meld validation (Sequence, Dublee, Tunnala)
- [x] Visual Card node with drag/drop
- [x] Hand layout manager
- [x] CPU AI with 3 difficulty levels
- [x] ENet multiplayer skeleton
- [ ] Scene files (.tscn) — build in Godot editor
- [ ] Card textures / custom art
- [ ] Sound effects
- [ ] Lobby + room system
- [ ] Leaderboard (Supabase)
- [ ] Mobile export (Android/iOS)
- [ ] Web export (HTML5)
- [ ] Steam / itch.io release
