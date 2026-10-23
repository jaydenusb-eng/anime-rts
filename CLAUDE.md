# Anime RTS: Project Guide

> **Read this whole file before editing anything.** This applies to every teammate and
> every Claude Code session. Then read "Current priorities" in [ROADMAP.md](ROADMAP.md)
> and the checklist in [TESTING.md](TESTING.md). If something here is out of date, fix
> this file in the same change.

## What we are building

A multiplayer Roblox **real-time strategy** game with an anime crossover theme. The
reference feel is Halo Wars 2's standard base-building multiplayer. You command squads
from above, build bases on fixed slots, run a two-resource economy (Supplies and Energy),
expand, counter the enemy army, and use leaders and heroes.

It is **not** a tower-defense game, not an auto-battler, and players never control a
single character. Each player is a camera above the battlefield.

Factions and characters are placeholders ("Faction A", "Faction B") until the team picks
franchises. Units are balanced by role, cost and counterplay, never by how strong a
character is in the source story. Every faction needs weaknesses.

## Golden rules

1. **The server decides.** The server owns unit state, movement, damage, resources,
   production, upgrades, cooldowns and victory. Clients only send *requests*, and handle
   input, camera, UI and visuals.
2. **Never trust the client.** Every RemoteEvent handler checks request shape and types,
   unit ownership, targets, destinations, affordability, cooldowns and request rate. Never
   accept a damage amount, a currency balance or "production finished" from a client.
3. **Numbers live in config.** Unit stats, costs, timings and key bindings belong in
   `src/Shared/Config`. Systems contain logic, not balance values.
4. **One loop for many units.** A system updates all of its units in one loop. Never
   start a loop or a `Heartbeat` connection per unit. Paths are worked out once per order,
   never every frame.
5. **Small, tested steps.** Change one thing, test it in Studio (TESTING.md), fix it,
   then move on. "The code looks right" is not a test result.
6. **Preserve work.** Look before you overwrite a place, a script or a teammate's file.
   Never delete map or art content you didn't make.
7. **Benchmark before promising scale.** See "Performance gates" in ROADMAP.md.

## Where things live

Code is kept in Git. Studio's **Script Sync** links three Studio folders to three folders
on disk, so editing a file updates Studio and editing in Studio updates the file.

| On disk (Git) | In Studio | Runs on |
|---|---|---|
| `src/Shared/` | `ReplicatedStorage.Shared` | both (server and every client) |
| `src/Server/` | `ServerScriptService.Server` | server only; players can't see it |
| `src/Client/` | `StarterPlayer.StarterPlayerScripts.Client` | each player's computer |
| `tools/` | not synced | you paste these into Studio's command bar when needed |

Not in Git (it lives in the Studio place, Team Create keeps it, and Roblox keeps version history):

| In Studio | What | Owner |
|---|---|---|
| `Workspace.Map` | the map (see "Map rules") | Person 1 |
| `ReplicatedStorage.Assets.Units` | unit models (see "Adding a unit model") | Person 3 |
| `ReplicatedStorage.Assets.UI` | designed UI templates (see `src/Client/UI/Hud.luau`) | Person 2 |
| Place settings | no avatars, no Shift-lock, streaming off (`tools/ApplyPlaceSettings.luau`) | Person 1 |

Created while the game runs (never edit these by hand): `ReplicatedStorage.Remotes`,
`Workspace.Units`, `ServerStorage.DevBridge` (Studio only).

### The code, file by file

```
src/
  Shared/
    Config/GameConfig.luau      match settings: slots, rate limits, movement tuning
    Config/FactionConfig.luau   placeholder factions and their starting armies
    Config/UnitConfig.luau      every unit type: role, speed, size, model name
    Config/CameraConfig.luau    camera angle, zoom limits, pan speed
    Config/InputConfig.luau     key bindings, drag and click tolerances
    AssetRegistry.luau          unit type -> 3D model (placeholder if no art yet)
    Formation.luau              spreads a group into slots so units don't stack
    MapInfo.luau                reads the map's play area and start points
    Net.luau                    names of every RemoteEvent + command kinds
  Server/
    Main.server.luau            starts the services below, in order
    Services/UnitService.luau        the official list of units (create, find, remove)
    Services/MovementSystem.luau     moves every walking unit, one loop per frame
    Services/NavigationService.luau  formations + paths for move orders
    Services/CommandService.luau     receives and checks every player order
    Services/MatchService.luau       seats players, spawns starting armies, cleans up leavers
    Services/DevBridge.luau          Studio-only test hooks (ServerStorage.DevBridge)
    Util/RateLimiter.luau            limits how fast each player can send orders
    Util/Validate.luau               type checks for anything a client sends
  Client/
    Main.local.luau             starts the controllers below, in order
    Controllers/InputGuard.luau      decides if an input may reach the world (not UI/chat)
    Controllers/UnitTracker.luau     knows which unit models exist and which are yours
    Controllers/CameraController.luau   overhead camera: WASD pan, wheel zoom, map bounds
    Controllers/SelectionController.luau   click / drag-box / Shift selection
    Controllers/CommandController.luau     right-click -> move order request
    UI/Hud.luau                 placeholder HUD (selected count, hints, messages)
    UI/DragBox.luau             the selection rectangle
    Visuals/SelectionRings.luau rings under selected units
    Visuals/ClickMarker.luau    flash where you right-clicked
tools/
  ApplyPlaceSettings.luau       one-time place setup (safe to re-run)
  BuildTestMap.luau             builds the Milestone 1 test map (won't overwrite a map)
```

