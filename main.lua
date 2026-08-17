--[[
  Guaranteed Crawlspaces

  One crawlspace per floor, the way the game intends -- but one the player can
  actually get to.

  ------------------------------------------------------------------
  What the game does, and why it usually comes to nothing
  ------------------------------------------------------------------
  A crawlspace is not placed as a crawlspace. Per floor the engine picks a room
  and, inside it, a single grid index -- "dungeon rock" is its internal name,
  readable through Room:GetDungeonRockIdx(). A crawlspace appears only if the
  rock at that index is broken.

  Nothing checks what is standing on that index. Most of the time it lands on
  bare floor, on a wall, or on an immovable block, and there is nothing there to
  break. The floor's one crawlspace is unreachable and the player never learns
  it existed.

  ------------------------------------------------------------------
  What this mod does instead
  ------------------------------------------------------------------
  Still one crawlspace per floor, still dug out of a rock. The difference is
  that the floor's crawlspace is guaranteed to be somewhere reachable:

    * One room is chosen per floor, from the rooms that are actually on the map.
      Plain rooms are preferred over secret ones, because a crawlspace behind an
      unbombed wall is only half available.
    * In that room, if the engine's own index already holds an intact breakable
      rock, it is used unchanged -- vanilla works there and nothing is gained by
      interfering.
    * Otherwise a rock really present in the room is used instead.
    * If the room has no breakable rock at all, one is placed, on floor clear of
      the doors, the player and the room's contents.

  If a crawlspace turns up on the floor by itself -- a room layout carries one,
  or the engine's pick happened to work -- the floor is considered served and
  the mod adds nothing. There is never more than one.

  ------------------------------------------------------------------
  Why the choices are seeded
  ------------------------------------------------------------------
  The room comes from the level's own GetDungeonPlacementSeed -- literally the
  seed the engine uses to place crawlspaces -- and the rock from the room's
  decoration seed. Rooms get re-entered, and mod-spawned grid entities are not
  reliably kept when they are, so the mod re-runs on entry and must answer the
  same room and the same rock every time.
--]]

local MOD_NAME = "Guaranteed Crawlspaces"

local mod = RegisterMod(MOD_NAME, 1)
local json = require("json")

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

-- Enum members with literal fallbacks, so a renamed member degrades to a
-- working number instead of a nil index at load time.
local function gridType(name, fallback)
  local v = GridEntityType and GridEntityType[name]
  return v or fallback
end

local GRID_STAIRS    = gridType("GRID_STAIRS", 18)
local GRID_ROCK      = gridType("GRID_ROCK", 2)
local COLLISION_NONE = (GridCollisionClass and GridCollisionClass.COLLISION_NONE) or 0
local COLLISION_PIT  = (GridCollisionClass and GridCollisionClass.COLLISION_PIT) or 1
local NUM_DOOR_SLOTS = (DoorSlot and DoorSlot.NUM_DOOR_SLOTS) or 8
local ENTITY_PICKUP  = (EntityType and EntityType.ENTITY_PICKUP) or 5
local ENTITY_SLOT    = (EntityType and EntityType.ENTITY_SLOT) or 6
local ENTITY_EFFECT  = (EntityType and EntityType.ENTITY_EFFECT) or 1000
local EFFECT_POOF    = (EffectVariant and EffectVariant.POOF01) or 15

-- A rock reports this state once broken; the rubble stays in the grid rather
-- than disappearing, so "is it gone" is not the question to ask.
local ROCK_STATE_BROKEN = 2

-- Entity id a crawlspace carries inside a room layout (the STB/XML "spawn" id).
local SPAWN_ID_CRAWLSPACE = 9100

-- Every rock a crawlspace can be dug out of.
--
-- GRID_ROCKB (the immovable block) and GRID_PILLAR are deliberately absent:
-- they cannot be broken, and an index landing on one is precisely the case this
-- mod exists to rescue.
local ROCK_TYPES = {}
for name, fallback in pairs({
  GRID_ROCK = 2, GRID_ROCKT = 4, GRID_ROCK_BOMB = 5, GRID_ROCK_ALT = 6,
  GRID_ROCK_SS = 22, GRID_ROCK_SPIKED = 25, GRID_ROCK_ALT2 = 26,
  GRID_ROCK_GOLD = 27,
}) do
  ROCK_TYPES[gridType(name, fallback)] = true
end

