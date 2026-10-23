# Roadmap

Milestones are built in order. Each one ends with a Studio-verified playtest
(see TESTING.md) before the next one starts. Status as of **2026-10-22**.

## Current priorities

1. **Team hands-on check of Milestone 1.** Play it in Studio and run the TESTING.md
   checklist, especially camera and selection feel, and frame rate with the Studio
   window in front (Claude could not measure that).
2. **Finish setup** (CLAUDE.md "Setup"): install Git, create the GitHub repo, turn on
   Script Sync and link the three code folders, make personal test places.
3. **Answer the open questions** at the bottom of this file. They shape Milestone 2.
4. Start **Milestone 2**.

Work that can start now, in parallel:

- **Person 2**: design the HUD in Studio as `ReplicatedStorage.Assets.UI.RTSHud`. The
  contract is at the top of `src/Client/UI/Hud.luau`. Sketch the control-group bar and
  the selected-unit panel for Milestone 2.
- **Person 3**: import one Meshy test model as `ReplicatedStorage.Assets.Units.FA_Trooper`
  following CLAUDE.md "Adding a unit model". Check its size against the placeholders and
  its readability at max zoom.
- **Person 1**: sketch the real 1v1 map (bases, expansions, chokepoints). Draft the unit
  role list for each placeholder faction (infantry, armored and air counters, one hero).

## Milestones

| # | Milestone | Status | Depends on |
|---|---|---|---|
| 0 | Project setup | Mostly done. Git, GitHub and Script Sync linking are manual steps left | none |
| 1 | Camera, selection, movement | **Done and verified in Studio**; waiting on the team's hands-on check | 0 |
| 2 | Commands and squads | Next | 1 |
| 3 | Combat core and unit counters | | 2 |
| 4 | Bases and economy | | 2 (3 for building damage) |
| 5 | Production and tech | | 4 |
| 6 | Leaders, heroes, abilities | | 3, 5 |
| 7 | Scouting, minimap, fog of war | | 3 (affects networking, see Performance gates) |
| 8 | Match flow: victory, defeat, restart | | 4 |
| 9 | **First complete playable version** | | 1 to 8 |

### Milestone 0: Project setup
- Done: Studio MCP connection verified; place settings (`tools/ApplyPlaceSettings.luau`);
  folder layout; CLAUDE.md, ROADMAP.md, TESTING.md; disk and Studio copies of all scripts
  checked identical.
- Left (manual, see CLAUDE.md "Setup"): install Git, create the GitHub repo, enable the
  Script Sync beta, link the folders, make personal test places, connect each teammate's
  Claude Code.

### Milestone 1: Camera, selection, movement (done)
Test map; 5 placeholder units per player; overhead camera (WASD, zoom limits, map
bounds); click, drag-box and Shift selection; selection rings and count; right-click
moves in formation; pathfinding around obstacles; unreachable destinations handled;
server checks ownership and input; UI clicks don't leak into the world. All verified
with one client, then with two clients. Details in TESTING.md.

### Milestone 2: Commands and squads
- **Squads**: regular troops grouped into squads (configurable size) that are selected and
  ordered as one; heroes stay individual. `Unit.squadId` and `Formation` are already in
  place for this.
- **Group movement cohesion**: one shared path per squad or group instead of one per
  unit. Simple separation so units don't overlap in chokepoints.
- **Control groups**: Ctrl+number to assign, number to select, double-tap to jump the camera.
- **Stop / hold position**, Shift+right-click **waypoint queue**, double-click to select
  all units of a type on screen, select-all-army hotkey.
- Hover highlight and a basic selected-unit panel (Person 2).
- Rally points come in Milestone 5; attack and attack-move come in Milestone 3.

### Milestone 3: Combat core and unit counters
- Health, damage, range, attack speed, target acquisition and death, all resolved on the server.
- Right-click an enemy to attack; attack-move.
- Counter system: infantry, armored and air roles with damage multipliers in config.
  Air units ignore ground obstacles (a separate movement layer).
- Readable hit and death feedback (Person 3); health bars (Person 2).
- Re-run the benchmark with fighting units (Performance gate A).

### Milestone 4: Bases and economy
- Headquarters with fixed building slots, construction, building health.
- **Supplies** (army and construction) and **Energy** (technology and abilities). Resource
  buildings, starting amounts, all costs in config.
