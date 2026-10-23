# Testing

How to test the game, what should happen, what has already been checked, and known
problems. Update this file in the same pull request as any feature change.

## How to playtest

**One player:** in Studio press **Play** (F5). You start as slot 1 (blue, west side) with
5 units and no avatar. Stop with **Stop** (Shift+F5).

**Two players (ownership and multiplayer checks):** on the **Test** tab, in "Clients and
Servers", choose **Local Server** with **2 Players** and press **Start**. Three windows
open: a server and two players. Player1 is blue (west), Player2 is red (east). Close
them with **Cleanup** on the Test tab. (Newer Studio versions may label these slightly
differently.)

**Watching the server while testing:** in the server window (or in "Server" view during
Play), open **View > Command Bar** and run, for example:

```lua
print(game.ServerStorage.DevBridge:Invoke("listUnits"))
print(game.ServerStorage.DevBridge:Invoke("getStats"))
```

DevBridge actions: `listUnits`, `getStats`, `resetStats`,
`spawnUnits(ownerUserId, unitType, count, center, slot)`, `removeUnitsOwnedBy(ownerUserId)`,
`moveUnits(ids, target)`. DevBridge only exists in Studio.

## Milestone 1 checklist

| # | Do this | You should see |
|---|---|---|
| 1 | Press Play | Camera looks down at the blue pad with 5 blue units. Bottom-left HUD says "Selected: 0". No red text in Output. |
| 2 | Hold W, A, S, D (or arrows) | Camera slides north, west, south, east. It stops at the map edge. |
| 3 | Scroll the mouse wheel | Zooms in and out smoothly and stops at a minimum and a maximum. |
| 4 | Left-click a unit | A green ring appears under it; HUD says "Selected: 1". |
| 5 | Shift+click another unit, then Shift+click the first one again | Count goes to 2, then back to 1 (the first unit is removed). |
| 6 | Click empty ground | All rings disappear; "Selected: 0". |
| 7 | Drag a box around all units | A green rectangle follows the mouse; all 5 get rings; "Selected: 5". |
| 8 | Right-click ground on the far side of the nearest wall | A green flash appears where you clicked. Units walk *around* the wall through a gap and stop in a tidy group about 4 studs apart. |
| 9 | Right-click several places quickly | Units always end up at the last place you clicked. |
| 10 | Right-click inside the closed wooden pen (north of centre) | Units go to the nearest spot outside the pen; HUD shows "Moving to the nearest reachable spot." |
| 11 | Right-click the top of the tall sand-coloured mesa (south of centre) | Units stop on the ground next to it, never on top. |
| 12 | Right-click outside the map (beyond the outer wall) | Units go to the nearest point inside the map. |
| 13 | With units selected, left-click and right-click the dark HUD panel | Nothing happens in the world: selection stays, no flash, no movement. |
| 14 | Press `/` to open chat, hold W, then click the world to leave chat | Camera does not move while chat is open; WASD works again afterwards. |
| 15 | Two players: each player box-selects the other player's units | Nothing gets selected. |
| 16 | Two players: both order their units at the same time | Both armies move; each player sees the other army moving too. |
| 17 | Two players: close Player2's window | Player2's units disappear for Player1. Player1's units and selection are unaffected. A new player who joins takes slot 2 with a fresh army. |

## Results so far

### 2026-10-22: Milestone 1, run by Claude through the Studio MCP

Shared place "Untitled Experience" (placeId 125396820051554), Studio 0.744.
All 28 scripts were checked byte-for-byte identical between `src/` and Studio.