-- Rocks that are nothing but a rock. Breaking one of these costs the player
-- nothing they would otherwise have had, which makes them the natural place to
-- bury a crawlspace. GRID_ROCK_ALT is the urn in the Basement, the mushroom in
-- the Caves and the skull in the Depths.
--
-- Everything else in ROCK_TYPES stays eligible, but only as a fallback -- see
-- intactRocks for why.
local PLAIN_ROCKS = {}
for name, fallback in pairs({ GRID_ROCK = 2, GRID_ROCK_ALT = 6 }) do
  PLAIN_ROCKS[gridType(name, fallback)] = true
end

-- Grid pieces that may be overwritten with a rock when the engine's chosen
-- index lands on one.
--
-- The engine's index is read-only, so the only way to keep it honest is to make
-- whatever sits on it breakable. Everything here is scenery or an obstacle: a
-- block or pillar becomes a rock the player can now actually clear, a pit
-- becomes something removable rather than permanent, poop and TNT and webs are
-- no loss.
--
-- What is absent matters more than what is present. Doors, trapdoors, stairs,
-- teleporters, pressure plates, locked blocks, statues and gravity are room
-- machinery: overwriting one can strand a player, void a challenge room's
-- reward, or delete the way out. Those keep their tile and the crawlspace moves
-- instead.
local REPLACEABLE = {}
for name, fallback in pairs({
  GRID_DECORATION = 1, GRID_ROCKB = 3, GRID_PIT = 7, GRID_SPIKES = 8,
  GRID_SPIKES_ONOFF = 9, GRID_SPIDERWEB = 10, GRID_TNT = 12, GRID_POOP = 14,
  GRID_PILLAR = 24,
}) do
  REPLACEABLE[gridType(name, fallback)] = true
end

local ROOM = {
  DEFAULT     = 1,  SHOP        = 2,  ERROR      = 3,  TREASURE   = 4,
  BOSS        = 5,  MINIBOSS    = 6,  SECRET     = 7,  SUPERSECRET = 8,
  ARCADE      = 9,  CURSE       = 10, CHALLENGE  = 11, LIBRARY    = 12,
  SACRIFICE   = 13, DEVIL       = 14, ANGEL      = 15, DUNGEON    = 16,
  BOSSRUSH    = 17, ISAACS      = 18, BARREN     = 19, CHEST      = 20,
  DICE        = 21, BLACK_MARKET = 22, GREED_EXIT = 23, PLANETARIUM = 24,
  TELEPORTER  = 25, TELEPORTER_EXIT = 26, SECRET_EXIT = 27, BLUE = 28,
  ULTRASECRET = 29,
}

-- Rooms that can never hold the floor's crawlspace. Crawlspaces and the Black
-- Market are already the far end of one; the rest are plumbing, not places.
local NEVER = {
  [ROOM.DUNGEON] = true,
  [ROOM.BLACK_MARKET] = true,
  [ROOM.ERROR] = true,
  [ROOM.GREED_EXIT] = true,
}

-- The ordinary rooms of a floor: the plain ones and the three secrets.
local ORDINARY = {
  [ROOM.DEFAULT] = true,
  [ROOM.SECRET] = true,
  [ROOM.SUPERSECRET] = true,
  [ROOM.ULTRASECRET] = true,
}

-- Grid tiles are 40x40 world units.
local TILE = 40

-- How far a planted rock has to sit from things it should not sit on. A rock is
-- solid, so these keep it from walling off a door or boxing the player in.
local CLEAR_DOOR   = TILE * 2
local CLEAR_PLAYER = TILE * 1.5
local CLEAR_ENTITY = TILE * 0.75

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------

local DEFAULTS = {
  -- The master switch, so the mod can be turned off mid-run.
  enabled = true,

  -- Place a rock when the chosen room has no breakable one. This is what turns
  -- "usually" into "guaranteed".
  addRock = true,

  -- Let the floor's crawlspace land in a Shop, Treasure Room, Boss Room and the
  -- rest of the special-room set. Off keeps it to ordinary and secret rooms.
  includeSpecial = true,

  -- Let it land in the room the floor begins in.
  includeStart = true,

  -- Wait for the room to be cleared before arming the rock.
  afterClear = false,

  -- Once the floor's crawlspace has been gone down, that is the floor done.
  -- Without this, walking out and back in re-rolls what is at the bottom.
  oncePerFloor = true,
}

local config = {}
for k, v in pairs(DEFAULTS) do config[k] = v end

-- One record per floor, keyed stage.stageType:
--   room    ListIndex of the room holding this floor's crawlspace
--   rock    grid index within that room
--   tried   rooms that turned out unusable, so a re-pick avoids them
--   opened  the rock has been broken and the crawlspace revealed
--   used    the player has gone down it
--   done    the floor needs nothing further
local state = { floors = {} }

