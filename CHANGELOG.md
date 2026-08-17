# Changelog

Notable changes to Guaranteed Crawlspaces. Versions match the `<version>` field
in `metadata.xml`, which is what the Steam Workshop shows.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0] — 2026-08-17

Initial release.

### What it does

- Every floor gets **one** crawlspace, in a room that is actually on the map.
  Plain rooms are preferred over secret ones.
- The crawlspace stays where the engine put it wherever possible: a breakable
  rock is built on the engine's own `GetDungeonRockIdx()` tile, either on bare
  floor or by rebuilding a block, pillar, pit, poop, TNT, web or patch of spikes
  as a rock. Only when that tile cannot be used does the crawlspace move.
- Rooms where vanilla already works are left untouched, and a floor that already
  carries a crawlspace in a room layout is left alone entirely — there is never
  a second one.
- Ordinary breakables are preferred over rocks that already carry a reward
  (tinted, super tinted, golden, bomb rocks, X-marked skulls), so nothing is
  spent to hide a crawlspace.
- Six settings through Mod Config Menu, which is optional.

### Safety rules

- A rock is never built where it would cut anything off. Placement floods the
  room before and after and refuses any tile that would shrink what the player
  can reach — checked once for a walking player, for whom pits are solid, and
  once for a flying one, for whom they are not.
- Room machinery is never overwritten: doors, trapdoors, stairs, teleporters,
  pressure plates, locked blocks and statues keep their tile.
- Rocks keep clear of doors, of the players, and of pickups, machines and NPCs.

### Interoperability

- Exposes `GuaranteedCrawlspaces.GetRockIndex()` and `.GetRoomListIndex()` for
  other mods, covering the cases where the crawlspace could not stay on the
  engine's index. [Secrets Reveal](https://github.com/ghoulfik/tboi-secrets-reveal)
  reads both, from its own 1.1.

[1.0]: https://github.com/ghoulfik/tboi-guaranteed-crawlspaces/releases/tag/v1.0