| Check | How | Result |
|---|---|---|
| Units spawn | Play, then DevBridge `listUnits` | Pass: 5 units per player in formation on the start pad, facing the centre; no avatar |
| Camera start, pan, bounds | Simulated W/A/S/D holds, then read camera | Pass: starts over own army; pans at 110 studs/s at default zoom; clamps exactly at x ±180, z ±120 |
| Zoom limits | Simulated wheel | Pass: stops at 40 and 160 |
| Click select, Shift add/remove, click ground to clear | Simulated clicks | Pass: counts 1, 2, 1, 0 with matching rings |
| Box select | Simulated drag | Pass: green box drawn under the drag; 5 selected |
| UI blocks world input | Left- and right-click on the HUD panel | Pass: selection unchanged; server received 0 orders |
| Move around a wall | Right-click behind the west wall | Pass: units used both gaps; closest approach to any wall 1.75 studs (unit radius 1.5); final spacing exactly 4 studs |
| Click on top of an obstacle | Right-click that grazed the wall top | Pass: moved to the nearest standable spot |
| Closed pen (unreachable inside) | Order to the pen centre | Pass: units stop outside the pen; "Moving to the nearest reachable spot." |
| Mesa top | Order to (0, 18, 80) | Pass: units stop on the ground beside the mesa |
| Outside the map | Order to (500, 0, 500) | Pass: clamped into the play area corner |
| Completely unreachable | Unit sealed inside the pen, ordered out | Pass: stays put; "Can't reach that location."; gives up after 5 probe paths |
| Forged orders (cheating client) | 21 hand-made bad requests from the client | Pass: someone else's units, malformed lists, NaN/infinite/string targets, unknown kinds and 500-id lists all rejected; unknown ids ignored; no server errors; warnings throttled to 1/s |
| Spam / repeated orders | 60 orders in one frame | Pass: 20 accepted (burst limit), 40 rate-limited; units end at the last accepted target; replaced orders' queued path jobs cancelled (12 jobs run, 13 cancelled) |
| Typing in chat | `/`, then hold W and D | **Failed first**: camera panned. **Fixed**: the camera now only uses key presses Roblox didn't give to chat, and also checks the chat bar's `IsFocused`. Re-test passed. |
| Two clients: selection ownership | Real Local Server (2 players) via StudioTestService | Pass: Player1 box/click on Player2's units selects nothing; the same box on Player2's client selects their 5 |
| Two clients: forged cross-player order | Player1 fires an order for Player2's units | Pass: rejected and logged; Player2's units didn't move |
| Two clients: simultaneous orders | Both players order at once | Pass: both armies move; each client sees both armies moving at 14 studs/s |
| Two clients: disconnect | Player2 leaves the test | Pass: Player2's units removed, slot 2 freed, Player1 unaffected, no errors |
| Two clients: rejoin | A third player joins | Pass: gets slot 2 and a fresh Faction B army; camera starts over it |
| Benchmark | 50, 100 and 200 extra units crossing the map | See ROADMAP.md "Performance gates" |

Problems found and fixed during these tests:

1. Unit models printed a "GetJoints" warning per part when spawned. Fixed by finding
   rigged parts without `GetJoints`.
2. Typing in chat moved the camera (above). Fixed.
3. Rapid repeated orders queued wasted path calculations. Fixed: path jobs for replaced
   orders are cancelled.
4. Large group orders were slow to start (3.6 s for 200 units). Improved:
   `MaxConcurrentPathJobs` raised from 6 to 16 (now 1.4 s), with no measured server cost.

## Still needs a human check

- **Feel and frame rate** with the Studio window in front. Claude's runs were throttled
  to 15 fps because Studio was in the background, so client frame rate is unmeasured.
  Target: 60 fps with 200 moving units. (Shift+F5 in a test shows the stats panel.)
- **Real mouse and keyboard**: Claude used simulated input. Check that drag-boxes,
  rings and click tolerance feel right at every zoom level.
- **Two-player test from the Test tab** (checklist rows 15 to 17), done once by a person.
- **Script Sync round trip** after linking (CLAUDE.md Setup step 7).
- A published, live server (real network lag, real player ids). Studio can't test that.

## Known problems and limitations (Milestone 1)

- Units can overlap while walking (no local avoidance yet), and a group may split
  around an obstacle because each unit finds its own path. Planned for Milestone 2.
- Clicking the top of a wall or rock sends units to the nearest standable ground, which
  can be on the far side.
- At the map corners the camera shows some area outside the map (the screen *centre* is
  clamped). Tune `CameraConfig.BoundsPadding` (negative values pull it inward).
- Units turn instantly to face where they walk.
- Movement replication costs about 1.4 kbps per moving unit per player (see Performance gates).
- When a player disconnects, their units are removed immediately. A grace period and
  forfeit come in Milestone 8.
- Mouse and keyboard only (no touch or gamepad yet).
- Pathfinding rounds the unit radius up to whole studs (1.5 becomes 2), so paths keep a
  little extra clearance.
- The map is not in Git. `tools/BuildTestMap.luau` can rebuild the test map in any place.
- `Workspace.StreamingEnabled` is off. That's fine for small maps; revisit for large ones.