### How an order travels (the most important picture in the project)

```
Player right-clicks
  -> CommandController (client) works out the clicked point
  -> fires RemoteEvent "UnitCommand" { kind = "Move", unitIds = {...}, target = Vector3 }
  -> CommandService (server): rate limit -> shape/type checks -> every unit exists and is
     owned by THIS player -> otherwise reject and log
  -> NavigationService: safe destination -> reachable? -> formation slots -> a path per unit
  -> MovementSystem: one Heartbeat loop moves every walking unit's Root part
  -> Roblox replicates the movement to every player's screen
  -> if something went wrong, CommandFeedback tells that player ("Can't reach that location.")
```

## Who owns what

Each person mostly works in their own area. Changing someone else's area is fine, but
ask them to review the pull request.

| Person | Leads | Main files / places |
|---|---|---|
| Person 1 | direction, gameplay, map flow, balance, testing | `src/Server/**`, `src/Shared/Config/**`, `Workspace.Map`, `TESTING.md`, `ROADMAP.md` |
| Person 2 | UI, progression design, marketing, events | `src/Client/UI/**`, `ReplicatedStorage.Assets.UI` |
| Person 3 | models, animation, sound, visual feedback, asset integration | `ReplicatedStorage.Assets.Units`, `src/Shared/AssetRegistry.luau`, `src/Client/Visuals/**` |
| Shared | core plumbing everyone depends on | `src/Shared/Net.luau`, `MapInfo.luau`, `Formation.luau`, `src/Client/Controllers/**`: talk to the team before changing |

## Conventions

- **File names decide the script type** (Script Sync rules): `Name.luau` is a
  ModuleScript, `Name.server.luau` a server Script, `Name.local.luau` a LocalScript.
  A folder on disk is a Folder in Studio.
- **Never put attributes or tags on scripts.** Script Sync ignores them and they get lost.
  Attributes on models and parts are fine.
- Tabs for indentation. `PascalCase` for modules and services, `camelCase` for functions
  and variables, `UPPER_SNAKE_CASE` for constants.
- Line endings are LF on every computer. `.gitattributes` enforces this so Git, Script
  Sync and Studio agree; don't change it.
- Every module starts with a short comment saying, in plain English, what it is for.
  Comments explain *why*, not *what*.
- Server services expose `init()` and/or `start()` and are started from
  `Main.server.luau`. Client controllers expose `start()` and are started from
  `Main.local.luau`.
- RemoteEvents are named only in `src/Shared/Net.luau`, and created only by the server.
- Use `task.wait`, `task.spawn` and `task.delay`, never the old `wait`, `spawn` and `delay`.
- Unit visuals come only from `AssetRegistry`. Gameplay code never builds unit parts.
- Studio-only test code goes in `DevBridge`, behind `RunService:IsStudio()`.

## Map rules (Person 1)

The code reads the map; it never hard-codes positions. A map is a folder
`Workspace.Map` with:

- `Ground`: floor parts units walk on.
- `Obstacles`: anything units must walk around. **Anchored, CanCollide = true.**
- `Boundary`: walls around the play area.
- `Markers.PlayArea`: an invisible, **unrotated** part. Its footprint is the playable
  area and its bottom is ground level. The camera and move orders are clamped to it.
- `Markers.StartPoints.Slot1`, `Slot2`, ...: where each player's army starts. Point
  the part's front face the way the army should face.

Decorations units can walk through should be `CanCollide = false` and stay out of
`Obstacles`. After any map change, playtest a move order through the changed area.

## Adding a unit model (Person 3)

1. Import the model (for example from Meshy) into Studio.
2. Make it a **Model** containing a part named **`Root`**: small, centred on the unit's
   feet. The unit faces Root's front (-Z, the "Front" face).
3. Name any part that should show the owner's colour **`TeamColor`**. A team-coloured
   disc is also added under every unit automatically.
4. Scale it to roughly the `radius` and `height` in `UnitConfig.luau`.
5. Name the model exactly like the unit's `asset` field (for example `FA_Trooper`) and
   put it in `ReplicatedStorage.Assets.Units`.
6. Playtest. If the model is missing or broken, the placeholder appears instead.

Don't add scripts or a Humanoid to unit models: scripts are deleted and the server moves
units itself. For animation, use an `AnimationController`. Animation hookup comes in a
later milestone, so talk to the team before you start on it.

## Adding a unit type or faction (design)

Add an entry to `UnitConfig.luau` (copy an existing one) and reference it from a faction
in `FactionConfig.luau`. Ids such as `FA_Trooper` never change once used; rename the
`displayName` instead.

## Setup (once per teammate)

