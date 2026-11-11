# EzWoW - Flight Map User Guide

Version: 0.6.2 (Interface 16001)

## 1. Installation & Language
1. Place `EzWoW-FlightMap` inside `Interface/AddOns/` (`Interface/AddOns/EzWoW-FlightMap/EzWoW-FlightMap.toc`).
2. Supports 8 languages (`koKR`, `enUS`, `deDE`, `frFR`, `esES`/`esMX`, `ruRU`, `zhCN`, `zhTW`) with `Auto` detection via `/ezfl config` or `/ezfl lang`.

## 2. Flight Map & Destination List
- Talk to a flight master to open the dedicated flight map (hold `Shift` while talking to keep the gossip dialog).
- **Route Highlighting**: Hover over any marker or label to highlight the flight path with animated route lights.
- **Destination List (`/ezfl list`)**:
  - **Search**: Filter by name and press `Enter` to fly to the first reachable match.
  - **Sort**: Sort by Name, Time, or Fare.
  - **Favorites (`★`) & Recent**: Starred destinations and your most recent destination from the current flight master stay pinned at the top.
  - **Unaffordable Fares**: Highlighted in red when exceeding your current money.

## 3. World Map Pins & Controls
- **Move & Resize**: Drag the window to move; use **`Ctrl + Mouse Wheel`** to resize (`50%–120%`).
- **World Map Flight Masters**: Click the `EzWoW-FlightMap` button docked at the bottom-left of the World Map (`EzWoWWorldMapDock`, Order #2) to filter Alliance (blue), Horde (red), and Neutral (gold) flight masters.

## 4. Map Look & Map Markers

Click the **map button** at the bottom left under the map to change the look. Your choice is saved.

| Look | Description |
|---|---|
| Game map (default) | The game's own continent map picture. |
| Auto | Changes with the month: spring (Mar-May), summer (Jun-Aug), autumn (Sep-Nov), winter (Dec-Feb). |
| Spring · Summer · Autumn · Winter | The real terrain with a seasonal sea and a corner decoration (cherry blossom, palm leaves, maple branch, snowy branch). Petals, glints, leaves or snow drift slowly over the map (`/ezfl fx` turns them off). |
| Parchment | The real terrain with an old paper sea. |

- **Zone names** in your game language; the zone under the cursor is highlighted.
- **Dungeon entrances** with a name and level label joined by a dotted line.
- **Quest turn-ins** for quests in your quest log (yellow when complete, grey while in progress).
- Clicking a dungeon or quest marker selects the nearest flight point in the list.
- Labels can be moved by hand with `/ezfl edit` (type it again to finish; `/ezfl edit reset` restores the default spots).

## 5. Slash Commands (`/ezfl`, `/ezwowflightmap`, `/비행지도`)
- `/ezfl` or `/ezfl config` : Open settings window
- `/ezfl on` / `/ezfl off` : Enable or disable the dedicated flight map
- `/ezfl list` / `/ezfl labels` / `/ezfl all` : Toggle destination list / labels / unreachable nodes
- `/ezfl bar` / `/ezfl alert` / `/ezfl skip` : Toggle flight timer bar / arrival alert / gossip skip
- `/ezfl scale <50~120>` / `/ezfl alpha <0~70>` / `/ezfl reset` : Set scale / background opacity / reset positions
- `/ezfl lang <auto|ko|en|de|fr|es|ru|zhcn|zhtw>` : Switch UI language
- `/ezfl season <plain|auto|spring|summer|autumn|winter|parchment>` : Change the map look
- `/ezfl fx` : Toggle the season effects
- `/ezfl edit` / `/ezfl edit reset` : Move labels by hand / restore default spots
- `/ezfl preview ek` / `/ezfl preview kal` : Look at a continent's flight map without a flight master
