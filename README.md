# Guaranteed Crawlspaces

A Repentance mod that gives every floor the one crawlspace it was already
allotted — somewhere the player can actually get to.

---

## The problem

A crawlspace is not placed as a crawlspace. Per floor the engine picks a room
and, inside it, a single **grid index** — *dungeon rock* is its internal name,
readable through `Room:GetDungeonRockIdx()`. A crawlspace appears only if the
rock at that index is broken.

Nothing checks what is standing on that index. Most of the time it lands on bare
floor, on a wall, or on an immovable block, and there is nothing there to break.
The floor's one crawlspace is unreachable and the player never learns it existed.

The sibling mod [Secrets_reveal](../Secrets_reveal/) documents the same flaw from
the other side — it marks the crawlspace rock, and notes that *"when the engine's
chosen index lands on a block the crawlspace is genuinely unreachable."* This mod
is the fix for that case.

## The fix

Still one crawlspace per floor, still dug out of a rock. The difference is where
it ends up.

**One room per floor** is chosen from the rooms actually on the map. Off-grid
rooms — Devil deals, the crawlspace interior itself — carry a negative
`SafeGridIndex` and are excluded outright. **Plain rooms are preferred over
secret ones**: a crawlspace behind an unbombed wall is only half available, and
"one the player can get to" is the whole point.

**Then, in that room:**

| Engine's index holds | What the mod does |
|---|---|
| An intact, breakable rock | **Nothing.** Vanilla works here; interfering would only risk breaking it. |
| Bare floor | **Builds a rock on that exact index** |
| A block, pillar, pit, poop, TNT, web, spikes or decoration | **Rebuilds it as a rock, in place** |
| Room machinery — door, trapdoor, stairs, teleporter, pressure plate, locked block, statue | Leaves it alone; the crawlspace moves |
| A wall, a doorway, an off-layout index | The crawlspace moves |