You need: **Roblox Studio**, **Git**, a **GitHub** account (free), **Claude Code**.

1. **Git**: install from https://git-scm.com/download/win (or `winget install --id Git.Git -e`).
2. **Get the code**: Person 1 creates a private GitHub repository from this folder and
   adds the others as collaborators. Everyone else clones it, for example into
   `Documents\AnimeRTS`.
3. **Studio MCP** (lets Claude see and test your Studio): open Studio, then **Assistant**,
   **...**, **Manage MCP Servers**. Turn on **Enable Studio as MCP server**, and under
   **Quick connect** turn on **Claude Code**. Restart Claude Code. Official page:
   https://create.roblox.com/docs/studio/mcp
4. **Script Sync**: in Studio, **File > Beta Features**, tick **Script Sync**, then restart
   Studio. Official page: https://create.roblox.com/docs/scripting/sync
5. **Your personal test place**: open the shared place and use **File > Save to File As**
   to save `AnimeRTS-<yourname>.rbxl` into your repo folder. `.rbxl` files are ignored by
   Git. Open that file.
6. **Link the code**: in the Explorer, select `ReplicatedStorage > Shared`,
   `ServerScriptService > Server` and `StarterPlayer > StarterPlayerScripts > Client`.
   Right-click, choose **Script Sync > Sync to...** and pick your repo's **`src`** folder.
   Studio matches each folder to `src/Shared`, `src/Server` and `src/Client` by name. If
   it asks how to resolve differences, choose **Keep Disk**: Git is the source of truth.
   Afterwards, check there is no doubled folder like `src/Shared/Shared`.
7. **Check it works**: edit a comment in `src/Shared/Config/GameConfig.luau`. The change
   should appear in Studio within a second or two.
8. **Claude Code**: start it inside your repo folder so it reads this file automatically.

## Team workflow

- **`main` is always working, tested code.** Nobody edits `main` directly.
- One branch per task: `p1/<topic>`, `p2/<topic>` or `p3/<topic>` (for example
  `p2/hud-layout`).
- Day to day:
  ```
  git switch main
  git pull
  git switch -c p2/hud-layout
  ... edit, playtest in your personal place, repeat ...
  git add -A
  git commit -m "HUD: new selection panel layout"
  git push -u origin p2/hud-layout
  ```
  Then open a **Pull Request** on GitHub. A teammate tests it, then it is merged into `main`.
- Switching branches changes the files, and Script Sync updates your personal place to match.
- **The shared Team Create place always runs `main`.** Only **one person** (Person 1,
  the integrator) links Script Sync in the shared place, and only while on `main`. Two
  people syncing different branches into one place overwrite each other.
- Map and art changes are made in Team Create. Re-save your personal place copy when
  you need the newest map or models.
- Update ROADMAP.md and TESTING.md in the same pull request as the feature.

## Notes for Claude sessions

- Read this file, ROADMAP.md "Current priorities" and TESTING.md before editing.
- Edit files in `src/` and let Script Sync update Studio. Use the Studio MCP to inspect
  the place, playtest, read the output log, build map pieces and run `tools/`.
- If Script Sync isn't linked yet, a change made in Studio must also be made to the file
  in `src/`. Both copies must match before you finish.
- Before claiming something works, playtest it: `start_stop_play`, then drive it with
  `user_mouse_input`/`user_keyboard_input` or the `UnitCommand` remote. Inspect the server
  with `game.ServerStorage.DevBridge:Invoke("listUnits" | "getStats" | ...)`. The mouse
  tool's y coordinate excludes the 58 px top bar: tool y = viewport y - 58.
- For two-player tests, run `StudioTestService:ExecuteMultiplayerTestAsync(2, args)`
  from an Edit-mode `execute_luau` inside `task.spawn`. The server and both clients appear
  in `list_roblox_studios`. End the test with `StudioTestService:EndTest(result)` on the
  server.
- Report results honestly: what you ran, what passed, what you could not check.

## Glossary for beginners

- **Server / client**: the server is Roblox's computer running the one true copy of the
  match. Each player's computer is a client: it shows the game and sends requests.
- **Script / LocalScript / ModuleScript**: a Script runs on the server, a LocalScript
  runs on a player's computer, and a ModuleScript is a library other scripts `require`.
- **RemoteEvent**: a message channel between client and server. Treat everything a
  client sends as possibly fake.
- **Replication**: Roblox copying server changes (like a unit's new position) to every
  client.
- **Attribute**: a small named value stored on an instance (for example a unit model's
  `OwnerUserId`).
- **Heartbeat / RenderStepped**: events that fire every frame. Heartbeat is used on the
  server, RenderStepped on the client for the camera.
- **Pathfinding / waypoint**: Roblox works out a route around obstacles, given as corner
  points to walk through.
- **Team Create**: several people editing one Studio place live.
- **Script Sync**: Studio feature that mirrors scripts to files on disk so Git can track them.
- **MCP**: the connection that lets Claude read, edit and playtest your open Studio place.
- **Branch / commit / pull request**: a branch is your own copy of the code, a commit is
  a saved step, and a pull request asks to merge your branch into `main`.
