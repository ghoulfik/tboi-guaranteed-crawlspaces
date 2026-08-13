-- Stubs enough of the Isaac API to run main.lua for real and assert on what it
-- does. The model is a whole floor of rooms, since the mod's job is to put one
-- crawlspace somewhere on it.

local MAIN = ...

----------------------------------------------------------------------
-- API stubs
----------------------------------------------------------------------

local VecMT = {}
VecMT.__index = VecMT
function VecMT:Distance(o)
  local dx, dy = self.X - o.X, self.Y - o.Y
  return math.sqrt(dx * dx + dy * dy)
end
function Vector(x, y) return setmetatable({ X = x, Y = y }, VecMT) end

local RngMT = {}
RngMT.__index = RngMT
function RngMT:SetSeed(s, n) self.seed = s end
function RngMT:RandomInt(n) return self.seed % n end
function RNG() return setmetatable({ seed = 1 }, RngMT) end

GridEntityType = {
  GRID_DECORATION = 1, GRID_ROCK = 2, GRID_ROCKB = 3, GRID_ROCKT = 4,
  GRID_ROCK_BOMB = 5, GRID_ROCK_ALT = 6, GRID_PIT = 7, GRID_SPIKES = 8,
  GRID_TNT = 12, GRID_WALL = 15, GRID_DOOR = 16, GRID_TRAPDOOR = 17,
  GRID_STAIRS = 18, GRID_ROCK_SS = 22, GRID_PILLAR = 24,
  GRID_ROCK_SPIKED = 25, GRID_ROCK_ALT2 = 26, GRID_ROCK_GOLD = 27,
}
GridCollisionClass = { COLLISION_NONE = 0 }
DoorSlot = { NUM_DOOR_SLOTS = 8 }
EntityType = { ENTITY_PICKUP = 5, ENTITY_SLOT = 6, ENTITY_EFFECT = 1000 }
EffectVariant = { POOF01 = 15 }
ModCallbacks = {
  MC_POST_NEW_ROOM = "newroom", MC_POST_UPDATE = "update",
  MC_POST_GAME_STARTED = "start", MC_PRE_GAME_EXIT = "exit",
}