-- The grid index being watched in the current room, or nil when there is
-- nothing to watch.
local armed = nil

-- Set when the chosen room is entered but is not clear yet, and afterClear is on.
local pending = false

-- Floor key of the last ordinary room, so arriving in a crawlspace can be
-- attributed back to the floor it was entered from.
local lastFloor = nil

local function saveData()
  local ok, encoded = pcall(json.encode, { config = config, state = state })
  if ok then mod:SaveData(encoded) end
end

local function loadData()
  if not mod:HasData() then return end

  local ok, decoded = pcall(json.decode, mod:LoadData())
  if not ok or type(decoded) ~= "table" then return end

  if type(decoded.config) == "table" then
    for k, v in pairs(decoded.config) do
      -- Only keys this version knows, and only at the right type, so an older or
      -- hand-edited save cannot inject junk into the settings.
      if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
        config[k] = v
      end
    end
  end

  if type(decoded.state) == "table" and type(decoded.state.floors) == "table" then
    state.floors = decoded.state.floors
  end
end

----------------------------------------------------------------------
-- Identity
----------------------------------------------------------------------

--- Stage and stage type together. Two floors never share a key within a run,
-- and the Ascent revisiting a floor deliberately shares its original's record:
-- that floor has already had its crawlspace.
local function floorKey()
  local level = Game():GetLevel()
  return string.format("%d.%d", level:GetStage(), level:GetStageType())
end

local function currentListIndex()
  return Game():GetLevel():GetCurrentRoomDesc().ListIndex
end

--- Room types are recorded as JSON object keys when saved, so `tried` is keyed
-- by string throughout rather than only after a round-trip.
local function triedKey(listIndex) return tostring(listIndex) end

local function typeOf(grid)
  local ok, gtype = pcall(function() return grid:GetType() end)
  if ok then return gtype end
  return nil
end

--- Whether a grid entity is a rock that still needs breaking.
local function isIntactRock(grid)
  if grid == nil then return false end
  if not ROCK_TYPES[typeOf(grid)] then return false end
  return grid.State ~= ROCK_STATE_BROKEN
end

--- Whether the room holds an open crawlspace -- one the layout carries, one the
-- game produced, or one of ours that survived being left and re-entered.
local function hasCrawlSpace(room)
  for index = 0, room:GetGridSize() - 1 do
    local grid = room:GetGridEntity(index)
    if grid and typeOf(grid) == GRID_STAIRS then return true end
  end
  return false
end

--- Whether a room's layout carries `spawnId`. Reading the layout rather than
-- the live grid means the answer is available for rooms the player has never
-- set foot in.
local function layoutContainsSpawn(data, spawnId)
  if not data then return false end

  local ok, found = pcall(function()
    local spawns = data.Spawns
    if not spawns then return false end

    local spawnCount = data.SpawnCount or spawns.Size or 0
    for i = 0, spawnCount - 1 do
      local spawn = spawns:Get(i)
      if spawn then
        local entries = spawn.Entries
        for j = 0, (spawn.EntryCount or 0) - 1 do
          local entry = entries:Get(j)
          if entry and entry.Type == spawnId then return true end
        end
      end
    end
    return false
  end)

  return ok and found or false
end

--- Whether some room on this floor is already built with a crawlspace in it.
--
-- Asked once, before anything is armed. Without it the "one per floor" promise
-- only holds by luck: break the armed rock before wandering into the room the
-- game already put one in, and the floor ends up with two. Off-grid rooms are
-- ignored, since a crawlspace the player cannot reach does not serve the floor.
local function floorAlreadyHasOne(level)
  local rooms = level:GetRooms()
  for i = 0, rooms.Size - 1 do
    local desc = rooms:Get(i)
    if desc and desc.Data and desc.SafeGridIndex >= 0 then
      if layoutContainsSpawn(desc.Data, SPAWN_ID_CRAWLSPACE) then return true end
    end
  end
  return false
end

----------------------------------------------------------------------
-- Choosing the room
----------------------------------------------------------------------

--- Seeded from the level's own crawlspace-placement seed, so the room this mod
-- picks is a property of the floor rather than of when it was asked.
local function floorRNG(level)
  local seed
  local ok, s = pcall(function() return level:GetDungeonPlacementSeed() end)
  if ok and type(s) == "number" and s ~= 0 then seed = s end

  if seed == nil then
    local ok2, s2 = pcall(function()
      return Game():GetSeeds():GetStageSeed(level:GetStage())
    end)
    if ok2 and type(s2) == "number" and s2 ~= 0 then seed = s2 end
  end

  if seed == nil or seed == 0 then seed = 1 end

  local rng = RNG()
  rng:SetSeed(seed, 35)
  return rng
