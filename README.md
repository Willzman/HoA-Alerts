# HoA Alerts

A BigWigs/DBM-style warning addon for **[Hordes of Azeroth](https://github.com/jonhaldors/hordes-of-azeroth)**.
It warns you when one of these appears during a run:

| Alert | Default | Default sound |
|---|---|---|
| **Ley Line** | on | Flag Taken |
| **Greed Totem** | on | Flag Taken |
| **Challenge Altar** | on | Flag Taken |
| **Elite Chest** (free chest) | on | Flag Taken |
| Moonwell | off | Flag Taken |
| Valor Chest (costs Valor) | off | Flag Taken |

Each warning can:

- show **big text** between your hero and the action bar with the spawn's icon, distance and direction (`Ley Line spawned! (230 yd, NE)`)
- play a **sound**, a different one per type. You can pick another sound for each type in `/hoaa` (click the sound button to go to the next one, right-click to go back; each click plays it) or with `/hoaa sound <type> <number>`. See [Sounds](#sounds).
- **flash the screen edges** in the spawn's color
- print a **chat message**
- add the spawn to a small **tracker list**, styled like the game's damage meter, that shows every active spawn, nearest first, with live distance and compass direction (N, NE, E, ...; north is up on the map). Each row's bar fills as you get closer (full when you're on it, empty at 400+ yards)

It also **flashes the screen edges red when a ground effect hits you**, meaning you didn't get out of a
telegraphed circle, cone, line, ring, eruption or bolt landing zone in time. Turn it off with `/hoaa ground`.

When several spawns of the same type appear within 3 seconds of each other (an elite pack dying
often drops a pile of chests), they merge into one warning that counts up, like `Elite Chest dropped!  x4`.
Only the first one plays a sound, flashes and prints to chat.

Warnings pop in, stay for 4 seconds, then fade out over 1 second. Up to three stack, with the newest
closest to the action bar. Use `/hoaa unlock` to drag them somewhere else.

![Mockup of HoA Alerts: three stacked spawn warnings at the top of the screen, a green screen-edge flash, and the tracker list on the right](docs/preview.png)

*Mockup of the layout, not an in-game screenshot. Type `/hoaa test` in game to see the real thing.*

## Sounds

Each alert type can use any of these (`/hoaa sounds` lists them with numbers):

- **Game sounds** from your own game data: Flag Taken (the Warsong Gulch flag horn, `PVPFlagTaken.Mono`, the default for every alert), Raid Warning, Ready Check, Coins, Quest Complete, Objective Done,
  Level Up, Map Ping, Party Invite, Quest Failed, Flight Path Found, Quest Accepted, Friend Online,
  PvP Update, Anvil, Target Enemy. All of them are sounds the Hordes of Azeroth addon or client already plays.
- **HoA Alerts' own sounds**: HoA Chime, HoA Bell, HoA Alarm and HoA Horn. They're shipped in
  `HoAAlerts/Sounds` and were synthesized from scratch by `tools/make_sounds.py`.
- **No Sound**: the text warning still shows.
- **Your own file**: put a `.wav` or `.mp3` in `HoAAlerts/Sounds`, then type
  `/hoaa soundfile <type> <file name>`, e.g. `/hoaa soundfile elite MyChest.mp3`. The game client plays WAV
  and MP3 only (not OGG or FLAC).

All sounds follow the game's Sound Effects volume.

## Install

1. Download this repository and copy the `HoAAlerts` folder into the game's AddOns folder.
   Hordes of Azeroth loads addons from **`benilla-config\AddOns`** inside the game folder (not `Interface\AddOns`),
   so you end up with `benilla-config\AddOns\HoAAlerts\HoAAlerts.toc`.
2. Start the game and enable **HoA Alerts** on the character select AddOns screen.
3. In game, type `/hoaa test` to see what the warnings look like.

## Commands

| Command | What it does |
|---|---|
| `/hoaa` | Open the options window |
| `/hoaa test [type]` | Show test warnings |
| `/hoaa unlock` / `/hoaa lock` | Move the warning text and the tracker |
| `/hoaa range <yards>` | Only warn for spawns within that distance (`0` = any) |
| `/hoaa leyline` / `greed` / `altar` / `elite` / `moonwell` / `valor` | Turn one alert type on or off |
| `/hoaa warning` / `sound` / `flash` / `chat` / `tracker` | Turn one kind of output on or off |
| `/hoaa sounds` | List the sounds and what each type plays |
| `/hoaa sound <type> <number>` | Pick a sound for one type, e.g. `/hoaa sound elite 1` |
| `/hoaa soundfile <type> <file>` | Play your own WAV/MP3 from `HoAAlerts/Sounds` for one type |
| `/hoaa ground` | Turn the red ground-effect hit flash on or off (`/hoaa test ground` to preview) |
| `/hoaa reset` | Reset frame positions |

Settings are saved per account in `HoAAlertsDB`.

## How it works

The Hordes of Azeroth server tells its own addon about every map pin with a hidden system chat line:

```
BONK~objective~<id>~<kind>~<x>~<y>~<mapId>~<label>~<seconds>~<icon>~<description>
BONK~objectiveclear[~<id>]
```

HoA Alerts listens for the same lines. Labels are translated, so it recognizes each spawn
by its pin kind and icon, which are fixed in the server code:

| Spawn | kind | icon |
|---|---|---|
| Ley Line | `shrine` | `Spell_Arcane_StarFire` |
| Greed Totem | `shrine` | `INV_Misc_Coin_02` |
| Challenge Altar | `shrine` | `Ability_Warrior_Challange` |
| Moonwell | `shrine` | `Spell_Arcane_TeleportMoonglade` |
| Free (Elite) Chest | `chest` | `INV_Box_04` |
| Valor Chest | `chest` | `INV_Box_02` |

Pins that the server sends again (for example after `/reload`) don't trigger a second warning.

### Ground-effect hits

Every ground effect in Hordes of Azeroth (telegraphed circles, cones, lines and rings, eruptions,
bolt landing zones) damages you as a direct enemy spell hit. The 1.12 combat log reports that as
`<enemy>'s <spell> hits you for <amount>` (or `crits you`). Enemy melee and damage over time use
different messages, so HoA Alerts flashes red only for those direct spell hits. Several hits within
a third of a second give one flash.

### Notes

- **Elite Chest** covers every *free* chest. Most come from elite kills (15% base chance, more per affix
  and with Luck, guaranteed after 5 elites without one). The server uses the same chest for Challenge
  Altar, event and hidden-find rewards, and the addon can't tell those apart.
- If the game changes these icons or the message format in a later version, update the table at the
  top of `HoAAlerts/HoAAlerts.lua`. This version was written against game version 0.6.4.
- The addon only reads chat and combat-log messages the game already sends to you. It doesn't change the game or send anything to the server.

## License

Copyright (C) 2026 willzman

HoA Alerts is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License version 3](LICENSE) as published by the Free Software Foundation.
It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the license for details.

This covers the addon code and the sounds in `HoAAlerts/Sounds`, which were generated from scratch
by `tools/make_sounds.py`. Game sounds picked by name come from your own game data and aren't part
of this repository.