local mcmSettings = {}
ModConfigMenu = {
  OptionType = { BOOLEAN = 1, NUMBER = 2 },
  RemoveCategory = function() end,
  AddSpace = function() end,
  AddText = function() end,
  AddSetting = function(cat, sub, t) mcmSettings[#mcmSettings + 1] = t end,
}

local function mcmSet(label, value)
  for _, s in ipairs(mcmSettings) do
    if s.Display():sub(1, #label) == label then s.OnChange(value); return true end
  end
  return false
end

package.preload["json"] = function()
  local stash
  return {
    encode = function(t) stash = t; return "<blob>" end,
    decode = function(_) return stash end,
  }
end

----------------------------------------------------------------------
-- World model
----------------------------------------------------------------------

local W, H = 15, 9          -- a 1x1 room's grid, walls included
local ROCK_BROKEN = 2

local T = {                  -- room types used by the tests
  DEFAULT = 1, SHOP = 2, ERROR = 3, TREASURE = 4, BOSS = 5,
  SECRET = 7, SUPERSECRET = 8, DUNGEON = 16, BLACK_MARKET = 22,
  GREED_EXIT = 23, ULTRASECRET = 29,
}

local world = {}

local function idxOf(x, y) return y * W + x end
local function gridPos(i) return Vector((i % W) * 40, math.floor(i / W) * 40) end
local function indexOfPos(p) return idxOf(p.X / 40, p.Y / 40) end

local DOOR_POS = {
  [0] = Vector(0, 4 * 40), [1] = Vector(7 * 40, 0),
  [2] = Vector(14 * 40, 4 * 40), [3] = Vector(7 * 40, 8 * 40),
}

function world.reset()
  world.stage, world.stageType = 1, 0
  world.placementSeed = 12345
  world.startGrid = 4
  world.rooms = {}
  world.order = {}
  world.current = nil
  world.spawned = {}          -- {room=, type=, index=}
  world.effects = {}
  world.players = { Vector(280, 200) }
end

--- Adds a room to the floor. `li` is its ListIndex, `safeGrid` its position in
-- the 13x13 level grid; a negative one marks an off-grid room.
function world.addRoom(li, roomType, safeGrid, opts)
  opts = opts or {}
  world.rooms[li] = {
    listIndex = li,
    type = roomType,
    safeGrid = safeGrid,
    grid = {},
    clear = opts.clear ~= false,
    decoSeed = opts.decoSeed or (1000 + li),
    dungeonIdx = opts.dungeonIdx or -1,
    doors = opts.doors or { 0, 2 },
    entities = opts.entities or {},
  }
  world.order[#world.order + 1] = li
  return world.rooms[li]
end

local function cur() return world.rooms[world.current] end

function world.putRock(li, index, gtype)
  world.rooms[li].grid[index] = { type = gtype or 2, state = 0 }
end
function world.breakRock(li, index)
  local g = world.rooms[li].grid[index]
  if g then g.state = ROCK_BROKEN end
end
function world.breakAll(li)
  for _, g in pairs(world.rooms[li].grid) do
    if g.type ~= 3 and g.type ~= 18 then g.state = ROCK_BROKEN end
  end
end

local room = {}
function room:GetType() return cur().type end
function room:GetGridWidth() return W end
function room:GetGridHeight() return H end
function room:GetGridSize() return W * H end
function room:GetGridPosition(i) return gridPos(i) end
function room:GetDungeonRockIdx() return cur().dungeonIdx end
function room:GetGridEntity(i)
  local g = cur().grid[i]
  if g == nil then return nil end
  return { State = g.state, GetType = function() return g.type end,
           PostInit = function() end }
end
function room:GetGridCollision(i)
  local x, y = i % W, math.floor(i / W)
  if x == 0 or x == W - 1 or y == 0 or y == H - 1 then return 1 end
  if cur().grid[i] then return 1 end
  return 0
end
function room:IsPositionInRoom(p, m) return true end
function room:RemoveGridEntity(i, pathTrail, keepDecoration) cur().grid[i] = nil end
function room:GetDoor(slot)
  for _, s in ipairs(cur().doors) do
    if s == slot and DOOR_POS[slot] then return { Position = DOOR_POS[slot] } end
  end
  return nil
end
function room:IsClear() return cur().clear end
function room:GetDecorationSeed() return cur().decoSeed end
function room:GetSpawnSeed() return cur().decoSeed end

local level = {}
function level:GetStage() return world.stage end
function level:GetStageType() return world.stageType end
function level:GetStartingRoomIndex() return world.startGrid end
function level:GetCurrentRoomIndex() return cur().safeGrid end
function level:GetDungeonPlacementSeed() return world.placementSeed end
--- RoomConfigRoom stand-in. `layoutCrawl` gives the room a crawlspace in its
-- layout, the way some vanilla rooms ship one.
local function layoutData(r)
  local data = { Type = r.type }
  if r.layoutCrawl then
    local entry = { Type = 9100 }
    local spawn = {
      EntryCount = 1,
      Entries = { Get = function(_, j) return j == 0 and entry or nil end },
    }
    data.SpawnCount = 1
    data.Spawns = { Size = 1, Get = function(_, i) return i == 0 and spawn or nil end }
  else
    data.SpawnCount = 0
    data.Spawns = { Size = 0, Get = function() return nil end }
  end
  return data
end

local function descOf(r)
  return { Data = layoutData(r), SafeGridIndex = r.safeGrid, ListIndex = r.listIndex }
end
function level:GetCurrentRoomDesc() return descOf(cur()) end
function level:GetRooms()
  local list = {}
  for _, li in ipairs(world.order) do list[#list + 1] = descOf(world.rooms[li]) end
  return {
    Size = #list,
    Get = function(_, i) return list[i + 1] end,
  }
end

local seeds = {}
function seeds:GetStageSeed(s) return world.placementSeed end

local game = {}
function game:GetLevel() return level end
function game:GetRoom() return room end
function game:GetSeeds() return seeds end
function game:GetNumPlayers() return #world.players end
function Game() return game end

Isaac = {}
function Isaac.GetPlayer(i) return { Position = world.players[i + 1] } end
function Isaac.GetRoomEntities() return cur().entities end
function Isaac.Spawn(t, v, s, pos)
  world.effects[#world.effects + 1] = { room = world.current, variant = v }
end
function Isaac.GridSpawn(t, v, pos, force)
  local i = indexOfPos(pos)
  local r = cur()
  if r.grid[i] and not force then return nil end
  r.grid[i] = { type = t, state = 0 }
  world.spawned[#world.spawned + 1] = { room = world.current, type = t, index = i }
  return { PostInit = function() end }
end

local callbacks = {}
local savedBlob = nil
function RegisterMod(name, ver)
  return {
    AddCallback = function(self, id, fn) callbacks[id] = fn end,
    SaveData = function(self, s) savedBlob = s end,
    LoadData = function(self) return savedBlob end,
    HasData = function(self) return savedBlob ~= nil end,
  }
end

----------------------------------------------------------------------
-- Load the mod under test
----------------------------------------------------------------------

world.reset()
world.addRoom(0, T.DEFAULT, 4)
world.current = 0

local chunk, err = loadfile(MAIN)
if chunk == nil then error("load failed: " .. tostring(err)) end
chunk()

local function enter(li) world.current = li; callbacks["newroom"](nil) end
local function tick() callbacks["update"](nil) end
local function startRun(cont) callbacks["start"](nil, cont) end

----------------------------------------------------------------------
-- Floor fixtures
----------------------------------------------------------------------

local ROCKS = { idxOf(4, 3), idxOf(6, 5), idxOf(9, 2), idxOf(10, 6) }

--- A normal-looking floor: start room, four plain rooms, a shop, a boss room,
-- a secret room, and an off-grid Devil deal. Every room has rocks in it unless
-- `bare` is set.
local function buildFloor(bare)
  world.reset()
  world.addRoom(0, T.DEFAULT, 4)          -- starting room
  world.addRoom(1, T.DEFAULT, 5)
  world.addRoom(2, T.DEFAULT, 18)
  world.addRoom(3, T.DEFAULT, 31)
  world.addRoom(4, T.SHOP, 6)
  world.addRoom(5, T.BOSS, 44)
  world.addRoom(6, T.SECRET, 19)
  world.addRoom(7, T.TREASURE, -1)        -- off-grid, unreachable
  if not bare then
    for _, li in ipairs(world.order) do
      for _, i in ipairs(ROCKS) do world.putRock(li, i, 2) end
    end
  end
end

--- Walks the whole floor, breaking everything breakable in each room.
local function sweepFloor()
  for _, li in ipairs(world.order) do
    if world.rooms[li].safeGrid >= 0 then
      enter(li); tick()
      world.breakAll(li)
      tick(); tick()
    end
  end
end

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------

local failures, passes = 0, 0
local function check(name, cond, detail)
  if cond then passes = passes + 1
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function spawnedOf(gtype)
  local out = {}
  for _, s in ipairs(world.spawned) do
    if s.type == gtype then out[#out + 1] = s end
  end
  return out
end
local function stairs() return spawnedOf(18) end
local function rocks() return spawnedOf(2) end

----------------------------------------------------------------------
-- 1. Exactly one crawlspace on the floor, in a plain room.
----------------------------------------------------------------------
buildFloor(); startRun(false)
sweepFloor()
local got = stairs()
check("exactly one crawlspace on the floor", #got == 1, "got " .. #got)
check("it is in a plain room",
      got[1] and world.rooms[got[1].room].type == T.DEFAULT,
      got[1] and tostring(world.rooms[got[1].room].type) or "none")
check("never in the off-grid room", not (got[1] and got[1].room == 7))
check("no rock planted -- the room had its own", #rocks() == 0,
      "planted " .. #rocks())

local chosenRoom = got[1] and got[1].room

----------------------------------------------------------------------
-- 2. The choice is stable: same floor, same room, same rock.
----------------------------------------------------------------------
buildFloor(); startRun(false)
sweepFloor()
local again = stairs()
check("same room chosen on a fresh run of the same floor",
      again[1] and again[1].room == chosenRoom,
      tostring(again[1] and again[1].room) .. " vs " .. tostring(chosenRoom))
check("same rock chosen", again[1] and again[1].index == got[1].index)

----------------------------------------------------------------------
-- 3. Visiting rooms in a different order changes nothing.
----------------------------------------------------------------------
buildFloor(); startRun(false)
for i = #world.order, 1, -1 do
  local li = world.order[i]
  if world.rooms[li].safeGrid >= 0 then
    enter(li); tick(); world.breakAll(li); tick(); tick()
  end
end
local rev = stairs()
check("room order does not affect the choice",
      #rev == 1 and rev[1].room == chosenRoom,
      tostring(rev[1] and rev[1].room))

----------------------------------------------------------------------
-- 4. Nothing appears until the rock is actually broken.
----------------------------------------------------------------------
buildFloor(); startRun(false)
for _, li in ipairs(world.order) do
  if world.rooms[li].safeGrid >= 0 then enter(li); tick(); tick() end
end
check("no crawlspace without breaking anything", #stairs() == 0,
      "got " .. #stairs())
enter(chosenRoom); world.breakAll(chosenRoom); tick()
check("breaking the armed rock delivers it", #stairs() == 1)
check("and it puffs into place", #world.effects == 1)

----------------------------------------------------------------------
-- 5. A room with no rocks gets one brought.
----------------------------------------------------------------------
buildFloor(true); startRun(false)      -- bare floor, no rocks anywhere
sweepFloor()
check("bare floor: a rock is planted", #rocks() == 1, "planted " .. #rocks())
check("bare floor: exactly one crawlspace", #stairs() == 1, "got " .. #stairs())
check("bare floor: planted and dug in the same room",
      rocks()[1] and stairs()[1] and rocks()[1].room == stairs()[1].room)

local planted = rocks()[1]
local pos = gridPos(planted.index)
local dmin = math.huge
for _, s in ipairs(world.rooms[planted.room].doors) do
  if DOOR_POS[s] then
    local d = pos:Distance(DOOR_POS[s]); if d < dmin then dmin = d end
  end
end
check("planted rock clears the doors", dmin >= 80, string.format("%.1f", dmin))
check("planted rock clears the player",
      pos:Distance(world.players[1]) >= 60)
local px, py = pos.X / 40, pos.Y / 40
check("planted rock is off the wall ring",
      px > 0 and px < W - 1 and py > 0 and py < H - 1)

----------------------------------------------------------------------
-- 6. The engine's own index is used when it is already a good rock.
----------------------------------------------------------------------
buildFloor(); startRun(false)
world.rooms[chosenRoom].dungeonIdx = ROCKS[3]
sweepFloor()
check("engine's good rock is honoured",
      #stairs() == 1 and stairs()[1].index == ROCKS[3],
      stairs()[1] and tostring(stairs()[1].index) or "none")

----------------------------------------------------------------------
-- 7. The engine's index is kept honest by rebuilding what sits on it, so
--    GetDungeonRockIdx() stays the right answer for other mods to read.
----------------------------------------------------------------------
-- An immovable block becomes a rock in place, rather than the crawlspace moving.
buildFloor(); startRun(false)
local BLOCK = idxOf(7, 4)
world.rooms[chosenRoom].grid[BLOCK] = { type = 3, state = 0 }
world.rooms[chosenRoom].dungeonIdx = BLOCK
sweepFloor()
check("block index: still exactly one crawlspace", #stairs() == 1)
check("block index: the block is rebuilt as a rock in place",
      #rocks() == 1 and rocks()[1].index == BLOCK,
      rocks()[1] and tostring(rocks()[1].index) or "none")
check("block index: crawlspace lands on the engine's own index",
      stairs()[1].index == BLOCK, tostring(stairs()[1].index))

-- Same for a pit, which is otherwise permanent.
buildFloor(); startRun(false)
local PIT = idxOf(8, 3)
world.rooms[chosenRoom].grid[PIT] = { type = 7, state = 0 }
world.rooms[chosenRoom].dungeonIdx = PIT
sweepFloor()
check("pit index: rebuilt as a rock in place",
      #rocks() == 1 and rocks()[1].index == PIT
      and #stairs() == 1 and stairs()[1].index == PIT,
      rocks()[1] and tostring(rocks()[1].index) or "none")

-- Room machinery is never overwritten: the crawlspace moves instead.
for _, machinery in ipairs({
  { 20, "pressure plate" }, { 17, "trapdoor" }, { 16, "door" },
  { 23, "teleporter" }, { 21, "statue" }, { 11, "locked block" },
}) do
  local gtype, label = machinery[1], machinery[2]
  buildFloor(); startRun(false)
  local SPOT = idxOf(7, 4)
  world.rooms[chosenRoom].grid[SPOT] = { type = gtype, state = 0 }
  world.rooms[chosenRoom].dungeonIdx = SPOT
  sweepFloor()
  check(label .. " is never overwritten",
        #stairs() == 1 and stairs()[1].index ~= SPOT
        and world.rooms[chosenRoom].grid[SPOT].type == gtype,
        tostring(stairs()[1] and stairs()[1].index))
end

----------------------------------------------------------------------
-- 8. A crawlspace already on the floor means the mod adds nothing.
----------------------------------------------------------------------
buildFloor(); startRun(false)
world.rooms[2].grid[idxOf(5, 4)] = { type = 18, state = 0 }  -- layout crawlspace
enter(2)                                   -- the player finds it first
sweepFloor()
check("existing crawlspace suppresses the mod's own", #stairs() == 0,
      "got " .. #stairs())
check("and nothing is planted", #rocks() == 0)

-- The layout is read up front, so a room the player never enters still counts.
buildFloor(); startRun(false)
world.rooms[3].layoutCrawl = true
for _, li in ipairs(world.order) do
  if li ~= 3 and world.rooms[li].safeGrid >= 0 then
    enter(li); tick(); world.breakAll(li); tick(); tick()
  end
end
check("a layout crawlspace suppresses even when never visited",
      #world.spawned == 0, "spawned " .. #world.spawned)

-- But one in an off-grid room does not serve the floor, so it must not count.
buildFloor(); startRun(false)
world.rooms[7].layoutCrawl = true          -- SafeGridIndex -1
sweepFloor()
check("an off-grid layout crawlspace does not suppress", #stairs() == 1,
      "got " .. #stairs())

----------------------------------------------------------------------
-- 9. Going down marks the floor spent.
----------------------------------------------------------------------
buildFloor(); startRun(false)
sweepFloor()
check("floor delivered", #stairs() == 1)

world.addRoom(90, T.DUNGEON, -1)
enter(90)                                  -- down the crawlspace
enter(chosenRoom)                          -- and back up
world.rooms[chosenRoom].grid = {}          -- grid did not persist
world.spawned = {}
enter(chosenRoom); tick(); tick()
check("used floor produces nothing further", #world.spawned == 0,
      "spawned " .. #world.spawned)

----------------------------------------------------------------------
-- 10. Re-entering before using it restores the crawlspace.
----------------------------------------------------------------------
buildFloor(); startRun(false)
sweepFloor()
check("floor delivered", #stairs() == 1)
local where = stairs()[1]
world.rooms[where.room].grid[where.index] = nil   -- did not persist
world.spawned = {}; world.effects = {}
enter(where.room)
check("re-entry restores it",
      #stairs() == 1 and stairs()[1].index == where.index)
check("restored silently", #world.effects == 0)

----------------------------------------------------------------------
-- 11. A second floor gets its own crawlspace.
----------------------------------------------------------------------
buildFloor(); startRun(false)
sweepFloor()
check("floor 1 delivered", #stairs() == 1)
world.stage = 2
world.placementSeed = 777
buildFloor()                              -- new layout, still stage 2
world.stage = 2
sweepFloor()
check("floor 2 delivers its own", #stairs() == 1, "got " .. #stairs())

----------------------------------------------------------------------
-- 12. Room filters.
----------------------------------------------------------------------
mcmSet("Starting room", false)
buildFloor(); startRun(false)
sweepFloor()
check("starting room excluded when off",
      #stairs() == 1 and stairs()[1].room ~= 0,
      tostring(stairs()[1] and stairs()[1].room))
mcmSet("Starting room", true)

-- With only special rooms available and specials off, nothing is placed.
mcmSet("Special rooms", false)
world.reset(); startRun(false)
world.addRoom(0, T.SHOP, 4)
world.addRoom(1, T.BOSS, 5)
for _, li in ipairs(world.order) do
  for _, i in ipairs(ROCKS) do world.putRock(li, i, 2) end
end
sweepFloor()
check("specials off: a shop-and-boss floor gets nothing", #world.spawned == 0,
      "spawned " .. #world.spawned)
mcmSet("Special rooms", true)
world.reset(); startRun(false)
world.addRoom(0, T.SHOP, 4)
world.addRoom(1, T.BOSS, 5)
for _, li in ipairs(world.order) do
  for _, i in ipairs(ROCKS) do world.putRock(li, i, 2) end
end
sweepFloor()
check("specials on: the same floor is served", #stairs() == 1,
      "got " .. #stairs())

-- Secret rooms are eligible, but plain rooms are preferred.
world.reset(); startRun(false)
world.addRoom(0, T.SECRET, 4)
world.addRoom(1, T.SUPERSECRET, 5)
world.addRoom(2, T.ULTRASECRET, 6)
for _, li in ipairs(world.order) do
  for _, i in ipairs(ROCKS) do world.putRock(li, i, 2) end
end
sweepFloor()
check("a secrets-only floor is still served", #stairs() == 1,
      "got " .. #stairs())

----------------------------------------------------------------------
-- 13. Rooms that can never hold it.
----------------------------------------------------------------------
for _, t in ipairs({ T.ERROR, T.GREED_EXIT }) do
  world.reset(); startRun(false)
  world.addRoom(0, t, 4)
  for _, i in ipairs(ROCKS) do world.putRock(0, i, 2) end
  sweepFloor()
  check("room type " .. t .. " never holds it", #world.spawned == 0)
end

----------------------------------------------------------------------
-- 14. Master switch, addRock, afterClear.
----------------------------------------------------------------------
mcmSet("Guarantee", false)
buildFloor(); startRun(false); sweepFloor()
check("master switch off does nothing", #world.spawned == 0)
mcmSet("Guarantee", true)

mcmSet("Bring a rock", false)
buildFloor(true); startRun(false); sweepFloor()
check("addRock off: bare floor gets nothing", #world.spawned == 0,
      "spawned " .. #world.spawned)
mcmSet("Bring a rock", true)

mcmSet("Only once cleared", true)
buildFloor(); startRun(false)
for _, li in ipairs(world.order) do world.rooms[li].clear = false end
for _, li in ipairs(world.order) do
  if world.rooms[li].safeGrid >= 0 then enter(li); tick(); tick() end
end
check("afterClear: nothing while uncleared", #world.spawned == 0)
enter(chosenRoom)
world.rooms[chosenRoom].clear = true
tick()
world.breakAll(chosenRoom)
tick()
check("afterClear: delivered once cleared", #stairs() == 1, "got " .. #stairs())
mcmSet("Only once cleared", false)

----------------------------------------------------------------------
-- 15. Degenerate floors do not crash.
----------------------------------------------------------------------
world.reset(); startRun(false)
world.addRoom(0, T.DEFAULT, 4)
for i = 0, W * H - 1 do world.rooms[0].grid[i] = { type = 3, state = 0 } end
local ok = pcall(function() sweepFloor() end)
check("solid room survives", ok)
check("solid room delivers nothing", #stairs() == 0)

world.reset(); startRun(false)
world.addRoom(0, T.DEFAULT, 4, { dungeonIdx = 9999 })
local ok2 = pcall(function() sweepFloor() end)
check("out-of-range engine index survives", ok2)
check("out-of-range engine index still delivers", #stairs() == 1,
      "got " .. #stairs())

-- A floor with nothing but off-grid rooms.
world.reset(); startRun(false)
world.addRoom(0, T.DEFAULT, -1)
local ok3 = pcall(function() enter(0); tick() end)
check("all-off-grid floor survives", ok3)
check("all-off-grid floor delivers nothing", #world.spawned == 0)

----------------------------------------------------------------------
-- 16. The engine's own index is kept wherever it can be, so anything reading
--     Room:GetDungeonRockIdx() -- Secrets Reveal's marker -- stays right.
----------------------------------------------------------------------
buildFloor(true); startRun(false)            -- bare rooms, nothing breakable
local ENGINE = idxOf(5, 3)
for _, li in ipairs(world.order) do world.rooms[li].dungeonIdx = ENGINE end
sweepFloor()
check("bare engine index: the rock is planted on it exactly",
      #rocks() == 1 and rocks()[1].index == ENGINE,
      rocks()[1] and tostring(rocks()[1].index) or "none")
check("bare engine index: the crawlspace ends up there",
      #stairs() == 1 and stairs()[1].index == ENGINE)

-- But not at any cost: an index in a doorway would seal the room.
buildFloor(true); startRun(false)
local NEARDOOR = idxOf(1, 4)                 -- one tile in front of door slot 0
for _, li in ipairs(world.order) do world.rooms[li].dungeonIdx = NEARDOOR end
sweepFloor()
check("door-adjacent engine index is refused",
      #rocks() == 1 and rocks()[1].index ~= NEARDOOR,
      rocks()[1] and tostring(rocks()[1].index) or "none")
check("and the floor is still served", #stairs() == 1)

----------------------------------------------------------------------
-- 17. The reading surface other mods use.
----------------------------------------------------------------------
local api = GuaranteedCrawlspaces
check("API is exposed", api ~= nil and api.GetRockIndex ~= nil
      and api.GetRoomListIndex ~= nil)

buildFloor(); startRun(false)
enter(0)
local targetRoom = api.GetRoomListIndex()
check("API names the room as soon as the floor is entered", targetRoom >= 0,
      tostring(targetRoom))

local otherRoom
for _, li in ipairs(world.order) do
  if li ~= targetRoom and world.rooms[li].safeGrid >= 0 then otherRoom = li; break end
end
enter(otherRoom)
check("API: no rock index outside the chosen room", api.GetRockIndex() == -1)

enter(targetRoom)
local rockIdx = api.GetRockIndex()
check("API: a rock index inside the chosen room", rockIdx >= 0, tostring(rockIdx))
check("API index points at a real intact rock",
      world.rooms[targetRoom].grid[rockIdx] ~= nil
      and world.rooms[targetRoom].grid[rockIdx].state ~= ROCK_BROKEN)

world.breakAll(targetRoom); tick()
check("API: -1 once dug out, the open crawlspace speaks for itself",
      api.GetRockIndex() == -1)
check("API: the room is still named while it is unused",
      api.GetRoomListIndex() == targetRoom)

world.addRoom(91, T.DUNGEON, -1)
enter(91)
check("API: nothing named once the floor is spent",
      api.GetRoomListIndex() == -1 and api.GetRockIndex() == -1)

-- With the mod switched off it reports nothing, so a consumer falls back to
-- the engine's own answer.
mcmSet("Guarantee", false)
check("API: silent while disabled",
      api.GetRockIndex() == -1 and api.GetRoomListIndex() == -1)
mcmSet("Guarantee", true)

----------------------------------------------------------------------
-- 18. Which kinds of breakable can hold the crawlspace.
----------------------------------------------------------------------
-- GRID_ROCK_ALT is the urn in the Basement, the mushroom in the Caves and the
-- skull in the Depths. A room whose only breakable is one of those must still
-- deliver.
local function onlyBreakableIs(gtype)
  buildFloor(true); startRun(false)          -- bare rooms
  local SPOT = idxOf(6, 5)
  for _, li in ipairs(world.order) do
    world.rooms[li].grid[SPOT] = { type = gtype, state = 0 }
  end
  sweepFloor()
  return SPOT
end

local vaseSpot = onlyBreakableIs(6)
check("a vase / skull / mushroom can hold the crawlspace",
      #stairs() == 1 and stairs()[1].index == vaseSpot,
      stairs()[1] and tostring(stairs()[1].index) or "none")
check("and no rock is planted when one is already there", #rocks() == 0)

-- The rest of the breakable family, each on its own.
local FAMILY = {
  { 2,  "plain rock" },      { 4,  "tinted rock" },
  { 5,  "bomb rock" },       { 6,  "urn / skull" },
  { 22, "super tinted rock" }, { 25, "spiked rock" },
  { 26, "X-marked skull" },  { 27, "golden rock" },
}
for _, entry in ipairs(FAMILY) do
  local spot = onlyBreakableIs(entry[1])
  check(entry[2] .. " is eligible",
        #stairs() == 1 and stairs()[1].index == spot,
        stairs()[1] and tostring(stairs()[1].index) or "none")
end

----------------------------------------------------------------------
-- 19. Reward-carrying rocks go second.
----------------------------------------------------------------------
-- A room offering both a plain rock and a reward rock must use the plain one,
-- so the reward is not spent and Secrets Reveal's tinted marker is not masked.
local PLAIN_SPOT, REWARD_SPOT = idxOf(4, 3), idxOf(9, 5)
for _, reward in ipairs({ { 4, "tinted" }, { 22, "super tinted" },
                          { 26, "X-marked skull" }, { 5, "bomb rock" },
                          { 27, "golden" } }) do
  buildFloor(true); startRun(false)
  for _, li in ipairs(world.order) do
    world.rooms[li].grid[PLAIN_SPOT] = { type = 2, state = 0 }
    world.rooms[li].grid[REWARD_SPOT] = { type = reward[1], state = 0 }
  end
  sweepFloor()
  check("plain rock beats a " .. reward[2],
        #stairs() == 1 and stairs()[1].index == PLAIN_SPOT,
        stairs()[1] and tostring(stairs()[1].index) or "none")
end

-- An urn counts as plain too, so it also beats a reward rock.
buildFloor(true); startRun(false)
for _, li in ipairs(world.order) do
  world.rooms[li].grid[PLAIN_SPOT] = { type = 6, state = 0 }
  world.rooms[li].grid[REWARD_SPOT] = { type = 4, state = 0 }
end
sweepFloor()
check("an urn / skull also beats a tinted rock",
      #stairs() == 1 and stairs()[1].index == PLAIN_SPOT,
      stairs()[1] and tostring(stairs()[1].index) or "none")

-- But a room with nothing but reward rocks still delivers.
buildFloor(true); startRun(false)
for _, li in ipairs(world.order) do
  world.rooms[li].grid[REWARD_SPOT] = { type = 4, state = 0 }
end
sweepFloor()
check("a tinted-only room still delivers a crawlspace",
      #stairs() == 1 and stairs()[1].index == REWARD_SPOT,
      stairs()[1] and tostring(stairs()[1].index) or "none")
check("and no rock is planted to avoid it", #rocks() == 0)

-- An unbreakable block is not eligible on its own: a rock gets planted instead.
buildFloor(true); startRun(false)
local BLOCKSPOT = idxOf(6, 5)
for _, li in ipairs(world.order) do
  world.rooms[li].grid[BLOCKSPOT] = { type = 3, state = 0 }
end
sweepFloor()
check("an immovable block alone is not treated as breakable",
      #rocks() == 1, "planted " .. #rocks())

print(string.format("\n%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