end

local function typeAllowed(roomType)
  if NEVER[roomType] then return false end
  if not ORDINARY[roomType] and not config.includeSpecial then return false end
  return true
end

--- Rooms on this floor that could hold the crawlspace.
--
-- Off-grid rooms -- Devil deals, the crawlspace interior itself -- carry a
-- negative SafeGridIndex and are not places the player walks to, so they are
-- excluded outright.
--
-- Plain rooms are returned in preference to everything else. A crawlspace in a
-- Super Secret Room is technically reachable but practically not, and "one the
-- player can get to" is the whole point of the mod.
local function candidateRooms(level, tried)
  local rooms = level:GetRooms()
  local startIndex = level:GetStartingRoomIndex()

  local plain, other = {}, {}
  for i = 0, rooms.Size - 1 do
    local desc = rooms:Get(i)
    if desc and desc.Data and desc.SafeGridIndex >= 0 then
      local roomType = desc.Data.Type
      local listIndex = desc.ListIndex
      local skipStart = not config.includeStart and desc.SafeGridIndex == startIndex

      if typeAllowed(roomType) and not skipStart
          and not (tried and tried[triedKey(listIndex)]) then
        if roomType == ROOM.DEFAULT then
          plain[#plain + 1] = listIndex
        else
          other[#other + 1] = listIndex
        end
      end
    end
  end

  if #plain > 0 then return plain end
  return other
end

--- Settles which room on this floor holds the crawlspace, if it is not settled
-- already. Marks the floor done when there is nowhere left to put it.
local function ensureTarget(record, level)
  if record.room ~= nil then return end

  local pool = candidateRooms(level, record.tried)
  if #pool == 0 then
    record.done = true
    return
  end

  record.room = pool[floorRNG(level):RandomInt(#pool) + 1]
  record.rock = nil
end

----------------------------------------------------------------------
-- Choosing the rock
----------------------------------------------------------------------

--- A room-stable RNG, so the same room always arms the same rock.
local function roomRNG(room)
  local seed = room:GetDecorationSeed()
  if seed == nil or seed == 0 then seed = room:GetSpawnSeed() end
  if seed == nil or seed == 0 then seed = 1 end

  local rng = RNG()
  rng:SetSeed(seed, 35)
  return rng
end

--- Positions of every door. A planted rock beside one can seal the room, and a
-- crawlspace right inside a doorway gets walked into by accident.
local function doorPositions(room)
  local out = {}
  for slot = 0, NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(slot)
    if door then out[#out + 1] = door.Position end
  end
  return out
end

--- Positions a planted rock should keep clear of: pickups and machines, which
-- it would cover up, and NPCs.
local function occupiedPositions()
  local out = {}
  for _, entity in ipairs(Isaac.GetRoomEntities()) do
    local etype = entity.Type
    if etype == ENTITY_PICKUP or etype == ENTITY_SLOT or entity:ToNPC() ~= nil then
      out[#out + 1] = entity.Position
    end
  end
  return out
end

local function playerPositions()
  local out = {}
  for i = 0, Game():GetNumPlayers() - 1 do
    local player = Isaac.GetPlayer(i)
    if player then out[#out + 1] = player.Position end
  end
  return out
end

local function minDistance(pos, list)
  local best = math.huge
  for _, other in ipairs(list) do
    local d = pos:Distance(other)
    if d < best then best = d end
  end
  return best
end

--- Indices holding a rock that can still be broken, preferring the ones that
-- are only a rock.
--
-- Tinted and super tinted rocks carry their own reward, X-marked skulls yield
-- one when broken, golden rocks pay out, and bomb rocks explode -- right where
-- the player is about to step onto a fresh crawlspace. Burying the crawlspace
-- in one of those spends a tile that was already worth something.
--
-- The tinted case is the sharpest, because the loss is silent: in Secrets
-- Reveal the crawlspace marker outranks the tinted-rock marker on the same
-- tile, so choosing a tinted rock would quietly hide a hint the player
-- installed that mod to see.
--
-- None of them are ruled out -- a room offering nothing else still delivers a
-- crawlspace, which is the whole point of the mod -- they simply go second.
local function intactRocks(room)
  local plain, special = {}, {}

  for index = 0, room:GetGridSize() - 1 do
    local grid = room:GetGridEntity(index)
    if isIntactRock(grid) then
      if PLAIN_ROCKS[typeOf(grid)] then
        plain[#plain + 1] = index
      else
        special[#special + 1] = index
      end
    end
  end

  if #plain > 0 then return plain end
  return special
end

-- Declared here because findTile below consults it, while its definition sits
-- with the rest of the connectivity checks further down.
local wouldIsolate

--- Every tile a rock could be planted on, with the measurements the relaxation
-- passes filter on.
--
-- The outer ring of the grid is the room's wall, and L-shaped rooms have whole
-- blocks of indices inside the grid but outside the room, so a tile has to pass
-- both the collision check and IsPositionInRoom to count as floor.
local function candidateTiles(room)
  local width = room:GetGridWidth()
  local height = room:GetGridHeight()

  local doors = doorPositions(room)
  local occupied = occupiedPositions()
  local players = playerPositions()

  local out = {}
  for index = 0, room:GetGridSize() - 1 do
    local x = index % width
    local y = math.floor(index / width)

    if x > 0 and x < width - 1 and y > 0 and y < height - 1 then
      local free = room:GetGridEntity(index) == nil
          and room:GetGridCollision(index) == COLLISION_NONE

      if free then
        local pos = room:GetGridPosition(index)
        if room:IsPositionInRoom(pos, 0) then
          out[#out + 1] = {
            index = index,
            door = minDistance(pos, doors),
            player = minDistance(pos, players),
            entity = minDistance(pos, occupied),
          }
        end
      end
    end
  end

  return out
end

--- Picks a tile to plant a rock on, or nil if the room has no floor to spare.
--
-- The passes run from comfortable to "anywhere at all". A single strict pass
-- would fail in cramped rooms, and failing is what this mod exists to remove;
-- a tight spot beats no crawlspace.
local function findTile(room)
  local candidates = candidateTiles(room)
  if #candidates == 0 then return nil end

  local passes = {
    { door = CLEAR_DOOR, player = CLEAR_PLAYER, entity = CLEAR_ENTITY },
    { door = CLEAR_DOOR, player = CLEAR_PLAYER, entity = 0 },
    { door = TILE * 1.5, player = TILE,         entity = 0 },
    { door = TILE,       player = TILE,         entity = 0 },
    { door = 0,          player = 0,            entity = 0 },
  }

  local viable
  for _, pass in ipairs(passes) do
    viable = {}
    for _, tile in ipairs(candidates) do
      if tile.door >= pass.door
          and tile.player >= pass.player
          and tile.entity >= pass.entity then
        viable[#viable + 1] = tile
      end
    end
    if #viable > 0 then break end
  end

  if viable == nil or #viable == 0 then return nil end

  -- One RNG for the whole search rather than one per draw: a fresh RNG reseeded
  -- from the room would return the same pick forever.
  --
  -- Tiles that would sever the room are struck off and the draw repeats, so a
  -- room whose only comfortable spots are all bridges still ends up with a
  -- worse-placed rock rather than a run-ending one.
  local rng = roomRNG(room)
  while #viable > 0 do
    local pick = rng:RandomInt(#viable) + 1
    local tile = viable[pick]
    if not wouldIsolate(room, tile.index) then return tile.index end
    table.remove(viable, pick)
  end

  return nil
end

----------------------------------------------------------------------
-- Not cutting the room in half
----------------------------------------------------------------------

--- Whether a tile can be crossed. Pits are the reason this takes `flying`:
-- they stop a walking player and not a flying one, so a room can be connected
-- one way and severed the other.
local function passable(room, index, flying)
  local collision = room:GetGridCollision(index)
  if collision == COLLISION_NONE then return true end
  if flying and collision == COLLISION_PIT then return true end
  return false
end

--- Flood fill across passable tiles from `seeds`, pretending `blocked` is solid.
local function reachableFrom(room, seeds, blocked, flying)
  local width = room:GetGridWidth()
  local size = room:GetGridSize()

  local seen, stack = {}, {}
  for _, seed in ipairs(seeds) do
    if seed ~= blocked and seed >= 0 and seed < size
        and passable(room, seed, flying) then
      seen[seed] = true
      stack[#stack + 1] = seed
    end
  end

  while #stack > 0 do
    local index = stack[#stack]
    stack[#stack] = nil

    -- Four-neighbourhood, with the row edges guarded so a step off the left of
    -- one row does not wrap onto the right of the row above.
    local x = index % width
    local neighbours = {}
    if x > 0 then neighbours[#neighbours + 1] = index - 1 end
    if x < width - 1 then neighbours[#neighbours + 1] = index + 1 end
    if index - width >= 0 then neighbours[#neighbours + 1] = index - width end
    if index + width < size then neighbours[#neighbours + 1] = index + width end

    for _, n in ipairs(neighbours) do
      if not seen[n] and n ~= blocked and passable(room, n, flying) then
        seen[n] = true
        stack[#stack + 1] = n
      end
    end
  end

  return seen
end

--- Whether putting a rock on `index` would cut the player off from anywhere
-- they can currently get to.
--
-- This is the check that distance from the doors cannot make. A room can be a
-- single one-tile bridge between two doors, with the bridge nowhere near
-- either of them: every clearance rule passes, and a rock there ends the run
-- for anyone out of bombs. So rather than reasoning about doors, this floods
-- the room before and after and refuses anything that shrinks what is
-- reachable.
--
-- Run twice, because "reachable" is not one question. A walking player is
-- stopped by pits and a flying one is not, so a rock replacing a pit costs a
-- flying player a route while changing nothing on foot. Either loss is a
-- refusal.
function wouldIsolate(room, index)
  local seeds = {}
  for _, pos in ipairs(playerPositions()) do
    local ok, seed = pcall(function() return room:GetGridIndex(pos) end)
    if ok and type(seed) == "number" and seed >= 0 then
      seeds[#seeds + 1] = seed
    end
  end

  -- With nobody to measure from there is nothing meaningful to compare, so this
  -- abstains rather than guessing; the clearance rules still apply.
  if #seeds == 0 then return false end

  for _, flying in ipairs({ false, true }) do
    local before = reachableFrom(room, seeds, nil, flying)
    local after  = reachableFrom(room, seeds, index, flying)
    for tile in pairs(before) do
      if tile ~= index and not after[tile] then return true end
    end
  end

  return false
end

--- Whether a rock could be built on `index` without breaking the room.
--
-- Two ways to qualify: the tile is real floor, or it holds something in
-- REPLACEABLE. Either way the position itself still has to be sane -- a rock in
-- a doorway can seal the room, and one on the player can trap them -- so the
-- clearances apply regardless of what is there now.
local function canBuildAt(room, index)
  if type(index) ~= "number" or index < 0 or index >= room:GetGridSize() then
    return false
  end

  local width, height = room:GetGridWidth(), room:GetGridHeight()
  local x, y = index % width, math.floor(index / width)
  if x <= 0 or x >= width - 1 or y <= 0 or y >= height - 1 then return false end

  local existing = room:GetGridEntity(index)
  if existing then
    -- Room machinery keeps its tile; scenery and obstacles do not.
    if not REPLACEABLE[typeOf(existing)] then return false end
  else
    -- Nothing there, so it has to be floor rather than a hole in the layout.
    if room:GetGridCollision(index) ~= COLLISION_NONE then return false end
  end

  local pos = room:GetGridPosition(index)
  if not room:IsPositionInRoom(pos, 0) then return false end
  if minDistance(pos, doorPositions(room)) < TILE * 1.5 then return false end
  if minDistance(pos, playerPositions()) < TILE then return false end

  -- Last, because it is the expensive one and the cheap rules reject most tiles
  -- before it has to run.
  if wouldIsolate(room, index) then return false end

  return true
end

--- Decides which grid index the crawlspace is buried at in this room.
--
-- The engine's index is read-only -- there is no SetDungeonRockIdx in the API,
-- vanilla or REPENTOGON -- so the mod cannot correct the engine's answer. What
-- it can do is make the answer true: put a breakable rock on the tile the
-- engine already named, whether that tile is bare floor or something
-- overwritable.
--
-- That is worth a lot more than tidiness. Room:GetDungeonRockIdx() stays the
-- honest answer for everything that reads it -- Secrets Reveal's
-- buried-crawlspace marker, for one -- and the game's own crawlspace logic is
-- pointed at a rock that can actually be broken, so vanilla often delivers the
-- crawlspace itself and this mod never has to.
--
-- Only when the tile cannot be built on -- a doorway, a wall, an off-layout
-- index, or room machinery that must not be overwritten -- does the crawlspace
-- move somewhere else.
local function chooseRock(room)
  local ok, engineIdx = pcall(function() return room:GetDungeonRockIdx() end)
  if ok and type(engineIdx) == "number" and engineIdx >= 0 then
    -- Already breakable: nothing to fix.
    if isIntactRock(room:GetGridEntity(engineIdx)) then return engineIdx end

    if config.addRock and canBuildAt(room, engineIdx) then return engineIdx end
  end

  local rocks = intactRocks(room)
  if #rocks > 0 then
    return rocks[roomRNG(room):RandomInt(#rocks) + 1]
  end

  if config.addRock then return findTile(room) end
  return nil
end

----------------------------------------------------------------------
-- Placing things
----------------------------------------------------------------------

--- Makes sure there is something to break at `index`, planting a rock if the
-- tile is empty. Returns whether the index is now armable.
local function ensureRock(room, index)
  if isIntactRock(room:GetGridEntity(index)) then return true end
  if not config.addRock then return false end

  -- Clear the tile first. GridSpawn's force flag is meant to overwrite on its
  -- own, but an explicit removal is what reliably frees a tile holding a block
  -- or a pit rather than a previous visit's rubble.
  if room:GetGridEntity(index) ~= nil then
    pcall(function() room:RemoveGridEntity(index, 0, false) end)
  end

  local pos = room:GetGridPosition(index)
  local ok, planted = pcall(Isaac.GridSpawn, GRID_ROCK, 0, pos, true)
  return ok and planted ~= nil
end

--- Digs the crawlspace out at `index`. `announce` puts a puff of smoke on it,
-- which is wanted when a rock has just been broken in front of the player and
-- not when the room is merely being restored on re-entry.
local function revealCrawlSpace(room, index, announce)
  if index == nil then return false end

  local existing = room:GetGridEntity(index)
  if existing and typeOf(existing) == GRID_STAIRS then return true end

  -- force=true: this deliberately replaces the broken rock's rubble.
  local pos = room:GetGridPosition(index)
  local ok, grid = pcall(Isaac.GridSpawn, GRID_STAIRS, 0, pos, true)
  if not ok or grid == nil then return false end

  -- Grid entities spawned outside the room's own init occasionally come up
  -- holding their pre-init sprite state. PostInit settles it, and is wrapped
  -- because it is the sort of call that moves between patches.
  pcall(function() grid:PostInit() end)

  if announce then
    Isaac.Spawn(ENTITY_EFFECT, EFFECT_POOF, 0, pos, Vector(0, 0), nil)
  end
  return true
end

--- Gives up on the current room and lets the floor pick another one.
local function rejectRoom(record)
  if record.room ~= nil then record.tried[triedKey(record.room)] = true end
  record.room = nil
  record.rock = nil
end

--- Arms the rock in the floor's chosen room, which the player is standing in.
local function armRock(record, room)
  local index = record.rock
  if index == nil then
    index = chooseRock(room)
    if index == nil then
      -- Nothing breakable and nowhere to plant: this room cannot hold it.
      rejectRoom(record)
      return
    end
    record.rock = index
  end

  if ensureRock(room, index) then
    armed = index
  else
    rejectRoom(record)
  end
end

----------------------------------------------------------------------
-- Callbacks
----------------------------------------------------------------------

function mod:OnNewRoom()
  armed = nil
  pending = false

  local game = Game()
  local room, level = game:GetRoom(), game:GetLevel()
  local roomType = room:GetType()

  -- Arriving in a crawlspace or the Black Market means the floor's crawlspace
  -- has been spent.
  if roomType == ROOM.DUNGEON or roomType == ROOM.BLACK_MARKET then
    local record = lastFloor and state.floors[lastFloor]
    if record and record.opened then
      record.used = true
      if config.oncePerFloor then record.done = true end
    end
    return
  end

  if not config.enabled then return end
  if NEVER[roomType] then return end

  lastFloor = floorKey()

  local record = state.floors[lastFloor]
  if record == nil then
    record = { tried = {} }
    -- Settled once, before anything is armed. A floor the game already builds a
    -- crawlspace into needs nothing from us.
    if floorAlreadyHasOne(level) then record.done = true end
    state.floors[lastFloor] = record
  end

  local listIndex = currentListIndex()

  -- The floor's crawlspace is in this room and already dug out. Put it back if
  -- it did not survive the trip, since the player has done the digging.
  if record.opened and record.room == listIndex then
    if not record.used then revealCrawlSpace(room, record.rock, false) end
    return
  end

  if record.done or record.used then return end

  -- Something already provides one on this floor -- a room layout carries it, or
  -- the engine's own pick worked out. The floor needs nothing from us, and a
  -- second crawlspace would be worse than the bug being fixed.
  if hasCrawlSpace(room) then
    record.done = true
    return
  end

  ensureTarget(record, level)
  if record.room ~= listIndex then return end

  if config.afterClear and not room:IsClear() then
    pending = true
    return
  end

  armRock(record, room)
end

--- Watches the armed rock. One grid lookup per frame while something is armed,
-- and an immediate return everywhere else.
function mod:OnUpdate()
  local game = Game()

  if pending then
    local room = game:GetRoom()
    if not room:IsClear() then return end
    pending = false

    local record = state.floors[floorKey()]
    if record and record.room == currentListIndex() then armRock(record, room) end
    return
  end

  if armed == nil then return end

  local room = game:GetRoom()
  local grid = room:GetGridEntity(armed)
  local record = state.floors[floorKey()]

  -- Vanilla got there first: the engine's index was already a good rock and it
  -- produced the crawlspace itself. Nothing to add.
  if grid and typeOf(grid) == GRID_STAIRS then
    if record then record.opened = true end
    armed = nil
    return
  end

  if isIntactRock(grid) then return end

  revealCrawlSpace(room, armed, true)
  if record then record.opened = true end
  armed = nil
end

function mod:OnGameStart(isContinued)
  loadData()

  -- Settings persist across runs; the per-floor records do not, because their
  -- keys describe a layout that a new run has thrown away.
  if not isContinued then state.floors = {} end

  armed = nil
  pending = false
  lastFloor = nil
end

function mod:OnGameExit()
  saveData()
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnGameExit)

----------------------------------------------------------------------
-- Reading surface for other mods
----------------------------------------------------------------------

-- Room:GetDungeonRockIdx() is the natural place to ask which rock hides a
-- crawlspace, and it stays correct whenever this mod keeps or plants at the
-- engine's index -- which is the common case. It cannot stay correct when the
-- index was a block, a pit or a wall and the crawlspace had to move: nothing
-- engine-side records where it went. This is how to find out.
--
-- Deliberately plain functions on a plain global: a consumer can call them
-- behind a nil check and needs no load-order guarantee.
GuaranteedCrawlspaces = GuaranteedCrawlspaces or {}

--- Grid index of the rock hiding the current room's crawlspace, or -1.
--
-- Returns -1 once the rock has been broken: from that point the crawlspace is
-- an ordinary GRID_STAIRS in the grid, which anything scanning the room can
-- see for itself.
function GuaranteedCrawlspaces.GetRockIndex()
  if not config.enabled then return -1 end

  local record = state.floors[floorKey()]
  if record == nil or record.rock == nil then return -1 end
  if record.opened or record.used or record.done then return -1 end
  if record.room ~= currentListIndex() then return -1 end

  return record.rock
end

--- ListIndex of the room holding this floor's crawlspace, or -1. Available as
-- soon as the player has entered any room on the floor, so it can drive a map
-- reveal before the room itself is found.
function GuaranteedCrawlspaces.GetRoomListIndex()
  if not config.enabled then return -1 end

  local record = state.floors[floorKey()]
  if record == nil or record.room == nil then return -1 end
  if record.used then return -1 end

  return record.room
end

----------------------------------------------------------------------
-- Mod Config Menu
----------------------------------------------------------------------

-- Optional. Without it every default applies and the mod still works.
local CATEGORY = "Guaranteed Crawlspaces"

local function toggle(key, label, info)
  ModConfigMenu.AddSetting(CATEGORY, "Settings", {
    Type = ModConfigMenu.OptionType.BOOLEAN,
    CurrentSetting = function() return config[key] end,
    Display = function()
      return label .. ": " .. (config[key] and "on" or "off")
    end,
    OnChange = function(v) config[key] = v; saveData() end,
    Info = info,
  })
end

local function setupMCM()
  if ModConfigMenu == nil then return end

  pcall(function() ModConfigMenu.RemoveCategory(CATEGORY) end)

  ModConfigMenu.AddSpace(CATEGORY, "Settings")
  ModConfigMenu.AddText(CATEGORY, "Settings", "One crawlspace per floor, always reachable")
  ModConfigMenu.AddSpace(CATEGORY, "Settings")

  toggle("enabled", "Guarantee",
    { "The master switch. Off leaves every floor as", "the game made it." })

  toggle("addRock", "Bring a rock",
    {
      "Place a rock when the chosen room has no",
      "breakable one. This is what turns 'usually'",
      "into 'guaranteed'.",
    })

  toggle("includeSpecial", "Special rooms",
    {
      "Let the crawlspace land in a Shop, Treasure,",
      "Boss, Devil, Angel, Library, Arcade room and",
      "the rest. Off keeps it to ordinary and secret",
      "rooms.",
    })

  toggle("includeStart", "Starting room",
    { "Let it land in the room the floor begins in." })

  toggle("afterClear", "Only once cleared",
    {
      "On: the rock is armed after the room is cleared.",
      "Off: it is armed the moment you walk in.",
    })

  toggle("oncePerFloor", "One per floor",
    {
      "Once you have gone down the floor's crawlspace,",
      "that is the floor done. Off lets you re-enter",
      "the room to re-roll what is at the bottom.",
    })
end

setupMCM()
