# One Must Imagine Sisyphus Rich

Source code for **One Must Imagine Sisyphus Rich** (应当想象西西弗斯很有钱), a short incremental game drawn like a Greek black-figure vase. Entry for GitHub Game Off 2026.

**Play:** [eolc.itch.io/one-must-imagine](https://eolc.itch.io/one-must-imagine) (Windows, English / 简体中文)

## The game

Sisyphus pushes the stone up the mountain by day. Every evening it breaks loose and rolls back down through the city where he used to live, and the Underworld pays him for whatever it flattens. He spends the money at the gods' night feast. At dawn the city is rebuilt and the stone is a little bigger than it was yesterday.

## Theme: SHIFT

Sisyphus works two shifts. The day shift is pushing the stone uphill in rhythm. The night shift is riding it back down through the city, and it ends with an itemised payslip from the Underworld. Then the day shift starts again.

## What's in this repository

| Folder | What it holds |
|---|---|
| `app/` | Boot and game flow, saves, settings, the debug console |
| `core/` | Small helpers: seeded random numbers, exact JSON, text templates, the in-game clock |
| `sim/` | The game rules as plain objects with no nodes: the day and night loop, prices, boons, story events, the bloodline between runs |
| `present/` | Everything on screen: the world, the stone and characters, HUD, menus, endings, effects, audio playback. Scenes and shaders live here |

The rules in `sim/` never touch nodes, input or the clock directly, so the same game can run without any graphics.

**Not included:** art, sprites, audio, fonts, the game data (numbers, upgrades, story text, the English translation), tests and development tools. The project opens in Godot 4.5, but it will not run without those files. To play the game, download it from itch.io.

## Built with

- Godot 4.5.1, statically typed GDScript, GL Compatibility renderer
- Windows

## AI use

- Art was made with AI image generation and then edited and assembled by hand.

## License

All rights reserved. The code is public so it can be read as part of Game Off 2026. It is not open source. See [LICENSE](LICENSE).