Keeping the crawlspace **on the engine's own index** rather than moving it is the
main design choice here, and it matters well beyond tidiness — see [Keeping the
engine's index honest](#keeping-the-engines-index-honest).

The chosen rock is then watched, and breaking it produces the crawlspace.

If the chosen room turns out to be unusable — no rock and nowhere to plant one —
it is struck off and the floor picks another.

## Never two

Three guards, because a second crawlspace would be worse than the bug being
fixed:

1. **Before anything is armed**, the floor's room *layouts* are read for a
   crawlspace spawn (`9100`). If the game already builds one into a reachable
   room, the mod stands down for that floor entirely. Reading the layout rather
   than the live grid is what makes this work — it covers rooms the player has
   not walked into yet, so the promise holds however they route through the
   floor.
2. The engine's index is used **unchanged** whenever it is already breakable, so
   the mod never competes with a working vanilla placement.
3. If the watched tile turns into a crawlspace on its own, the mod disarms
   instead of spawning.

## Which rock, when the crawlspace has to move

Every breakable is eligible — plain rock, urn/mushroom/skull, tinted, super
tinted, spiked, golden, bomb rock, X-marked skull — but not equally.

**Preferred:** plain rocks and urns/mushrooms/skulls (`GRID_ROCK`,
`GRID_ROCK_ALT`). Breaking one costs the player nothing they would otherwise
have had.

**Second:** everything else. Tinted and super tinted rocks carry their own
reward, X-marked skulls yield one, golden rocks pay out, and bomb rocks explode
right where the player is about to step onto a fresh crawlspace.

The tinted case is the sharpest, because the loss would be silent: in
Secrets_reveal the crawlspace marker **outranks** the tinted-rock marker on the
same tile, so choosing a tinted rock would quietly hide a hint the player
installed that mod to see.

Nothing is ruled out — a room offering only tinted rocks still delivers, because
delivering is the point — they simply go second. The engine's own pick is never
overridden by this: if vanilla chose a tinted rock itself, that is vanilla's
call.

## Placing a rock

Only reached when the chosen room has nothing breakable. The tile is chosen, not
dropped at random: a rock is solid, so a careless one can wall off a door or box
the player in.

| Constraint | Why |
|---|---|
| **Cuts nothing off** | See below — this is the one that matters |
| ≥ 2 tiles from every door | A rock beside a door can seal the room |
| ≥ 1.5 tiles from every player | Never materialise on top of someone |
| ≥ 0.75 tiles from pickups, machines and NPCs | Nothing gets covered up |
| Empty floor, no grid collision | Never inside an existing rock or a pit |
| Passes `IsPositionInRoom` | L-shaped rooms have indices inside the grid but outside the room |

The outer ring of the grid is the room's wall and is skipped outright.

### Never severing the room

Distance from the doors is not enough, and assuming it was is how this mod once
ended runs. A room can be a **single one-tile bridge between two doors**, with
the bridge nowhere near either of them. Every clearance rule above passes it. A
rock there strands anyone out of bombs.

So placement does not reason about doors at all. It floods the room from the
player, before and after, and refuses any tile whose rock would shrink what is
reachable.

That flood runs **twice**, because "reachable" is not one question:

| Model | Pits are | Catches |
|---|---|---|
| Walking | solid | a rock closing the only floor path |
| Flying | passable | a rock replacing the pit that was the only crossing |

Either loss is a refusal. The second model is why rebuilding a pit as a rock is
safe: a pit that is somebody's only route stays a pit.

If every comfortable tile in a room turns out to be a bridge, the search strikes
them off and keeps drawing — a worse-placed rock beats a run-ending one.

### Relaxation, not refusal

A single strict pass would fail in cramped rooms, and failing is exactly what
this mod exists to remove. So the filter runs as passes from comfortable to
"anywhere at all":

```
door ≥ 80,  player ≥ 60,  entity ≥ 30
door ≥ 80,  player ≥ 60,  entity ≥ 0
door ≥ 60,  player ≥ 40,  entity ≥ 0
door ≥ 40,  player ≥ 40,  entity ≥ 0
anything
```

The first pass that yields survivors wins.

## Stable choices

Both choices are seeded, never taken from the global RNG:

- **Which room** — from `Level:GetDungeonPlacementSeed()`, literally the seed the
  engine uses to place crawlspaces.
- **Which rock** — from that room's `GetDecorationSeed()`.

This matters because **mod-spawned grid entities are not reliably kept when a
room is left and re-entered**. The mod re-runs on entry, so it must answer the
same room and the same rock every time — otherwise the crawlspace wanders around
the floor between visits. The order the player walks the floor in changes
nothing.

Once a rock has been dug out, re-entering the room **restores the crawlspace**
rather than burying a fresh one. The player did the digging; they should not have
to do it twice.

## Which rooms are eligible

**Always** — this is what "rooms you can walk into" means:

- `ROOM_DEFAULT` (preferred), `ROOM_SECRET`, `ROOM_SUPERSECRET`,
  `ROOM_ULTRASECRET`

**As a group**, toggleable: Shop, Treasure, Boss, Miniboss, Arcade, Curse,
Challenge, Library, Sacrifice, Devil, Angel, Boss Rush, Planetarium, Chest, Dice,
Isaac's, Barren, Blue.

**Never**, whatever the settings say:

- `ROOM_DUNGEON`, `ROOM_BLACK_MARKET` — already the far end of a crawlspace
- `ROOM_ERROR`, `ROOM_GREED_EXIT` — plumbing, not places

## Settings

Through [Mod Config Menu](https://steamcommunity.com/sharedfiles/filedetails/?id=2681875787),
which is optional — without it, the defaults apply.

| Setting | Default | Effect |
|---|---|---|
| Guarantee | on | Master switch; can be flipped mid-run |
| Bring a rock | on | Place one when the chosen room has none. This is what turns "usually" into "guaranteed". |
| Special rooms | on | Let it land in the special-room set too |
| Starting room | on | Let it land in the room the floor begins in |
| Only once cleared | off | Arm after the room is cleared rather than on entry |
| One per floor | on | Do not replace a crawlspace you have gone down |

## Keeping the engine's index honest

`Room:GetDungeonRockIdx()` is **read-only**. There is no `SetDungeonRockIdx` in
the Repentance Lua API, and REPENTOGON's `Room` class does not add one, so a mod
cannot correct the engine's answer.

What it *can* do is make the answer true. Rather than moving the crawlspace to a
rock that suits it, the mod puts a breakable rock on the tile the engine already
named — building on bare floor, or rebuilding whatever is there when the tile
holds something safely overwritable.

This is the difference between correcting the game's state and running a second
copy of it alongside, and it buys two things:

- **Everything that reads the engine keeps working.** `GetDungeonRockIdx()` stays
  the honest answer, so Secrets Reveal's buried-crawlspace marker needs to know
  nothing about this mod.
- **The game's own logic is pointed at a rock that can be broken.** Whether the
  engine then produces the crawlspace itself — treating a mod-planted rock at
  its own index the same as one it generated — is *unverified*, and the mod does
  not rely on it: if the tile turns into a crawlspace on its own the mod stands
  aside, and otherwise it digs it out itself. Either way the player gets exactly
  one.

What is *not* overwritten is the important half. Doors, trapdoors, stairs,
teleporters, pressure plates, locked blocks and statues are room machinery:
overwriting one can strand a player, void a challenge room's reward, or delete
the way out. Those keep their tile, and so do walls, doorway-adjacent tiles and
indices outside the room layout.

### The residual, and the side channel

For that remainder the crawlspace genuinely has to move, and nothing engine-side
records where it went. So the mod exposes two functions:

```lua
GuaranteedCrawlspaces.GetRockIndex()      -- grid index in the current room, or -1
GuaranteedCrawlspaces.GetRoomListIndex()  -- ListIndex of the floor's room, or -1
```

Plain functions on a plain global, both safe to call behind a `nil` check with no
load-order guarantee. `GetRockIndex` returns `-1` once the rock is broken — from
then on the crawlspace is an ordinary `GRID_STAIRS` that any room scan can see —
and both return `-1` while the mod is switched off, so a consumer falls back to
the engine's own answer.

Secrets_reveal consults both: the first for its buried-crawlspace marker in the
residual cases, the second so the room shows on the map — which layout scanning
can never find, because this mod picks its room at runtime rather than shipping
one built with a crawlspace in it.

Both call sites are nil-checked and `pcall`-wrapped, so Secrets Reveal is
unchanged when this mod is absent, silent, or misbehaving. That is verified
rather than assumed: `Secrets_reveal/tools/run_compat_tests.py` loads its
`main.lua` under stubs and drives it with the integration absent, reporting a
moved rock, reporting nothing, throwing, and returning nonsense — 15 checks.

## Bookkeeping

One record per floor, keyed `stage.stageType`:

| Field | Meaning |
|---|---|
| `room` | `ListIndex` of the room holding this floor's crawlspace |
| `rock` | grid index within that room |
| `tried` | rooms that turned out unusable, so a re-pick avoids them |
| `opened` | the rock has been broken and the crawlspace revealed |
| `used` | the player has gone down it |
| `done` | the floor needs nothing further |

Keying by stage means the Ascent revisiting a floor deliberately shares the
original's record — that floor has already had its crawlspace.

Written on `MC_PRE_GAME_EXIT`, read on `MC_POST_GAME_STARTED`. Settings survive
across runs; per-floor records are discarded on a new run, since their keys
describe a layout that no longer exists.

## Cost per frame

`MC_POST_UPDATE` does one grid lookup while a rock is armed, and returns
immediately everywhere else — which is most rooms, since only one room per floor
is ever armed. The full grid scans happen on room entry; the layout scan happens
once per floor.

## Tests

There is no Lua on a typical Windows box and no way to script the game, so
[tools/](tools/) carries a harness that stubs the Isaac API — a whole floor of
rooms, their grids, doors, entities, room descriptors and layouts, plus Mod
Config Menu — loads `main.lua` unmodified, and asserts on what it actually does.

```
pip install lupa
python tools/run_tests.py
```

90 checks, including:

- exactly **one** crawlspace per floor, in a plain room, never in an off-grid one
- the same room and rock chosen regardless of the order the floor is walked
- deferring to vanilla: a good engine index honoured untouched
- keeping the engine's index: a bare one built on, a block and a pit **rebuilt as
  a rock in place**, a doorway index correctly refused
- room machinery never overwritten — pressure plate, trapdoor, door, teleporter,
  statue, locked block each keep their tile and push the crawlspace elsewhere
- every breakable type eligible on its own, and reward-carrying rocks (tinted,
  super tinted, golden, bomb, X-marked skull) losing to a plain rock or urn when
  the room offers both
- a layout crawlspace suppressing the mod **even in a room never visited**, while
  one in an off-grid room correctly does not
- planting when a room has nothing, with door and player clearance verified
- **never severing a room** — a one-tile bridge between two doors is refused, the
  engine's own index cannot override the check, and a pit that is the only
  flying route is not rebuilt as a rock
- restoring a dug-out crawlspace, and the used-floor rule
- the reading surface: naming a room on entry, `-1` outside the chosen room,
  `-1` once dug out, `-1` while disabled
- room-type filters, every MCM toggle, a second floor getting its own
- degenerate floors: fully solid rooms, out-of-range engine index, all-off-grid

What it cannot prove is that `Isaac.GridSpawn(GRID_STAIRS, …)` yields a working
crawlspace in the real game. That needs an in-game check.

## Files

```
main.lua               the whole mod
metadata.xml           Workshop metadata
tools/harness.lua      Isaac API stubs + assertions
tools/run_tests.py     runs the harness under lupa
```

## Installation

Copy `main.lua` and `metadata.xml` into:

```
...\steamapps\common\The Binding of Isaac Rebirth\mods\guaranteed-crawlspaces
```

Then enable it in the in-game Mods menu.

## Compatibility

Lua only. No content overrides, no `entities2.xml`, no room layouts touched, so
it cannot conflict with mods that change rooms, items or graphics.

[Secrets_reveal](../Secrets_reveal/) marks the armed rock and puts its room on
the map — see [Working with Secrets Reveal](#working-with-secrets-reveal). That
needs the version of Secrets_reveal in this repo; older copies mark only the
engine's index, which is right in most rooms but not all.