- Expansion sites around the map; building or capturing expansion bases.
- Buildings become obstacles that pathfinding respects.

### Milestone 5: Production and tech
- Production buildings with queues and build times. Timers run on the server only; a
  client never reports "done".
- Population cap, rally points, tech tiers (headquarters upgrades), unit upgrades.

### Milestone 6: Leaders, heroes, abilities
- Each faction's leader: a passive bonus plus leader powers that cost Energy and have
  cooldowns.
- One hero unit per faction (individual, not in a squad) with revive rules.
- Ability framework: point, unit and area targeting; clear telegraphs, cooldowns and a
  chance for the opponent to respond; all checked on the server.

### Milestone 7: Scouting, minimap, fog of war
- Minimap with camera jump. Vision radius per unit and building.
- Fog of war must *hide* enemy units from clients, not just darken them, and that changes
  what the server replicates. Decide together with Performance gate B.

### Milestone 8: Match flow
- Lobby and ready-up, faction pick, countdown.
- Victory when all enemy headquarters, including expansions, are destroyed. Defeat,
  disconnect grace period and forfeit, results screen, restart.

### Milestone 9: First complete playable version
One small map, 1v1, two placeholder factions, each with one hero and three regular
unit types, a small building roster, basic economy, production, combat, and
victory/restart. Then a balance pass and team playtests.

## Later (after the first playable version)

- Real anime factions and characters chosen by the team, then more factions.
- 2v2 and 3v3 team matches, larger maps (turn streaming back on and test it).
- Map and unit art as Roblox **Packages** so personal test places stay up to date.
- Progression and persistent roster unlocks. These are **separate** from spending
  Supplies and Energy inside a match: unlocks decide what you may bring, never how strong
  it is once there.
- Summoning, gamepasses, premium currency, ranked matchmaking, events, marketing.
- Touch and gamepad controls.

## Performance gates

Measured on 2026-10-22 in Studio on the development PC (single client), with every unit
crossing the map around both wall lines.

| Moving units | Every unit has a path after | Movement loop | Server heartbeat (avg) | Server send rate per player (avg / peak) |
|---|---|---|---|---|
| 50 | 1.03 s (6 parallel path jobs) | 0.14 ms | 0.52 ms | 72 / 86 kbps |
| 100 | 0.92 s (16 parallel) / 1.83 s (6) | 0.21 ms | 0.37 to 0.87 ms | 145 / 177 kbps |
| 200 | 1.44 s (16 parallel) / 3.58 s (6) | about 0.1 to 0.2 ms | 0.64 to 1.40 ms | 282 / 373 kbps |

What this means:

- **Server CPU is not the limit yet.** About 1.4 ms per frame with 200 moving units,
  out of a 16.7 ms budget.
- **Network is the limit.** Each moving unit costs about 1.4 kbps for *each* player.
  Around 200 moving units is the practical ceiling for the current method (the server
  moves each model and Roblox replicates it).
- **Path start-up delay**: each path takes about 0.1 s of waiting. `MaxConcurrentPathJobs`
  is now 16, which halved the delay with no measured server cost. Squad paths
  (Milestone 2) will cut it further.
- **Not measured**: client frame rate. Studio was in the background (throttled to
  15 fps), so this needs a manual check.

Gates:

- **Gate A (during Milestone 3):** 100 vs 100 fighting units. Target: server heartbeat
  under 4 ms, no frame drops on a mid-range PC.
- **Gate B (before team matches, big battles or fog of war):** if sustained moving units
  will exceed about 150, or fog of war needs hidden units, switch movement replication to
  compact server snapshots (an UnreliableRemoteEvent carrying positions) with clients
  drawing and smoothing the models. `MovementSystem` is the only server code that writes
  unit positions, so the change stays contained.
- **Gate C (before release):** frame rate with 200+ animated, textured units on a low-end
  device and on mobile.

## Open questions for the team (none of them blocked Milestone 1)

1. Should the camera rotate (Q/E) or always face north? Should the screen scroll when the
   mouse touches the edge?
2. **S** pans the camera, so which keys for Stop and Hold position?
3. Default squad sizes for infantry, armored and air?
4. Should players be able to click enemy units to inspect them (without commanding them)?
