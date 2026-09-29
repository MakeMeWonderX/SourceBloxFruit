--[[ ============================================================================
     ADMINTOOLS  -  Vehicle Suite                                       v1.0.0
     ----------------------------------------------------------------------------
     Single-file executor script.  Default menu key: INSERT (rebindable in-UI).

     World assumptions (from the target game):
        workspace["<Username>_<CarName>"]  -> the local vehicle model
        workspace.TrafficLanes.LaneN       -> folders of numbered waypoint parts
        workspace.TrafficFolder            -> streamed-in traffic vehicles

     Everything here is client side.  The automation drives the car through the
     physics ownership the client already has over its own vehicle.

     TUNING: if the in-game speedometer disagrees with this UI, edit
     CONFIG.MphPerStud below (studs/second -> MPH).
============================================================================ ]]

--============================================================================
-- SERVICES
--============================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- NOTE on VirtualInputManager: an early probe crashed this client on
-- GetService("VirtualInputManager"), so for a long time this script refused to
-- touch it. That was later disproved by a working clicker, and Settings ->
-- Auto click now uses it for real mouse events. It is still fetched lazily,
-- only when that feature runs, never at load.

--============================================================================
-- UNLOAD GUARD  (re-running the script cleans up the previous instance)
--============================================================================
-- NOTE: falls back to a private table, never _G.  Some executors share _G with
-- the game's own LocalScripts, which would publish this table to the game.
local ENV = (typeof(getgenv) == "function") and getgenv() or {}
if ENV.AdminTools and ENV.AdminTools.Unload then
    pcall(ENV.AdminTools.Unload)
end

--============================================================================
-- CONFIG
--============================================================================
local CONFIG = {
    Brand          = "AdminTools",
    Status         = "UNDETECTED",   -- shown beside the build number in the header
    Discord        = "https://discord.com/invite/FCRK59bu5Y",
    Version        = "3.12.0-Mobile",
    MphPerStud     = 0.6263,   -- studs/sec -> MPH  (1 stud ~= 0.28m)
    ESPRefresh     = 0.30,     -- seconds between target rescans
    MaxESPObjects  = 150,      -- pooled 2D drawings
    MaxHighlights  = 24,       -- Roblox soft-caps Highlights, stay under it
    PathNodes      = 30,       -- waypoint segments drawn by the Path preview
    WaypointRange  = 700,      -- lane-waypoint ESP draw distance
}

-- ARC HUD palette.  Every key that existed before still exists with the same
-- name and the same role - only the values moved - so all ~350 construction
-- sites keep compiling.  Nine keys are new.
--
-- Elevation reads  Void < Bg < Carbon < Panel < Row < RowHover.
-- Track is DELIBERATELY darker than Row: a slider track, a textbox, a keycap
-- and a value well should look milled INTO the plate, not floated on top of it.
-- The old Track (38,41,56) was brighter than the old Row (25,27,38), which is
-- why every well in the old UI looked like it was hovering.
--
-- Blue sits 4-9 points above red/green on the neutrals.  That is a whisper of
-- cool, not navy.  If a surface needs to read warmer, move its LIGHTNESS step;
-- never push more hue into a neutral.
local THEME = {
    Void     = Color3.fromRGB(  6,   7,   9),   -- loader ground, scrims, deepest well
    Bg       = Color3.fromRGB( 13,  14,  18),   -- window body
    Carbon   = Color3.fromRGB( 18,  20,  24),   -- gradient partner, weave tint
    Panel    = Color3.fromRGB( 24,  26,  31),   -- sections, header, sidebar
    Row      = Color3.fromRGB( 33,  35,  42),   -- control rows
    RowHover = Color3.fromRGB( 45,  48,  57),   -- now used by EVERY hover, not just rows
    Track    = Color3.fromRGB( 16,  17,  22),   -- recessed wells.  BELOW Row on purpose.

    -- Line work.  StrokeSoft @0.50-0.60 for resting edges, Stroke @0.25-0.35
    -- for emphasis/focus, Rail @0.55 for tick marks and brackets.
    StrokeSoft = Color3.fromRGB( 48,  51,  61),
    Stroke     = Color3.fromRGB( 68,  73,  86),
    Rail       = Color3.fromRGB( 92,  98, 114),

    -- Three text steps.  Dim was (88,95,118), which measures ~2.6:1 on Panel at
    -- 10px - unreadable.  At (114,121,137) it is ~3.4:1, and it is now reserved
    -- for captions and tick labels: descriptions and note bodies use Sub.
    Text = Color3.fromRGB(240, 243, 250),
    Sub  = Color3.fromRGB(158, 165, 181),
    Dim  = Color3.fromRGB(114, 121, 137),

    -- TWO USER-OWNED CHANNELS, and the rule that keeps them legible:
    --   Accent  = STATE.        On/selected/focused/in-progress.  Fills, rails,
    --                           gradients.  ~3.4:1 on Row - it NEVER carries text.
    --   Accent2 = MEASUREMENT.  Any number read from the world, always RobotoMono.
    --                           ~8.2:1 on Row.
    --   Accent3 = PEAK.         Far stop of a 3-stop gradient.  Never a large fill.
    -- Violet/cyan/magenta instead of the obvious amber: amber sits ~36 degrees
    -- from Warn and no review rule saves a collision that tight.
    Accent   = Color3.fromRGB(150,  96, 255),   -- ion violet  hue .738
    Accent2  = Color3.fromRGB(  0, 214, 255),   -- arc cyan    hue .527
    Accent3  = Color3.fromRGB(255,  92, 200),   -- hot magenta hue .900

    -- DERIVED on every accent change by TH.write.  Seeded here only so the very
    -- first frame is correct; never hardcode these at a call site.
    AccentDim  = Color3.fromRGB( 65,  45, 108),
    AccentGlow = Color3.fromRGB(184, 147, 255),
    AccentWash = Color3.fromRGB( 49,  44,  72),
    OnAccent   = Color3.fromRGB(255, 255, 255),  -- luminance-flipped, see TH.write

    -- Semantic.  These NEVER follow the accent and NEVER cycle under RGB mode,
    -- and they never fill a surface - 1px strokes, 2-3px slabs, 6px dots and
    -- labels at <= 11px only.
    Good = Color3.fromRGB( 52, 226, 138),   -- hue .416
    Warn = Color3.fromRGB(255, 176,  48),   -- hue .103
    Bad  = Color3.fromRGB(255,  72, 108),   -- hue .967

    -- Alias key so the 220 wireframe SelectionBoxes can be recoloured through
    -- one throttled registry bucket instead of following Accent2 directly.
    Wire = Color3.fromRGB(  0, 214, 255),
}

-- Read OVER the game world, not over a dark panel, so saturation is up across
-- the board.  All seven are user-settable in the Appearance tab.
local ESPCOL = {
    Car     = Color3.fromRGB( 52, 226, 138),
    Traffic = Color3.fromRGB(255, 140,  40),
    Player  = Color3.fromRGB(  0, 214, 255),
    -- MUST stay exactly 4 entries: the lane ESP indexes this cyclically with
    -- ((li - 1) % #ESPCOL.Lane) + 1, so an empty table is a divide-by-zero
    -- every frame.  The Appearance tab rewrites entries IN PLACE.
    Lane    = {
        Color3.fromRGB(255, 214,  64),
        Color3.fromRGB(176, 120, 255),
        Color3.fromRGB( 64, 255, 208),
        Color3.fromRGB(255, 110, 180),
    },
}

-- The only two top-level locals this overhaul adds.  They are DECLARED EMPTY
-- here and POPULATED in the do...end block below the primitive helpers, because
-- every consumer beneath this line (notify, the component library, Window, the
-- render loops) must be able to index them, while their bodies must be able to
-- capture new/tw/corner/stroke/grad/pad/bind - which do not exist yet.
-- Populate earlier and the closures capture nil globals; declare later and
-- notify() indexes a nil global.  Both fail at runtime, not at load.
local TH = {}   -- theme engine: live palette, tint registry, RGB driver
local FX = {}   -- motion tokens, shape helpers, one shared idle driver

--============================================================================
-- STATE
--============================================================================
local S = {
    Car = { Model = nil, Root = nil, Name = "-", Seat = nil },

    Keys = { Menu = Enum.KeyCode.Insert, Boost = Enum.KeyCode.LeftShift },

    -- Simple mode is a VIEW, not a preset: it decides which rows are on screen
    -- and never writes a control's value.  It launches ON, because the Auto
    -- defaults below are already the tuned setup - a first-time user should see
    -- four rows, not forty.  A saved config's "@simple" key overrides this.
    Simple = true,

    Boost = { Power = 180 },
    Fly   = { Enabled = false, Speed = 160 },
    Spin  = { Enabled = false, Speed = 28 },

    Wire = { Enabled = false, HideBody = false },

    -- every ESP option starts off; nothing draws until it is switched on
    ESP = {
        Master = false,
        Cars = false, Traffic = false, Players = false, Waypoints = false,
        Lines = false, Boxes = false, Highlights = false, Glow = false,
        ThroughWalls = false, IncludeLocal = false,
        Names = false, Distance = false,
        MaxDistance = 1500,
        ProgressBox = false, PathPreview = false,
        TrafficHitbox = false, ScoreHitbox = false,
    },

    Auto = {
        Running   = false,
        -- THESE EIGHT DEFAULTS ARE THE KNOWN-GOOD SETUP, measured at 98%
        -- accuracy in testing, not guesses.  A fresh launch now behaves like a
        -- tuned one, which is the whole point: nobody should have to configure
        -- anything to make this work.  A saved config still overrides them.
        Mode      = "Normal",
        SpeedMode = "Static",
        StaticMph = 310,
        Profile   = "Normal",
        Lane      = "Auto",
        Overtake  = true,
        Recover   = true,
        FollowGap = 70,
        NoBrake   = true,       -- ignore traffic entirely, never slow down
        Rotate    = true,       -- turn the body to follow the path
        Dodge     = true,       -- steer around traffic while still on the path
        DodgeMax  = 14,         -- studs of lateral room the fixed dodge may use
        -- deliberately OFF: on would arm a background poller at boot for someone
        -- who never asked for it.  It is one toggle away when they want it.
        AfkClick  = false,      -- real click every 30s while automation is driving
        SmartDodge = true,      -- measure real hitboxes instead of using DodgeMax
        DodgeClear = 0.5,       -- studs of air to leave on each side
        Bubble     = false,     -- a cushion of space held around our own car
        BubbleR    = 10,        -- studs of air it starts pushing at
        BubblePush = 6,         -- most it may add to the dodge offset
        Hover     = 0,          -- ride height; 0 is Normal, above it is Hover
        -- MEASURED, not derived.  Normal used to take its height from
        -- model:GetBoundingBox() - but that box covers the WHOLE model, and the
        -- root is at the chassis rather than at the box centre, so half the box
        -- height always came out too tall and the car floated.  Driven and
        -- checked against the Hover slider: 1 is in the deck, 2 is wheels down,
        -- 3 and up floats.  Change this number, not the formula.
        NormalHeight = 2,
        Goal      = "None",
        GoalValue = 10,
        -- live telemetry
        Logic = "Idle", Mph = 0, TargetMph = 0, Progress = 0,
        StartedAt = 0, Studs = 0, LaneIndex = 1, WpIndex = 1,
        NearMiss = 0, NearRate = 0, ActivePathName = nil, RunStartedAt = 0,
        Chasing = false, ChaseNote = "", ChaseLaps = 0, ChaseProgress = 0, ChaseCash = nil,
        EarnMoney = 0, EarnRate = 0, EarnPoints = 0, EarnStreak = 0,
    },
}

CONFIG.Profiles = {
    Slow   = { min = 50,  max = 100 },
    Normal = { min = 80,  max = 150 },
    Fast   = { min = 80,  max = 220 },
    Insane = { min = 200, max = 1000 },
}

--============================================================================
-- UTIL
--============================================================================
local CONN = {}
local REF = {}   -- live UI handles, so features can talk back to controls
local ALIVE = true      -- cleared by Unload so background loops exit

local function bind(signal, fn)
    local c = signal:Connect(fn)
    CONN[#CONN + 1] = c
    return c
end

-- RESERVED PSEUDO-PROPERTY: "Tint".  No Roblox GUI class has a property by that
-- name, so the key is safe to claim.  It subscribes the instance to the live
-- palette without touching any of the existing call sites.  A typo still throws
-- ("Tnt is not a valid member"), which is what we want.
--   Tint = "Row"                                  -> BackgroundColor3
--   Tint = { TextColor3 = "Accent2" }
--   Tint = { ImageColor3 = { "AccentGlow", -0.2 } }   -- { key, mul }
-- Always write the literal colour too, so the first frame is correct before any
-- repaint has run.  The TH.tag guard covers the window between here and the
-- do...end block where TH is populated.
local function new(class, props, kids)
    local inst = Instance.new(class)
    local parent, tint
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v
        elseif k == "Tint" then tint = v
        else inst[k] = v end
    end
    for _, kid in ipairs(kids or {}) do kid.Parent = inst end
    inst.Parent = parent
    if tint and TH.tag then TH.tag(inst, tint) end
    return inst
end

-- Strictly backward compatible - TweenInfo.new takes
-- (Time, EasingStyle, EasingDirection, RepeatCount, Reverses, DelayTime)
-- positionally, so all existing 5-argument calls behave identically.  Exposing
-- rep/rev/delayT is what makes delay-based staggers and looping idle tweens
-- possible with ONE tween primitive instead of two competing APIs.
local function tw(inst, t, props, style, dir, rep, rev, delayT)
    local info = TweenInfo.new(
        t,
        style or Enum.EasingStyle.Quart,
        dir   or Enum.EasingDirection.Out,
        rep   or 0,
        rev   or false,
        delayT or 0
    )
    local tween = TweenService:Create(inst, info, props)
    tween:Play()
    return tween
end

-- corner() now owns the radius multiplier and records the AUTHORED radius, so
-- the Appearance "Corner style" dropdown rescales every one of the 36 existing
-- call sites live without any of them changing.  `keep` opts a fixed shape out
-- (the colour-picker cursor and hue knob must stay perfect circles/capsules).
-- TH.c is weak-keyed, so radii of destroyed UI drop out on their own.
local function corner(inst, r, keep)
    local base = r or 8
    local rad  = base
    if not keep then rad = math.max(0, math.floor(base * (TH.rmul or 1) + 0.5)) end
    local c = new("UICorner", { CornerRadius = UDim.new(0, rad), Parent = inst })
    if not keep and TH.c then TH.c[c] = base end
    return c
end

-- `key` subscribes the stroke's Color to a live palette key.  Everything else
-- is unchanged, so all 14 existing call sites still work.
local function stroke(inst, color, thick, trans, key)
    local s = new("UIStroke", {
        Color = color or THEME.Stroke,
        Thickness = thick or 1,
        Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = inst,
    })
    if key and TH.bind then TH.bind(s, "Color", key) end
    return s
end

local function grad(inst, c1, c2, rot)
    return new("UIGradient", {
        Color = ColorSequence.new(c1, c2),
        Rotation = rot or 0,
        Parent = inst,
    })
end

local function pad(inst, l, r, t, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        Parent = inst,
    })
end

--============================================================================
-- THEME ENGINE (TH) + MOTION ENGINE (FX)
--============================================================================
-- Everything in here is a FIELD of TH or FX.  Locals declared inside this
-- do...end block are free - they do not count against the main chunk's 200
-- register budget, which is already at 160.
--
-- IN SCOPE here: services, LocalPlayer, Camera, ENV, CONFIG, THEME, ESPCOL,
--                TH, FX, S, CONN, REF, ALIVE, bind, new, tw, corner, stroke,
--                grad, pad.
-- NOT IN SCOPE:  lerp, round, fmtNum, keyName, GUI_MOUNT, ScreenMain,
--                ScreenESP, AdornHolder, NotifyHolder, notify, UI, CONTROLS,
--                Loading, Window, winRoot, ESP, Prog, A, World.
-- Anything here that needs a GUI root takes it as a parameter, and TH.uiOn /
-- FX.on are PUSHED IN from the window's Visible signal rather than pulled.
do
    --------------------------------------------------------------- colour maths
    function TH.mix(a, b, t)
        return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
    end
    function TH.tint(c, t)  return TH.mix(c, Color3.new(1, 1, 1), t) end
    function TH.shade(c, t) return TH.mix(c, Color3.new(0, 0, 0), t) end
    function TH.lum(c)      return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B end

    function TH.hex(c)
        return string.format("%02X%02X%02X",
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    function TH.unhex(s)
        if type(s) ~= "string" then return nil end
        local h = s:gsub("%s", ""):gsub("^#", "")
        if #h ~= 6 or h:match("%X") then return nil end
        local n = tonumber(h, 16)
        if not n then return nil end
        return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    end

    --------------------------------------------------------------------- state
    TH.b    = {}                                        -- TH.b[key] = { inst, prop, mul, ... }
    TH.g    = setmetatable({}, { __mode = "k" })        -- TH.g[UIGradient] = { key, key, key? }
    TH.ag   = {}                                        -- accent-family gradients, array
    TH.c    = setmetatable({}, { __mode = "k" })        -- TH.c[UICorner] = authored radius
    TH.ext  = {}                                        -- "ESP:Car" -> Color3 (ESPCOL mirror)
    TH.hooks = {}
    -- Per-key repaint throttle.  This is why TH.rate is per-key and not global:
    -- 220 wireframe SelectionBoxes at 5 Hz is 1,100 writes/sec worst case, and
    -- only while the wireframe is actually on.
    TH.rate = { Wire = 0.20, ["ESP:Traffic"] = 0.25, ["ESP:Car"] = 0.25 }
    TH.last = {}

    TH.r    = { win = 14, card = 10, row = 8, well = 6, chip = 4, tick = 2, pill = 999 }
    TH.rmul = 1

    TH.ACC  = { "Accent", "Accent2", "Accent3", "AccentDim", "AccentGlow", "AccentWash", "OnAccent" }
    TH.ISACC = { Accent = true, Accent2 = true, Accent3 = true,
                 AccentDim = true, AccentGlow = true, AccentWash = true, OnAccent = true }

    TH.opt = {
        rgb = false, speed = 0.12, spread = 0.18, sat = 0.86, val = 1.00,
        espRgb = false, shimmer = true, glowMul = 1.0,
        glowRate = 3.00, glowDepth = 0.16, wireThick = 0.040,
    }
    TH.t, TH.pulse, TH.hue = 0, 0, 0.738
    TH.acc, TH.gcAcc, TH.tickRate = 0, 0, 1 / 30
    TH.cur, TH.off, TH.gcur, TH.gcKey = 1, 1, 1, 1
    TH.slice = 64          -- MAX registry triples repainted per RGB tick. Never raise above 96.
    TH.uiOn  = false       -- pushed from the window Visible signal; false = skip UI repaint entirely

    -- PUMP OWNERSHIP.  Set true by the shared RenderStepped driver at the bottom
    -- of the file the instant it is bound.  The loader's own connection pumps
    -- TH.step/FX.step only while this is false, so the two engines are advanced
    -- EXACTLY once per frame at every point in the session - including boot,
    -- where the loader connection and the shared driver are both live and used
    -- to pump both engines twice with the same dt.
    TH.driven = false

    TH.base = {}
    for k, v in pairs(THEME) do TH.base[k] = v end

    ------------------------------------------------------------------ read
    function TH.get(key, mul)
        local c = THEME[key] or TH.ext[key] or Color3.new(1, 1, 1)
        if mul and mul ~= 0 then
            c = (mul < 0) and TH.mix(c, THEME.Void, -mul) or TH.tint(c, mul)
        end
        return c
    end

    ------------------------------------------------------------- subscription
    -- THE primitive.  Registers inst[prop] to follow THEME[key], applies it now,
    -- and returns inst so it chains inside a new() call.
    function TH.bind(inst, prop, key, mul)
        if not inst or not prop then return inst end
        local a = TH.b[key]
        if not a then a = {} TH.b[key] = a end
        local n = #a
        a[n + 1], a[n + 2], a[n + 3] = inst, prop, mul or 0
        inst[prop] = TH.get(key, mul)
        return inst
    end

    -- spec = "Accent"  ->  BackgroundColor3
    --      = { TextColor3 = "Sub", BackgroundColor3 = "Row" }
    --      = { ImageColor3 = { "AccentGlow", -0.2 } }     -- { key, mul }
    function TH.tag(inst, spec)
        if type(spec) == "string" then
            TH.bind(inst, "BackgroundColor3", spec)
        elseif type(spec) == "table" then
            for prop, v in pairs(spec) do
                if type(v) == "table" then TH.bind(inst, prop, v[1], v[2])
                else TH.bind(inst, prop, v) end
            end
        end
        return inst
    end

    function TH.stroke(inst, key, thick, trans, mul)
        local s = stroke(inst, TH.get(key, mul), thick, trans)
        TH.bind(s, "Color", key, mul)
        return s
    end

    -- corner() already applies TH.rmul AND records the authored radius in TH.c,
    -- so the token base is passed through raw and nothing is re-recorded here -
    -- multiplying or registering twice would square the effect.
    --
    -- `pill` opts OUT of the multiplier entirely via corner()'s `keep` flag.
    -- Merely clearing TH.c afterwards (the earlier attempt) was not enough: the
    -- 999 had ALREADY been scaled on the way in, so a "Sharp" corner style
    -- (rmul 0) turned every capsule into a rectangle and, because the TH.c
    -- record was gone, setRadius could never scale it back.
    function TH.corner(inst, token)
        local base = TH.r[token] or TH.r.row
        if token == "pill" then return corner(inst, base, true) end
        return corner(inst, base)
    end

    local function noteGrad(g, keys)
        TH.g[g] = keys
        for i = 1, #keys do
            if TH.ISACC[keys[i]] then TH.ag[#TH.ag + 1] = g return end
        end
    end

    function TH.grad(inst, kA, kB, rot, transSeq)
        local g = new("UIGradient", {
            Color = ColorSequence.new(TH.get(kA), TH.get(kB)),
            Rotation = rot or 0, Parent = inst,
        })
        if transSeq then g.Transparency = transSeq end
        noteGrad(g, { kA, kB })
        return g
    end

    function TH.grad3(inst, kA, kM, kB, rot, transSeq)
        local g = new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.0, TH.get(kA)),
                ColorSequenceKeypoint.new(0.5, TH.get(kM)),
                ColorSequenceKeypoint.new(1.0, TH.get(kB)),
            }),
            Rotation = rot or 0, Parent = inst,
        })
        if transSeq then g.Transparency = transSeq end
        noteGrad(g, { kA, kM, kB })
        return g
    end

    function TH.paintGrad(g)
        local k = TH.g[g]
        if not k then return end
        if k[3] then
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.0, TH.get(k[1])),
                ColorSequenceKeypoint.new(0.5, TH.get(k[2])),
                ColorSequenceKeypoint.new(1.0, TH.get(k[3])),
            })
        else
            g.Color = ColorSequence.new(TH.get(k[1]), TH.get(k[2]))
        end
    end

    function TH.hook(fn) TH.hooks[#TH.hooks + 1] = fn end

    -- live registry size, for the Appearance tab's "Bound instances" readout -
    -- it exists so the <=150 triple budget stays visible during development
    function TH.count()
        local n = 0
        for _, a in pairs(TH.b) do n = n + #a end
        return math.floor(n / 3)
    end

    --------------------------------------------------------------- repaint
    -- BUCKET-only repaint of ONE key, with in-place prune.  Split out of
    -- TH.paint so a caller changing several keys at once can do all the bucket
    -- work first and touch the gradient map ONCE at the end.  Returns false when
    -- the per-key throttle swallowed the call, so TH.paint can skip the gradient
    -- pass too and behave exactly as the single function did.
    local function paintKey(key)
        local rate = TH.rate[key]
        if rate then
            local now = tick()
            if now - (TH.last[key] or 0) < rate then return false end
            TH.last[key] = now
        end
        local a = TH.b[key]
        if a then
            local w = 1
            for i = 1, #a, 3 do
                local inst, prop, mul = a[i], a[i + 1], a[i + 2]
                if inst.Parent then
                    inst[prop] = TH.get(key, mul)
                    a[w], a[w + 1], a[w + 2] = inst, prop, mul
                    w = w + 3
                end
            end
            for i = w, #a do a[i] = nil end
        end
        return true
    end

    -- The gradient registry is one flat map, so it can only be searched by
    -- walking it - and every match rebuilds a ColorSequence plus its keypoints,
    -- which makes this the heaviest allocation site in the engine.  `keys` is
    -- therefore either ONE key string or a SET of keys, so an accent change
    -- (seven keys) walks the map once instead of seven times and rebuilds each
    -- accent gradient once instead of two or three times.  UI.Color's live drag
    -- drives that path at 20 Hz.
    function TH.paintGrads(keys)
        local one = (type(keys) == "string") and keys or nil
        for g, k in pairs(TH.g) do
            if g.Parent then
                if one then
                    if k[1] == one or k[2] == one or k[3] == one then TH.paintGrad(g) end
                elseif keys[k[1]] or keys[k[2]] or (k[3] and keys[k[3]]) then
                    TH.paintGrad(g)
                end
            end
        end
    end

    -- Full repaint of ONE key, with in-place prune.  Used for user colour changes.
    function TH.paint(key)
        if paintKey(key) then TH.paintGrads(key) end
    end

    function TH.repaintAll()
        for key in pairs(TH.b) do paintKey(key) end
        -- ONE unconditional sweep instead of a filtered sweep per key: O(#TH.g)
        -- rather than O(#TH.g x #keys), and it also reaches the gradients whose
        -- keys have no bound instances at all (the Panel -> Carbon plates and
        -- friends), which the per-key version silently skipped.
        for g in pairs(TH.g) do
            if g.Parent then TH.paintGrad(g) end
        end
        for _, fn in ipairs(TH.hooks) do pcall(fn, THEME) end
    end

    -- Walk the accent buckets in bounded slices, round-robin.  Per-frame cost is
    -- CONSTANT no matter how many accent surfaces exist, which is what keeps RGB
    -- mode from stuttering as the menu grows.  A record being up to three slices
    -- stale is invisible, because the hue itself moves slowly.
    function TH.slicePaint()
        local budget, guard, nk = TH.slice, 0, #TH.ACC
        while budget > 0 and guard < nk * 2 do
            local key = TH.ACC[TH.cur]
            local a = TH.b[key]
            if a and TH.off <= #a then
                local i = TH.off
                while i <= #a and budget > 0 do
                    local inst = a[i]
                    if inst.Parent then inst[a[i + 1]] = TH.get(key, a[i + 2]) end
                    i, budget = i + 3, budget - 1
                end
                TH.off = i
            else
                TH.off = 1
                TH.cur = (TH.cur % nk) + 1
                guard  = guard + 1
            end
        end
        local ng = #TH.ag
        if ng > 0 then
            for _ = 1, math.min(6, ng) do
                local g = TH.ag[TH.gcur]
                if g and g.Parent then TH.paintGrad(g) end
                TH.gcur = (TH.gcur % ng) + 1
            end
        end
    end

    ---------------------------------------------------------------- mutation
    -- writes the derived family into THEME without repainting (the RGB hot path)
    function TH.write(a, b, c)
        if a then THEME.Accent  = a end
        if b then THEME.Accent2 = b end
        if c then THEME.Accent3 = c end
        local A = THEME.Accent
        THEME.AccentDim  = TH.mix(A, THEME.Bg,  0.62)
        THEME.AccentGlow = TH.tint(A, 0.32)
        THEME.AccentWash = TH.mix(A, THEME.Row, 0.86)
        -- Luminance flip.  This is the single thing that stops a user-picked pale
        -- accent producing invisible button labels.  Never hardcode white/black
        -- for text that sits on an accent fill.
        THEME.OnAccent   = (TH.lum(A) > 0.55) and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
    end

    function TH.setAccent(a, b, c, quiet)
        TH.write(a, b, c)
        -- Seven buckets first, the gradient map ONCE at the end.  Calling
        -- TH.paint per key here walked that map seven times per accent change
        -- (~1,050 hash iterations with the shipped registry) and rebuilt every
        -- 3-stop accent gradient two or three times - 20 times a second for as
        -- long as the user drags the colour picker.
        for i = 1, #TH.ACC do paintKey(TH.ACC[i]) end
        TH.paintGrads(TH.ISACC)
        for _, fn in ipairs(TH.hooks) do pcall(fn, THEME) end
        if not quiet then TH.hue = select(1, Color3.toHSV(THEME.Accent)) end
    end

    function TH.set(key, col)
        if not col then return end
        if TH.ISACC[key] then
            if key == "Accent"  then return TH.setAccent(col, nil, nil) end
            if key == "Accent2" then return TH.setAccent(nil, col, nil) end
            if key == "Accent3" then return TH.setAccent(nil, nil, col) end
        end
        THEME[key] = col
        TH.paint(key)
        for _, fn in ipairs(TH.hooks) do pcall(fn, THEME) end
    end

    function TH.setRadius(mul)
        TH.rmul = mul
        for c, r in pairs(TH.c) do
            c.CornerRadius = UDim.new(0, math.max(0, math.floor(r * mul + 0.5)))
        end
    end

    ------------------------------------------------------------------- ESP
    -- cat = "Car" | "Traffic" | "Player" | "Lane1".."Lane4"
    function TH.esp(cat, col)
        if not col then return end
        local li = cat:match("^Lane(%d)$")
        if li then ESPCOL.Lane[tonumber(li)] = col       -- in place: never reassign ESPCOL.Lane
        else ESPCOL[cat] = col end
        TH.ext["ESP:" .. cat] = col
        TH.paint("ESP:" .. cat)
    end

    function TH.espCycle(h)
        local s, v = TH.opt.sat, math.max(TH.opt.val, 0.72)
        TH.esp("Car",     Color3.fromHSV(h, s, v))
        TH.esp("Traffic", Color3.fromHSV((h + 0.12) % 1, s, v))
        TH.esp("Player",  Color3.fromHSV((h + 0.24) % 1, s, v))
    end

    ------------------------------------------------- garbage collect (amortised)
    function TH.gc()
        local keys = TH.ACC
        local key = keys[(TH.gcKey % #keys) + 1]
        TH.gcKey = TH.gcKey + 1
        local a = TH.b[key]
        if not a then return end
        local w = 1
        for i = 1, #a, 3 do
            if a[i].Parent then
                a[w], a[w + 1], a[w + 2] = a[i], a[i + 1], a[i + 2]
                w = w + 3
            end
        end
        for i = w, #a do a[i] = nil end
        if TH.off > #a then TH.off = 1 end
        local n = #TH.ag
        if n > 0 then
            local gw = 1
            for i = 1, n do
                local g = TH.ag[i]
                if g and g.Parent then TH.ag[gw] = g gw = gw + 1 end
            end
            for i = gw, n do TH.ag[i] = nil end
            if TH.gcur > #TH.ag then TH.gcur = 1 end
        end
    end

    ------------------------------------------------------------------ THE PUMP
    -- Called once per frame from the RenderStepped bind that ALREADY EXISTS near
    -- the bottom of the file, and from the loader's temporary connection during
    -- boot.  This overhaul adds ZERO new RunService connections.
    function TH.step(dt)
        TH.acc = TH.acc + dt
        if TH.acc < TH.tickRate then return end
        local e = TH.acc
        TH.acc = 0
        TH.t = TH.t + e
        TH.pulse = 0.5 + 0.5 * math.sin(TH.t * 2.4)

        TH.gcAcc = TH.gcAcc + e
        if TH.gcAcc >= 2 then TH.gcAcc = 0 TH.gc() end

        if not TH.opt.rgb then return end
        TH.hue = (TH.hue + e * TH.opt.speed) % 1
        local s = TH.opt.sat
        local v = math.max(TH.opt.val, 0.72)          -- readability floor. Do not remove.
        TH.write(
            Color3.fromHSV(TH.hue, s, v),
            Color3.fromHSV((TH.hue + TH.opt.spread) % 1, s, v),
            Color3.fromHSV((TH.hue + TH.opt.spread * 2) % 1, s, v)
        )
        if TH.opt.espRgb then TH.espCycle(TH.hue) end
        if not TH.uiOn then return end                -- window closed = no UI repaint at all
        TH.slicePaint()
    end

    function TH.reset()
        for k, v in pairs(TH.base) do THEME[k] = v end
        TH.opt.rgb = false
        TH.write(THEME.Accent, THEME.Accent2, THEME.Accent3)
        TH.setRadius(1)
        TH.repaintAll()
    end

    -- Normalise the derived family from the shipped accent, so AccentDim /
    -- AccentGlow / AccentWash / OnAccent are exact rather than the hand-seeded
    -- approximations in the THEME literal.
    TH.write()
    for k, v in pairs(THEME) do TH.base[k] = v end

    -- ======================================================================= FX
    -- Four verbs: arrive, settle, lift, tick.  Arrivals are fast and
    -- decelerating; an exit is ALWAYS slower than its entrance.
    FX.T = { tap = 0.10, hov = 0.14, out = 0.20, base = 0.24,
             mid = 0.32, slow = 0.44, boot = 0.60 }
    -- `pop` (Back) is permitted in exactly THREE places: the toggle knob, the
    -- window open scale, and the loader mark snap.  Overshoot anywhere else
    -- fights the precision-instrument read.
    FX.E = {
        snap  = { Enum.EasingStyle.Quint,       Enum.EasingDirection.Out },
        glide = { Enum.EasingStyle.Quart,       Enum.EasingDirection.Out },
        drop  = { Enum.EasingStyle.Exponential, Enum.EasingDirection.Out },
        pop   = { Enum.EasingStyle.Back,        Enum.EasingDirection.Out },
        soft  = { Enum.EasingStyle.Sine,        Enum.EasingDirection.InOut },
    }
    FX.rate, FX.motion, FX.stagger, FX.flashOn = 1.0, true, true, true
    FX.toastBar = true                          -- Appearance "Toast countdown bar"
    FX.toastSeq = 0                             -- LayoutOrder sequence for the toast stack
    FX.on = false                               -- window open; gates the idle driver
    FX.anim, FX._loops = {}, {}
    -- Bumped by FX.stopLoops.  An owner of a repeating tween stamps this when it
    -- arms one, so a single integer compare tells it the loop was cancelled
    -- underneath it and needs re-arming.
    FX.loopGen = 0
    FX.acc, FX.CAP = 0, 24
    FX.IMG   = "rbxassetid://5554236805"        -- the one 9-slice glow already proven in this file
    FX.SLICE = Rect.new(23, 23, 277, 277)

    -- FX.motion = false makes this assign properties directly and return nil, so
    -- the Appearance "Reduced motion" toggle kills animation globally with no
    -- per-call-site branching.
    function FX.tw(inst, t, props, ease, rep, rev, delayT)
        if not inst then return nil end
        if not FX.motion then
            for k, v in pairs(props) do inst[k] = v end
            return nil
        end
        local e = ease or FX.E.snap
        local r = math.max(0.05, FX.rate)
        return tw(inst, (t or FX.T.base) / r, props, e[1], e[2], rep, rev, (delayT or 0) / r)
    end

    -- For the ONE case that genuinely needs a reversing TweenInfo (the keybind
    -- capture chip's breathing stroke).  Everything else belongs on FX.add.
    function FX.loop(inst, t, props, ease)
        if not FX.motion or #FX._loops >= 4 then return nil end
        local e = ease or FX.E.soft
        local tween = tw(inst, t, props, e[1], e[2], -1, true, 0)
        FX._loops[#FX._loops + 1] = tween
        return tween
    end

    -- FX.loop with the repeat / reverse / delay knobs exposed, for a repeating
    -- tween that is NOT a symmetric breathe - the world reticle's ping expands
    -- and restarts with a gap rather than reversing.  The bookkeeping is the
    -- whole point: a repeating tween created straight through FX.tw is invisible
    -- to the cap above and FX.stopLoops can never cancel it, so it outlives both
    -- "Reduced motion" and Unload.  Goes through FX.tw, not the raw tw, so the
    -- animation-speed slider still scales it.
    function FX.loopN(inst, t, props, ease, rep, rev, delayT)
        if not inst or not FX.motion or #FX._loops >= 4 then return nil end
        local tween = FX.tw(inst, t, props, ease, rep or -1, rev or false, delayT)
        if tween then FX._loops[#FX._loops + 1] = tween end
        return tween
    end

    function FX.stopLoops()
        for i = 1, #FX._loops do pcall(function() FX._loops[i]:Cancel() end) end
        FX._loops = {}
        -- Anything that owns a loop can now see that it was cancelled and re-arm
        -- itself: "Reduced motion" calls this and the user can turn it straight
        -- back off again.
        FX.loopGen = FX.loopGen + 1
    end

    -- Staggers go through tw's delayT, never task.delay chains - that is what
    -- stops a 20-row page spawning 20 closures on every tab switch.  Hard cap of
    -- 12 animated items per container; everything past it snaps.
    function FX.delay(i, step, cap)
        if not FX.motion or not FX.stagger then return 0 end
        return math.min(i or 1, cap or 12) * (step or 0.024)
    end

    function FX.add(inst, kind, rate, base)
        -- nil guard: a caller adopting an instance built in another region
        -- (REF.hMarkGrad and friends) must not be able to burn one of the 24
        -- slots on a nil that FX.step would skip forever.
        if not inst or #FX.anim >= FX.CAP then return inst end
        FX.anim[#FX.anim + 1] = { inst = inst, kind = kind, rate = rate or 1, base = base or 0 }
        return inst
    end

    -- Idempotent FX.add.  Use it whenever the instance was CREATED somewhere
    -- else and more than one region might plausibly claim it, so whichever runs
    -- first wins and the second is a no-op instead of a doubled write.
    function FX.once(inst, kind, rate, base)
        if not inst then return inst end
        for i = 1, #FX.anim do
            if FX.anim[i].inst == inst then return inst end
        end
        return FX.add(inst, kind, rate, base)
    end

    -- Remove an entry, for the Appearance toggles that kill a specific shimmer
    -- (rim light, ambient wash) without disabling the whole driver.
    function FX.remove(inst)
        for i = #FX.anim, 1, -1 do
            if FX.anim[i].inst == inst then table.remove(FX.anim, i) end
        end
    end

    -- The single shared idle driver.  Early-returning when the window is closed
    -- matters more than it looks: winRoot is a CanvasGroup, and ANY animating
    -- descendant forces the whole subtree to re-rasterise every frame.
    function FX.step(dt)
        if not FX.on or not TH.opt.shimmer then return end
        FX.acc = FX.acc + dt
        if FX.acc < 1 / 30 then return end
        FX.acc = 0
        local t, p = TH.t, TH.pulse
        for i = 1, #FX.anim do
            local a = FX.anim[i]
            local o = a.inst
            if o and o.Parent then
                local k = a.kind
                if k == "rim" or k == "spin" then
                    o.Rotation = (t * a.rate) % 360
                elseif k == "sweep" then
                    o.Offset = Vector2.new(((t * a.rate) % 2) - 1, 0)
                elseif k == "led" then
                    o.BackgroundTransparency = a.base + 0.34 * p
                elseif k == "glow" then
                    o.ImageTransparency = math.clamp(
                        1 - (1 - (a.base + 0.12 * p)) * TH.opt.glowMul, 0, 1)
                end
            end
        end
    end

    ------------------------------------------------------------ shape helpers
    -- LAYERING RULE: under ZIndexBehavior.Sibling a ZIndex-0 CHILD still paints
    -- in front of its own parent's BACKGROUND.  A soft shadow is therefore only
    -- valid when parent.BackgroundTransparency == 1, or as a sibling placed
    -- before the target inside a transparent wrapper.  Give FX.shadow a
    -- TRANSPARENT parent or it becomes a black wash over the thing it shades.
    function FX.shadow(parent, spread, trans)
        return TH.bind(new("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 4),
            Size = UDim2.new(1, spread or 72, 1, spread or 72), BackgroundTransparency = 1,
            Image = FX.IMG, ImageTransparency = trans or 0.45,
            ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
            ZIndex = 0, Parent = parent,
        }), "ImageColor3", "Void")
    end

    function FX.glow(parent, spread, trans, key)
        return TH.bind(new("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(1, spread or 40, 1, spread or 40), BackgroundTransparency = 1,
            Image = FX.IMG, ImageTransparency = trans or 0.85,
            ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
            ZIndex = 0, Parent = parent,
        }), "ImageColor3", key or "AccentGlow")
    end

    -- Two hairlines meeting at a point, replacing the literal GothamBold letter
    -- "v" the dropdown used as a chevron.
    function FX.chev(parent, key)
        local h = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -11, 0.5, 0),
            Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Parent = parent,
        })
        for i = 1, 2 do
            local b = TH.bind(new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, (i == 1) and -2 or 2, 0.5, 0),
                Size = UDim2.fromOffset(8, 1.6), Rotation = (i == 1) and 45 or -45,
                BorderSizePixel = 0, Parent = h,
            }), "BackgroundColor3", key or "Sub")
            corner(b, 1)
        end
        return h
    end

    -- Guarded value-change flash.  MANDATORY: the 10 Hz UI loop writes ~20 Info
    -- rows plus the footer every tick.  Unguarded that is 200+ tweens a second
    -- created and discarded forever, which shows up as GC pressure long before
    -- it shows up as frame time.  Callers must ALSO gate on string equality.
    function FX.flash(lbl, restKey, rule)
        if not FX.motion or not FX.flashOn then return end
        local now = tick()
        if now - (lbl:GetAttribute("ATFlash") or 0) < 0.60 then return end
        lbl:SetAttribute("ATFlash", now)
        lbl.TextColor3 = THEME.Accent
        FX.tw(lbl, 0.50, { TextColor3 = TH.get(restKey or "Accent2") }, FX.E.soft)
        if rule then
            rule.BackgroundTransparency = 0.10
            FX.tw(rule, 0.45, { BackgroundTransparency = 0.80 }, FX.E.soft)
        end
    end

    function FX.press(target, scale)
        bind(target.MouseButton1Down, function()
            FX.tw(scale, FX.T.tap, { Scale = 0.992 })
        end)
        bind(target.MouseButton1Up, function()
            FX.tw(scale, FX.T.out, { Scale = 1 })
        end)
        bind(target.MouseLeave, function()
            FX.tw(scale, FX.T.out, { Scale = 1 })
        end)
    end

    -- Toast glyphs, composed from 2 Frames each so no image asset is needed.
    -- Lives on FX rather than as a top-level local: the 2-local budget is spent.
    function FX.toastIcon(holder, kind, col)
        local function bar(w, h, x, y, rot)
            local b = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, x, 0.5, y),
                Size = UDim2.fromOffset(w, h), Rotation = rot or 0,
                BackgroundColor3 = col, BorderSizePixel = 0, Parent = holder,
            })
            corner(b, 1)
            return b
        end
        if kind == "bad" then
            bar(11, 2, 0, 0, 45) bar(11, 2, 0, 0, -45)          -- crossed
        elseif kind == "warn" then
            bar(2, 8, 0, -3, 0)  bar(2, 2, 0, 5, 0)             -- bang
        else
            bar(6, 2, -3, 2, 45) bar(11, 2, 1, -1, -45)         -- tick
        end
    end
end

local function lerp(a, b, t) return a + (b - a) * t end
local function round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
local function toMph(studs)  return studs * CONFIG.MphPerStud end
local function toStuds(mph)  return mph / CONFIG.MphPerStud end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

local function fmtNum(n)
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return string.format("%d", math.floor(n))
end

local function keyName(kc)
    if not kc then return "NONE" end
    local n = kc.Name
    n = n:gsub("^Left", "L"):gsub("^Right", "R")
    return n:upper()
end

--============================================================================
-- GUI ROOTS
--============================================================================
-- Mount order matters for detection: gethui() is a hidden container the game
-- cannot enumerate, plain CoreGui CAN be walked by an ordinary LocalScript, and
-- PlayerGui is fully visible to the game.
local GUI_MOUNT = "none"
local function mountGui(gui)
    if typeof(gethui) == "function" then
        local ok = pcall(function() gui.Parent = gethui() end)
        if ok and gui.Parent then GUI_MOUNT = "gethui" return gui end
    end
    if syn and syn.protect_gui then
        local ok = pcall(function() syn.protect_gui(gui) gui.Parent = CoreGui end)
        if ok and gui.Parent then GUI_MOUNT = "protect_gui" return gui end
    end
    local ok = pcall(function() gui.Parent = CoreGui end)
    if ok and gui.Parent then GUI_MOUNT = "coregui" return gui end
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    GUI_MOUNT = "playergui"
    return gui
end

local ScreenMain = mountGui(new("ScreenGui", {
    Name = "AT_" .. tostring(math.random(1e5, 1e6)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999999,
}))

local ScreenESP = mountGui(new("ScreenGui", {
    Name = "AT_ESP_" .. tostring(math.random(1e5, 1e6)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999990,
}))

--============================================================================
-- MOBILE TOGGLE BUTTON (Floating Action Button - 56x56)
--============================================================================
local MobileToggle = {}

function MobileToggle.Create(screenGui)
    -- Use TextButton instead of Frame so MouseButton events work
    local fab = new("TextButton", {
        Name = "MobileToggle",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -16),  -- Bottom-right corner
        Size = UDim2.fromOffset(64, 64),  -- Larger for mobile touch
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 105,  -- Higher ZIndex for visibility
        Text = "",  -- No text, just icon
        Parent = screenGui,
    })
    
    TH.corner(fab, "row")
    
    local iconContainer = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = fab,
    })
    
    for i = 1, 2 do
        TH.corner(new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, (i == 1) and -3 or 3, 0.5, 0),
            Size = UDim2.fromOffset(10, 2),
            BackgroundColor3 = THEME.Text,
            BorderSizePixel = 0,
            Rotation = (i == 1) and -45 or 45,
            Parent = iconContainer,
        }), 1)
    end
    
    return fab
end

function MobileToggle.ToggleWindow()
    if Window and Window.Toggle then
        Window.Toggle()
        notify("Menu " .. (Window.open and "opened" or "closed"), "", "good", 1)
    else
        print("[MobileToggle] Window.Toggle not ready")
    end
end

-- INVARIANT: this script never parents anything to Workspace.
-- Client-made instances do not replicate, but client-side anticheats watch
-- workspace.ChildAdded / DescendantAdded and report unknown instances to the
-- server.  Everything we create lives in the executor GUI container instead,
-- and world overlays (path preview) are drawn in screen space.
-- Adornments (Highlight / SelectionBox / BillboardGui) must NOT live inside a
-- ScreenGui - they render from the same container the ScreenGuis are mounted in.
local GuiRoot = ScreenMain.Parent
local AdornHolder = new("Folder", { Name = "AT_Adorn", Parent = GuiRoot })

local Unload  -- forward declaration (assigned at the bottom of the file)

--============================================================================
-- NOTIFICATIONS
--============================================================================
-- ZIndex 60 puts the stack above the window shell, so a toast fired while the
-- menu is open is never buried under it.
local NotifyHolder = new("Frame", {
    Name = "Notify",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -12, 1, -90),  -- Below toggle button
    Size = UDim2.fromOffset(240, 350),  -- Smaller for mobile
    BackgroundTransparency = 1,
    ZIndex = 60,
    Parent = ScreenMain,
}, {
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

-- Signature, the "bad"/"warn"/else colour mapping and the `dur or 4` default are
-- all frozen - this is called 77 times.
--
-- THE FIX: the old card was a DIRECT child of a UIListLayout, which rewrites
-- Position every frame, so the 30px slide at the old lines 330/331/337 never
-- once rendered - users only ever saw a crossfade.  The card now lives inside a
-- transparent `slot` that the layout owns, and the tween moves `body` instead.
-- Any future animation that tweens a direct child of a UIListLayout will
-- silently do nothing in exactly the same way.
--
-- Toasts are transient, so nothing here registers with TH - churning the colour
-- registry 77 times a session for instances that live 4 seconds is pure waste.
-- `col` is a runtime Color3, deliberately not a theme key.
local function notify(title, body, kind, dur)
    local col = (kind == "bad" and THEME.Bad) or (kind == "warn" and THEME.Warn) or THEME.Good

    -- Stack cap.  FOUR FOR MOBILE, not a target: the boot sequence alone can
    -- fire four (loaded, no-lane-map, no-vehicle, autoload).
    local live, oldest = 0, nil
    for _, ch in ipairs(NotifyHolder:GetChildren()) do
        if ch:IsA("GuiObject") then
            live = live + 1
            if (not oldest) or ch.LayoutOrder < oldest.LayoutOrder then oldest = ch end
        end
    end
    if live >= 4 and oldest then oldest:Destroy() end

    FX.toastSeq = FX.toastSeq + 1
    local slot = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, LayoutOrder = FX.toastSeq, Parent = NotifyHolder,
    })

    -- Built inline rather than via FX.shadow so it does not add a permanent
    -- record to the colour registry for something that dies in four seconds.
    local shade = new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 4),
        Size = UDim2.new(1, 24, 1, 24), BackgroundTransparency = 1,
        Image = FX.IMG, ImageColor3 = THEME.Void, ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
        ZIndex = 0, Parent = slot,
    })

    local card = new("Frame", {
        Position = UDim2.fromOffset(34, 0),
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Panel, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 2, Parent = slot,
    })
    TH.corner(card, "row")
    local cs = stroke(card, col, 1, 1)
    cs.LineJoinMode = Enum.LineJoinMode.Miter

    -- Type rail: the same left-edge vocabulary every control row uses, so a
    -- toast reads as part of the instrument rack rather than a browser popup.
    local rail = new("Frame", {
        Position = UDim2.new(0, 0, 0, 1), Size = UDim2.new(0, 3, 1, -2),
        BackgroundColor3 = col, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 3, Parent = card,
    })
    TH.corner(rail, "tick")

    -- Everything measurable lives in `inner`; the rail and the timer are
    -- scale-sized so they do not feed the card's AutomaticSize.
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, ZIndex = 3, Parent = card,
    })
    pad(inner, 14, 12, 10, 12)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })

    local head = new("Frame", {
        Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1,
        LayoutOrder = 1, ZIndex = 3, Parent = inner,
    })

    local ico = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(22, 22), BackgroundColor3 = THEME.Track,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = head,
    })
    TH.corner(ico, "well")
    local is = stroke(ico, THEME.StrokeSoft, 1, 1)
    FX.toastIcon(ico, kind, col)
    for _, g in ipairs(ico:GetChildren()) do
        if g:IsA("Frame") then g.ZIndex = 4 g.BackgroundTransparency = 1 end
    end

    local t = new("TextLabel", {
        Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -86, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = string.upper(title or ""), TextSize = 11, TextColor3 = col,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        TextTransparency = 1, ZIndex = 3, Parent = head,
    })

    local stamp = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(52, 12), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = os.date("%H:%M:%S"), TextSize = 8,
        TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Right,
        TextTransparency = 1, ZIndex = 3, Parent = head,
    })

    local b = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = body or "",
        TextSize = 10, TextColor3 = THEME.Sub, LineHeight = 1.18,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
        TextTransparency = 1, LayoutOrder = 2, ZIndex = 3, Parent = inner,
    })
    pad(b, 30, 0, 0, 0)   -- indent under the title, since UIListLayout owns Position

    -- One tween, zero per-frame cost, and the user can see how long they have.
    local timer = new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = col,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = card,
    })

    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "",
        AutoButtonColor = false, ZIndex = 5, Parent = card,
    })

    local gone = false
    local function dismiss()
        if gone or not slot.Parent then return end
        gone = true
        FX.tw(card, 0.24, { BackgroundTransparency = 1, Position = UDim2.fromOffset(34, 0) }, FX.E.glide)
        FX.tw(cs, 0.24, { Transparency = 1 }, FX.E.glide)
        FX.tw(is, 0.24, { Transparency = 1 }, FX.E.glide)
        FX.tw(shade, 0.24, { ImageTransparency = 1 }, FX.E.glide)
        FX.tw(rail, 0.24, { BackgroundTransparency = 1 }, FX.E.glide)
        FX.tw(timer, 0.20, { BackgroundTransparency = 1 }, FX.E.glide)
        FX.tw(t, 0.24, { TextTransparency = 1 }, FX.E.glide)
        FX.tw(b, 0.24, { TextTransparency = 1 }, FX.E.glide)
        FX.tw(stamp, 0.24, { TextTransparency = 1 }, FX.E.glide)
        for _, g in ipairs(ico:GetChildren()) do
            if g:IsA("Frame") then FX.tw(g, 0.24, { BackgroundTransparency = 1 }, FX.E.glide) end
        end
        task.delay(0.28, function() slot:Destroy() end)
    end
    bind(hit.MouseButton1Click, dismiss)

    -- Entrance: the 34px slide that was dead for the whole life of this script.
    FX.tw(card, 0.32, { BackgroundTransparency = 0.06, Position = UDim2.fromOffset(0, 0) }, FX.E.drop)
    FX.tw(cs, 0.30, { Transparency = 0.45 }, FX.E.glide)
    FX.tw(is, 0.30, { Transparency = 0.70 }, FX.E.glide)
    FX.tw(shade, 0.30, { ImageTransparency = 0.68 }, FX.E.glide)
    FX.tw(rail, 0.30, { BackgroundTransparency = 0 }, FX.E.glide)
    FX.tw(ico, 0.30, { BackgroundTransparency = 0.25 }, FX.E.glide)
    FX.tw(t, 0.30, { TextTransparency = 0 }, FX.E.glide)
    FX.tw(b, 0.30, { TextTransparency = 0.05 }, FX.E.glide)
    FX.tw(stamp, 0.30, { TextTransparency = 0.25 }, FX.E.glide)
    for _, g in ipairs(ico:GetChildren()) do
        if g:IsA("Frame") then FX.tw(g, 0.30, { BackgroundTransparency = 0 }, FX.E.glide) end
    end

    local life = dur or 4
    if FX.toastBar then
        timer.BackgroundTransparency = 0.35
        -- raw tw(), not FX.tw: this bar IS the clock, so it must not be scaled
        -- by the Appearance animation-speed slider.
        tw(timer, life, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    end
    task.delay(life, dismiss)
end

--============================================================================
-- UI COMPONENT LIBRARY
--============================================================================
local UI = {}

-- Every stateful control registers itself under "<section>/<label>", which is
-- what the config system saves and restores.  No per-control wiring needed.
local CONTROLS = {}
local function registerControl(parent, o, api)
    -- NoSave no longer bails first.  It used to, and that dropped five controls
    -- out of the registry before anything was recorded - one of them
    -- "Engine/Run automation", the main drive switch.  A user typing "auto" and
    -- not finding it is exactly the failure the search index exists to prevent.
    -- Indexed for search, then filtered for saving.
    if not o.Text then return end
    local sec = parent and parent:GetAttribute("ATSection")
    if not sec then return end
    -- o.Key pins the SAVED name while o.Text is free to be renamed for display.
    -- Saved configs key on "<section>/<name>", so without this every rename in
    -- the menu silently breaks every config anyone has saved.
    local key = sec .. "/" .. (o.Key or o.Text)
    local title = parent:GetAttribute("ATTitle") or sec
    UI.index[#UI.index + 1] = {
        key = key, sec = sec, secTitle = title, text = o.Text, desc = o.Desc,
        tags = o.Tags, opts = o.Options, simple = o.Simple,
        frame = api.Frame, secFrame = parent, page = parent.Parent,
        kind = "control",
        hay = (sec .. " " .. title .. " " .. o.Text .. " " .. (o.Desc or "") .. " "
            .. table.concat(o.Options or {}, " ") .. " " .. (o.Tags or "")):lower(),
    }
    if o.NoSave then
        -- Known, just deliberately not persisted.  Recorded so an old config
        -- carrying its key is not reported as "matched nothing" - that warning
        -- has to mean a genuinely dead key or nobody will read it.
        UI.noSave[key] = true
        return
    end
    CONTROLS[key] = api
end

function UI.Page(parent)
    local sf = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollBarImageTransparency = 0.45,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
        Parent = parent,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 16) }),
    })
    TH.bind(sf, "ScrollBarImageColor3", "Accent")   -- only 2 pages exist; cheap to keep live
    return sf
end

-- A section is a machined plate with a channel header:
--   [tick] CAPTION ---------------- hairline ---------------- S/03
-- It stays a PLAIN FRAME on purpose.  A CanvasGroup would clip its own UIStroke
-- at the canvas edge, and registerControl reads the ATSection attribute off the
-- exact instance rows are parented to.
function UI.Section(parent, title, order, key)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        -- WHITE on purpose.  A UIGradient MULTIPLIES BackgroundColor3, so filling
        -- the plate with Panel and then ramping Panel -> Carbon over it squares
        -- the tone and renders near-black.  White fill + tonal gradient is the
        -- same idiom the loader card and the world pod already use.
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.30,
        BorderSizePixel = 0,
        LayoutOrder = order or 1,
        Parent = parent,
    })
    TH.corner(holder, "card")
    local hs = stroke(holder, THEME.StrokeSoft, 1, 0.50)
    hs.LineJoinMode = Enum.LineJoinMode.Miter
    -- through the registry, not the raw grad(), so the plate matches the header
    -- and sidebar and follows a palette change like every other major surface
    TH.grad(holder, "Panel", "Carbon", 90)
    pad(holder, 14, 12, 12, 14)
    -- LOAD-BEARING: registerControl reads this.  `key` lets the section be
    -- RENAMED on screen while the string saved configs key on stays put.
    holder:SetAttribute("ATSection", key or title)
    -- The caption as DRAWN.  ATSection is the string saved configs key on, and
    -- nineteen of the twenty-one keyed sections show a different one - so an
    -- index built on the key alone could not find a single section by the name
    -- the user can actually see.
    holder:SetAttribute("ATTitle", title)
    new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })

    local head = new("Frame", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = -100, Parent = holder,
    })
    -- The lit top edge lives INSIDE head (which owns no layout) and reaches back
    -- over the card padding.  A direct child of holder would be swallowed by the
    -- holder's UIListLayout and laid out as a row.
    new("Frame", {
        Position = UDim2.new(0, -14, 0, -12), Size = UDim2.new(1, 26, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.94,
        BorderSizePixel = 0, Parent = head,
    })
    new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(32, 12),
        BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = string.format("S/%02d", order or 1), TextSize = 9, TextColor3 = THEME.Dim,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = head,
    })

    local strip = new("Frame", {
        Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Parent = head,
    }, {
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }),
    })
    local tick = TH.bind(new("Frame", {
        Size = UDim2.fromOffset(2, 10), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
        LayoutOrder = 1, Parent = strip,
    }), "BackgroundColor3", "Accent")
    TH.corner(tick, "tick")
    new("TextLabel", {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = string.upper(title), TextSize = 10, TextColor3 = THEME.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = strip,
    })
    local hair = new("Frame", {
        Size = UDim2.fromOffset(72, 1), BackgroundColor3 = THEME.StrokeSoft,
        BackgroundTransparency = 0.40, BorderSizePixel = 0, LayoutOrder = 3, Parent = strip,
    }, {
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })
    -- UIFlexItem is newer than some executor clients; the fixed 72px rule above
    -- is the fallback when Instance.new throws here.
    pcall(function()
        new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = hair })
    end)
    return holder
end

-- auto layout order: rows stack in creation order unless one is given explicitly
UI.orders = setmetatable({}, { __mode = "k" })
local function nextOrder(parent)
    UI.orders[parent] = (UI.orders[parent] or 0) + 1
    return UI.orders[parent]
end

-- Per-row hover / press / active handles.  Weak-keyed so a destroyed row drops
-- out on its own.  Lives on UI rather than in a new top-level local: the main
-- chunk is at its register budget and TH/FX are the whole allowance.
UI.rowfx = setmetatable({}, { __mode = "k" })

-- Every row the menu builds, in build order, for the search bar to walk.  A
-- plain array on UI rather than a new top-level local: the main chunk is near
-- the 200 register ceiling and TH/FX/UI are the whole allowance.
UI.index = {}
-- keys of controls that exist but are deliberately never saved
UI.noSave = {}

-- Buttons, Infos and Notes never call registerControl - they hold no saveable
-- state - but they are still things a user searches for.  A button IS a
-- feature (RESTORE COMBO, REBUILD LANE MAP), and a note carries the words
-- people actually type.  These take positional arguments rather than an
-- options table, so the entry is synthesised here.
--   kind: "control" saves state, "action" runs something, "prose" explains.
-- Prose is ranked below the control it describes so it never outranks it.
-- ONE owner for row visibility, because there are about to be three.
--
-- Feature logic already hides rows conditionally (the Hover slider only exists
-- in Hover, the Farm speed slider only in Smart farmer).  Simple mode and
-- the search bar want to hide rows too, and three writers to one boolean means
-- the last one to run wins: clear the search box and the Hover slider comes
-- back in a mode that hides it.  So nobody writes .Visible directly any more -
-- each reason sets its own bit, and the row is visible only when no bit is set.
UI.vis = setmetatable({}, { __mode = "k" })
UI.HIDE_COND, UI.HIDE_SIMPLE, UI.HIDE_SEARCH = 1, 2, 4

function UI.setVis(frame, reason, hidden)
    if not frame then return end
    local m = UI.vis[frame] or 0
    m = hidden and bit32.bor(m, reason) or bit32.band(m, bit32.bnot(reason))
    UI.vis[frame] = m
    local want = (m == 0)
    -- The guard is not cosmetic: a search keystroke touches every indexed row,
    -- and assigning Visible even when unchanged forces a layout pass on every
    -- ScrollingFrame in the window.
    if frame.Visible ~= want then frame.Visible = want end
end

function UI.indexRow(parent, text, frame, kind, extra)
    if not text or text == "" or not frame then return end
    local sec = parent and parent:GetAttribute("ATSection")
    if not sec then return end
    local title = parent:GetAttribute("ATTitle") or sec
    UI.index[#UI.index + 1] = {
        key = sec .. "/" .. text, sec = sec, secTitle = title, text = text, kind = kind,
        frame = frame, secFrame = parent, page = parent.Parent,
        hay = (sec .. " " .. title .. " " .. text .. " " .. (extra or "")):lower(),
    }
end

-- ONE type-rail vocabulary for the entire library.  The 2px rail down the left
-- of every row is colour-coded by what KIND of control it is, so a 24-control
-- page can be scanned before it is read.  Seven consistent rails are a system;
-- seven per-component literals are just decoration - keep this table the only
-- place these keys appear.
UI.tone = {
    Toggle   = "Accent",    -- violet  - a state you set
    Slider   = "Accent3",   -- magenta - a quantity you set
    Dropdown = "Rail",      -- steel   - a choice
    Input    = "Good",      -- green   - text you type
    Keybind  = "Warn",      -- amber   - a key you bind
    Info     = "Accent2",   -- cyan    - a value the tool measured
    Button   = "Accent",    -- violet  - an action
    Color    = "Accent",    -- the swatch overrides this with its own colour
}

-- UI.Button infers its danger variant from the label so no call site changes.
UI.danger = { "UNLOAD", "CLEAR", "STOP", "RESET", "KILL", "DELETE", "REMOVE" }

-- One inline panel open at a time (dropdown / colour picker), same idiom as
-- UI.listening.  Holds a closer function, nil when nothing is open.
UI.openPanel = nil

-- Returns the stroke, type rail and UIScale handles as well as the row.  The old
-- build threw the stroke away, which is why nothing in the library could light a
-- border on hover, focus, or an active toggle.
--   toneKey is a THEME key from UI.tone, never a literal colour.
local function baseRow(parent, height, order, toneKey)
    local tone = toneKey or "Rail"
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = THEME.Row,
        BackgroundTransparency = 0.30,
        BorderSizePixel = 0,
        LayoutOrder = order or nextOrder(parent),
        Parent = parent,
    })
    TH.corner(row, "row")
    local rs = stroke(row, THEME.StrokeSoft, 1, 0.55)
    rs.LineJoinMode = Enum.LineJoinMode.Miter
    local rail = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 2, 1, -10), BackgroundColor3 = TH.get(tone),
        BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = row,
    })
    TH.corner(rail, "tick")
    -- press feedback lives INSIDE the row; a wrapper frame around it would break
    -- registerControl, which requires the Section to be the row's direct parent
    local sc = new("UIScale", { Scale = 1, Parent = row })
    UI.rowfx[row] = { stroke = rs, rail = rail, scale = sc, tone = tone, active = false }
    return row, rs, rail, sc
end

-- `gutter` is the pixel width reserved on the right for the control itself.  The
-- old helper used a flat 70 for every row while the real controls are 49-143px
-- wide, so long labels ran underneath the Input and Keybind chips.  TextTruncate
-- now cuts them instead - visibly different, strictly better.
local function rowTitle(row, text, desc, gutter)
    local g = (gutter or 86) + 14
    local t = new("TextLabel", {
        Position = UDim2.fromOffset(14, desc and 7 or 0),
        Size = UDim2.new(1, -g, 0, desc and 15 or row.Size.Y.Offset),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text, TextSize = 12,
        TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    if desc then
        new("TextLabel", {
            Position = UDim2.fromOffset(14, 22), Size = UDim2.new(1, -g, 0, 14),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = desc, TextSize = 10,
            TextColor3 = THEME.Sub, LineHeight = 1.2, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
        })
    end
    return t
end

-- Four properties, one idiom, used by EVERY interactive row including Button and
-- Dropdown.  Previously hoverFx moved only BackgroundTransparency while UI.Button
-- moved only BackgroundColor3, so a button and a toggle side by side behaved
-- visibly differently.
-- Optional per-row overrides (set on UI.rowfx[row] before calling): restBg,
-- restTrans, hoverBg, hoverTrans, titleRest, titleHover, strokeRest,
-- strokeRestTrans - that is how the three Button variants share this one
-- function instead of each growing its own hover code.
local function hoverFx(row, rowStroke, rail, title, toneKey)
    local fx = UI.rowfx[row]
    if not fx then
        fx = { active = false }
        UI.rowfx[row] = fx
    end
    fx.stroke = rowStroke or fx.stroke
    fx.rail = rail or fx.rail
    fx.title = title or fx.title
    fx.tone = toneKey or fx.tone or "Rail"
    if fx.titleRest == nil then fx.titleRest = (title and title.TextColor3) or THEME.Text end

    local function paint(on)
        local d = on and FX.T.hov or FX.T.out
        if fx.stroke then
            FX.tw(fx.stroke, d, {
                Transparency = on and 0.28 or (fx.strokeRestTrans or 0.55),
                Color = on and TH.get(fx.tone) or (fx.strokeRest or THEME.StrokeSoft),
            })
        end
        -- an enabled toggle owns its row wash and its lit rail; hover must never
        -- steal them back on the leave branch
        if fx.active then return end
        FX.tw(row, d, {
            BackgroundColor3 = on and (fx.hoverBg or THEME.RowHover) or (fx.restBg or THEME.Row),
            BackgroundTransparency = on and (fx.hoverTrans or 0.08) or (fx.restTrans or 0.30),
        })
        if fx.rail then
            FX.tw(fx.rail, d, {
                BackgroundColor3 = TH.get(fx.tone),
                BackgroundTransparency = on and 0.15 or 0.85,
            })
        end
        if fx.title then
            FX.tw(fx.title, d, { TextColor3 = on and (fx.titleHover or THEME.Text) or fx.titleRest })
        end
    end
    fx.paint = paint

    bind(row.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then paint(true) end
    end)
    bind(row.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then paint(false) end
    end)
end

-- ---------------------------------------------------------------- INFO LABEL
-- The readout well.  46 of these are the workhorse of the tool, so the label is
-- DEMOTED to Sub and the number is the brightest thing on the row - the number
-- is what the user is actually reading.
function UI.Info(parent, text, value, order)
    local row = baseRow(parent, 34, order, UI.tone.Info)
    local title = rowTitle(row, text, nil, 140)
    title.TextColor3 = THEME.Sub
    -- no hoverFx: an Info row is not interactive and must not pretend to be

    local well = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(116, 22), BackgroundColor3 = THEME.Track,
        BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = row,
    })
    TH.corner(well, "well")
    stroke(well, THEME.StrokeSoft, 1, 0.70)
    -- DELIBERATELY UNREGISTERED, same rule the footer's fCar/fAuto follow.  The
    -- 10 Hz loop paints ~18 of these rows semantically - Good / Warn / Bad /
    -- Dim / Sub - and a TH.bind here would let TH.paint("Accent2") and the RGB
    -- slice write the accent straight over "not found" red and "RUNNING" green.
    -- Accent tracking is preserved by :Set writing THEME.Accent2 (THEME is
    -- mutated in place by TH.write) rather than by a registry slot.
    local val = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = (value ~= nil) and tostring(value) or "-", TextSize = 13, TextColor3 = THEME.Accent2,
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = well,
    })
    pad(val, 6, 8, 0, 0)
    local rule = new("Frame", {
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -3),
        Size = UDim2.fromOffset(28, 1), BackgroundColor3 = THEME.Rail,
        BackgroundTransparency = 0.80, BorderSizePixel = 0, Parent = well,
    })

    local api = { Frame = row }
    api._t, api._c = val.Text, nil
    -- COLOUR CONTRACT, unchanged from the original build: passing `color` wins,
    -- and OMITTING it LEAVES THE PREVIOUS COLOUR IN PLACE.  api._c is therefore
    -- sticky - it is only ever written when a caller supplies a colour - and a
    -- row that was last painted Bad stays Bad until a caller says otherwise.
    -- Call sites rely on this; do not "simplify" it into an Accent2 reset.
    --
    -- MANDATORY GUARD.  The 10 Hz UI loop calls Set on ~20 of these every tick;
    -- without the equality test the value flash starts 200+ tweens a second and
    -- the whole menu pulses.  The guard tests the LABEL, not the arguments, so
    -- an unchanged string still re-asserts its colour after the accent moves.
    -- The ATFlash window is skipped so the re-assert cannot fight FX.flash's
    -- own 0.50s tween back to rest.
    function api:Set(v, color)
        local s = tostring(v)
        if color then api._c = color end
        local want = api._c or THEME.Accent2
        local fresh = (s ~= api._t)
        if not fresh and (val.TextColor3 == want
            or (tick() - (val:GetAttribute("ATFlash") or 0)) < 0.60) then return end
        api._t = s
        val.Text = s
        val.TextColor3 = want
        if fresh and not api._c then FX.flash(val, "Accent2", rule) end
    end
    UI.indexRow(parent, text, row, "prose")
    return api
end

-- ---------------------------------------------------------------------- NOTE
function UI.Note(parent, text, color, order)
    local col = color or THEME.Warn
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = col, BackgroundTransparency = 0.93, BorderSizePixel = 0,
        LayoutOrder = order or nextOrder(parent), Parent = parent,
    })
    TH.corner(row, "well")
    pad(row, 14, 12, 8, 8)
    -- Full-height quote rail.  The old one was a fixed 2x12 at y=3, so on a
    -- three-line note it read as a stray tick beside line one.  Scale-sized
    -- children are excluded from AutomaticSize, so this cannot feed back.
    local bar = new("Frame", {
        Position = UDim2.new(0, -12, 0, -5), Size = UDim2.new(0, 2, 1, 10),
        BackgroundColor3 = col, BackgroundTransparency = 0.20, BorderSizePixel = 0, Parent = row,
    })
    TH.corner(bar, "tick")
    -- the // prefix is its own label so it can carry the rail colour while the
    -- body stays readable at Sub
    new("TextLabel", {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = "//", TextSize = 10, TextColor3 = col,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    local lbl = new("TextLabel", {
        Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = text, TextSize = 10, TextColor3 = THEME.Sub, TextWrapped = true, LineHeight = 1.22,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    UI.indexRow(parent, text, row, "prose")
    return { Frame = row, Label = lbl }
end

-- -------------------------------------------------------------------- BUTTON
-- `variant` is a new OPTIONAL 5th argument: "ghost" (default), "primary" or
-- "danger".  When it is omitted the label is matched against UI.danger, so
-- "UNLOAD ADMINTOOLS" reads red with zero call-site edits.
function UI.Button(parent, text, callback, order, variant)
    local row, rs, rail, sc = baseRow(parent, 34, order, UI.tone.Button)
    row.ClipsDescendants = true          -- keeps the charge wipe inside the rounded corners
    if not variant then
        local up = string.upper(text)
        for _, w in ipairs(UI.danger) do
            if string.find(up, w, 1, true) then variant = "danger" break end
        end
        variant = variant or "ghost"
    end

    -- one reused frame for the press "charge wipe": two tweens, one instance
    local wipe = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = row,
    })
    local lbl = new("TextLabel", {
        Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -30, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = string.upper(text), TextSize = 11, TextColor3 = THEME.Text,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3, Parent = row,
    })
    local chev = FX.chev(row, "Sub")
    chev.ZIndex = 3

    local fx, g3 = UI.rowfx[row], nil
    local restLbl = THEME.Text
    if variant == "primary" then
        -- A UIGradient MULTIPLIES BackgroundColor3, so a white fill reveals it and
        -- a Row fill hides it: hover is one colour tween, never a gradient swap.
        row.BackgroundColor3 = Color3.new(1, 1, 1)
        row.BackgroundTransparency = 0.10
        g3 = TH.grad3(row, "Accent", "Accent3", "Accent2", 0)
        -- OnAccent, never a hardcoded white: the user owns the accent, and a pale
        -- one would otherwise produce an invisible label
        TH.bind(lbl, "TextColor3", "OnAccent")
        restLbl = THEME.OnAccent
        rs.Color, rs.Transparency = THEME.Accent, 0.20
        fx.strokeRest, fx.strokeRestTrans = THEME.Accent, 0.20
        fx.restBg, fx.restTrans = Color3.new(1, 1, 1), 0.10
        fx.hoverBg, fx.hoverTrans = Color3.new(1, 1, 1), 0.02
        fx.titleRest, fx.titleHover = THEME.OnAccent, THEME.OnAccent
    elseif variant == "danger" then
        row.BackgroundColor3 = THEME.Bad
        row.BackgroundTransparency = 0.92
        lbl.TextColor3 = THEME.Bad
        rs.Color, rs.Transparency = THEME.Bad, 0.35
        rail.BackgroundColor3 = THEME.Bad
        restLbl = THEME.Bad
        fx.tone = "Bad"
        fx.strokeRest, fx.strokeRestTrans = THEME.Bad, 0.35
        fx.restBg, fx.restTrans = THEME.Bad, 0.92
        fx.hoverBg, fx.hoverTrans = THEME.Bad, 0.85
        fx.titleRest, fx.titleHover = THEME.Bad, Color3.new(1, 1, 1)
    else
        row.BackgroundTransparency = 0.15
        fx.restTrans, fx.hoverTrans = 0.15, 0.04
        fx.titleRest, fx.titleHover = THEME.Text, THEME.Text
    end
    hoverFx(row, rs, rail, lbl, fx.tone)

    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 4, Parent = row,
    })
    FX.press(btn, sc)
    bind(row.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then
            FX.tw(chev, FX.T.hov, { Position = UDim2.new(1, -8, 0.5, 0) })
            if g3 then FX.tw(g3, FX.T.hov, { Rotation = 8 }) end
        end
    end)
    bind(row.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then
            FX.tw(chev, FX.T.out, { Position = UDim2.new(1, -11, 0.5, 0) })
            if g3 then FX.tw(g3, FX.T.out, { Rotation = 0 }) end
        end
    end)
    bind(btn.MouseButton1Click, function()
        wipe.Size = UDim2.new(0, 0, 1, 0)
        wipe.BackgroundColor3 = THEME.Accent
        wipe.BackgroundTransparency = 0.70
        FX.tw(wipe, 0.12, { Size = UDim2.new(1, 0, 1, 0) }, FX.E.drop)
        FX.tw(wipe, 0.20, { BackgroundTransparency = 1 }, FX.E.glide, nil, nil, 0.12)
        FX.tw(lbl, 0.08, { TextColor3 = THEME.Accent2 })
        task.delay(0.12, function() FX.tw(lbl, 0.25, { TextColor3 = restLbl }) end)
        task.spawn(callback)
    end)
    UI.indexRow(parent, text, row, "action")
    -- Label is handed back for the two-press confirm idiom in Stage 5
    return { Frame = row, Label = lbl }
end

-- -------------------------------------------------------------------- TOGGLE
-- "This feature is ON" is carried by the whole row - wash, lit type rail, track
-- fill, brightened title - and NOT by a glow ImageLabel.  43 toggles x one halo
-- each would blow both the ImageLabel budget and the looping-tween cap, and the
-- row wash reads from further away anyway.
function UI.Toggle(parent, o)
    local row, rs, rail, sc = baseRow(parent, o.Desc and 44 or 34, o.Order, UI.tone.Toggle)
    local title = rowTitle(row, o.Text, o.Desc, 86)
    title.TextColor3 = THEME.Sub          -- an OFF row is quiet; ON brightens it to Text
    hoverFx(row, rs, rail, title, UI.tone.Toggle)

    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(42, 20), BackgroundColor3 = THEME.Track,
        BorderSizePixel = 0, Parent = row,
    })
    TH.corner(track, "chip")
    local ts = stroke(track, THEME.StrokeSoft, 1, 0.45)
    -- NO GRADIENT ON THE TRACK.  A UIGradient multiplies BackgroundColor3, and
    -- this fill is TWEENED between two palette colours (Track <-> AccentWash),
    -- so an AccentGlow -> Accent2 ramp would square whichever one is showing:
    -- the OFF track went muddier than Track and the ON track landed at
    -- RGB(35,25,72) - darker and more saturated than AccentWash, the opposite
    -- of "alive".  White-filling is not an option either, because the tween
    -- would immediately fight it.  The fill tween carries the state on its own
    -- and the stroke below supplies the accent.
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(16, 14), BackgroundColor3 = THEME.Rail,
        BorderSizePixel = 0, ZIndex = 2, Parent = track,
    })
    TH.corner(knob, "tick")
    -- The knob fill is tweened too (Rail when OFF, white when ON), so its ramp
    -- is a white -> grey SHADING gradient: it darkens the lower half of whatever
    -- colour is in the fill instead of replacing it.  The old Rail -> Text ramp
    -- over a Carbon fill multiplied out to RGB(6,8,11) and the OFF knob simply
    -- vanished against the track.
    grad(knob, Color3.new(1, 1, 1), Color3.fromRGB(176, 180, 190), 90)
    stroke(knob, THEME.StrokeSoft, 1, 0.45)
    local st = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0),
        Size = UDim2.fromOffset(26, 12), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = "OFF", TextSize = 9, TextColor3 = THEME.Dim,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
    })
    local btn = new("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = row })
    FX.press(btn, sc)

    local api = { Frame = row, Value = false }
    function api:Set(v, silent)
        v = v and true or false
        api.Value = v
        local fx = UI.rowfx[row]
        if fx then fx.active = v end      -- so hover's leave branch cannot undo the lit row
        FX.tw(knob, 0.22, {
            Position = UDim2.new(0, v and 23 or 3, 0.5, 0),
            -- Rail, not Carbon: the OFF knob has to be legible against a Track
            -- of RGB(16,17,22).  Carbon sits inside that, which is why the old
            -- OFF knob read as an empty slot.
            BackgroundColor3 = v and Color3.new(1, 1, 1) or THEME.Rail,
        }, FX.E.pop)                      -- permitted Back overshoot 1 of 3
        FX.tw(track, 0.18, { BackgroundColor3 = v and THEME.AccentWash or THEME.Track })
        FX.tw(ts, 0.18, { Color = v and THEME.Accent or THEME.StrokeSoft, Transparency = v and 0.20 or 0.45 })
        FX.tw(row, 0.20, {
            BackgroundColor3 = v and THEME.AccentWash or THEME.Row,
            BackgroundTransparency = v and 0.08 or 0.30,
        })
        FX.tw(rail, 0.18, { BackgroundColor3 = THEME.Accent, BackgroundTransparency = v and 0.15 or 0.85 })
        FX.tw(title, 0.20, { TextColor3 = v and THEME.Text or THEME.Sub })
        st.Text = v and "ON" or "OFF"
        FX.tw(st, 0.12, { TextColor3 = v and THEME.Accent or THEME.Dim })
        if not silent and o.Callback then
            local ok, err = pcall(o.Callback, v)
            if not ok then warn("[AdminTools] toggle error:", err) end
        end
    end
    bind(btn.MouseButton1Click, function() api:Set(not api.Value) end)
    api:Set(o.Default and true or false, true)
    if o.Default and o.Callback then task.defer(o.Callback, true) end
    registerControl(parent, o, api)
    return api
end

-- -------------------------------------------------------------------- SLIDER
-- A gauge, not a web control: milled track, tick scale, gradient fill, a head
-- riding the fill's right edge and a NEEDLE instead of a round knob.  The value
-- chip auto-sizes, which fixes the hardcoded 84px label that clipped any long
-- o.Format string.
function UI.Slider(parent, o)
    local row, rs, rail = baseRow(parent, 50, o.Order, UI.tone.Slider)
    local minV, maxV = o.Min or 0, o.Max or 100
    local dec = o.Decimals or 0
    local suffix = o.Suffix or ""

    local lbl = new("TextLabel", {
        Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -130, 0, 15), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = o.Text, TextSize = 12, TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    hoverFx(row, rs, rail, lbl, UI.tone.Slider)

    local chip = new("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6),
        Size = UDim2.new(0, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = THEME.Track, BackgroundTransparency = 0.45,
        BorderSizePixel = 0, Parent = row,
    })
    TH.corner(chip, "chip")
    pad(chip, 8, 8, 2, 2)
    local valLbl = TH.bind(new("TextLabel", {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = "-", TextSize = 12, TextColor3 = THEME.Accent2,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = chip,
    }), "TextColor3", "Accent2")

    local track = new("Frame", {
        Position = UDim2.new(0, 14, 1, -16), Size = UDim2.new(1, -28, 0, 4),
        BackgroundColor3 = THEME.Track, BorderSizePixel = 0, Parent = row,
    })
    TH.corner(track, "tick")
    stroke(track, THEME.StrokeSoft, 1, 0.70)
    -- tick scale: 0 / 50 / 100, plus the step marks when a step divides the range
    -- into 16 or fewer notches (any more and they read as noise)
    for i = 0, 2 do
        new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(i / 2, 0, 1, 3),
            Size = UDim2.fromOffset(1, 6), BackgroundColor3 = THEME.Rail,
            BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = track,
        })
    end
    if o.Step and o.Step > 0 and maxV > minV then
        local n = math.floor((maxV - minV) / o.Step + 0.5)
        if n > 1 and n <= 16 then
            for i = 1, n - 1 do
                new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(i / n, 0, 1, 3),
                    Size = UDim2.fromOffset(1, 4), BackgroundColor3 = THEME.Dim,
                    BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = track,
                })
            end
        end
    end
    -- WHITE fill, gradient supplies the colour.  Filling with Accent under an
    -- Accent -> Accent2 ramp squared it to violet -> pure blue with no cyan
    -- anywhere, so the gauge did not match the loader bar or the Prog bar, which
    -- both already use this idiom.
    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track,
    })
    TH.corner(fill, "tick")
    TH.grad(fill, "Accent", "Accent2", 0)
    -- Head and needle are REGISTERED, not painted inside apply().  apply() only
    -- runs on a drag or an api:Set, so an imperative repaint there freezes the
    -- most prominent element of every gauge at a stale accent while the fill
    -- gradient and the value chip beside it keep cycling under RGB mode.
    -- anchored to the fill's right edge, so it rides every bar tween for free
    TH.bind(new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(2, 9), BorderSizePixel = 0, ZIndex = 2, Parent = fill,
    }), "BackgroundColor3", "AccentGlow")
    local needle = TH.bind(new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 12), BorderSizePixel = 0, ZIndex = 3, Parent = track,
    }), "BackgroundColor3", "Accent")
    corner(needle, 1)
    new("Frame", {   -- 1px white core: the tell that turns a bar into an instrument
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 1, 1, -4), BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4, Parent = needle,
    })
    local hit = new("TextButton", {
        Position = UDim2.new(0, 0, 0, -8), Size = UDim2.new(1, 0, 1, 16),
        BackgroundTransparency = 1, Text = "", Parent = track,
    })

    local api = { Frame = row, Value = o.Default or minV }
    local dragging = false

    local function apply(v, silent, instant)
        v = math.clamp(v, minV, maxV)
        if o.Step then v = math.floor(v / o.Step + 0.5) * o.Step end
        v = round(v, dec)
        api.Value = v
        local a = (maxV > minV) and ((v - minV) / (maxV - minV)) or 0
        -- `instant` is INVERTED and has always been: api:Set passes true and wants
        -- the TWEEN, the drag path passes nil and wants the SNAP, because a tween
        -- lags the pointer.  It reads like a bug.  It is load-bearing - leave it.
        if instant then
            FX.tw(fill, 0.20, { Size = UDim2.new(a, 0, 1, 0) })
            FX.tw(needle, 0.20, { Position = UDim2.new(a, 0, 0.5, 0) })
        else
            fill.Size = UDim2.new(a, 0, 1, 0)
            needle.Position = UDim2.new(a, 0, 0.5, 0)
        end
        if o.Format then
            valLbl.Text = o.Format(v)
        else
            valLbl.Text = (dec > 0 and string.format("%." .. dec .. "f", v) or tostring(math.floor(v))) .. suffix
        end
        -- no imperative accent repaint here: needle and head are registered at
        -- construction, so they follow an accent change and RGB mode like the
        -- fill gradient and the value chip do
        if not silent and o.Callback then pcall(o.Callback, v) end
    end
    function api:Set(v, silent) apply(v, silent, true) end
    function api:Get() return api.Value end

    local function fromX(px)
        local a = math.clamp((px - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        apply(minV + (maxV - minV) * a)
    end
    bind(hit.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            FX.tw(needle, FX.T.tap, { Size = UDim2.fromOffset(3, 18) })
            FX.tw(chip, FX.T.tap, { BackgroundTransparency = 0.15 })
            fromX(i.Position.X)
        end
    end)
    bind(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                FX.tw(needle, FX.T.out, { Size = UDim2.fromOffset(3, 12) })
                FX.tw(chip, FX.T.out, { BackgroundTransparency = 0.45 })
            end
        end
    end)
    bind(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromX(i.Position.X)
        end
    end)
    apply(o.Default or minV, true, true)
    registerControl(parent, o, api)
    return api
end

-- ------------------------------------------------------------------ DROPDOWN
-- The inline push-down expansion is KEPT ON PURPOSE.  An overlay popup would
-- have to escape the tab page's ScrollingFrame and be re-anchored in screen
-- space against a scrolling, draggable, clipped window - the one change in this
-- overhaul with real layering risk.  The chevron, the spine, the 7-item scroll
-- cap and the staggered reveal get most of the benefit for none of it.
function UI.Dropdown(parent, o)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, ClipsDescendants = true,
        LayoutOrder = o.Order or nextOrder(parent), Parent = parent,
    })
    local row, rs, rail, sc = baseRow(holder, 34, 1, UI.tone.Dropdown)
    local title = rowTitle(row, o.Text, nil, 140)
    hoverFx(row, rs, rail, title, UI.tone.Dropdown)

    local cur = TH.bind(new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -32, 0.5, 0),
        Size = UDim2.fromOffset(108, 16), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = tostring(o.Default or (o.Options and o.Options[1]) or "-"), TextSize = 11,
        TextColor3 = THEME.Accent2, TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    }), "TextColor3", "Accent2")
    -- the old chevron was the literal letter "v" in GothamBold rotated 180 deg,
    -- the most dated element in the whole UI
    local chev = FX.chev(row, "Sub")
    local bars = chev:GetChildren()
    local btn = new("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = row })
    FX.press(btn, sc)

    -- a ScrollingFrame from birth so a data-driven SetOptions (the lane list can
    -- reach ~40 entries) switches scrolling on without rebuilding the panel
    local list = new("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = THEME.Carbon, BackgroundTransparency = 0.40, BorderSizePixel = 0,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 0,
        ScrollBarImageColor3 = THEME.Accent, ScrollBarImageTransparency = 0.40,
        ScrollingEnabled = false, Parent = holder,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    TH.corner(list, "card")
    stroke(list, THEME.StrokeSoft, 1, 0.55)
    -- schematic spine tethering the expansion to its row.  Child of `holder`,
    -- not of `list`: a UIListLayout would position anything parented to the list.
    local spine = new("Frame", {
        Position = UDim2.new(0, 6, 0, 34), Size = UDim2.new(0, 1, 0, 0),
        BackgroundColor3 = THEME.Rail, BackgroundTransparency = 0.55,
        BorderSizePixel = 0, ZIndex = 2, Parent = holder,
    })

    local api = { Frame = holder, Value = o.Default or (o.Options and o.Options[1]) }
    local open, optBtns, optList = false, {}, {}
    local setOpen

    local function refreshMarks()
        for value, item in pairs(optBtns) do
            local active = (value == api.Value)
            FX.tw(item.frame, 0.18, {
                BackgroundColor3 = active and THEME.AccentWash or THEME.Row,
                BackgroundTransparency = active and 0.10 or 0.55,
            })
            FX.tw(item.label, 0.18, { TextColor3 = active and THEME.Text or THEME.Sub })
            item.bar.BackgroundColor3 = THEME.Accent3
            FX.tw(item.bar, 0.18, { BackgroundTransparency = active and 0.10 or 1 })
        end
    end

    function api:Set(v, silent)
        api.Value = v
        cur.Text = tostring(v)
        refreshMarks()
        if not silent and o.Callback then pcall(o.Callback, v) end
    end

    setOpen = function(v)
        open = v
        if v then
            if UI.openPanel and UI.openPanel ~= api._close then pcall(UI.openPanel) end
            UI.openPanel = api._close
        elseif UI.openPanel == api._close then
            UI.openPanel = nil
        end
        local n = #(o.Options or {})
        local shown = math.min(n, 7)          -- long lists scroll instead of shoving the page down
        local lh = math.max(0, shown * 32 - 4)
        FX.tw(holder, 0.24, { Size = UDim2.new(1, 0, 0, v and (40 + lh) or 34) })
        FX.tw(list, 0.24, { Size = UDim2.new(1, 0, 0, v and lh or 0) })
        FX.tw(spine, 0.24, { Size = UDim2.new(0, 1, 0, v and (lh + 6) or 0) })
        FX.tw(chev, 0.24, { Rotation = v and 180 or 0 })
        for _, bar in ipairs(bars) do
            FX.tw(bar, 0.24, { BackgroundColor3 = v and THEME.Accent3 or THEME.Sub })
        end
        for i, item in ipairs(optList) do
            if v then
                -- The option frames are laid out by a UIListLayout, so the arrival
                -- slide moves their CHILDREN.  Tweening a layout child's Position
                -- silently does nothing - that is the bug that killed the old
                -- toast slide.
                item.frame.BackgroundTransparency = 1
                item.label.TextTransparency = 1
                item.idx.TextTransparency = 1
                item.label.Position = UDim2.fromOffset(40, 0)
                item.idx.Position = UDim2.fromOffset(20, 0)
                local d = FX.delay(i, 0.028, 8)
                local active = (item.value == api.Value)
                FX.tw(item.frame, 0.26, { BackgroundTransparency = active and 0.10 or 0.55 }, FX.E.snap, nil, nil, d)
                FX.tw(item.label, 0.26, { TextTransparency = 0, Position = UDim2.fromOffset(30, 0) }, FX.E.drop, nil, nil, d)
                FX.tw(item.idx, 0.26, { TextTransparency = 0.15, Position = UDim2.fromOffset(10, 0) }, FX.E.drop, nil, nil, d)
            else
                FX.tw(item.frame, 0.16, { BackgroundTransparency = 1 })
                FX.tw(item.label, 0.16, { TextTransparency = 1 })
                FX.tw(item.idx, 0.16, { TextTransparency = 1 })
            end
        end
    end
    api._close = function() if open then setOpen(false) end end

    local function buildOptions()
        for _, item in pairs(optBtns) do
            pcall(function() item.frame:Destroy() end)
        end
        optBtns, optList = {}, {}
        local n = #(o.Options or {})
        list.ScrollingEnabled = n > 7
        list.ScrollBarThickness = (n > 7) and 2 or 0
        for idx, value in ipairs(o.Options or {}) do
            local f = new("Frame", {
                Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = THEME.Row,
                BackgroundTransparency = 0.55, BorderSizePixel = 0, LayoutOrder = idx, Parent = list,
            })
            TH.corner(f, "well")
            local bar = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(3, 14), BackgroundColor3 = THEME.Accent3,
                BackgroundTransparency = 1, BorderSizePixel = 0, Parent = f,
            })
            corner(bar, 2)
            local ix = new("TextLabel", {
                Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(16, 28),
                BackgroundTransparency = 1, Font = Enum.Font.RobotoMono, Text = string.format("%02d", idx),
                TextSize = 9, TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = f,
            })
            local l = new("TextLabel", {
                Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -40, 1, 0),
                BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = tostring(value),
                TextSize = 11, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, Parent = f,
            })
            local b = new("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = f })
            local item = { frame = f, label = l, bar = bar, idx = ix, value = value }
            optBtns[value] = item
            optList[#optList + 1] = item
            -- raw Connect for the hover pair: these frames are rebuilt every time
            -- SetOptions runs, and their connections die with them.  bind() would
            -- pile dead entries into CONN on every lane rescan.
            b.MouseEnter:Connect(function()
                if value ~= api.Value then FX.tw(f, FX.T.hov, { BackgroundTransparency = 0.30 }) end
            end)
            b.MouseLeave:Connect(function()
                if value ~= api.Value then FX.tw(f, FX.T.out, { BackgroundTransparency = 0.55 }) end
            end)
            bind(b.MouseButton1Click, function()
                api:Set(value)
                setOpen(false)
            end)
        end
    end

    -- Repopulate a data-driven dropdown (e.g. the lane list once the map streams
    -- in).  Keeps the current selection when it still exists.
    function api:SetOptions(list2)
        o.Options = list2 or {}
        buildOptions()
        local stillThere = false
        for _, v in ipairs(o.Options) do
            if v == api.Value then stillThere = true break end
        end
        local prev = api.Value
        if not stillThere then api.Value = o.Options[1] end
        if open then setOpen(false) end
        -- Silent ONLY when the value survived.  A silent Set skips the callback,
        -- which is the one thing that writes the variable behind the control -
        -- so a dropped selection used to leave the widget reading one value and
        -- the feature reading another, with no way to tell from the screen.
        api:Set(api.Value, api.Value == prev)
    end
    function api:Count() return #(o.Options or {}) end

    buildOptions()
    bind(btn.MouseButton1Click, function() setOpen(not open) end)
    api:Set(api.Value, true)
    registerControl(parent, o, api)
    return api
end

-- --------------------------------------------------------------- TEXT INPUT
-- This was the only control in the tool with ZERO visual response to being
-- clicked into.  Focus now deepens the well, lights the stroke, draws an accent
-- rule along the bottom edge and lifts the row's type rail.
function UI.Input(parent, o)
    local row, rs, rail = baseRow(parent, 34, o.Order, UI.tone.Input)
    local title = rowTitle(row, o.Text, nil, 174)
    hoverFx(row, rs, rail, title, UI.tone.Input)
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(150, 24), BackgroundColor3 = THEME.Track,
        BackgroundTransparency = 0.25, BorderSizePixel = 0,
        Font = Enum.Font.RobotoMono, Text = o.Default or "", TextSize = 11,
        TextColor3 = THEME.Text, PlaceholderText = o.Placeholder or "",
        PlaceholderColor3 = THEME.Dim, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    TH.corner(box, "well")
    local bs = stroke(box, THEME.StrokeSoft, 1, 0.45)
    pad(box, 8, 8, 0, 0)
    local under = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(0, 0, 0, 1), BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.20, BorderSizePixel = 0, Parent = box,
    })

    local api = { Frame = row, Value = o.Default or "" }
    -- Toggle, Slider, Dropdown and Keybind all take (v, silent) and fire their
    -- callback unless silenced.  Input did not, so restoring a config set the
    -- visible text while the variable behind it kept its construction-time
    -- default - and Config.Apply still counted the key as applied.  Same shape
    -- as the other four now.
    function api:Set(v, silent)
        box.Text = tostring(v)
        api.Value = box.Text
        if not silent and o.Callback then pcall(o.Callback, api.Value) end
    end
    bind(box.Focused, function()
        FX.tw(bs, FX.T.hov, { Color = THEME.Accent, Transparency = 0, Thickness = 1.4 }, FX.E.drop)
        FX.tw(box, FX.T.hov, { BackgroundColor3 = THEME.Void, BackgroundTransparency = 0.10 })
        FX.tw(under, FX.T.hov, { Size = UDim2.new(1, 0, 0, 1) }, FX.E.drop)
        FX.tw(rail, FX.T.hov, { BackgroundTransparency = 0.10 })
    end)
    bind(box.FocusLost, function()
        local raw = box.Text
        local v = box.Text:gsub("[^%w_%-%.]", "")   -- keep it usable as a file name
        if v == "" then v = o.Default or "path" end
        box.Text = v
        api.Value = v
        FX.tw(bs, FX.T.out, { Color = THEME.StrokeSoft, Transparency = 0.45, Thickness = 1 })
        FX.tw(box, FX.T.out, { BackgroundColor3 = THEME.Track, BackgroundTransparency = 0.25 })
        FX.tw(under, FX.T.out, { Size = UDim2.new(0, 0, 0, 1) })
        FX.tw(rail, FX.T.out, { BackgroundTransparency = 0.85 })
        -- the sanitiser silently rewrites what was typed; a short amber pulse
        -- makes that visible instead of mysterious
        if raw ~= v then
            bs.Color = THEME.Warn
            FX.tw(bs, 0.30, { Color = THEME.StrokeSoft }, FX.E.soft, nil, nil, 0.20)
        end
        if o.Callback then pcall(o.Callback, v) end
    end)
    registerControl(parent, o, api)
    return api
end

-- --------------------------------------------------------------------- MODAL
-- A dialog the user has to acknowledge, for the cases where a toast is not
-- enough - a feature that will get them kicked, or one the game has quietly
-- broken.  Generalised from the Discord card the loader shows, which already
-- had the scrim, the card and the fade right.
--
-- THE ONE THING THAT MUST NOT BE COPIED FROM IT IS THE BLOCKING WAIT.  Promo
-- blocks on a while-loop because the boot sequence waits for it.  These open
-- from inside a control's Callback, which runs inside pcall(o.Callback, v)
-- inside api:Set - and Config.Apply calls api:Set for every restored key.  A
-- yielding dialog there would stall an entire config restore behind a box
-- nobody is looking at.  UI.Modal returns immediately.
--
--   UI.Modal{ Title=, Body=, Kind="warn"|"bad"|"good", Confirm="OK",
--             Cancel="Cancel", OnConfirm=fn, OnCancel=fn }
--
-- Kind only paints it.  OnConfirm/OnCancel are optional.
function UI.Modal(o)
    o = o or {}
    -- one at a time: a second call replaces the first rather than stacking
    if UI.modal and UI.modal.Parent then UI.modal:Destroy() end

    local tone = (o.Kind == "bad" and THEME.Bad)
        or (o.Kind == "good" and THEME.Good)
        or (o.Kind == "warn" and THEME.Warn)
        or TH.get("Accent")

    local scrim = new("Frame", {
        Name = "AT_Modal", Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = THEME.Void, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 190, Active = true, Parent = ScreenMain,
    })
    UI.modal = scrim

    local card = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(420, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Panel, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 191, Parent = scrim,
    })
    TH.corner(card, "card")
    -- read the palette once rather than TH.bind: TH.b holds strong references,
    -- and a card that lives a few seconds would leave dead registry entries
    -- for the rest of the session
    local edge = stroke(card, tone, 1, 1)
    local scale = new("UIScale", { Scale = 0.94, Parent = card })
    pad(card, 20, 20, 18, 16)
    new("UIListLayout", {
        Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = card,
    })

    local title = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = o.Title or "Heads up",
        TextSize = 13, TextColor3 = tone, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
        ZIndex = 192, Parent = card,
    })
    local body = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = o.Body or "", TextSize = 12, TextColor3 = THEME.Text,
        TextWrapped = true, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2,
        ZIndex = 192, Parent = card,
    })

    local rowBtn = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1,
        LayoutOrder = 3, ZIndex = 192, Parent = card,
    })
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = rowBtn,
    })

    local closing = false
    local function shut(which)
        if closing then return end
        closing = true
        FX.tw(scrim, FX.T.out, { BackgroundTransparency = 1 }, FX.E.glide)
        FX.tw(card, FX.T.out, { BackgroundTransparency = 1 }, FX.E.glide)
        FX.tw(edge, FX.T.out, { Transparency = 1 }, FX.E.glide)
        FX.tw(scale, FX.T.out, { Scale = 0.97 }, FX.E.glide)
        for _, d in ipairs(card:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                FX.tw(d, FX.T.hov, { TextTransparency = 1 }, FX.E.glide)
            end
        end
        task.delay(0.45, function() pcall(function() scrim:Destroy() end) end)
        if UI.modal == scrim then UI.modal = nil end
        local fn = (which == "confirm") and o.OnConfirm or o.OnCancel
        if fn then task.spawn(function() pcall(fn) end) end
    end

    local function mkBtn(text, col, which, order)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(text:len() * 8 + 34, 30),
            BackgroundColor3 = col, BackgroundTransparency = 0.15,
            AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = text,
            TextSize = 11, TextColor3 = THEME.Text, TextTransparency = 1,
            BorderSizePixel = 0, LayoutOrder = order, ZIndex = 193, Parent = rowBtn,
        })
        TH.corner(b, "well")
        b.MouseEnter:Connect(function()
            FX.tw(b, FX.T.hov, { BackgroundTransparency = 0.02 })
        end)
        b.MouseLeave:Connect(function()
            FX.tw(b, FX.T.hov, { BackgroundTransparency = 0.15 })
        end)
        b.MouseButton1Click:Connect(function() shut(which) end)
        return b
    end

    if o.Cancel then mkBtn(o.Cancel, THEME.Row, "cancel", 1) end
    mkBtn(o.Confirm or "OK", tone, "confirm", 2)

    FX.tw(scrim, FX.T.base, { BackgroundTransparency = 0.45 }, FX.E.glide)
    FX.tw(card, FX.T.base, { BackgroundTransparency = 0.02 }, FX.E.glide)
    FX.tw(edge, FX.T.base, { Transparency = 0.45 }, FX.E.glide)
    FX.tw(scale, FX.T.base, { Scale = 1 }, FX.E.glide)
    FX.tw(title, FX.T.base, { TextTransparency = 0 }, FX.E.glide)
    FX.tw(body, FX.T.base, { TextTransparency = 0.05 }, FX.E.glide)
    for _, d in ipairs(rowBtn:GetChildren()) do
        if d:IsA("TextButton") then
            FX.tw(d, FX.T.base, { TextTransparency = 0 }, FX.E.glide)
        end
    end
    return scrim
end

-- ------------------------------------------------------------------- KEYBIND
UI.listening = nil
function UI.Keybind(parent, o)
    local row, rs, rail, sc = baseRow(parent, o.Desc and 44 or 34, o.Order, UI.tone.Keybind)
    local title = rowTitle(row, o.Text, o.Desc, 116)
    hoverFx(row, rs, rail, title, UI.tone.Keybind)

    local chip = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(84, 24), BackgroundColor3 = THEME.Row,
        BorderSizePixel = 0, Parent = row,
    })
    TH.corner(chip, "well")
    -- The chip fill is TWEENED (Row at rest, Accent while capturing), so this is
    -- a white -> grey SHADING ramp, not a palette ramp.  The old Row -> Carbon
    -- gradient multiplied the rest fill down to RGB(4,5,7) and, worse, squashed
    -- the capture fill to RGB(19,12,33) - so "the chip turns Accent" never
    -- actually happened on screen.  This ramp keeps whichever hue is in the fill
    -- and only darkens the key's lower face.
    grad(chip, Color3.new(1, 1, 1), Color3.fromRGB(184, 188, 196), 90)
    local cs = stroke(chip, THEME.StrokeSoft, 1, 0.35)
    -- 2px dark bar along the bottom inside edge: reads as a physical key face
    new("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1),
        Size = UDim2.new(1, -8, 0, 2), BackgroundColor3 = THEME.Void,
        BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = chip,
    })
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = keyName(o.Default), TextSize = 11, TextColor3 = THEME.Text, Parent = chip,
    })
    local btn = new("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = chip })
    FX.press(btn, sc)

    local api = { Frame = row, Value = o.Default }
    function api:Set(kc, silent)
        api.Value = kc
        lbl.Text = keyName(kc)
        if not silent and o.Callback then pcall(o.Callback, kc) end
    end
    bind(btn.MouseButton1Click, function()
        if UI.listening then return end
        UI.listening = api
        lbl.Text = "..."
        FX.tw(chip, 0.20, { BackgroundColor3 = THEME.Accent })
        FX.tw(lbl, 0.20, { TextColor3 = THEME.OnAccent })
        cs.Color, cs.Transparency = THEME.Accent, 0
        -- one of at most FOUR permitted reversing loops in the whole file: the
        -- capture chip breathes so it is obvious the tool is waiting for a key
        local lp = FX.loop(cs, 0.70, { Transparency = 0.60 }, FX.E.soft)
        local function restLook()
            if lp then
                pcall(function() lp:Cancel() end)
                for i = #FX._loops, 1, -1 do
                    if FX._loops[i] == lp then table.remove(FX._loops, i) end
                end
                lp = nil
            end
            cs.Color, cs.Transparency = THEME.StrokeSoft, 0.35
            FX.tw(chip, 0.25, { BackgroundColor3 = THEME.Row })
            FX.tw(lbl, 0.25, { TextColor3 = THEME.Text })
        end
        local conn
        conn = UserInputService.InputBegan:Connect(function(i, gp)
            if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
            conn:Disconnect()
            UI.listening = nil
            restLook()
            if i.KeyCode == Enum.KeyCode.Escape then
                lbl.Text = keyName(api.Value)
            else
                api:Set(i.KeyCode)
                cs.Color = THEME.Good                     -- confirm the bind landed
                FX.tw(cs, 0.25, { Color = THEME.StrokeSoft }, FX.E.soft, nil, nil, 0.25)
            end
        end)
    end)
    registerControl(parent, o, api)
    return api
end

--============================================================================
-- LOADING SCREEN
--============================================================================
local Loading = {}
do
    -- one table instead of ~50 block-level locals: Luau caps a function at
    -- 200 live registers and the main chunk cannot afford a 50-wide block here
    local L = {}
    ------------------------------------------------------------------------
    -- "SYSTEM ARM"
    --
    -- A hairline draws itself across pure black and splits; the wordmark wipes
    -- into the gap; an arming L.ring spins up behind a chamfered L.plate; a mono
    -- percentage counts against a ticked instrument scale.  Finish detonates
    -- the L.ring into a shockwave and dissolves the whole L.card, so the window
    -- (opened 0.15s later by the boot sequence) rises THROUGH the dissolve.
    -- That overlap is the best moment in the sequence and is why L.root.ZIndex
    -- is raised rather than the window being lowered.
    --
    -- Contract frozen: Start() / Step(text, pct, hold) / Finish().  Step still
    -- yields via task.wait(hold or 0.28); boot at the bottom of the file
    -- depends on that.
    --
    -- Everything below is local to this do..end block, so the file gains no
    -- top-level locals.
    ------------------------------------------------------------------------

    -- delayT is FX.tw's 7th argument.  Wrapping it keeps the L.beat tables below
    -- readable as a timeline instead of a wall of nil, nil.
    function L.beat(inst, t, props, ease, delayT)
        return FX.tw(inst, t, props, ease, nil, nil, delayT)
    end

    -- FX.tw divides both its duration AND its delay by FX.rate.  Anything this
    -- region schedules with task.delay has to be scaled the same way or the
    -- hand-scheduled half of a L.beat drifts out of step with the tweened half
    -- the moment the user moves the animation-speed slider.
    function L.rdelay(t)
        return t / math.max(0.05, FX.rate)
    end

    -- A UIGradient MULTIPLIES the L.fill it sits on, so any surface that carries
    -- a colour gradient is filled white and lets the gradient supply the hue.
    -- Filling it with one of the gradient's own colours squares it into mud -
    -- that is why the old loader's L.mark read almost black.
    L.WHITE = Color3.new(1, 1, 1)

    ------------------------------------------------------------------- L.root
    -- Same pcall + Frame fallback already proven for winRoot.  A CanvasGroup
    -- lets Finish dissolve the entire L.card - ImageLabels, UIScales and all -
    -- with a single GroupTransparency tween instead of a descendant walk that
    -- silently misses classes.
    L.root = nil
    do
        local ok = pcall(function() L.root = Instance.new("CanvasGroup") end)
        if not ok or not L.root then L.root = Instance.new("Frame") end
    end
    L.isCG = L.root:IsA("CanvasGroup")
    L.root.Name = "Loader"
    L.root.Size = UDim2.new(1, 0, 1, 0)
    L.root.BackgroundColor3 = TH.get("Void")
    L.root.BackgroundTransparency = 1
    L.root.BorderSizePixel = 0
    -- RAISE THE LOADER, never lower the window.  The window opens while this is
    -- still dissolving; at the old ZIndex 50 it would have punched through.
    L.root.ZIndex = 200
    L.root.Parent = ScreenMain

    L.weave = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = L.WHITE,
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = L.root,
    })
    TH.grad3(L.weave, "Void", "Carbon", "Void", 90)

    L.bloom = TH.bind(new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -40),
        Size = UDim2.fromOffset(640, 400), BackgroundTransparency = 1,
        Image = FX.IMG, ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice,
        SliceCenter = FX.SLICE, Parent = L.root,
    }), "ImageColor3", "AccentGlow")

    -- The horizon sits on the wordmark's centre line, not the screen's, so the
    -- split brackets the logotype instead of cutting the L.card in half.
    L.RULE_Y, L.RULE_GAP = -68, 28
    L.rule = {}
    for i = 1, 2 do
        local r = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, L.RULE_Y),
            Size = UDim2.new(0, 0, 0, 1), BackgroundColor3 = TH.get("StrokeSoft"),
            BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = L.root,
        })
        -- fades at both screen edges, so it reads as a horizon and not a border
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = r,
        })
        L.rule[i] = r
    end

    -- A single full-screen white sheet, built up front so Finish allocates
    -- nothing at the instant the shockwave fires.
    L.flash = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = L.WHITE,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9, Parent = L.root,
    })

    ------------------------------------------------------------------- L.card
    L.card = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(420, 200), BackgroundTransparency = 1, Parent = L.root,
    })
    L.cardScale = new("UIScale", { Scale = 0.94, Parent = L.card })

    -- L.markBox exists purely so the shockwave can blow `L.ring` out to 560px
    -- without dragging the shadow with it - FX.shadow sizes itself off its
    -- parent.  Its own L.fill is transparent, which is what makes a ZIndex-0
    -- shadow child legal here.
    L.markBox = new("Frame", {
        Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(78, 78),
        BackgroundTransparency = 1, Parent = L.card,
    })
    L.shade = FX.shadow(L.markBox, 40, 1)

    L.ring = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(78, 78), BackgroundTransparency = 1, Parent = L.markBox,
    })
    TH.corner(L.ring, "pill")
    L.ringStroke = stroke(L.ring, L.WHITE, 2, 1)
    -- The gradient's Transparency sequence hides everything but a bright ARC of
    -- the circle, so spinning it reads as a mechanism arming rather than as a
    -- loading spinner.  One Rotation write per 30 Hz tick, via FX.anim.
    L.ringGrad = TH.grad3(L.ringStroke, "Accent", "Accent3", "Accent2", 0,
        NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }))

    L.plate = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(46, 46), BackgroundColor3 = L.WHITE,
        BackgroundTransparency = 1, BorderSizePixel = 0, Rotation = -12,
        ZIndex = 2, Parent = L.markBox,
    })
    TH.corner(L.plate, "chip")
    TH.grad(L.plate, "Carbon", "Panel", 135)
    L.plateStroke = TH.stroke(L.plate, "Accent", 1, 1)
    L.mark = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBlack, Text = "A", TextSize = 24,
        TextColor3 = THEME.Text, TextTransparency = 1, ZIndex = 3, Parent = L.plate,
    })
    L.markScale = new("UIScale", { Scale = 1.35, Parent = L.mark })

    ---------------------------------------------------------------- logotype
    -- The wordmark is revealed by growing its clipping frame, not by fading or
    -- by one label per character: one tween, two instances, no reflow.
    L.BRAND = CONFIG.Brand:upper()
    L.WRAP_W, L.SUB_W = 324, 322
    L.wrap = new("Frame", {
        Position = UDim2.fromOffset(96, 14), Size = UDim2.new(0, 0, 0, 36),
        BackgroundTransparency = 1, ClipsDescendants = true, Parent = L.card,
    }, {
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    new("TextLabel", {
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
        Text = L.BRAND:sub(1, 5), TextSize = 30, TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = L.wrap,
    })
    L.w2 = new("TextLabel", {
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
        Text = L.BRAND:sub(6), TextSize = 30, TextColor3 = L.WHITE,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = L.wrap,
    })
    -- A UIGradient does not cascade to children, so one shine cannot physically
    -- span two labels; driving both in phase would read as two words strobing
    -- rather than one highlight travelling.  The accent half carries the glint,
    -- the white half stays solid, and the split still reads as one logotype.
    L.shineGrad = TH.grad3(L.w2, "Accent", "AccentGlow", "Accent2", 0)

    L.subwrap = new("Frame", {
        Position = UDim2.fromOffset(98, 56), Size = UDim2.new(0, 0, 0, 14),
        BackgroundTransparency = 1, ClipsDescendants = true, Parent = L.card,
    })
    new("TextLabel", {
        Size = UDim2.fromOffset(L.SUB_W, 14), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, TextSize = 10, TextColor3 = THEME.Dim,
        -- GUI_MOUNT is final by the time this block runs (both ScreenGuis are
        -- mounted above), so the boot screen states where it actually landed.
        Text = "V" .. CONFIG.Version .. " · " .. CONFIG.Status .. " · " .. GUI_MOUNT:upper(),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = L.subwrap,
    })

    -------------------------------------------------------------- instrument
    L.cap = new("TextLabel", {
        Position = UDim2.fromOffset(0, 116), Size = UDim2.fromOffset(96, 10),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "SYSTEM ARM",
        TextSize = 9, TextColor3 = THEME.Dim, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = L.card,
    })
    L.capRule = new("Frame", {
        Position = UDim2.fromOffset(100, 121), Size = UDim2.fromOffset(160, 1),
        BackgroundColor3 = TH.get("Rail"), BackgroundTransparency = 1,
        BorderSizePixel = 0, Parent = L.card,
    })

    -- "%03d" so the digit count never changes and the readout never reflows.
    L.pctLbl = TH.bind(new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 98),
        Size = UDim2.fromOffset(150, 38), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = "000", TextSize = 30,
        TextColor3 = THEME.Accent, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = L.card,
    }), "TextColor3", "Accent")

    L.scaleLbl = {}
    for i, d in ipairs({
        { "0",   0,   0,   Enum.TextXAlignment.Left },
        { "50",  0.5, 0.5, Enum.TextXAlignment.Center },
        { "100", 1,   1,   Enum.TextXAlignment.Right },
    }) do
        L.scaleLbl[i] = new("TextLabel", {
            AnchorPoint = Vector2.new(d[3], 0), Position = UDim2.new(d[2], 0, 0, 142),
            Size = UDim2.fromOffset(34, 10), BackgroundTransparency = 1,
            Font = Enum.Font.RobotoMono, Text = d[1], TextSize = 9,
            TextColor3 = THEME.Dim, TextTransparency = 1,
            TextXAlignment = d[4], Parent = L.card,
        })
    end

    L.ticks = {}
    for i = 0, 4 do
        L.ticks[i + 1] = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(i / 4, 0, 0, 155),
            Size = UDim2.fromOffset(1, 5), BackgroundColor3 = TH.get("Rail"),
            BackgroundTransparency = 1, BorderSizePixel = 0, Parent = L.card,
        })
    end

    L.track = new("Frame", {
        Position = UDim2.fromOffset(0, 164), Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = THEME.Track, BackgroundTransparency = 1,
        BorderSizePixel = 0, Parent = L.card,
    })
    TH.corner(L.track, "tick")
    L.trackStroke = TH.stroke(L.track, "StrokeSoft", 1, 1)
    L.fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = L.WHITE,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = L.track,
    })
    TH.corner(L.fill, "tick")
    TH.grad(L.fill, "Accent", "Accent2", 0)
    -- Anchored to the L.fill's right edge, so the needle rides every bar tween for
    -- free: no second tween, no per-frame maths.
    L.head = TH.bind(new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(2, 9), BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 3, Parent = L.fill,
    }), "BackgroundColor3", "AccentGlow")

    L.led = TH.bind(new("Frame", {
        Position = UDim2.fromOffset(0, 183), Size = UDim2.fromOffset(4, 4),
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = L.card,
    }), "BackgroundColor3", "Accent")
    TH.corner(L.led, "tick")

    L.MASK_OPEN, L.MASK_CLOSED = UDim2.new(1, -180, 0, 14), UDim2.new(0, 0, 0, 14)
    L.statusMask = new("Frame", {
        Position = UDim2.fromOffset(12, 178), Size = L.MASK_OPEN,
        BackgroundTransparency = 1, ClipsDescendants = true, Parent = L.card,
    })
    L.status = new("TextLabel", {
        Size = UDim2.new(0, 320, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = "", TextSize = 10,
        TextColor3 = THEME.Sub, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = L.statusMask,
    })
    L.elapsed = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 178),
        Size = UDim2.fromOffset(96, 14), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = "T+0.00s", TextSize = 9,
        TextColor3 = THEME.Dim, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = L.card,
    })

    ------------------------------------------------------------------ state
    L.shineConn, L.t0 = nil, 0
    L.pctTarget, L.pctShown, L.pctText = 0, 0, "000"
    L.lastClock = 0

    function Loading.Start()
        L.t0 = tick()
        -- FX.step early-returns unless FX.on; the window owns that flag from its
        -- Visible signal, so the loader claims it for the duration of boot and
        -- releases it in Finish only if the window has not already taken over.
        FX.on, TH.uiOn = true, true

        -- Every L.beat carries a real delay.  The old loader fired ten tweens at
        -- t=0 with only different durations, so everything arrived at once -
        -- that is the whole difference between "a screen appeared" and "a
        -- sequence played".
        L.beat(L.root,  0.25, { BackgroundTransparency = 0 },    FX.E.glide, 0.00)
        L.beat(L.weave, 0.70, { BackgroundTransparency = 0.92 }, FX.E.soft,  0.03)
        L.beat(L.bloom, 0.70, { ImageTransparency = 0.94 },      FX.E.soft,  0.03)

        -- Both hairlines draw from the centre perfectly overlapped, then part:
        -- one line becomes two, and the logotype wipes into the gap.
        for i = 1, 2 do
            L.beat(L.rule[i], 0.50, { Size = UDim2.new(1, 0, 0, 1) }, FX.E.drop, 0.06)
            L.beat(L.rule[i], 0.40, {
                Position = UDim2.new(0.5, 0, 0.5,
                    L.RULE_Y + ((i == 1) and -L.RULE_GAP or L.RULE_GAP)),
            }, FX.E.drop, 0.14)
        end

        L.beat(L.cardScale, 0.55, { Scale = 1 }, FX.E.drop, 0.12)

        L.beat(L.ringStroke, 0.50, { Transparency = 0.20 }, FX.E.glide, 0.16)
        FX.add(L.ringGrad, "spin", 150)

        -- The one Back in this region: the L.plate lands with a machined snap.
        -- Only Rotation gets the overshoot - a Back curve on a transparency
        -- drives it past 0 on the way in, which reads as a flicker.
        L.beat(L.plate,       0.40, { Rotation = 0 },                FX.E.pop,   0.22)
        L.beat(L.plate,       0.40, { BackgroundTransparency = 0 },  FX.E.glide, 0.22)
        L.beat(L.plateStroke, 0.40, { Transparency = 0.40 },         FX.E.glide, 0.22)
        L.beat(L.shade,       0.40, { ImageTransparency = 0.60 },    FX.E.glide, 0.22)

        L.beat(L.mark,      0.34, { TextTransparency = 0 }, FX.E.glide, 0.30)
        L.beat(L.markScale, 0.34, { Scale = 1 },            FX.E.glide, 0.30)

        L.beat(L.wrap, 0.42, { Size = UDim2.new(0, L.WRAP_W, 0, 36) }, FX.E.drop, 0.38)
        FX.add(L.shineGrad, "sweep", 0.55)

        L.beat(L.subwrap, 0.40, { Size = UDim2.new(0, L.SUB_W, 0, 14) }, FX.E.drop, 0.52)

        L.beat(L.track,       0.35, { BackgroundTransparency = 0.10 }, FX.E.glide, 0.62)
        L.beat(L.trackStroke, 0.35, { Transparency = 0.60 },           FX.E.glide, 0.62)
        L.beat(L.fill,        0.35, { BackgroundTransparency = 0 },    FX.E.glide, 0.62)
        L.beat(L.cap,         0.35, { TextTransparency = 0 },          FX.E.glide, 0.62)
        L.beat(L.capRule,     0.35, { BackgroundTransparency = 0.72 }, FX.E.glide, 0.62)
        for i = 1, #L.ticks do
            L.beat(L.ticks[i], 0.35, { BackgroundTransparency = 0.55 }, FX.E.glide, 0.62 + i * 0.02)
        end
        for i = 1, #L.scaleLbl do
            L.beat(L.scaleLbl[i], 0.35, { TextTransparency = 0 }, FX.E.glide, 0.62 + i * 0.02)
        end

        L.beat(L.pctLbl, 0.35, { TextTransparency = 0 },       FX.E.glide, 0.68)
        L.beat(L.head,   0.35, { BackgroundTransparency = 0 }, FX.E.glide, 0.68)

        L.beat(L.led,     0.35, { BackgroundTransparency = 0.12 }, FX.E.glide, 0.74)
        L.beat(L.status,  0.35, { TextTransparency = 0 },          FX.E.glide, 0.74)
        L.beat(L.elapsed, 0.35, { TextTransparency = 0 },          FX.E.glide, 0.74)
        -- The LED joins the shared driver only after its reveal has landed,
        -- otherwise the 30 Hz transparency write fights the fade-in tween.
        task.delay(L.rdelay(1.15), function()
            if L.led.Parent then FX.add(L.led, "led", 1, 0.12) end
        end)

        L.shineConn = RunService.RenderStepped:Connect(function(dt)
            -- PUMP OWNERSHIP.  The bottom-of-file RenderStepped driver pumps
            -- both engines too and is bound before BOOT yields, so it and this
            -- connection are live on the same frames for the whole boot.
            -- Pumping unconditionally here meant TH.acc and FX.acc took the same
            -- dt twice, which ran the theme clock, the RGB hue, the arming L.ring,
            -- the wordmark shine and the LED at ~2x wall rate until Finish.
            -- TH.driven is set the instant that driver is bound, so the loader
            -- owns the pump ONLY across the stretch of boot that runs before the
            -- driver exists and stands down the moment it appears: exactly one
            -- pump per frame, always.
            if not TH.driven then
                TH.step(dt)
                FX.step(dt)
            end

            -- Ease the readout toward its target over ~12 frames so the number
            -- counts instead of jumping, and only touch .Text when it changes.
            if L.pctShown ~= L.pctTarget then
                L.pctShown = L.pctShown + (L.pctTarget - L.pctShown) * 0.18
                if math.abs(L.pctTarget - L.pctShown) < 0.4 then L.pctShown = L.pctTarget end
                local s = string.format("%03d", math.floor(L.pctShown + 0.5))
                if s ~= L.pctText then L.pctText = s L.pctLbl.Text = s end
            end

            local now = tick()
            if now - L.lastClock >= 0.1 then
                L.lastClock = now
                L.elapsed.Text = string.format("T+%.2fs", now - L.t0)
            end
        end)
    end

    function Loading.Step(text, pct, hold)
        pct = math.clamp(pct or 0, 0, 1)

        -- The L.status line swaps by wipe, never a crossfade: a mono readout that
        -- dissolves reads as a glitch, one that is wiped reads as a machine
        -- updating its display.  Under reduced motion FX.tw assigns instead of
        -- tweening, so the wipe would leave the line hidden for the length of
        -- the task.delay and read as a flicker - there, swap the text outright.
        if FX.motion then
            FX.tw(L.statusMask, FX.T.hov, { Size = L.MASK_CLOSED }, FX.E.drop)
            task.delay(L.rdelay(FX.T.hov), function()
                if not L.statusMask.Parent then return end
                L.status.Text = text or ""
                FX.tw(L.statusMask, FX.T.hov, { Size = L.MASK_OPEN }, FX.E.drop)
            end)
        else
            L.status.Text = text or ""
        end

        FX.tw(L.fill, 0.40, { Size = UDim2.new(pct, 0, 1, 0) }, FX.E.snap)

        -- One tick stamped per Step, so by the end the bar carries a visible
        -- record of the seven boot stages.  No data is invented: Step already
        -- receives pct, this just stops throwing it away.
        local stamp = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(pct, 0, 0, 169),
            Size = UDim2.fromOffset(1, 5), BackgroundColor3 = TH.get("Rail"),
            BackgroundTransparency = 1, BorderSizePixel = 0, Parent = L.card,
        })
        FX.tw(stamp, 0.30, { BackgroundTransparency = 0.35 }, FX.E.glide)

        L.pctTarget = math.floor(pct * 100)
        task.wait(hold or 0.28)   -- BLOCKING, unchanged: the boot sequence paces on this
    end

    function Loading.Finish()
        Loading.Step("ALL SYSTEMS ARMED", 1, 0.35)

        -- FX.anim is a hard-capped array of 24.  Hand the loader's three slots
        -- back before the instances die, or they stay occupied by destroyed
        -- objects for the rest of the session.
        FX.remove(L.ringGrad)
        FX.remove(L.shineGrad)
        FX.remove(L.led)

        L.pctText = "100"
        L.pctLbl.Text = "100"
        L.pctLbl.TextColor3 = TH.get("AccentGlow")

        -- The L.ring swells, then detonates outward.  Thickness decays across the
        -- whole expansion rather than in a short burst, so the wave thins as it
        -- travels instead of vanishing mid-flight.
        --
        -- The collapse is scheduled rather than delay-tweened on purpose: two
        -- tweens created in the same frame that touch the SAME property cancel
        -- each other, so a delayed Thickness -> 0 would silently kill the swell.
        -- Transparency and Size are different properties, so those are free.
        L.beat(L.ringStroke, 0.12, { Thickness = 5 },    FX.E.snap, 0.00)
        L.beat(L.ringStroke, 0.50, { Transparency = 1 }, FX.E.drop, 0.10)
        L.beat(L.ring, 0.50, { Size = UDim2.fromOffset(560, 560) }, FX.E.drop, 0.10)
        task.delay(L.rdelay(0.12), function()
            if L.ringStroke.Parent then
                FX.tw(L.ringStroke, 0.46, { Thickness = 0 }, FX.E.glide)
            end
        end)

        -- One reversing tween is the whole muzzle L.flash: up in 0.08, back down
        -- in 0.08, no second tween to cancel the first and no closure.  Guarded
        -- on FX.motion because with motion off FX.tw ASSIGNS the property and
        -- never reverses, which would leave a white wash over the dissolve.
        if FX.motion then
            FX.tw(L.flash, 0.08, { BackgroundTransparency = 0.90 }, FX.E.glide, 0, true, 0.06)
        end

        for i = 1, 2 do
            L.beat(L.rule[i], 0.36,
                { Size = UDim2.new(1.8, 0, 0, 1), BackgroundTransparency = 1 },
                FX.E.glide, 0.14)
        end

        -- No Back overshoot on the exit: the L.card has to leave calmly while the
        -- window is arriving, or the two motions fight each other.
        L.beat(L.cardScale, 0.40, { Scale = 1.04 },        FX.E.glide, 0.16)
        L.beat(L.bloom,     0.30, { ImageTransparency = 1 }, FX.E.glide, 0.18)

        if L.isCG then
            L.beat(L.root, 0.34, { GroupTransparency = 1 }, FX.E.glide, 0.20)
        else
            -- CanvasGroup unavailable on this executor.  Fade every leaf by
            -- hand.  ImageLabel is in this list because the design adds four of
            -- them; the class was missing from the old loop, which would leave
            -- the shadow and the L.bloom hanging after the L.card had gone.
            --
            -- `held` is the load-bearing part.  Playing a second tween on an
            -- instance CANCELS the one already running there, so a blanket fade
            -- over every descendant would kill the shockwave (L.ring Size), its
            -- stroke fade and the parting hairlines - the exact three beats this
            -- exit is built around.  Everything Finish drives itself is skipped;
            -- everything else, including `L.weave` and the whole L.card, is faded.
            local held = {
                [L.ring] = true, [L.ringStroke] = true, [L.flash] = true,
                [L.bloom] = true, [L.rule[1]] = true, [L.rule[2]] = true,
            }
            for _, d in ipairs(L.root:GetDescendants()) do
                if not held[d] then
                    if d:IsA("TextLabel") then
                        L.beat(d, 0.30, { TextTransparency = 1 }, FX.E.glide, 0.20)
                    elseif d:IsA("ImageLabel") then
                        L.beat(d, 0.30, { ImageTransparency = 1 }, FX.E.glide, 0.20)
                    elseif d:IsA("Frame") then
                        L.beat(d, 0.30, { BackgroundTransparency = 1 }, FX.E.glide, 0.20)
                    elseif d:IsA("UIStroke") then
                        L.beat(d, 0.30, { Transparency = 1 }, FX.E.glide, 0.20)
                    end
                end
            end
        end
        L.beat(L.root, 0.40, { BackgroundTransparency = 1 }, FX.E.glide, 0.24)

        task.delay(L.rdelay(0.56), function()
            if L.shineConn then L.shineConn:Disconnect() L.shineConn = nil end
            L.root:Destroy()
            -- The window opens 0.15s into this dissolve and takes ownership of
            -- both flags through its Visible signal.  Only release them if it
            -- did not, or the menu's idle driver dies the moment it appears.
            local w = ScreenMain:FindFirstChild("Window")
            if not (w and w.Visible) then FX.on, TH.uiOn = false, false end
        end)
    end
end

--============================================================================
-- DISCORD PROMPT
--============================================================================
-- Shown once, between the loader finishing and the menu opening.  Deliberately
-- blocking: the boot sequence waits on it, so the three screens follow one
-- another instead of stacking up on top of each other.
local function copyInvite()
    if typeof(setclipboard) == "function" then
        local ok = pcall(setclipboard, CONFIG.Discord)
        if ok then
            notify("Invite copied", CONFIG.Discord, "good", 7)
            return true
        end
    end
    -- no clipboard in this executor: put it somewhere they can still get at it
    notify("No clipboard here", CONFIG.Discord, "warn", 14)
    print("[AdminTools] Discord: " .. CONFIG.Discord)
    return false
end

local Promo = {}

function Promo.Show(seconds)
    local life = seconds or 5
    local done = false

    local scrim = new("Frame", {
        Name = "AT_Promo", Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = THEME.Void, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 190, Parent = ScreenMain,
    })
    local card = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(430, 196), BackgroundColor3 = THEME.Panel,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 191, Parent = scrim,
    })
    corner(card, 14)
    -- read the palette once rather than TH.bind: TH.b holds strong references,
    -- and a card that lives five seconds would leave dead entries in the RGB
    -- sweep for the rest of the session
    local accent = TH.get("Accent")
    local edge = stroke(card, accent, 1, 1)
    local scale = new("UIScale", { Scale = 0.94, Parent = card })

    local brand = new("TextLabel", {
        Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(200, 12),
        BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = CONFIG.Brand:upper(), TextSize = 10, TextColor3 = TH.get("Accent2"),
        TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1,
        ZIndex = 192, Parent = card,
    })

    local body = new("TextLabel", {
        Position = UDim2.fromOffset(18, 44), Size = UDim2.fromOffset(394, 48),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        Text = "Join AdminTools discord for more scripts, or to report bugs",
        TextSize = 15, TextColor3 = THEME.Text, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextTransparency = 1,
        ZIndex = 192, Parent = card,
    })

    local link = new("TextButton", {
        Position = UDim2.fromOffset(18, 104), Size = UDim2.fromOffset(394, 40),
        BackgroundColor3 = accent, BackgroundTransparency = 1,
        AutoButtonColor = false, Font = Enum.Font.GothamBold,
        Text = "COPY INVITE LINK", TextSize = 13, TextColor3 = THEME.Text,
        TextTransparency = 1, BorderSizePixel = 0, ZIndex = 192, Parent = card,
    })
    corner(link, 10)

    local url = new("TextLabel", {
        Position = UDim2.fromOffset(18, 150), Size = UDim2.fromOffset(394, 14),
        BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = CONFIG.Discord, TextSize = 10, TextColor3 = THEME.Dim,
        TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1,
        ZIndex = 192, Parent = card,
    })

    local close = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
        Size = UDim2.fromOffset(26, 26), BackgroundColor3 = THEME.Row,
        BackgroundTransparency = 1, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, Text = "X", TextSize = 11,
        TextColor3 = THEME.Sub, TextTransparency = 1,
        BorderSizePixel = 0, ZIndex = 192, Parent = card,
    })
    corner(close, 8)

    -- Drains over `life`.  Driven by a plain clock rather than a tween, so it
    -- still reads correctly with reduced motion on, where FX.tw assigns instead
    -- of animating and the bar would otherwise snap straight to empty.
    local barWell = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
        Size = UDim2.fromOffset(394, 3), BackgroundColor3 = THEME.Track,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 192, Parent = card,
    })
    corner(barWell, 2)
    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = accent,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 193, Parent = barWell,
    })
    corner(bar, 2)

    local function shut()
        if done then return end
        done = true
        FX.tw(scrim, FX.T.out, { BackgroundTransparency = 1 }, FX.E.glide)
        FX.tw(scale, FX.T.out, { Scale = 0.97 }, FX.E.glide)
        for _, d in ipairs(card:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                FX.tw(d, FX.T.hov, { TextTransparency = 1 }, FX.E.glide)
            end
        end
        FX.tw(card, FX.T.out, { BackgroundTransparency = 1 }, FX.E.glide)
        FX.tw(edge, FX.T.out, { Transparency = 1 }, FX.E.glide)
    end

    link.MouseButton1Click:Connect(function()
        copyInvite()
        link.Text = "COPIED"
    end)
    close.MouseButton1Click:Connect(shut)
    for _, b in ipairs({ link, close }) do
        b.MouseEnter:Connect(function()
            FX.tw(b, FX.T.hov, { BackgroundTransparency = b == link and 0.05 or 0.2 }, FX.E.glide)
        end)
        b.MouseLeave:Connect(function()
            FX.tw(b, FX.T.hov, { BackgroundTransparency = b == link and 0.15 or 0.45 }, FX.E.glide)
        end)
    end

    -- in
    FX.tw(scrim, FX.T.base, { BackgroundTransparency = 0.45 }, FX.E.glide)
    FX.tw(card, FX.T.base, { BackgroundTransparency = 0.02 }, FX.E.glide)
    FX.tw(edge, FX.T.base, { Transparency = 0.45 }, FX.E.glide)
    FX.tw(scale, FX.T.base, { Scale = 1 }, FX.E.glide)
    FX.tw(link, FX.T.base, { BackgroundTransparency = 0.15, TextTransparency = 0 }, FX.E.glide)
    FX.tw(close, FX.T.base, { BackgroundTransparency = 0.45, TextTransparency = 0.1 }, FX.E.glide)
    FX.tw(body, FX.T.base, { TextTransparency = 0 }, FX.E.glide)
    FX.tw(url, FX.T.base, { TextTransparency = 0.25 }, FX.E.glide)
    FX.tw(barWell, FX.T.base, { BackgroundTransparency = 0.4 }, FX.E.glide)
    FX.tw(bar, FX.T.base, { BackgroundTransparency = 0.25 }, FX.E.glide)
    FX.tw(brand, FX.T.base, { TextTransparency = 0.15 }, FX.E.glide)

    local t0 = tick()
    while not done and ALIVE do
        local left = 1 - (tick() - t0) / life
        if left <= 0 then break end
        bar.Size = UDim2.new(left, 0, 1, 0)
        task.wait()
    end
    shut()
    task.wait(0.45)                      -- let the fade finish before it goes
    pcall(function() scrim:Destroy() end)
end

--============================================================================
-- MAIN WINDOW
--============================================================================
local Window = {}
-- WIN_W / WIN_H, the sidebar width (168), the header height (56), the tab-strip
-- height and the footer height are ONE coupled edit.  Budget down the sidebar:
--   14 top gap + 304 tab strip = 318,  footer top = 440 - 84 - 14 = 342.
-- Change any one of them without the others and the footer eats the tab strip.
-- MOBILE: Reduced to 380×400 for DPI 360 (fits in 360×800 with space)
local WIN_W, WIN_H = 380, 400

local winRoot
do
    local ok = pcall(function() winRoot = Instance.new("CanvasGroup") end)
    if not ok or not winRoot then winRoot = Instance.new("Frame") end
end
winRoot.Name = "Window"
winRoot.AnchorPoint = Vector2.new(0.5, 0.5)
-- MOBILE: Position window centered both ways
-- Screen is 360×800, window is 380×400 at scale 0.65 = 247×260px effective
-- Centered vertically for best mobile fit
winRoot.Position = UDim2.new(0.5, 0, 0.50, 0)  -- Center vertically for mobile
winRoot.Size = UDim2.fromOffset(WIN_W, WIN_H)
winRoot.BackgroundColor3 = THEME.Bg
-- readability escape hatch: the Appearance "Window opacity" slider drives this
-- between 0.00 and 0.30 for players on bright maps.
winRoot.BackgroundTransparency = 0.06
winRoot.BorderSizePixel = 0
winRoot.Visible = false
-- ClipsDescendants respects UICorner.  That single property retires the header's
-- 14px corner-squaring patch frame (two Panel@0.35 layers compositing to ~0.12,
-- which is the darker stripe visible across the old header) and stops the
-- sidebar's square bottom-left corner poking past the window radius.
winRoot.ClipsDescendants = true
winRoot.Parent = ScreenMain
TH.corner(winRoot, "win")
Window.scale = new("UIScale", { Scale = 0.65, Parent = winRoot })  -- MOBILE: 0.65 (was 0.94)

-- Body wash: a very low contrast graphite ramp so the plate reads as lit rather
-- than flat.  It has to live on its own ZIndex-0 layer and NOT on winRoot: a
-- UIGradient parented to a CanvasGroup multiplies the whole RENDERED GROUP, so
-- it would tint every panel, every label and every accent in the menu with it.
--
-- This one keeps its Carbon fill deliberately: the gradient below sets ONLY
-- Transparency, and an unset UIGradient.Color is white, which multiplies to the
-- identity.  A transparency-only ramp never needs the white-fill treatment.
new("Frame", {
    Name = "BodyWash", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Carbon,
    BorderSizePixel = 0, ZIndex = 0, Parent = winRoot,
}, {
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.62),
            NumberSequenceKeypoint.new(0.55, 0.92),
            NumberSequenceKeypoint.new(1, 0.74),
        }),
    }),
})

-- THE RIM OF LIGHT.  A single accent band travels around the whole window edge
-- forever for exactly one Rotation write per 30Hz tick from the shared driver.
-- It is what makes the window read as lit instead of pasted on.  If frame time
-- ever has to be reclaimed, cut the badge spin and the header sweep first and
-- cut this LAST.
do
    -- A UIGradient MULTIPLIES UIStroke.Color exactly as it multiplies
    -- BackgroundColor3.  The stroke is therefore WHITE and the gradient supplies
    -- the colour.  TH.stroke(winRoot, "Stroke", ...) would have painted it
    -- Stroke (68,73,86) and the accent ramp would then square that down to about
    -- (40,27,86): a dull dark indigo hairline instead of a band of light.
    -- Unregistered on purpose - there is no palette key a white carrier should
    -- follow, and the gradient is already in TH.g, so accent changes still reach
    -- the rim.
    local ws = stroke(winRoot, Color3.new(1, 1, 1), 1.4, 0.30)
    ws.LineJoinMode = Enum.LineJoinMode.Miter
    Window.rimStroke = ws
    Window.rimGrad = TH.grad3(ws, "Accent", "Accent2", "Accent3", 0)
    FX.add(Window.rimGrad, "rim", 20)
end

-- ------------------------------------------------------------ DEPTH (SIBLINGS)
-- The old shadow was a CHILD of winRoot and rendered nothing useful: a
-- CanvasGroup clips a child's bleed away entirely, and under
-- ZIndexBehavior.Sibling a ZIndex-0 CHILD still paints in front of its own
-- parent's BACKGROUND.  All it ever produced was a black wash ON the window.
-- Both layers are now siblings under ScreenMain, kept in step by Window.syncFx.
Window.shadowRest, Window.glowRest, Window.glowOn = 0.42, 0.88, true

Window.shadow = TH.bind(new("ImageLabel", {
    Name = "WinShadow", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 8), Size = UDim2.fromOffset(WIN_W + 96, WIN_H + 96),
    BackgroundTransparency = 1, Image = FX.IMG, ImageTransparency = 1,
    ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
    Visible = false, ZIndex = 0, Parent = ScreenMain,
}), "ImageColor3", "Void")

Window.glow = TH.bind(new("ImageLabel", {
    Name = "WinGlow", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(WIN_W + 150, WIN_H + 150),
    BackgroundTransparency = 1, Image = FX.IMG, ImageTransparency = 1,
    ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
    Visible = false, ZIndex = 0, Parent = ScreenMain,
}), "ImageColor3", "Accent")

-- One handler covers open, close AND drag, so neither Window.SetOpen nor the
-- drag block below needs to know the depth layers exist.  It is also where the
-- two engines learn whether the window is on screen: pushed in, never pulled,
-- because TH/FX are populated far above winRoot and cannot reference it.
function Window.syncFx()
    local p, s, v = winRoot.Position, winRoot.Size, winRoot.Visible
    Window.shadow.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + 8)
    Window.glow.Position   = p
    Window.shadow.Size     = UDim2.new(s.X.Scale, s.X.Offset + 96,  s.Y.Scale, s.Y.Offset + 96)
    Window.glow.Size       = UDim2.new(s.X.Scale, s.X.Offset + 150, s.Y.Scale, s.Y.Offset + 150)
    Window.shadow.Visible  = v
    Window.glow.Visible    = v and Window.glowOn
    TH.uiOn, FX.on = v, v
end
bind(winRoot:GetPropertyChangedSignal("Position"), Window.syncFx)
bind(winRoot:GetPropertyChangedSignal("Size"),     Window.syncFx)
bind(winRoot:GetPropertyChangedSignal("Visible"),  Window.syncFx)

-- the depth layers live OUTSIDE the CanvasGroup, so GroupTransparency does not
-- reach them and setWinAlpha has to fade them by hand.
local function setWinAlpha(a)
    if winRoot:IsA("CanvasGroup") then winRoot.GroupTransparency = a end
    Window.shadow.ImageTransparency = Window.shadowRest + a * (1 - Window.shadowRest)
    Window.glow.ImageTransparency   = Window.glowRest   + a * (1 - Window.glowRest)
end
setWinAlpha(1)
Window.syncFx()

-- ------------------------------------------------------------------- HEADER
-- 56px, SQUARE, and with no patch frame: winRoot.ClipsDescendants + its UICorner
-- round the top corners, so the header only has to be a flat plate.
local header = new("Frame", {
    Name = "Header",
    -- WHITE, not Panel.  The TH.grad below MULTIPLIES BackgroundColor3, so a
    -- Panel fill under a Panel -> Carbon ramp squares to about RGB(2,3,4) -
    -- darker than Bg, which is how the header lost its plate.  White carries,
    -- the gradient colours.  Same rule as ov_loading.lua and ov_world.lua.
    Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.30,
    BorderSizePixel = 0, Active = true, Parent = winRoot,  -- MOBILE: Ensure header is active for input
})
-- TH.grad, not TH.bind: a grey gradient lands in TH.g (repainted only when its
-- own keys change) and never in TH.ag, so it costs the RGB driver nothing.
-- Per-property TH.bind is reserved for accent-family keys.  It is also why the
-- white fill is safe for theming: the gradient is registered, so a palette
-- change still reaches this surface.
TH.grad(header, "Panel", "Carbon", 90)
new("Frame", {
    Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 2, Parent = header,
})

-- THE RAIL.  A resting hairline the full width of the header, with a brighter
-- accent sweep riding on top of it.  This is the single most identity-carrying
-- pixel row in the tool, which is why it wipes in on window open rather than
-- just appearing.  Window.rail is the handle the Appearance "Telemetry rail"
-- toggle hides.
new("Frame", {
    Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = THEME.StrokeSoft, BackgroundTransparency = 0.50,
    BorderSizePixel = 0, ZIndex = 2, Parent = header,
})
local headLine = new("Frame", {
    Name = "Rail",
    Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
    -- WHITE carrier, and deliberately NOT TH.bind'd to Accent.  The sweep
    -- gradient below multiplies this fill: Accent under an Accent ramp is Accent
    -- squared, which reads oversaturated and loses the AccentGlow highlight in
    -- the middle stop.  Binding it back would also undo the fix on every repaint,
    -- because TH.paint writes the key colour straight into BackgroundColor3.
    -- Accent tracking is not lost - TH.grad3 registers the gradient itself.
    BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3, Parent = header,
})
-- Window.rail is what the open animation wipes in; REF.headRail is the name the
-- Appearance tab's "Telemetry rail" toggle looks for.  Same instance, two
-- handles, so neither region has to learn about the other.
Window.rail, REF.headRail = headLine, headLine
-- kept on REF purely so the legacy shimmer lines in the live loop, if they are
-- still present, write to a live gradient instead of throwing on nil.
REF.headLineGrad = TH.grad3(headLine, "Accent", "AccentGlow", "Accent2", 0,
    NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
    }))
FX.add(REF.headLineGrad, "sweep", 0.22)

-- ---------------------------------------------------------------- LEFT CLUSTER
-- The badge halo is a sibling in the header, NOT a child of the badge: under
-- ZIndexBehavior.Sibling a ZIndex-0 child would paint in front of the badge's
-- own fill and wash it out.  A glow must always sit BEHIND its surface.
FX.add(TH.bind(new("ImageLabel", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(33, 28),
    Size = UDim2.fromOffset(54, 54), BackgroundTransparency = 1, Image = FX.IMG,
    ImageTransparency = 0.82, ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
    ZIndex = 1, Parent = header,
}), "ImageColor3", "AccentGlow"), "glow", 1, 0.82)

local hMark = new("Frame", {
    Position = UDim2.fromOffset(18, 13), Size = UDim2.fromOffset(30, 30),
    -- WHITE carrier again: Carbon under the accent ramp multiplied out to about
    -- RGB(11,8,24), i.e. a black square where the badge should be the single
    -- brightest chip in the header.
    BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = header,
})
TH.corner(hMark, "chip")
REF.hMarkGrad = TH.grad3(hMark, "Accent", "Accent3", "Accent2", 45)
FX.add(REF.hMarkGrad, "spin", 28)
TH.stroke(hMark, "Accent", 1, 0.35)
-- OnAccent, never a hardcoded white: the user owns the accent and a pale pick
-- would otherwise produce an invisible glyph.
TH.bind(new("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "A",
    TextSize = 15, TextColor3 = THEME.OnAccent, ZIndex = 3, Parent = hMark,
}), "TextColor3", "OnAccent")

do  -- status LED, breathing off the shared clock rather than its own tween
    local led = new("Frame", {
        Position = UDim2.fromOffset(43, 10), Size = UDim2.fromOffset(5, 5),
        BackgroundColor3 = THEME.Good, BorderSizePixel = 0, ZIndex = 4, Parent = header,
    })
    TH.corner(led, "tick")
    FX.add(led, "led", 1, 0.12)
end

new("TextLabel", {
    Position = UDim2.fromOffset(58, 11), Size = UDim2.fromOffset(220, 17), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBlack, Text = string.upper(CONFIG.Brand), TextSize = 14, TextColor3 = THEME.Text,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Parent = header,
})
new("TextLabel", {
    Position = UDim2.fromOffset(58, 30), Size = UDim2.fromOffset(240, 12), BackgroundTransparency = 1,
    Font = Enum.Font.RobotoMono, Text = "V" .. CONFIG.Version .. "  ·  " .. CONFIG.Status, TextSize = 9,
    TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Parent = header,
})

-- --------------------------------------------------------------- HERO READOUT
-- REF.fSpeed is REPOINTED from the footer to here and promoted to a tachometer.
-- The 10Hz loop writes ONLY .Text into it, so it must stay a TextLabel - the
-- group wrapper below is a SEPARATE handle (REF.hSpeedBox) purely so the
-- Appearance "Header speed readout" toggle can hide caption, value and rule
-- together without ever touching REF.fSpeed's class.
--
-- The -104 is sized for BOTH header buttons, not one.  headerButton anchors at
-- AnchorPoint (1, 0.5) with a 28px box, so at WIN_W = 726 the close button spans
-- x 684..712 and the Appearance shortcut at -52 spans 646..674.  The hero's
-- right edge is 726 - 104 = 622, leaving a 24px gutter before the shortcut.
-- Move either button offset and this number moves with it.
Window.hero = new("Frame", {
    Name = "Hero", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -104, 0.5, 0),
    Size = UDim2.fromOffset(170, 46), BackgroundTransparency = 1, ZIndex = 2, Parent = header,
})
new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
    Text = "GROUND SPEED", TextSize = 8, TextColor3 = THEME.Dim,
    TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2, Parent = Window.hero,
})
REF.fSpeed = TH.bind(new("TextLabel", {
    Position = UDim2.fromOffset(0, 11), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
    Font = Enum.Font.RobotoMono, Text = "0 MPH", TextSize = 22, TextColor3 = THEME.Accent2,
    TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2, Parent = Window.hero,
}), "TextColor3", "Accent2")
new("Frame", {
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 40), Size = UDim2.fromOffset(40, 1),
    BackgroundColor3 = THEME.Rail, BackgroundTransparency = 0.50, BorderSizePixel = 0,
    ZIndex = 2, Parent = Window.hero,
})
REF.hSpeedBox = Window.hero

-- Menu-key hint.  A static chip, not a control: the keybind itself still lives
-- in the Settings tab.  REF.hKeyChip is refreshed from the existing 0.1s block
-- so it cannot go stale after a rebind.
new("TextLabel", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -344, 0.5, 0),
    Size = UDim2.fromOffset(44, 12), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
    Text = "MENU", TextSize = 9, TextColor3 = THEME.Dim,
    TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2, Parent = header,
})
do
    local chip = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -288, 0.5, 0),
        Size = UDim2.fromOffset(52, 20), BackgroundColor3 = THEME.Track,
        BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 2, Parent = header,
    })
    TH.corner(chip, "well")
    stroke(chip, THEME.StrokeSoft, 1, 0.55)
    REF.hKeyChip = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = keyName(S.Keys.Menu), TextSize = 10, TextColor3 = THEME.Sub, ZIndex = 3, Parent = chip,
    })
end

-- Signature unchanged (offsetX, glyph, col, cb), so the one existing call site
-- - headerButton(-14, "X", THEME.Bad, ...) - keeps working untouched.
local function headerButton(offsetX, glyph, col, cb)
    local b = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, offsetX, 0.5, 0), Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = THEME.Row, BackgroundTransparency = 0.25, Text = glyph, Font = Enum.Font.GothamBold,
        TextSize = 13, TextColor3 = THEME.Sub, AutoButtonColor = false, ClipsDescendants = true,
        ZIndex = 2, Parent = header,
    })
    TH.corner(b, "chip")
    local bs = stroke(b, THEME.StrokeSoft, 1, 0.50)
    local sc = new("UIScale", { Parent = b })
    -- 2px rail growing along the bottom edge: the same "lit underline" grammar
    -- as the header rail and the text-input focus rule, so hover reads as the
    -- control arming rather than merely highlighting.
    local rail = new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(0, 0, 0, 2), BackgroundColor3 = col, BorderSizePixel = 0,
        ZIndex = 3, Parent = b,
    })
    bind(b.MouseEnter, function()
        FX.tw(b,    FX.T.hov, { BackgroundColor3 = col, BackgroundTransparency = 0.20, TextColor3 = Color3.new(1, 1, 1) })
        FX.tw(bs,   FX.T.hov, { Color = col, Transparency = 0.25 })
        FX.tw(rail, FX.T.hov, { Size = UDim2.new(1, 0, 0, 2) })
    end)
    bind(b.MouseLeave, function()
        FX.tw(b,    FX.T.out, { BackgroundColor3 = THEME.Row, BackgroundTransparency = 0.25, TextColor3 = THEME.Sub })
        FX.tw(bs,   FX.T.out, { Color = THEME.StrokeSoft, Transparency = 0.50 })
        FX.tw(rail, FX.T.out, { Size = UDim2.new(0, 0, 0, 2) })
        FX.tw(sc,   FX.T.out, { Scale = 1 })
    end)
    bind(b.MouseButton1Down, function() FX.tw(sc, FX.T.tap, { Scale = 0.92 }) end)
    bind(b.MouseButton1Up,   function() FX.tw(sc, FX.T.out, { Scale = 1 }) end)
    bind(b.MouseButton1Click, cb)
    return b
end

-- ------------------------------------------------------------------ SIDEBAR
local sidebar = new("Frame", {
    Name = "Sidebar",
    -- WHITE carrier under the Panel -> Carbon ramp, matching the header plate.
    -- Panel x Panel was near-black and took the whole left column with it.
    Position = UDim2.fromOffset(0, 56), Size = UDim2.new(0, 168, 1, -56),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = winRoot,
})
TH.grad(sidebar, "Panel", "Carbon", 90)
-- the divider fades at both ends instead of butting into the rounded corners
-- (Transparency-only gradient below, so its Panel-family fill needs no change)
new("Frame", {
    Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = THEME.StrokeSoft,
    BackgroundTransparency = 0.50, BorderSizePixel = 0, Parent = sidebar,
}, {
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.45),
            NumberSequenceKeypoint.new(0.85, 0.45), NumberSequenceKeypoint.new(1, 1),
        }),
    }),
})

-- A ScrollingFrame, not a Frame with a hard 310px cap.  Nine tabs already need
-- 302px before group captions; anything added later (the planned "Fun" tab)
-- now scrolls gracefully instead of silently overflowing off the bottom.
-- y = 48, not 14: the Simple-mode pill occupies the first 30px of the sidebar
-- and is NOT part of this strip.  Inside it, the pill would have cost the tab
-- list 34 of the 304px it had - and eight tabs plus two captions already need
-- 308 - so the Theme tab would have gone below the fold, and the one control
-- that gets a lost user back to the full menu would scroll away with it.
local tabHolder = new("ScrollingFrame", {
    Name = "Tabs",
    -- Height is 290 (440 sidebar - 150), the most that still clears the footer
    -- card at y=342.  It is not slack: the slab's band test hides the marker
    -- whenever a row's bottom edge falls outside the strip, and at 270 the
    -- Settings row missed by 2px, so that tab lit up with no slab at all.
    Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 1, -150),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    -- A 2px bar, not 0.  Nine tabs plus two group captions overrun the strip by
    -- ~38px, and with a zero-width bar there was nothing on screen to say the
    -- list scrolls at all - the Appearance tab sat below the fold, invisible.
    -- VerticalScrollBarInset defaults to None, so the bar overlays and steals no
    -- row width.
    ScrollBarThickness = 2, ScrollBarImageTransparency = 0.45,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Parent = sidebar,
}, {
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})
TH.bind(tabHolder, "ScrollBarImageColor3", "Accent")

-- Group captions, placed by LayoutOrder so they land correctly whatever order
-- the tabs happen to be built in.  85 sits above every shipped tab order and
-- below the Appearance tab's 90, so it works with tab orders 1..8 as well as
-- with a rescaled 10..90.  EXTRAS stays hidden until a tab actually claims it.
do
    local function groupCap(text, order)
        local f = new("Frame", {
            Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
            LayoutOrder = order, Parent = tabHolder,
        })
        new("TextLabel", {
            Size = UDim2.fromOffset(58, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
            Text = text, TextSize = 9, TextColor3 = THEME.Dim,
            TextXAlignment = Enum.TextXAlignment.Left, Parent = f,
        })
        new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 1),
            Size = UDim2.new(1, -60, 0, 1), BackgroundColor3 = THEME.StrokeSoft,
            BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = f,
        })
        return f
    end
    -- Captured so Simple mode can drop both.  Three tabs need no grouping, and
    -- an EXTRAS caption sitting alone over Settings reads as a mistake.
    Window.driveCap  = groupCap("DRIVING", 0)
    Window.extrasCap = groupCap("EXTRAS", 85)
end

local content = new("Frame", {
    Name = "Content",
    Position = UDim2.fromOffset(168, 56), Size = UDim2.new(1, -168, 1, -56), BackgroundTransparency = 1,
    ClipsDescendants = true, Parent = winRoot,
}, {
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 10),
        -- 50, not 16: the search bar occupies the first 34px and reaches back
        -- over this padding with a negative offset, the same way UI.Section's
        -- lit top edge does.  Pushing the pages down here rather than resizing
        -- them keeps UI.Page and the three tab-select tweens untouched.
        PaddingTop = UDim.new(0, 50), PaddingBottom = UDim.new(0, 10),
    }),
})

-- Ambient wash: two very faint blooms at ZIndex 0 behind every page.  `content`
-- is fully transparent, so ZIndex 0 really is behind here.  Capped at 0.90 /
-- 0.93 even at full glow strength so no body text ever sits over one.
Window.wash = {}
do
    local a = TH.bind(new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.26, 0, 0.20, 0),
        Size = UDim2.new(0.9, 0, 0.8, 0), BackgroundTransparency = 1, Image = FX.IMG,
        ImageTransparency = 0.90, ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
        ZIndex = 0, Parent = content,
    }), "ImageColor3", "Accent")
    local b = TH.bind(new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.80, 0, 0.84, 0),
        Size = UDim2.new(0.9, 0, 0.8, 0), BackgroundTransparency = 1, Image = FX.IMG,
        ImageTransparency = 0.93, ScaleType = Enum.ScaleType.Slice, SliceCenter = FX.SLICE,
        ZIndex = 0, Parent = content,
    }), "ImageColor3", "Accent2")
    FX.add(a, "glow", 1, 0.90)
    FX.add(b, "glow", 1, 0.93)
    Window.wash[1], Window.wash[2] = a, b
end
-- REF.ambient is the array the Appearance "Ambient wash" toggle walks.
REF.ambient = Window.wash

-- Four corner brackets.  Eight static frames, zero animation, and they do more
-- for the instrument-rack read than any other piece of chrome here.  AnchorPoint
-- flips the L for free, so one loop covers all four corners.
-- The offsets pull each bracket back OUT through content's own UIPadding so it
-- frames the page instead of being buried under the first Section, which starts
-- at exactly the padded origin.
Window.brackets = {}
do
    local corners = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
    for i = 1, 4 do
        local c = corners[i]
        local ox = (c[1] == 0) and -14 or 6
        -- -4 on top, not -12: that reach-back is now the search bar's space
        local oy = (c[2] == 0) and -4 or 6
        for j = 1, 2 do
            local arm = new("Frame", {
                AnchorPoint = Vector2.new(c[1], c[2]), Position = UDim2.new(c[1], ox, c[2], oy),
                Size = (j == 1) and UDim2.fromOffset(12, 1) or UDim2.fromOffset(1, 12),
                BackgroundColor3 = THEME.Rail, BackgroundTransparency = 0.72,
                BorderSizePixel = 0, ZIndex = 0, Parent = content,
            })
            Window.brackets[#Window.brackets + 1] = arm
        end
    end
end
-- REF.brackets is the array the Appearance "Corner brackets" toggle walks.
REF.brackets = Window.brackets

-- ONE shared selection slab replaces the old per-tab indicator loop, taking a
-- tab switch from 4 tweens PER TAB (32 with eight tabs) to 6 total.  It has to
-- be a SIBLING of tabHolder: a UIListLayout authoritatively rewrites Position
-- on every child it owns, so a slab inside the strip could never be moved.
--
-- ZIndex 0 IS LOAD-BEARING.  ZIndexBehavior is Sibling and the slab is created
-- AFTER tabHolder, so at the default ZIndex of 1 the tie would break on child
-- order and this near-opaque plate would paint OVER the number plate, glyph and
-- label of the very row it is meant to be highlighting.  At 0 it sorts behind
-- the strip while still painting in front of the sidebar's own background.
Window.slab = TH.bind(new("Frame", {
    Name = "Slab", Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 0, 30),
    BackgroundColor3 = THEME.AccentWash, BackgroundTransparency = 0.10,
    BorderSizePixel = 0, Visible = false, ZIndex = 0, Parent = sidebar,
}), "BackgroundColor3", "AccentWash")
TH.corner(Window.slab, "row")
TH.stroke(Window.slab, "Accent", 1, 0.45)
do
    local r = TH.bind(new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 3, 1, -8), BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0, Parent = Window.slab,
    }), "BackgroundColor3", "Accent")
    TH.corner(r, "tick")
end

-- Window.slabY is stored in CANVAS space, so the slab can follow the strip when
-- it scrolls without another AbsolutePosition read.
--
-- The band test is the price of the slab being a SIBLING of the strip: it is
-- therefore not clipped by the strip either, and nine tabs plus two group
-- captions overrun the 304px strip by ~38px.  Without it, scrolling the tab
-- list far enough sends the slab floating up over the header seam or down onto
-- the footer card.  Out of band it hides - which is right, because the row it
-- marks has scrolled out of sight too.
-- A raw Position write does NOT stop a TweenService tween that is still
-- playing, so every raw write has to cancel the outstanding one first.  Without
-- this, anything that reflows the strip within 0.22s of a tab switch - Simple
-- mode hiding five rows and a caption, for instance - gets overwritten by a
-- tween whose goal was baked from the OLD layout, and the slab settles 20px
-- low, straddling two rows and appearing to mark the wrong one.
function Window.slabStop()
    if Window.slabTween then
        pcall(function() Window.slabTween:Cancel() end)
        Window.slabTween = nil
    end
end

function Window.placeSlab()
    if not Window.slabY then return end
    local y = Window.slabY - tabHolder.CanvasPosition.Y
    Window.slabStop()
    Window.slab.Position = UDim2.fromOffset(14, tabHolder.Position.Y.Offset + y)
    Window.slab.Visible  = (y >= -2) and (y + 30 <= tabHolder.AbsoluteSize.Y + 2)
end

function Window.slabTo(tab, animate)
    local btn = tab and tab.btn
    if not btn then return end
    if tabHolder.AbsoluteSize.Y <= 0 then return end   -- layout has not run yet
    Window.slabY = btn.AbsolutePosition.Y - tabHolder.AbsolutePosition.Y + tabHolder.CanvasPosition.Y
    local y = Window.slabY - tabHolder.CanvasPosition.Y
    Window.slab.Visible = (y >= -2) and (y + 30 <= tabHolder.AbsoluteSize.Y + 2)
    Window.slabStop()
    if animate and Window.slab.Visible then
        Window.slabTween = FX.tw(Window.slab, 0.22,
            { Position = UDim2.fromOffset(14, tabHolder.Position.Y.Offset + y) }, FX.E.snap)
    else
        Window.slab.Position = UDim2.fromOffset(14, tabHolder.Position.Y.Offset + y)
    end
end
bind(tabHolder:GetPropertyChangedSignal("CanvasPosition"), Window.placeSlab)
-- The very first Select() runs during the main chunk while the window is still
-- hidden, so AbsolutePosition is not meaningful yet and slabTo bails.  Re-sync
-- shortly after the window is shown, once a layout pass has actually run - the
-- 0.06s lands well inside the 0.42s open animation, so the snap is never seen.
bind(winRoot:GetPropertyChangedSignal("Visible"), function()
    if winRoot.Visible and Window.activeTab then
        task.delay(0.06, function() Window.slabTo(Window.activeTab, false) end)
    end
end)

local tabs, activeTab = {}, nil
local function addTab(name, glyph, order)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = THEME.RowHover, BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false, LayoutOrder = order, Parent = tabHolder,
    })
    TH.corner(btn, "row")
    -- .ind stays in the returned table for compatibility but is now an inert
    -- stub; the shared slab does its job.
    local ind = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = btn,
    })
    -- Number plate.  Hand-composed 16px icons were rejected as unidentifiable at
    -- this size, and a car number is exactly the right idiom for this tool.
    local plate = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
        Size = UDim2.fromOffset(22, 18), BackgroundColor3 = THEME.Track,
        BorderSizePixel = 0, Parent = btn,
    })
    TH.corner(plate, "chip")
    local ps = stroke(plate, THEME.StrokeSoft, 1, 0.60)
    local g = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
        Text = glyph, TextSize = 11, TextColor3 = THEME.Dim, Parent = plate,
    })
    local l = new("TextLabel", {
        Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -62, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = name, TextSize = 12, TextColor3 = THEME.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
    })
    local mark = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(1, 10), BackgroundColor3 = THEME.Rail,
        BackgroundTransparency = 0.70, BorderSizePixel = 0, Parent = btn,
    })
    local page = UI.Page(content)
    local tab = { name = name, btn = btn, page = page, ind = ind, glyph = g, label = l }
    tab.plate, tab.pstroke, tab.mark = plate, ps, mark
    tabs[#tabs + 1] = tab

    -- the EXTRAS caption only earns its place once something is under it
    -- Through setVis, not a raw .Visible write: UI.vis owns this frame now that
    -- Simple mode hides it, and a raw write would force it on while the mask
    -- still recorded it hidden.
    if order and order >= 85 and Window.extrasCap then
        UI.setVis(Window.extrasCap, UI.HIDE_COND, false)
    end

    local function select()
        if activeTab == tab then return end
        local prev = activeTab
        activeTab = tab
        Window.activeTab = tab

        if prev then
            FX.tw(prev.label,   0.20, { TextColor3 = THEME.Sub },  FX.E.glide)
            FX.tw(prev.glyph,   0.20, { TextColor3 = THEME.Dim },  FX.E.glide)
            FX.tw(prev.plate,   0.20, { BackgroundColor3 = THEME.Track }, FX.E.glide)
            FX.tw(prev.pstroke, 0.20, { Color = THEME.StrokeSoft, Transparency = 0.60 }, FX.E.glide)
            FX.tw(prev.mark,    0.20, { BackgroundTransparency = 0.70 }, FX.E.glide)
            prev.btn.BackgroundTransparency = 1
            local gone = prev.page
            FX.tw(gone, 0.14, { Position = UDim2.fromOffset(-12, 0) }, FX.E.drop)
            task.delay(0.16, function()
                -- the user can click back before the outgoing slide finishes
                if Window.activeTab and Window.activeTab.page ~= gone then gone.Visible = false end
            end)
        end

        Window.slabTo(tab, prev ~= nil)
        FX.tw(l,     0.20, { TextColor3 = THEME.Text },   FX.E.glide)
        FX.tw(g,     0.20, { TextColor3 = THEME.Accent }, FX.E.glide)
        FX.tw(plate, 0.20, { BackgroundColor3 = THEME.AccentWash }, FX.E.glide)
        FX.tw(ps,    0.20, { Color = THEME.Accent, Transparency = 0.30 }, FX.E.glide)
        FX.tw(mark,  0.20, { BackgroundTransparency = 1 }, FX.E.glide)
        btn.BackgroundTransparency = 1

        page.Visible = true
        page.Position = UDim2.fromOffset(16, 0)
        FX.tw(page, 0.30, { Position = UDim2.fromOffset(0, 0) }, FX.E.drop)

        -- Sections fade in on a stagger.  Only BackgroundTransparency is
        -- animated: UI.Page owns a UIListLayout, which rewrites Position on
        -- every child, so a per-section Position tween would silently do
        -- nothing.  The resting value is cached on an attribute the first time
        -- so repeated tab-mashing can never latch a mid-tween value as "rest".
        if FX.motion and FX.stagger then
            local i = 0
            for _, ch in ipairs(page:GetChildren()) do
                if ch:IsA("GuiObject") then
                    i = i + 1
                    if i > 8 then break end
                    local rest = ch:GetAttribute("ATRest")
                    if rest == nil then
                        rest = ch.BackgroundTransparency
                        ch:SetAttribute("ATRest", rest)
                    end
                    ch.BackgroundTransparency = 1
                    FX.tw(ch, 0.26, { BackgroundTransparency = rest }, FX.E.glide,
                        nil, nil, FX.delay(i, 0.030, 8))
                end
            end
        end
    end
    bind(btn.MouseButton1Click, select)
    bind(btn.MouseEnter, function()
        if activeTab == tab then return end
        FX.tw(btn, FX.T.hov, { BackgroundTransparency = 0.72 }, FX.E.snap)
        FX.tw(l,   FX.T.hov, { TextColor3 = THEME.Text }, FX.E.snap)
        FX.tw(g,   FX.T.hov, { TextColor3 = THEME.Sub },  FX.E.snap)
    end)
    bind(btn.MouseLeave, function()
        if activeTab == tab then return end
        FX.tw(btn, FX.T.out, { BackgroundTransparency = 1 }, FX.E.snap)
        FX.tw(l,   FX.T.out, { TextColor3 = THEME.Sub }, FX.E.snap)
        FX.tw(g,   FX.T.out, { TextColor3 = THEME.Dim }, FX.E.snap)
    end)
    tab.Select = select
    return tab
end

-- ------------------------------------------------------------ SIDEBAR FOOTER
-- The old footer was 74px with pad(10,10,8,8) = 58px of inner room trying to
-- hold four 16px rows plus three 3px gaps (73px), so the bottom of the FPS row
-- drew outside its own rounded card.  SPEED is promoted to the header hero, so
-- three 18px rows plus two 5px gaps = 64 now fit a 64px well exactly.
local footer = new("Frame", {
    Name = "Footer",
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -28, 0, 84),
    -- WHITE carrier under the Row -> Carbon ramp below.  A Row fill squared to
    -- about RGB(4,5,7), so the telemetry card read as a hole in the sidebar
    -- rather than a raised well.
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.30,
    ClipsDescendants = true, Parent = sidebar,
})
TH.corner(footer, "card")
TH.grad(footer, "Row", "Carbon", 90)
stroke(footer, THEME.StrokeSoft, 1, 0.55)
-- NOTE: no UIPadding on the card itself - the 1px highlight below has to hug
-- the top border, and UIPadding would push it 10px inward.
new("Frame", {
    Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.94, BorderSizePixel = 0, ZIndex = 2, Parent = footer,
})

-- Live FPS sparkline.  Heights come from REF.fpsRing, pushed by the FPS block
-- that ALREADY runs on a 0.5s cadence, so this measures nothing new: 24 Size
-- writes twice a second.
REF.fpsRing, REF.fpsBars = {}, {}
Window.spark = new("Frame", {
    Name = "Spark", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 6),
    BackgroundTransparency = 1, Parent = footer,
}, {
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})
do
    for i = 1, 24 do
        REF.fpsRing[i] = 0
        REF.fpsBars[i] = new("Frame", {
            Size = UDim2.fromOffset(1, 1), BackgroundColor3 = THEME.Rail,
            BackgroundTransparency = 0.45, BorderSizePixel = 0, LayoutOrder = i, Parent = Window.spark,
        })
    end
    -- newest sample is the only bar that follows the accent
    TH.bind(REF.fpsBars[24], "BackgroundColor3", "Accent")
end
-- REF.fpsSpark is the handle the Appearance "FPS sparkline" toggle hides.
REF.fpsSpark = Window.spark

function Window.pushFps(v)
    local r = REF.fpsRing
    if not r or #r < 1 then return end
    table.remove(r, 1)
    r[#r + 1] = v or 0
    local peak = 1
    for i = 1, #r do if r[i] > peak then peak = r[i] end end
    for i = 1, #r do
        local b = REF.fpsBars[i]
        if b then b.Size = UDim2.fromOffset(1, math.max(1, math.floor(r[i] / peak * 6 + 0.5))) end
    end
end

-- rows live in their own container so the card can keep its flush highlight
Window.footRows = new("Frame", {
    Name = "Rows", Position = UDim2.fromOffset(12, 16), Size = UDim2.new(1, -24, 0, 64),
    BackgroundTransparency = 1, Parent = footer,
}, {
    new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Signature and return value unchanged: still hands back the value TextLabel,
-- which the 10Hz loop writes .Text (and for CAR/AUTO, .TextColor3) into.
local function footerLine(caption, order)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
        LayoutOrder = order, Parent = Window.footRows,
    })
    if (order or 1) > 1 then
        new("Frame", {
            Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.StrokeSoft,
            BackgroundTransparency = 0.80, BorderSizePixel = 0, Parent = f,
        })
    end
    new("TextLabel", {
        Size = UDim2.new(0.40, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = string.upper(caption), TextSize = 9, TextColor3 = THEME.Dim,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = f,
    })
    local v = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.60, 0, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.RobotoMono, Text = "-", TextSize = 11,
        TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = f,
    })
    return v
end
REF.fCar   = footerLine("CAR", 1)
REF.fAuto  = footerLine("AUTO", 2)
REF.fFps   = footerLine("FPS", 3)
-- fCar and fAuto have their TextColor3 rewritten by the 10Hz loop, so binding
-- them to the palette would just fight that loop.  fFps gets no colour there at
-- all, so it is bound to the measurement channel and stops reading as filler.
TH.bind(REF.fFps, "TextColor3", "Accent2")

-- --------------------------------------------------------------- OPEN/CLOSE
-- The open/close GUARDS and the two task.delay unlock windows (0.42 / 0.30) are
-- byte-identical to before.  Only the choreography inside them is new, and
-- every beat is scheduled through tw()'s delayT argument rather than a chain of
-- task.delay closures, so mashing the menu key cannot queue up work.
Window.open, Window.busy = false, false
function Window.SetOpen(v)
    if Window.busy or v == Window.open then return end
    -- Closing clears the query unconditionally.  Otherwise the menu reopens
    -- filtered, with the reason scrolled off the top of a pane nobody is
    -- looking at, and reads as half the features having vanished.
    if not v and Window.searchBox and Window.searchBox.Text ~= "" then
        Window.searchBox.Text = ""
    end
    Window.open = v
    Window.busy = true
    if v then
        winRoot.Visible = true
        Window.scale.Scale = 0.65  -- MOBILE: 0.65 (was 0.94)
        setWinAlpha(1)
        -- MOBILE: Don't tween scale on mobile, keep it at 0.65
        -- FX.tw(Window.scale, FX.T.slow, { Scale = 1 }, FX.E.pop)   -- permitted Back use 2 of 3
        if winRoot:IsA("CanvasGroup") then FX.tw(winRoot, 0.26, { GroupTransparency = 0 }, FX.E.glide) end
        FX.tw(Window.shadow, 0.40, { ImageTransparency = Window.shadowRest }, FX.E.glide)
        if Window.glowOn then
            FX.tw(Window.glow, 0.40, { ImageTransparency = Window.glowRest }, FX.E.glide)
        end
        header.Position = UDim2.fromOffset(0, -10)
        FX.tw(header, FX.T.mid, { Position = UDim2.fromOffset(0, 0) }, FX.E.drop, nil, nil, 0.04)
        sidebar.Position = UDim2.fromOffset(-16, 56)
        FX.tw(sidebar, 0.34, { Position = UDim2.fromOffset(0, 56) }, FX.E.drop, nil, nil, 0.07)
        content.Position = UDim2.fromOffset(168, 68)
        FX.tw(content, FX.T.mid, { Position = UDim2.fromOffset(168, 56) }, FX.E.drop, nil, nil, 0.11)
        Window.rail.Size = UDim2.new(0, 0, 0, 1)
        FX.tw(Window.rail, FX.T.slow, { Size = UDim2.new(1, 0, 0, 1) }, FX.E.drop, nil, nil, 0.14)
        task.delay(0.42, function() Window.busy = false end)
    else
        -- no stagger on the way out: a reversal should feel like one motion
        FX.tw(Window.scale, FX.T.base, { Scale = 0.96 }, FX.E.glide)
        if winRoot:IsA("CanvasGroup") then FX.tw(winRoot, FX.T.out, { GroupTransparency = 1 }, FX.E.glide) end
        FX.tw(Window.shadow, FX.T.out, { ImageTransparency = 1 }, FX.E.glide)
        FX.tw(Window.glow,   FX.T.out, { ImageTransparency = 1 }, FX.E.glide)
        FX.tw(Window.rail, 0.16, { Size = UDim2.new(0, 0, 0, 1) }, FX.E.glide)
        task.delay(0.3, function()
            winRoot.Visible = false
            Window.busy = false
        end)
    end
end
function Window.Toggle() Window.SetOpen(not Window.open) end

-- ------------------------------------------------------------------ DRAGGING
-- The position maths is UNCHANGED, including the deliberate absence of screen
-- clamping (that decides WHERE the window can go, not how it looks).  The only
-- additions are feedback: the plate lifts a hair and its shadow tightens, which
-- is what sells "picked up".  Window.shadow / Window.glow follow the drag via
-- Window.syncFx on the Position signal, so nothing here has to move them.
do
    local dragging, dragStart, startPos = false, nil, nil
    bind(header.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, winRoot.Position
            FX.tw(Window.shadow, FX.T.hov, { ImageTransparency = math.max(0, Window.shadowRest - 0.16) }, FX.E.snap)
            FX.tw(Window.scale,  FX.T.hov, { Scale = 1.006 }, FX.E.snap)
        end
    end)
    bind(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging and Window.open then
                FX.tw(Window.shadow, FX.T.out, { ImageTransparency = Window.shadowRest }, FX.E.snap)
                FX.tw(Window.scale,  FX.T.out, { Scale = 1 }, FX.E.snap)
            end
            dragging = false
        end
    end)
    bind(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            winRoot.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

--============================================================================
-- CAR  (discovery + physics rigs)
--============================================================================
local Car = {}

Car.RootNames = { "Chassis", "Base", "Body", "Main", "Hitbox", "Engine", "Platform", "Car", "Vehicle" }

function Car.FindModel()
    local prefix = LocalPlayer.Name:lower() .. "_"
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") then
            local n = m.Name:lower()
            if #n > #prefix and n:sub(1, #prefix) == prefix then
                return m, m.Name:sub(#prefix + 1)
            end
        end
    end
    -- fallback: any model that carries our name and a seat we occupy
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        local model = hum.SeatPart:FindFirstAncestorOfClass("Model")
        if model and model ~= char then
            local nm = model.Name
            local us = nm:find("_")
            return model, us and nm:sub(us + 1) or nm
        end
    end
    return nil, nil
end

function Car.RootOf(model)
    if not model then return nil end
    local function assembly(p) return (p and (p.AssemblyRootPart or p)) or nil end
    if model.PrimaryPart then return assembly(model.PrimaryPart) end
    local seat = model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true)
    if seat then return assembly(seat) end
    for _, name in ipairs(Car.RootNames) do
        local p = model:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then return assembly(p) end
    end
    local best, bestVol
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            local v = p.Size.X * p.Size.Y * p.Size.Z
            if not bestVol or v > bestVol then best, bestVol = p, v end
        end
    end
    return assembly(best)
end

Car.onChanged = {}
function Car.Refresh()
    local model, name = Car.FindModel()
    if model ~= S.Car.Model then
        S.Car.Model = model
        S.Car.Name  = name or "-"
        S.Car.Root  = Car.RootOf(model)
        S.Car.Seat  = model and (model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true)) or nil
        for _, fn in ipairs(Car.onChanged) do pcall(fn, model) end
    elseif model and (not S.Car.Root or not S.Car.Root.Parent) then
        S.Car.Root = Car.RootOf(model)
    end
    return S.Car.Model
end

function Car.Velocity()
    local r = S.Car.Root
    if not r or not r.Parent then return Vector3.zero end
    return r.AssemblyLinearVelocity
end

function Car.Speed()  -- studs/sec, horizontal
    local v = Car.Velocity()
    return Vector3.new(v.X, 0, v.Z).Magnitude
end

function Car.Position()
    local r = S.Car.Root
    return (r and r.Parent) and r.Position or nil
end

-- ------------------------------------------------------------- PHYSICS RIGS
local Rig = { sets = {} }

function Rig.Clear(name)
    local r = Rig.sets[name]
    if not r then return end
    for _, k in ipairs({ "lv", "ao", "att" }) do
        if r[k] then pcall(function() r[k]:Destroy() end) end
    end
    Rig.sets[name] = nil
end

function Rig.Get(name, root)
    local r = Rig.sets[name]
    if r and r.root == root and r.att and r.att.Parent then return r end
    Rig.Clear(name)
    if not root or not root.Parent then return nil end
    local force = math.max(1e6, (root.AssemblyMass or 1000) * 20000)
    local att = new("Attachment", { Name = "AT_" .. name, Parent = root })
    local lv = new("LinearVelocity", {
        Name = "AT_LV_" .. name, Attachment0 = att, RelativeTo = Enum.ActuatorRelativeTo.World,
        VelocityConstraintMode = Enum.VelocityConstraintMode.Vector, MaxForce = force,
        VectorVelocity = Vector3.zero,
        -- Plane mode axes, used by the automation so the Y axis is left to
        -- gravity and the car cannot climb: X/Z plane, PlaneVelocity is (X, Z)
        PrimaryTangentAxis = Vector3.new(1, 0, 0),
        SecondaryTangentAxis = Vector3.new(0, 0, 1),
        PlaneVelocity = Vector2.new(0, 0),
        Parent = root,
    })
    local ao = new("AlignOrientation", {
        Name = "AT_AO_" .. name, Attachment0 = att, Mode = Enum.OrientationAlignmentMode.OneAttachment,
        RigidityEnabled = false, MaxTorque = force, Responsiveness = 35, MaxAngularVelocity = math.huge,
        ReactionTorqueEnabled = false, CFrame = root.CFrame, Parent = root,
    })
    r = { root = root, att = att, lv = lv, ao = ao }
    Rig.sets[name] = r
    return r
end

--============================================================================
-- FEATURE: BOOST
--============================================================================
S.boostHeld = false
S.carForwardRef = nil  -- assigned by the automation module once calibration exists

bind(RunService.Heartbeat, function(dt)
    if not S.boostHeld then return end
    local r = S.Car.Root
    if not r or not r.Parent then return end
    -- calibrated body forward when available, root -Z otherwise
    local look = S.carForwardRef and S.carForwardRef() or r.CFrame.LookVector
    r.AssemblyLinearVelocity = r.AssemblyLinearVelocity + look * (S.Boost.Power * dt * 3)
end)

--============================================================================
-- FEATURE: FLY
--============================================================================
local Fly = {}
Fly.conn = nil 

local function flyInput()
    local dir = Vector3.zero
    local cf = Camera.CFrame
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
        dir = dir - Vector3.yAxis
    end
    return (dir.Magnitude > 0) and dir.Unit or Vector3.zero
end

function Fly.Set(on)
    S.Fly.Enabled = on
    if Fly.conn then Fly.conn:Disconnect() Fly.conn = nil end
    if not on then
        Rig.Clear("fly")
        local r = S.Car.Root
        if r and r.Parent then r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X * 0.3, 0, r.AssemblyLinearVelocity.Z * 0.3) end
        return
    end
    Fly.conn = RunService.Heartbeat:Connect(function()
        local root = S.Car.Root
        if not root or not root.Parent then return end
        local rig = Rig.Get("fly", root)
        if not rig then return end
        local dir = flyInput()
        rig.lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector  -- fly needs the Y axis
        rig.lv.VectorVelocity = dir * S.Fly.Speed
        local flat = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
        if flat.Magnitude > 0.01 then
            rig.ao.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
        end
        rig.ao.Responsiveness = 25
    end)
    CONN[#CONN + 1] = Fly.conn
end

--============================================================================
-- FEATURE: BAYBLADE (spin)
--============================================================================
S.spinConn = nil 
local function setSpin(on)
    S.Spin.Enabled = on
    if S.spinConn then S.spinConn:Disconnect() S.spinConn = nil end
    if not on then
        local r = S.Car.Root
        if r and r.Parent then r.AssemblyAngularVelocity = Vector3.zero end
        return
    end
    S.spinConn = RunService.Heartbeat:Connect(function()
        local r = S.Car.Root
        if not r or not r.Parent then return end
        r.AssemblyAngularVelocity = Vector3.new(0, S.Spin.Speed, 0)
    end)
    CONN[#CONN + 1] = S.spinConn
end

--============================================================================
-- WORLD VISUALS : THEME-ENGINE SEEDS
--============================================================================
-- TH.get falls back to WHITE for a key it has never seen, so the ESPCOL mirror,
-- the Wire alias and the world-visual options are seeded here, above the first
-- bound adornment.  Every line is idempotent: if the theme engine already
-- seeded a value this block leaves it alone, so ordering against the palette
-- region does not matter.
if not TH.ext  then TH.ext  = {} end
if not TH.rate then TH.rate = {} end
if not TH.opt  then TH.opt  = {} end
if not TH.last then TH.last = {} end

THEME.Wire = THEME.Wire or THEME.Accent2
if TH.base and not TH.base.Wire then TH.base.Wire = THEME.Wire end

TH.ext["ESP:Car"]     = TH.ext["ESP:Car"]     or ESPCOL.Car
TH.ext["ESP:Traffic"] = TH.ext["ESP:Traffic"] or ESPCOL.Traffic
TH.ext["ESP:Player"]  = TH.ext["ESP:Player"]  or ESPCOL.Player

-- per-key repaint throttles: 220 wireframe boxes and 60 hitbox boxes must not
-- repaint at picker speed, and a colour landing 0.2s late is invisible in world
TH.rate.Wire           = TH.rate.Wire           or 0.20
TH.rate["ESP:Traffic"] = TH.rate["ESP:Traffic"] or 0.25
TH.rate["ESP:Car"]     = TH.rate["ESP:Car"]     or 0.25

-- World-visual options the Appearance tab writes to.  The two dropdown values
-- are stored as the option STRINGS verbatim, so the dropdown callback can
-- assign v straight through with no mapping table on either side.  The KEY
-- NAMES have to match the Appearance region exactly - it writes TH.opt.boxStyle
-- and TH.opt.originPt, so those are the two names read back below.
TH.opt.boxStyle  = TH.opt.boxStyle  or "Frame"    -- Frame | Brackets | Brackets + fill
TH.opt.originPt  = TH.opt.originPt  or "Bottom"   -- Bottom | Centre | Top
TH.opt.glowRate  = TH.opt.glowRate  or 3.00       -- highlight breathe speed
TH.opt.glowDepth = TH.opt.glowDepth or 0.16       -- highlight breathe amplitude
TH.opt.wireThick = TH.opt.wireThick or 0.040      -- SelectionBox LineThickness

--============================================================================
-- FEATURE: WIREFRAME
--============================================================================
local Wire = { boxes = {}, parts = {} }
Wire.folder = new("Folder", { Name = "AT_Wire", Parent = AdornHolder })

function Wire.Clear()
    for _, b in ipairs(Wire.boxes) do pcall(function() b:Destroy() end) end
    Wire.boxes = {}
    for part, _ in pairs(Wire.parts) do
        if part and part.Parent then pcall(function() part.LocalTransparencyModifier = 0 end) end
    end
    Wire.parts = {}
    -- Every rebuild registers up to 220 fresh tint records.  TH.gc only sweeps
    -- the accent buckets, so the Wire bucket is pruned here instead: TH.paint
    -- drops any record whose instance has lost its Parent, which is all of them
    -- at this point.  The rate stamp is cleared first or the throttle skips it.
    if TH.b and TH.b.Wire then
        TH.last.Wire = 0
        TH.paint("Wire")
    end
end

function Wire.Build()
    Wire.Clear()
    local model = S.Car.Model
    if not model or not S.Wire.Enabled then return end
    local count = 0
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and count < 220 then
            count = count + 1
            -- 0.025 all but vanishes past ~80 studs; 0.040 still reads as a
            -- hairline up close but survives distance
            local sb = new("SelectionBox", {
                Adornee = p, LineThickness = TH.opt.wireThick, SurfaceTransparency = 1, Transparency = 0.1,
                Color3 = TH.get("Wire"), Parent = Wire.folder,
            })
            -- Colour is baked at construction, so without a registry record a
            -- later THEME.Wire change could never reach a box that is already
            -- built.  "Wire" is deliberately NOT an accent key: it is outside
            -- TH.ACC, so the RGB sweep leaves the wireframe alone and only an
            -- explicit TH.paint("Wire") / TH.repaintAll repaints it.  Wire.Clear
            -- prunes this bucket, which is what keeps 220 records bounded.
            TH.bind(sb, "Color3", "Wire")
            Wire.boxes[#Wire.boxes + 1] = sb
            Wire.parts[p] = true
        end
    end
end

function Wire.Set(on)
    S.Wire.Enabled = on
    if on then Wire.Build() else Wire.Clear() end
end

-- keeps hidden bodywork hidden (LocalTransparencyModifier is client-only)
bind(RunService.Heartbeat, function()
    if not S.Wire.Enabled then return end
    local want = S.Wire.HideBody and 1 or 0
    for part, _ in pairs(Wire.parts) do
        if part and part.Parent then
            if part.LocalTransparencyModifier ~= want then part.LocalTransparencyModifier = want end
        end
    end
end)

Car.onChanged[#Car.onChanged + 1] = function()
    if S.Wire.Enabled then task.defer(Wire.Build) end
end

--============================================================================
-- WORLD MAP  (traffic lanes / waypoints / traffic cars)
--============================================================================
-- lanes  = the real TrafficLanes folders
-- paths  = what the automation may drive: those lanes plus the white line
--          between each neighbouring pair (Lane 1.5, Lane 2.5, ...)
local World = { lanes = {}, paths = {}, laneWidth = 18, traffic = {}, lastTraffic = 0 }

local function partOf(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
    return nil
end

local function posOf(inst)
    local p = partOf(inst)
    return p and p.Position or nil
end

local function finishLane(name, pts, loopHint, isBlend)
    local cum, len = { 0 }, 0
    for i = 2, #pts do
        len = len + (pts[i].pos - pts[i - 1].pos).Magnitude
        cum[i] = len
    end
    local closeDist = (pts[1].pos - pts[#pts].pos).Magnitude
    local avgSeg = len / math.max(1, #pts - 1)
    -- Traffic lanes are circuits, so be generous about calling one a loop: the
    -- cost of a false negative is the car parking on the last waypoint after a
    -- single lap, while a false positive self-corrects on the next re-acquire.
    local isLoop = closeDist < math.max(400, avgSeg * 6) or closeDist < len * 0.2
    if loopHint ~= nil then isLoop = loopHint end   -- explicit false must win too
    return {
        name = name, points = pts, cum = cum, length = len,
        loop = isLoop,
        blend = isBlend or false,
    }
end

-- The white line between two lanes.  For every point on A we take the midpoint
-- with the nearest point on B, walking B with a moving window since the lanes
-- run parallel.  Returns nil if the two lanes are not actually neighbours
-- running the same way (e.g. oncoming traffic).
local function buildBlend(a, b, name)
    local an, bn = #a.points, #b.points
    if an < 3 or bn < 3 then return nil end

    local j, seed = 1, math.huge
    for k = 1, bn do
        local d = (b.points[k].pos - a.points[1].pos).Magnitude
        if d < seed then seed, j = d, k end
    end

    local pts, widthSum, agree, samples = {}, 0, 0, 0
    for i = 1, an do
        local ap = a.points[i].pos
        local bi, bd = j, (b.points[j].pos - ap).Magnitude
        for off = -8, 8 do
            local k = ((j - 1 + off) % bn) + 1
            local d = (b.points[k].pos - ap).Magnitude
            if d < bd then bd, bi = d, k end
        end
        j = bi
        if bd > 90 then return nil end          -- not adjacent lanes
        widthSum = widthSum + bd

        -- do both lanes flow the same way here?
        if i % 5 == 0 then
            local an2 = a.points[(i % an) + 1].pos - ap
            local bn2 = b.points[(bi % bn) + 1].pos - b.points[bi].pos
            if an2.Magnitude > 0.1 and bn2.Magnitude > 0.1 then
                samples = samples + 1
                if an2.Unit:Dot(bn2.Unit) > 0.5 then agree = agree + 1 end
            end
        end
        pts[#pts + 1] = { n = i, pos = (ap + b.points[bi].pos) * 0.5 }
    end
    if samples > 0 and agree < samples * 0.6 then return nil end

    local lane = finishLane(name, pts, a.loop, true)
    lane.width = widthSum / an
    return lane
end

--============================================================================
-- BUILT-IN PATHS
--============================================================================
-- Routes recorded in-game and baked in, for when the
-- TrafficLanes waypoints are unusable.  Stored as "x,y,z;x,y,z;..." strings
-- rather than 1582 nested tables, and decoded once at load.
--
--   Map Loop : full circuit, 1582 points at 60 stud spacing,
--              94,860 studs (16.5 miles), closed, max turn 7.3 deg per point.
local BUILTIN_PATHS = {
    {
        name = "Map Loop", closed = true, spacing = 60,
        data = table.concat({
            "-3537.8,139.1,-211.2;-3535.3,137.5,-271.1;-3533.4,135.4,-331;-3535.4,133.3,-391;-3536.7,131.2,-450.9;-3537.9,129.1,-510.9;-3539,127,-570.8;-3538.5,124.7,-630.8;-3538.9,120.5,-690.6;-3538.7,116.3,-750.5;-3538.6,112.1,-810.3;-3538.4,107.9,-870.2;",
            "-3538.3,103.8,-930;-3538.1,99.6,-989.9;-3537.9,95.4,-1049.8;-3537.8,91.2,-1109.6;-3537.7,87,-1169.5;-3537.5,82.8,-1229.3;-3537.4,78.7,-1289.2;-3537.3,74.5,-1349;-3537.2,70.3,-1408.9;-3537.1,66.2,-1468.7;-3536.1,64.2,-1528.7;-3533.5,64.2,-1588.6;",
            "-3529.4,64.2,-1648.5;-3524.2,64.2,-1708.3;-3517.9,64.2,-1767.9;-3511.6,64.2,-1827.6;-3505.4,64.2,-1887.3;-3501.1,64.2,-1947.1;-3498.4,64.2,-2007.1;-3496.8,64.2,-2067.1;-3495.7,64.2,-2127;-3495,64.2,-2187;-3495.1,64.2,-2247;-3495.2,64.2,-2307;",
            "-3495.2,64.2,-2367;-3495.3,64.2,-2427;-3495.3,64.2,-2487;-3495.4,64.2,-2547;-3495.4,64.2,-2607;-3495.5,64.2,-2667;-3495.6,64.2,-2727;-3495.6,64.2,-2787;-3495.7,64.2,-2847;-3495.8,64.2,-2907;-3495.8,64.2,-2967;-3495.7,64.2,-3027;",
            "-3496,64.2,-3087;-3496.5,64.2,-3147;-3497.5,64.2,-3207;-3498.6,64.2,-3267;-3499.8,64.2,-3327;-3501.9,64.2,-3387;-3504.1,64.2,-3446.9;-3506.3,64.2,-3506.9;-3508.6,64.2,-3566.8;-3510.8,64.2,-3626.8;-3513.1,64.2,-3686.8;-3515.4,64.2,-3746.7;",
            "-3517.7,64.2,-3806.7;-3520,64.2,-3866.6;-3522.3,64.2,-3926.6;-3524.6,64.2,-3986.5;-3526.9,64.2,-4046.5;-3529.2,64.2,-4106.5;-3531.6,64.2,-4166.4;-3533.9,64.2,-4226.4;-3536.9,64.2,-4286.3;-3540.3,64.2,-4346.2;-3544,64.2,-4406.1;-3547.8,64.2,-4466;",
            "-3552,64.2,-4525.8;-3556.2,64.2,-4585.7;-3561.2,64.2,-4645.5;-3567.5,64.2,-4705.1;-3572.9,64.2,-4764.9;-3577.3,64.2,-4824.7;-3581.7,64.2,-4884.6;-3586.1,64.2,-4944.4;-3590.6,64.2,-5004.2;-3595.1,64.2,-5064.1;-3601.5,64.2,-5123.7;-3609.3,64.2,-5183.2;",
            "-3618.3,64.2,-5242.5;-3627.3,64.2,-5301.8;-3636.3,64.2,-5361.2;-3644.7,64.2,-5420.6;-3653.2,64.2,-5480;-3661.6,64.2,-5539.4;-3670.9,64.2,-5598.7;-3679.8,64.2,-5658;-3687.8,64.2,-5717.5;-3695.8,64.2,-5776.9;-3703.8,64.2,-5836.4;-3711.8,64.2,-5895.9;",
            "-3720,64.2,-5955.3;-3728.9,64.2,-6014.6;-3736.9,64.2,-6074.1;-3745.3,64.2,-6133.5;-3754.3,64.2,-6192.8;-3765.9,64.2,-6251.7;-3778.9,64.2,-6310.3;-3792.1,64.2,-6368.8;-3805.2,64.2,-6427.3;-3818.4,64.2,-6485.9;-3831.5,64.2,-6544.4;-3844.7,64.2,-6603;",
            "-3857.8,64.2,-6661.5;-3870.9,64.2,-6720.1;-3883.6,64.2,-6778.7;-3896.1,64.2,-6837.4;-3908.7,64.2,-6896.1;-3921.2,64.2,-6954.7;-3933.7,64.2,-7013.4;-3946.3,64.2,-7072.1;-3958.9,64.2,-7130.7;-3972.7,64.2,-7189.1;-3987.6,64.2,-7247.2;-4003.2,64.2,-7305.2;",
            "-4019.4,64.2,-7363;-4036.4,64.2,-7420.5;-4053.4,64.2,-7478;-4070.4,64.2,-7535.6;-4087.5,64.2,-7593.1;-4104.5,64.2,-7650.6;-4121.5,64.2,-7708.2;-4138.6,64.2,-7765.7;-4155.6,64.2,-7823.2;-4172.7,64.2,-7880.7;-4189.1,64.2,-7938.5;-4205.2,64.2,-7996.3;",
            "-4221.3,64.2,-8054.1;-4238.2,64.2,-8111.6;-4255.4,64.2,-8169.1;-4274.6,64.2,-8226;-4296,64.2,-8282;-4317.5,64.2,-8338;-4338.5,64.2,-8394.2;-4358.9,64.2,-8450.6;-4379.4,64.2,-8507.1;-4399.8,64.2,-8563.5;-4420.2,64.2,-8619.9;-4440.7,64.2,-8676.3;",
            "-4461.2,64.2,-8732.7;-4481.6,64.2,-8789.1;-4502.1,64.2,-8845.5;-4522.6,64.2,-8901.9;-4543.1,64.2,-8958.3;-4563.6,64.2,-9014.6;-4584.2,64.2,-9071;-4604.7,64.2,-9127.4;-4625.3,64.2,-9183.7;-4649.9,64.2,-9238.5;-4676.4,64.2,-9292.3;-4701.4,64.2,-9346.8;",
            "-4726.1,64.2,-9401.5;-4750.7,64.2,-9456.3;-4775.4,64.2,-9511;-4800,64.2,-9565.7;-4824.6,64.2,-9620.4;-4849.2,64.2,-9675.1;-4873.1,64.2,-9730.1;-4897.5,64.2,-9785;-4921.8,64.2,-9839.8;-4946,64.2,-9894.7;-4971,64.2,-9949.3;-4995.6,64.2,-10004;",
            "-5020.7,64.2,-10058.5;-5047.6,64.2,-10112.1;-5075.4,64.2,-10165.3;-5104.5,64.2,-10217.8;-5132.8,64.2,-10270.7;-5160.3,64.2,-10324;-5189.3,64.2,-10376.5;-5217.9,64.2,-10429.3;-5246.1,64.2,-10482.2;-5274.3,64.2,-10535.2;-5303.2,64.2,-10587.8;-5332.1,64.2,-10640.3;",
            "-5360.4,64.2,-10693.3;-5388.7,64.2,-10746.2;-5418.1,64.2,-10798.5;-5447.6,64.2,-10850.7;-5477.1,64.2,-10903;-5506.9,64.2,-10955;-5537,64.2,-11007;-5567,64.2,-11058.9;-5598.6,64.2,-11109.9;-5631.3,64.2,-11160.2;-5664,64.2,-11210.6;-5696.6,64.2,-11260.9;",
            "-5728.9,64.2,-11311.5;-5760.3,64.2,-11362.6;-5792,64.2,-11413.5;-5823.9,64.2,-11464.3;-5855.8,64.2,-11515.2;-5887.7,64.2,-11566;-5919.8,64.2,-11616.7;-5951.9,64.2,-11667.4;-5984,64.2,-11718;-6016.2,64.2,-11768.7;-6048.5,64.2,-11819.3;-6082.2,64.2,-11868.9;",
            "-6116,64.2,-11918.5;-6150.2,64.2,-11967.7;-6185.4,64.2,-12016.4;-6220.8,64.2,-12064.8;-6256.7,64.2,-12112.9;-6292.7,64.2,-12160.9;-6328.6,64.2,-12208.9;-6364.3,64.2,-12257.2;-6399.7,64.2,-12305.6;-6434.8,64.2,-12354.2;-6469.2,64.2,-12403.4;-6504,64.2,-12452.3;",
            "-6538.9,64.2,-12501.1;-6573.8,64.2,-12549.9;-6608.8,64.2,-12598.6;-6644.1,64.2,-12647.2;-6680,64.2,-12695.2;-6717.4,64.2,-12742.2;-6755.3,64.2,-12788.7;-6793.9,64.2,-12834.6;-6832.4,64.2,-12880.6;-6871,64.2,-12926.6;-6909.6,64.2,-12972.5;-6948.2,64.2,-13018.5;",
            "-6986.8,64.2,-13064.4;-7025.4,64.2,-13110.3;-7064,64.2,-13156.2;-7102.7,64.2,-13202.1;-7141.3,64.2,-13248;-7180,64.2,-13293.9;-7218.6,64.2,-13339.8;-7257.3,64.2,-13385.6;-7296,64.2,-13431.5;-7334.7,64.2,-13477.4;-7373.4,64.2,-13523.2;-7413,64.2,-13568.3;",
            "-7455.5,64.2,-13610.6;-7498.4,64.2,-13652.6;-7540.8,64.2,-13695.1;-7582.9,64.2,-13737.8;-7624.8,64.2,-13780.8;-7666.7,64.2,-13823.7;-7708.2,64.2,-13867;-7749.9,64.2,-13910.1;-7791.9,64.2,-13953;-7833.9,64.2,-13995.9;-7875.9,64.2,-14038.7;-7918,64.2,-14081.5;",
            "-7960,64.2,-14124.3;-8002.1,64.2,-14167.1;-8044.1,64.2,-14209.9;-8086.3,64.2,-14252.6;-8129.2,64.2,-14294.5;-8172.9,64.2,-14335.6;-8217.3,64.2,-14375.9;-8261.8,64.2,-14416.2;-8306.3,64.2,-14456.5;-8350.8,64.2,-14496.7;-8395.3,64.2,-14536.9;-8439.9,64.2,-14577.1;",
            "-8484.7,64.2,-14617;-8529.6,64.2,-14656.8;-8574.6,64.2,-14696.5;-8619.5,64.2,-14736.3;-8664.4,64.2,-14776;-8709.4,64.2,-14815.8;-8754.4,64.2,-14855.5;-8799.4,64.2,-14895.2;-8845.7,64.2,-14933.4;-8892.6,64.2,-14970.7;-8939.6,64.2,-15008;-8986.8,64.2,-15045.1;",
            "-9034.6,64.2,-15081.3;-9082.5,64.2,-15117.5;-9130.2,64.2,-15153.9;-9177.7,64.2,-15190.5;-9225.3,64.2,-15227.1;-9272.9,64.2,-15263.6;-9320.5,64.2,-15300.1;-9368.1,64.2,-15336.7;-9415.7,64.2,-15373.2;-9463.3,64.2,-15409.7;-9510.9,64.2,-15446.2;-9558.6,64.2,-15482.6;",
            "-9606.2,64.2,-15519.1;-9654,64.2,-15555.5;-9702.5,64.2,-15590.7;-9751.3,64.2,-15625.6;-9800.6,64.2,-15659.8;-9850,64.2,-15693.9;-9899.3,64.2,-15728.1;-9948.8,64.2,-15762;-9998.6,64.2,-15795.5;-10048.4,64.2,-15828.9;-10098.2,64.2,-15862.4;-10147.9,64.2,-15895.9;",
            "-10197.7,64.2,-15929.4;-10247.5,64.2,-15962.9;-10297.2,64.2,-15996.6;-10346.4,64.2,-16030.9;-10396,64.2,-16064.7;-10445.9,64.2,-16098;-10496.1,64.2,-16130.8;-10547.6,64.2,-16161.7;-10599.3,64.2,-16192.1;-10651,64.2,-16222.5;-10702.8,64.2,-16252.7;-10754.9,64.2,-16282.6;",
            "-10807,64.2,-16312.4;-10859.1,64.2,-16342.1;-10911.2,64.2,-16371.9;-10963.3,64.2,-16401.7;-11015.4,64.2,-16431.4;-11067.5,64.2,-16461.2;-11119.6,64.2,-16490.9;-11171.7,64.2,-16520.6;-11223.8,64.2,-16550.4;-11275.9,64.2,-16580.1;-11328,64.2,-16609.8;-11380.9,64.2,-16638.2;",
            "-11434.2,64.2,-16665.8;-11487.6,64.2,-16693.2;-11541.6,64.2,-16719.2;-11596.5,64.2,-16743.6;-11651.3,64.2,-16767.9;-11705.8,64.2,-16793;-11760.3,64.2,-16818.2;-11814.7,64.2,-16843.3;-11869.2,64.2,-16868.5;-11923.7,64.2,-16893.7;-11978.2,64.2,-16918.8;-12032.7,64.2,-16943.9;",
            "-12087.2,64.2,-16969;-12141.6,64.2,-16994.1;-12195.8,64.2,-17020;-12249.5,64.2,-17046.7;-12302.7,64.2,-17074.4;-12356,64.2,-17102.1;-12409.1,64.2,-17130;-12461.6,64.2,-17158.9;-12513.7,64.2,-17188.7;-12565.8,64.2,-17218.5;-12617.9,64.2,-17248.3;-12669.9,64.2,-17278.2;",
            "-12721.9,64.2,-17308.2;-12773.8,64.2,-17338.2;-12825.8,64.2,-17368.2;-12877.8,64.2,-17398.1;-12929.8,64.2,-17428;-12981.8,64.2,-17457.9;-13033.8,64.2,-17487.9;-13085.5,64.2,-17518.3;-13137.2,64.2,-17548.9;-13188.8,64.2,-17579.4;-13240.2,64.2,-17610.5;-13289.9,64.2,-17644;",
            "-13338.4,64.2,-17679.4;-13386.6,64.2,-17715.1;-13435,64.2,-17750.5;-13483.7,64.2,-17785.5;-13532.5,64.2,-17820.5;-13581.7,64.2,-17854.8;-13631.1,64.2,-17888.9;-13680.5,64.2,-17923;-13729.8,64.2,-17957.1;-13779.2,64.2,-17991.2;-13828.6,64.2,-18025.2;-13878,64.2,-18059.3;",
            "-13927.4,64.2,-18093.3;-13976.8,64.2,-18127.4;-14026,64.2,-18161.7;-14074,64.2,-18197.7;-14121.4,64.2,-18234.5;-14168,64.2,-18272.3;-14214.6,64.2,-18310.1;-14261.2,64.2,-18347.9;-14307.7,64.2,-18385.8;-14353.8,64.2,-18424.2;-14400,64.2,-18462.5;-14446.1,64.2,-18500.9;",
            "-14492.2,64.2,-18539.3;-14538.3,64.2,-18577.7;-14584.5,64.2,-18616;-14630.7,64.2,-18654.3;-14676.8,64.2,-18692.6;-14723,64.2,-18730.9;-14769.2,64.2,-18769.2;-14815.4,64.2,-18807.5;-14861.6,64.2,-18845.8;-14907.9,64.2,-18883.9;-14955.3,64.2,-18920.8;-15003,64.2,-18957.1;",
            "-15051.5,64.2,-18992.5;-15100.4,64.2,-19027.2;-15149.5,64.2,-19061.8;-15198.8,64.2,-19095.9;-15248.1,64.2,-19130.1;-15297.5,64.2,-19164.2;-15346.8,64.2,-19198.3;-15396.2,64.2,-19232.5;-15445.5,64.2,-19266.6;-15494.9,64.2,-19300.7;-15544.3,64.2,-19334.8;-15593.6,64.2,-19368.9;",
            "-15643,64.2,-19403;-15693.1,64.2,-19436;-15743.7,64.2,-19468.2;-15794.4,64.2,-19500.4;-15845.4,64.2,-19531.9;-15896.9,64.2,-19562.7;-15948.4,64.2,-19593.5;-16000,64.2,-19624.1;-16052.1,64.2,-19654;-16104.3,64.2,-19683.5;-16156.6,64.2,-19712.9;-16208.8,64.2,-19742.4;",
            "-16261.1,64.2,-19771.8;-16313.4,64.2,-19801.3;-16365.7,64.2,-19830.7;-16418,64.2,-19860.1;-16470.3,64.2,-19889.5;-16522.6,64.2,-19918.9;-16574.9,64.2,-19948.3;-16627.2,64.2,-19977.7;-16679.7,64.2,-20006.8;-16733,64.2,-20034.3;-16786.9,64.2,-20060.8;-16841.2,64.2,-20086.2;",
            "-16895.5,64.2,-20111.6;-16949.9,64.2,-20137;-17004.2,64.2,-20162.5;-17058.6,64.2,-20187.9;-17113,64.2,-20213.2;-17167.4,64.2,-20238.5;-17221.9,64.2,-20263.5;-17276.5,64.2,-20288.6;-17331,64.2,-20313.6;-17385.5,64.2,-20338.6;-17440.1,64.2,-20363.6;-17495,64.2,-20387.7;",
            "-17550.7,64.2,-20410;-17606.5,64.2,-20432;-17662.4,64.2,-20453.9;-17718.7,64.2,-20474.5;-17775.2,64.2,-20494.8;-17831.7,64.2,-20515.1;-17888.2,64.2,-20535.3;-17944.7,64.2,-20555.5;-18001.2,64.2,-20575.7;-18057.7,64.2,-20595.9;-18114.2,64.2,-20616.1;-18170.6,64.2,-20636.3;",
            "-18227.1,64.2,-20656.5;-18283.6,64.2,-20676.7;-18340.2,64.2,-20696.9;-18396.7,64.2,-20717.1;-18453.2,64.2,-20737.2;-18509.8,64.2,-20757;-18567.1,64.2,-20774.8;-18624.7,64.2,-20791.6;-18682.6,64.2,-20807.5;-18740.5,64.2,-20823.2;-18798.4,64.2,-20838.9;-18856.3,64.2,-20854.5;",
            "-18914.2,64.2,-20870.2;-18972.3,64.2,-20885.4;-19030.4,64.2,-20900.2;-19088.5,64.2,-20915.1;-19146.7,64.2,-20929.9;-19204.6,64.2,-20945.5;-19262.5,64.2,-20961.2;-19320.5,64.2,-20976.9;-19378.4,64.2,-20992.5;-19436.3,64.2,-21008.2;-19494.2,64.2,-21023.8;-19552.1,64.2,-21039.5;",
            "-19610.1,64.2,-21055.2;-19668,64.2,-21070.8;-19725.9,64.2,-21086.4;-19783.8,64.2,-21102;-19841.8,64.2,-21117.6;-19899.7,64.2,-21133.2;-19957.7,64.2,-21148.7;-20015.6,64.2,-21164.2;-20073.6,64.2,-21179.7;-20131.6,64.2,-21195.2;-20189.6,64.2,-21210.6;-20247.5,64.2,-21226.1;",
            "-20305.5,64.2,-21241.5;-20363.5,64.2,-21256.8;-20421.5,64.2,-21272.2;-20479.5,64.2,-21287.5;-20537.5,64.2,-21302.9;-20595.6,64.2,-21318.2;-20653.6,64.2,-21333.5;-20711.6,64.2,-21348.9;-20769.6,64.2,-21364.2;-20827.6,64.2,-21379.5;-20885.6,64.2,-21394.8;-20943.6,64.2,-21410.1;",
            "-21001.7,64.2,-21425.4;-21059.7,64.2,-21440.7;-21117.7,64.2,-21455.9;-21175.7,64.2,-21471.2;-21233.7,64.2,-21486.5;-21291.8,64.2,-21501.7;-21349.8,64.2,-21517;-21407.8,64.2,-21532.2;-21465.8,64.2,-21547.8;-21523.7,64.2,-21563.5;-21581.6,64.2,-21579.2;-21639.5,64.2,-21594.8;",
            "-21697.4,64.2,-21610.5;-21755.4,64.2,-21626.2;-21813.3,64.2,-21641.8;-21871.2,64.2,-21657.4;-21929.2,64.2,-21673;-21987.1,64.2,-21688.6;-22045,64.2,-21704.2;-22103,64.2,-21719.8;-22160.9,64.2,-21735.3;-22218.9,64.2,-21750.9;-22276.8,64.2,-21766.4;-22334.8,64.2,-21781.9;",
            "-22392.7,64.2,-21797.5;-22450.7,64.2,-21813;-22508.7,64.2,-21828.5;-22566.6,64.2,-21844;-22624.6,64.2,-21859.5;-22682.6,64.2,-21874.9;-22740.5,64.2,-21890.4;-22798.5,64.2,-21905.9;-22856.5,64.2,-21921.3;-22914.5,64.2,-21936.8;-22972.5,64.2,-21952.2;-23030.4,64.2,-21967.5;",
            "-23088.4,64.2,-21982.9;-23146.4,64.2,-21998.3;-23204.4,64.2,-22013.7;-23262.5,64.2,-22029;-23320.9,64.2,-22042.5;-23379.7,64.2,-22054.3;-23438.6,64.2,-22065.7;-23497.7,64.2,-22076.6;-23556.7,64.2,-22087.3;-23615.7,64.2,-22098.1;-23674.7,64.2,-22108.8;-23733.8,64.2,-22119.6;",
            "-23792.8,64.2,-22130.3;-23851.8,64.2,-22141.1;-23910.9,64.2,-22151.8;-23969.9,64.2,-22162.5;-24029,64.2,-22172.8;-24088.6,64.2,-22180.2;-24148.4,64.2,-22184.7;-24208.2,64.2,-22188.9;-24268.2,64.2,-22191.9;-24328.1,64.2,-22193.3;-24388.1,64.2,-22194.7;-24448.1,64.2,-22196.1;",
            "-24508.1,64.2,-22197.4;-24568.1,64.2,-22198.8;-24628.1,64.2,-22200.2;-24688,64.2,-22201.5;-24748,64.2,-22202.8;-24808,64.2,-22202.8;-24868,64.2,-22201.1;-24927.9,64.2,-22198;-24987.7,64.2,-22193.2;-25047.5,64.2,-22187.4;-25107.2,64.2,-22181.6;-25166.9,64.2,-22175.8;",
            "-25226.6,64.2,-22169.5;-25286.2,64.2,-22162.7;-25345.8,64.2,-22155.8;-25405.4,64.2,-22148.9;-25465,64.2,-22142;-25524.4,64.2,-22133.9;-25583.5,64.2,-22123.6;-25642.3,64.2,-22111.6;-25700.5,64.2,-22097;-25758.7,64.2,-22082.4;-25817.1,64.2,-22068.4;-25875.3,64.2,-22054.1;",
            "-25933.5,64.2,-22039.2;-25991.6,64.2,-22024.3;-26049.7,64.2,-22009.4;-26107.8,64.2,-21994.6;-26166,64.2,-21979.7;-26224,64.2,-21964.6;-26281.7,64.2,-21948.1;-26339.3,64.2,-21931.3;-26395.8,64.2,-21911;-26451.9,64.2,-21889.8;-26508,64.2,-21868.6;-26564.1,64.2,-21847.1;",
            "-26619.8,64.2,-21825;-26675.6,64.2,-21802.9;-26731.2,64.2,-21780.2;-26786.6,64.2,-21757.3;-26842.1,64.2,-21734.5;-26897,64.2,-21710.2;-26951.3,64.2,-21684.7;-27005.5,64.2,-21659;-27058.9,64.2,-21631.7;-27111.7,64.2,-21603.1;-27164.2,64.2,-21574.2;-27216.7,64.2,-21545.1;",
            "-27268.7,64.2,-21515.2;-27320.7,64.2,-21485.2;-27372.7,64.2,-21455.3;-27424.7,64.2,-21425.4;-27476.5,64.2,-21395;-27528.1,64.2,-21364.4;-27579.7,64.2,-21333.7;-27630.7,64.2,-21302.2;-27679.5,64.2,-21267.3;-27727.4,64.2,-21231.2;-27775.3,64.2,-21195;-27823.1,64.2,-21158.8;",
            "-27870,64.2,-21121.3;-27916.6,64.2,-21083.5;-27963.2,64.2,-21045.7;-28009.8,64.2,-21007.9;-28056.4,64.2,-20970.1;-28103,64.2,-20932.4;-28149.6,64.2,-20894.6;-28195.6,64.2,-20856.1;-28240.5,64.2,-20816.3;-28284.4,64.2,-20775.4;-28326.2,64.2,-20732.3;-28367.8,64.2,-20689;",
            "-28409.3,64.2,-20645.7;-28450.8,64.2,-20602.5;-28492.4,64.2,-20559.2;-28533.9,64.2,-20515.9;-28575.5,64.2,-20472.6;-28616.6,64.2,-20428.9;-28654.4,64.2,-20382.3;-28690.8,64.2,-20334.6;-28726.4,64.2,-20286.3;-28761.7,64.2,-20237.8;-28797,64.2,-20189.2;-28832.3,64.2,-20140.7;",
            "-28867.5,64.2,-20092.2;-28902.8,64.2,-20043.6;-28936.9,64.2,-19994.3;-28970,64.2,-19944.2;-29002.4,64.2,-19893.8;-29032.8,64.2,-19842;-29062.4,64.2,-19789.8;-29091.2,64.2,-19737.2;-29119.5,64.2,-19684.3;-29147.1,64.2,-19631;-29174.4,64.2,-19577.6;-29201.4,64.2,-19524;",
            "-29226.6,64.2,-19469.5;-29250.4,64.2,-19414.5;-29272.8,64.2,-19358.8;-29294.2,64.2,-19302.8;-29315.7,64.2,-19246.7;-29337.1,64.2,-19190.7;-29359.2,64.2,-19134.9;-29381.4,64.2,-19079.2;-29403.7,64.2,-19023.4;-29425.9,64.2,-18967.7;-29448.2,64.2,-18912;-29470.4,64.2,-18856.3;",
            "-29493.2,64.2,-18800.8;-29516.1,64.2,-18745.3;-29539,64.2,-18689.8;-29561.9,64.2,-18634.4;-29586.3,64.2,-18579.6;-29614.1,64.2,-18526.4;-29642.7,64.2,-18473.6;-29671.3,64.2,-18420.9;-29699.9,64.2,-18368.1;-29728.3,64.2,-18315.3;-29756.5,64.2,-18262.4;-29783.6,64.2,-18208.8;",
            "-29808.9,64.2,-18154.4;-29833.2,64.2,-18099.5;-29857.1,64.2,-18044.5;-29879.7,64.2,-17988.9;-29902.1,64.2,-17933.3;-29924,64.2,-17877.4;-29944.3,64.2,-17821;-29964.3,64.2,-17764.4;-29982.2,64.2,-17707.1;-29998.9,64.2,-17649.5;-30014,64.2,-17591.4;-30027.7,64.2,-17533;",
            "-30041,64.2,-17474.5;-30054.2,64.2,-17416;-30066.1,64.2,-17357.2;-30076.5,64.2,-17298.1;-30085.3,64.2,-17238.7;-30093.8,64.2,-17179.3;-30102.2,64.2,-17119.9;-30109.5,64.2,-17060.4;-30114.7,64.2,-17000.6;-30118.4,64.2,-16940.7;-30121.4,64.2,-16880.8;-30123.7,64.2,-16820.8;",
            "-30125.2,64.2,-16760.8;-30125.3,64.2,-16700.8;-30125,64.2,-16640.8;-30124.4,64.2,-16580.8;-30123,64.2,-16520.9;-30120.9,64.2,-16460.9;-30116.4,64.2,-16401.1;-30110.2,64.2,-16341.4;-30103.8,64.2,-16281.7;-30097.3,64.2,-16222.1;-30091.3,64.2,-16162.4;-30087,64.2,-16102.5;",
            "-30084.7,64.2,-16042.6;-30082.7,64.2,-15982.6;-30081.3,64.2,-15922.6;-30081.6,64.2,-15862.6;-30083.2,64.2,-15802.7;-30086.2,64.2,-15742.7;-30091.7,64.2,-15683;-30097.9,64.2,-15623.3;-30104.1,64.2,-15563.6;-30110.9,64.2,-15504;-30117.9,64.2,-15444.4;-30124.7,64.2,-15384.8;",
            "-30132.4,64.2,-15325.3;-30139.8,64.2,-15265.8;-30146.9,64.2,-15206.2;-30153.8,64.2,-15146.6;-30158.7,64.2,-15086.8;-30161.9,64.2,-15026.9;-30163.1,64.2,-14966.9;-30164.9,64.2,-14906.9;-30166.7,64.2,-14846.9;-30167.1,64.2,-14786.9;-30167.2,64.2,-14726.9;-30166.3,64.2,-14666.9;",
            "-30164.4,64.2,-14607;-30160.7,64.2,-14547.1;-30154.9,64.2,-14487.4;-30148.5,64.2,-14427.7;-30142.1,64.2,-14368.1;-30134.4,64.2,-14308.5;-30126.4,64.2,-14249.1;-30117.3,64.2,-14189.8;-30105.9,64.2,-14130.9;-30093.8,64.2,-14072.1;-30081.7,64.2,-14013.3;-30070.2,64.6,-13954.5;",
            "-30060.3,64.7,-13895.3;-30051.6,64.7,-13835.9;-30045.2,64.7,-13776.3;-30043.4,64.7,-13716.3;-30047.8,64.7,-13656.4;-30056.8,64.7,-13597.1;-30068.5,64.7,-13538.3;-30081.7,64.7,-13479.7;-30097.8,64.7,-13421.9;-30118,64.7,-13365.4;-30141.4,64.7,-13310.2;-30166.8,64.7,-13255.8;",
            "-30194.4,64.7,-13202.6;-30228.6,64.7,-13153.2;-30265.5,64.7,-13105.9;-30302.8,64.7,-13059;-30340.2,64.7,-13012;-30376.8,64.7,-12964.5;-30411.9,64.7,-12915.8;-30444.3,64.7,-12865.3;-30473.9,64.7,-12813.2;-30497.9,64.7,-12758.2;-30516.1,64.7,-12701;-30530.5,64.7,-12642.7;",
            "-30542.2,64.7,-12583.9;-30550.8,64.7,-12524.5;-30556.8,64.7,-12464.8;-30560,64.7,-12404.9;-30559.3,64.7,-12344.9;-30555,64.7,-12285;-30547.9,64.7,-12225.5;-30537.1,64.7,-12166.4;-30523.3,64.7,-12108;-30511.3,64.7,-12049.3;-30500.7,64.7,-11990.2;-30489,64.7,-11931.4;",
            "-30478.1,64.7,-11872.4;-30468,64.7,-11813.2;-30457.3,64.7,-11754.2;-30446.1,64.7,-11695.2;-30434.6,64.7,-11636.3;-30422.9,64.7,-11577.5;-30411.2,64.7,-11518.6;-30399.5,64.7,-11459.8;-30387.8,64.7,-11400.9;-30376.1,64.7,-11342.1;-30364.4,64.7,-11283.2;-30352.7,64.7,-11224.4;",
            "-30340.6,64.7,-11165.6;-30326.1,64.7,-11107.4;-30309.7,64.7,-11049.7;-30292.5,64.7,-10992.2;-30274.1,64.7,-10935.1;-30254.5,64.7,-10878.4;-30232.6,64.7,-10822.6;-30206.5,64.7,-10768.5;-30177.1,64.7,-10716.2;-30146.8,64.7,-10664.4;-30114.9,64.7,-10613.6;-30079.7,64.7,-10565;",
            "-30041.6,64.7,-10518.6;-30002.2,64.7,-10473.4;-29960.7,64.7,-10430;-29916.9,64.7,-10389;-29869.2,64.7,-10352.6;-29819.1,64.7,-10319.6;-29768.4,64.7,-10287.6;-29716.4,64.7,-10257.6;-29663.1,64.7,-10230.1;-29607.7,64.7,-10207.2;-29551.9,64.7,-10184.9;-29495.6,64.7,-10164.4;",
            "-29437.5,64.7,-10149.2;-29379,64.7,-10135.8;-29320.1,64.7,-10124.7;-29260.7,64.7,-10115.8;-29201.1,64.7,-10108.8;-29141.5,64.7,-10102.6;-29081.5,64.7,-10101.5;-29021.6,64.7,-10105;-28961.7,64.7,-10107.9;-28901.7,64.7,-10108.8;-28841.7,64.7,-10110.7;-28781.7,64.7,-10112.1;",
            "-28721.7,64.7,-10112.6;-28661.7,64.7,-10113.5;-28601.7,64.7,-10114.7;-28541.7,64.7,-10115.8;-28481.7,64.7,-10116.9;-28421.8,64.7,-10118.2;-28361.9,64.7,-10121.8;-28302.2,64.7,-10127.9;-28242.9,64.7,-10137.1;-28184.2,64.7,-10149.6;-28126.1,64.7,-10164.5;-28068.2,64.7,-10180.4;",
            "-28011,64.7,-10198.4;-27953.9,64.7,-10216.7;-27896.7,64.7,-10235;-27839.4,64.7,-10252.8;-27781.1,64.7,-10267;-27722.3,64.7,-10278.9;-27663.4,64.7,-10290.4;-27604.5,64.7,-10301.9;-27545.4,64.7,-10311.9;-27485.9,64.7,-10319.5;-27426,64.7,-10323.5;-27366.1,64.7,-10326;",
            "-27306.1,64.7,-10325.9;-27246.4,64.7,-10319.8;-27187,64.7,-10311.2;-27127.9,64.7,-10300.8;-27069.5,64.7,-10287.2;-27011.4,64.7,-10272;-26953.6,64.7,-10256;-26897.5,64.7,-10234.8;-26842.3,64.7,-10211.1;-26787.4,64.7,-10186.9;-26733.7,64.7,-10160.2;-26680.8,64.7,-10131.9;",
            "-26627.6,64.7,-10104.2;-26575.6,64.7,-10074.3;-26523.7,64.7,-10044;-26471.6,64.7,-10014.4;-26419.4,64.7,-9984.7;-26367.2,64.7,-9955.2;-26314.3,64.7,-9927;-26260.8,64.7,-9899.7;-26206.5,64.7,-9874.2;-26151.2,64.7,-9850.9;-26095.5,64.7,-9828.5;-26039.8,64.7,-9806.3;",
            "-25983.3,64.7,-9786;-25926.2,64.7,-9767.8;-25868.4,64.7,-9751.4;-25810.3,64.7,-9736.6;-25751.8,64.7,-9723.2;-25693.1,64.7,-9710.9;-25633.9,64.7,-9701.2;-25574.3,64.7,-9693.8;-25514.5,64.7,-9689.1;-25454.6,64.7,-9686.4;-25394.6,64.7,-9685.3;-25334.7,64.7,-9689.1;",
            "-25275.1,64.7,-9696.3;-25215.6,64.7,-9703.6;-25156.1,64.7,-9711.3;-25096.8,64.7,-9720.2;-25037.6,64.7,-9730.5;-24978.9,64.7,-9743;-24920.6,64.7,-9756.9;-24862.3,64.7,-9771;-24804,64.7,-9785.1;-24745.5,64.7,-9798.8;-24686.8,64.7,-9811;-24627.8,64.7,-9822.2;",
            "-24568.5,64.7,-9831;-24508.8,64.7,-9836.7;-24448.9,64.7,-9840.4;-24389,64.7,-9843.8;-24329,64.7,-9846;-24269,64.7,-9845;-24209.1,64.7,-9842.3;-24149.3,64.7,-9837.5;-24089.8,64.7,-9829.8;-24030.5,64.7,-9820.7;-23971.4,64.7,-9810.5;-23912.4,64.7,-9799.3;",
            "-23853.8,64.7,-9786.5;-23795.7,64.7,-9771.4;-23738.2,64.7,-9754.4;-23680.8,64.7,-9737;-23624,64.7,-9717.5;-23568.2,64.7,-9695.4;-23513.1,64.7,-9671.8;-23458.7,64.7,-9646.6;-23405.1,64.7,-9619.5;-23352.4,64.7,-9590.9;-23300.7,64.7,-9560.4;-23249.7,64.7,-9528.8;",
            "-23198.9,64.7,-9496.8;-23149.7,64.7,-9462.5;-23101.9,64.7,-9426.2;-23055.2,64.7,-9388.5;-23008.8,64.7,-9350.5;-22963.4,64.7,-9311.2;-22919.2,64.7,-9270.7;-22876,64.7,-9229.1;-22834.1,64.7,-9186.1;-22794.8,64.7,-9140.8;-22757.6,64.7,-9093.7;-22721.5,64.7,-9045.8;",
            "-22686.5,64.7,-8997;-22653.2,64.7,-8947.2;-22621.3,64.7,-8896.3;-22590.8,64.7,-8844.7;-22561.6,64.7,-8792.2;-22531.4,64.7,-8740.4;-22501.5,64.7,-8688.4;-22471.9,64.7,-8636.2;-22442.1,64.7,-8584.1;-22411.7,64.7,-8532.4;-22378.7,64.7,-8482.3;-22344,64.7,-8433.3;",
            "-22308.3,64.7,-8385.1;-22271.5,64.7,-8337.7;-22232.8,64.7,-8291.9;-22192.3,64.7,-8247.6;-22150.5,64.7,-8204.5;-22107.1,64.7,-8163.2;-22061.6,64.7,-8124;-22014.4,64.7,-8086.9;-21966,64.7,-8051.6;-21915.4,64.7,-8019.2;-21862.7,64.7,-7990.6;-21808.9,64.7,-7964.1;",
            "-21755.4,64.7,-7936.8;-21701.2,64.7,-7911;-21647,64.7,-7885.3;-21594.4,64.7,-7856.6;-21542.7,64.7,-7826.1;-21492.3,64.7,-7793.6;-21442.6,64.7,-7759.9;-21392.6,64.7,-7726.7;-21343,64.7,-7693;-21293.4,64.7,-7659.3;-21243.7,64.7,-7625.6;-21194.1,64.7,-7591.9;",
            "-21144.6,64.7,-7557.9;-21096.2,64.7,-7522.5;-21049,64.7,-7485.4;-21003.3,64.7,-7446.5;-20959,64.7,-7406.1;-20915.8,64.7,-7364.5;-20873.9,64.7,-7321.5;-20833.6,64.7,-7277;-20795.1,64.7,-7231;-20758.3,64.7,-7183.6;-20723.9,64.7,-7134.5;-20692.5,64.7,-7083.4;",
            "-20662.6,64.7,-7031.3;-20634,64.7,-6978.6;-20607.5,64.7,-6924.7;-20581.9,64.7,-6870.5;-20557.8,64.7,-6815.5;-20534.5,64.7,-6760.3;-20515.2,64.7,-6703.5;-20496.8,64.7,-6646.3;-20479.4,64.7,-6588.9;-20463.6,64.7,-6531;-20449.7,64.7,-6472.7;-20438.3,64.7,-6413.8;",
            "-20429.5,64.7,-6354.4;-20423.2,64.7,-6294.7;-20418.2,64.7,-6234.9;-20413.6,64.7,-6175.1;-20410.7,64.7,-6115.2;-20408.2,64.7,-6055.2;-20406.8,64.7,-5995.3;-20405.4,64.7,-5935.3;-20404.2,64.7,-5875.3;-20402.9,64.7,-5815.3;-20401.7,64.7,-5755.3;-20400.5,64.7,-5695.3;",
            "-20399.3,64.7,-5635.3;-20398,64.7,-5575.4;-20396.7,64.7,-5515.4;-20395.6,64.7,-5455.4;-20394.9,64.7,-5395.4;-20394.2,64.7,-5335.4;-20393.5,64.7,-5275.4;-20392.2,64.7,-5215.4;-20390.8,64.7,-5155.4;-20389.3,64.7,-5095.4;-20387.8,64.7,-5035.5;-20386.3,64.7,-4975.5;",
            "-20384.9,64.7,-4915.5;-20383.4,64.7,-4855.5;-20381.9,64.7,-4795.5;-20380.4,64.7,-4735.5;-20378.9,64.7,-4675.6;-20377.5,64.7,-4615.6;-20376.1,64.7,-4555.6;-20375.8,64.7,-4495.6;-20375.7,64.7,-4435.6;-20375.3,64.7,-4375.6;-20374.1,64.7,-4315.6;-20372.8,64.7,-4255.6;",
            "-20371.5,64.7,-4195.6;-20370.3,64.7,-4135.7;-20369.3,64.7,-4075.7;-20368.9,64.7,-4015.7;-20369.3,64.7,-3955.7;-20369.1,64.7,-3895.7;-20368.1,64.7,-3835.7;-20367.2,64.7,-3775.7;-20366.2,64.7,-3715.7;-20365.3,64.7,-3655.7;-20364.3,64.7,-3595.7;-20363.4,64.7,-3535.7;",
            "-20362.4,64.7,-3475.7;-20361.5,64.7,-3415.7;-20360.5,64.7,-3355.7;-20359.6,64.7,-3295.7;-20358.6,64.7,-3235.7;-20357.7,64.7,-3175.8;-20356.7,64.7,-3115.8;-20355.7,64.7,-3055.8;-20354.7,64.7,-2995.8;-20353.8,64.7,-2935.8;-20352.8,64.7,-2875.8;-20351.8,64.7,-2815.8;",
            "-20350.8,64.7,-2755.8;-20349.8,64.7,-2695.8;-20348.8,64.7,-2635.8;-20347.8,64.7,-2575.8;-20346.8,64.7,-2515.8;-20345.8,64.7,-2455.9;-20344.7,64.7,-2395.9;-20343.7,64.7,-2335.9;-20342.6,64.7,-2275.9;-20341.5,64.7,-2215.9;-20340.5,64.7,-2155.9;-20339.4,64.7,-2095.9;",
            "-20338.3,64.7,-2035.9;-20337.3,64.7,-1975.9;-20336.2,64.7,-1915.9;-20335.2,64.7,-1855.9;-20334.2,64.7,-1796;-20333.1,64.7,-1736;-20332.1,64.7,-1676;-20331,64.7,-1616;-20329.9,64.7,-1556;-20328.8,64.7,-1496;-20327.7,64.7,-1436;-20326.7,64.7,-1376;",
            "-20325.6,64.7,-1316;-20324.5,64.7,-1256;-20323.4,64.7,-1196.1;-20322.3,64.7,-1136.1;-20321.2,64.7,-1076.1;-20320.2,64.7,-1016.1;-20319.1,64.7,-956.1;-20318.1,64.7,-896.1;-20317,64.7,-836.1;-20315.9,64.7,-776.1;-20314.9,64.7,-716.1;-20313.8,64.7,-656.1;",
            "-20312.7,64.7,-596.1;-20311.6,64.7,-536.2;-20310.5,64.7,-476.2;-20309.3,64.7,-416.2;-20308.1,64.7,-356.2;-20307,64.7,-296.2;-20305.8,64.7,-236.2;-20304.6,64.7,-176.2;-20303.3,64.7,-116.2;-20302.1,64.7,-56.3;-20301,64.7,3.7;-20300.2,64.7,63.7;",
            "-20299.4,64.7,123.7;-20298.6,64.7,183.7;-20297.8,64.7,243.7;-20297,64.7,303.7;-20296.2,64.7,363.7;-20295.3,64.7,423.7;-20294.5,64.7,483.7;-20293.7,64.7,543.7;-20292.9,64.7,603.7;-20292,64.7,663.7;-20291.2,64.7,723.7;-20290.3,64.7,783.7;",
            "-20290.2,64.7,843.7;-20290.4,64.7,903.7;-20291.3,64.7,963.7;-20292.8,64.6,1023.6;-20293.8,64.2,1083.6;-20294.8,64.2,1143.6;-20296.8,64.2,1203.6;-20300.5,64.2,1263.5;-20305.6,64.2,1323.3;-20312.7,64.2,1382.8;-20321.3,64.2,1442.2;-20331.5,64.2,1501.3;",
            "-20343.5,64.2,1560.1;-20356.9,64.2,1618.6;-20371.8,64.2,1676.7;-20387.3,64.2,1734.7;-20404.6,64.2,1792.1;-20423.2,64.2,1849.2;-20443.2,64.2,1905.8;-20464.7,64.2,1961.8;-20487.3,64.2,2017.3;-20511.3,64.2,2072.4;-20537,64.2,2126.6;-20563.4,64.2,2180.4;",
            "-20590.1,64.2,2234.2;-20618.4,64.2,2287.1;-20646.7,64.2,2340;-20674.2,64.2,2393.3;-20701.3,64.2,2446.8;-20727.6,64.2,2500.8;-20752.8,64.2,2555.2;-20776.8,64.2,2610.2;-20799.6,64.2,2665.7;-20819.4,64.2,2722.4;-20837,64.2,2779.7;-20852.7,64.2,2837.6;",
            "-20866.6,64.2,2896;-20880.1,64.2,2954.5;-20893,64.2,3013.1;-20904.8,64.2,3071.9;-20914.4,64.2,3131.1;-20922.3,64.2,3190.6;-20929.4,64.2,3250.2;-20934.7,64.2,3309.9;-20937.9,64.2,3369.8;-20939.7,64.2,3429.8;-20940.9,64.2,3489.8;-20941.4,64.2,3549.8;",
            "-20939.6,64.2,3609.8;-20937.2,64.2,3669.7;-20934.3,64.2,3729.7;-20929.6,64.2,3789.5;-20923.2,64.2,3849.1;-20916.2,64.2,3908.7;-20907.2,64.2,3968;-20896.4,64.2,4027.1;-20884.3,64.2,4085.8;-20871.7,64.2,4144.5;-20858.8,64.2,4203.1;-20843.6,64.2,4261.1;",
            "-20828.1,64.2,4319.1;-20810.9,64.2,4376.6;-20791.5,64.2,4433.4;-20768.9,64.2,4488.9;-20745.3,64.2,4544.1;-20720.8,64.2,4598.9;-20694.9,64.2,4653;-20668.5,64.2,4706.9;-20642.2,64.2,4760.8;-20615.2,64.2,4814.4;-20587.1,64.2,4867.4;-20557,64.2,4919.3;",
            "-20526.9,64.2,4971.2;-20495.6,64.2,5022.4;-20462.4,64.2,5072.4;-20427.4,64.2,5121.1;-20391,64.2,5168.8;-20352.3,64.2,5214.7;-20313.6,64.2,5260.5;-20274,64.2,5305.6;-20233.6,64.2,5349.9;-20192.1,64.2,5393.3;-20148.6,64.2,5434.6;-20104.6,64.2,5475.4;",
            "-20060.6,64.2,5516.2;-20016.5,64.2,5556.9;-19971.2,64.2,5596.2;-19924.9,64.2,5634.4;-19878,64.2,5671.8;-19830.2,64.2,5708;-19781.6,64.2,5743.2;-19731.9,64.2,5776.8;-19681.9,64.2,5810;-19631.8,64.2,5843;-19581.8,64.2,5876.1;-19531.2,64.2,5908.4;",
            "-19479.7,64.2,5939.3;-19428.2,64.2,5970;-19376.7,64.2,6000.8;-19325.1,64.2,6031.5;-19273.6,64.2,6062.2;-19221.9,64.2,6092.6;-19169.7,64.2,6122.2;-19117.5,64.2,6151.8;-19065.3,64.2,6181.4;-19013,64.2,6210.9;-18960.3,64.2,6239.4;-18907.4,64.2,6267.8;",
            "-18854.5,64.2,6296.1;-18801.1,64.2,6323.6;-18747.3,64.2,6350;-18692.9,64.2,6375.3;-18638.5,64.2,6400.6;-18584,64.2,6425.8;-18529.6,64.2,6451;-18475.1,64.2,6476.2;-18420.7,64.2,6501.4;-18366.2,64.2,6526.6;-18311.7,64.2,6551.7;-18256.7,64.2,6575.7;",
            "-18201.2,64.2,6598.4;-18145.3,64.2,6620.4;-18089.4,64.2,6642.1;-18033.3,64.2,6663.3;-17977,64.2,6684;-17920.6,64.2,6704.6;-17864.3,64.2,6725.3;-17808,64.2,6745.9;-17751.6,64.2,6766.6;-17695.3,64.2,6787.2;-17638.9,64.2,6807.8;-17582.6,64.2,6828.4;",
            "-17526.2,64.2,6849;-17469.8,64.2,6869.5;-17413.1,64.2,6889.2;-17356,64.2,6907.5;-17298.8,64.2,6925.7;-17241.6,64.2,6943.8;-17184.4,64.2,6961.8;-17126.8,64.2,6978.6;-17068.9,64.2,6994.3;-17010.7,64.2,7009.1;-16952.5,64.2,7023.6;-16894.3,64.2,7038.1;",
            "-16836.1,64.2,7052.6;-16777.8,64.2,7067;-16719.6,64.2,7081.5;-16661.4,64.2,7096;-16603.2,64.2,7110.5;-16544.9,64.2,7125;-16486.7,64.2,7139.5;-16428.5,64.2,7153.9;-16370.3,64.2,7168.5;-16311.9,64.2,7182.4;-16253.1,64.2,7194.2;-16194.1,64.2,7205.4;",
            "-16135.1,64.2,7216;-16076,64.2,7226.6;-16017,64.2,7237.1;-15957.9,64.2,7247.7;-15898.8,64.2,7258.3;-15839.8,64.2,7268.8;-15780.7,64.2,7279.4;-15721.6,64.2,7289.9;-15662.6,64.2,7300.5;-15603.5,64.2,7311.1;-15544.4,64.2,7321.4;-15485.1,64.2,7330.1;",
            "-15425.6,64.2,7338.4;-15366.2,64.2,7346.6;-15306.8,64.2,7354.8;-15247.2,64.2,7362.2;-15187.6,64.2,7368.9;-15128,64.2,7375.5;-15068.3,64.2,7381.5;-15008.5,64.2,7387.1;-14948.8,64.2,7392.6;-14888.9,64.2,7397.1;-14829,64.2,7400.2;-14769.1,64.2,7403.5;",
            "-14709.3,64.2,7408.2;-14649.5,64.2,7413.5;-14589.8,64.2,7418.7;-14530,64.2,7424;-14470.2,64.2,7429.2;-14410.4,64.2,7434.4;-14350.7,64.2,7439.6;-14290.9,64.2,7444.9;-14231.1,64.2,7450.1;-14171.3,64.2,7455.3;-14111.6,64.2,7460.5;-14051.8,64.2,7465.8;",
            "-13992,64.2,7471;-13932.3,64.2,7476.2;-13872.5,64.2,7481.4;-13812.7,64.2,7486.6;-13752.9,64.2,7491.7;-13693.2,64.2,7496.9;-13633.4,64.2,7502.1;-13573.6,64.2,7507.3;-13513.8,64.2,7512.5;-13454,64.2,7517.3;-13394.1,64.2,7520.8;-13334.2,64.2,7524;",
            "-13274.3,64.2,7527.1;-13214.3,64.2,7529.1;-13154.3,64.2,7530.1;-13094.3,64.2,7531.1;-13034.3,64.2,7531.9;-12974.3,64.2,7531.6;-12914.4,64.2,7530.7;-12854.4,64.2,7529.8;-12794.4,64.2,7528.5;-12734.4,64.2,7526.1;-12674.5,64.2,7523.3;-12614.6,64.2,7520.5;",
            "-12554.6,64.2,7517.7;-12494.7,64.2,7514.5;-12434.8,64.2,7510.4;-12375,64.2,7506;-12315.2,64.2,7501.7;-12255.3,64.2,7497.4;-12195.5,64.2,7492.3;-12135.8,64.2,7486.7;-12076.1,64.2,7481.1;-12016.3,64.2,7475.4;-11956.6,64.2,7469.8;-11896.9,64.2,7464.2;",
            "-11837.1,64.2,7458.5;-11777.4,64.2,7452.9;-11717.6,64.2,7447.3;-11657.9,64.2,7441.6;-11598.2,64.2,7435.9;-11538.5,64.2,7430.2;-11478.7,64.2,7424.5;-11419,64.2,7418.9;-11359.3,64.2,7413.2;-11299.5,64.2,7407.7;-11239.8,64.2,7402.2;-11180,64.2,7396.8;",
            "-11120.3,64.2,7391.4;-11060.5,64.2,7386;-11000.7,64.2,7380.6;-10941,64.2,7375.2;-10881.2,64.2,7369.8;-10821.5,64.2,7364.5;-10761.7,64.2,7359.1;-10701.9,64.2,7353.8;-10642.2,64.2,7348.5;-10582.4,64.2,7343.2;-10522.6,64.2,7337.9;-10462.9,64.2,7332.6;",
            "-10403.1,64.2,7327.4;-10343.3,64.2,7322.1;-10283.6,64.2,7316.9;-10223.8,64.2,7311.7;-10164,64.2,7306.5;-10104.2,64.2,7301.4;-10044.5,64.2,7296.3;-9984.7,64.2,7291.2;-9924.9,64.2,7286.1;-9865.1,64.2,7281.1;-9805.3,64.2,7276;-9745.5,64.2,7271;",
            "-9685.7,64.2,7266;-9625.9,64.2,7261;-9566.1,64.2,7256;-9506.4,64.2,7251;-9446.6,64.2,7246.1;-9386.8,64.2,7241.2;-9327,64.2,7236.3;-9267.2,64.2,7231.4;-9207.4,64.2,7226.5;-9147.6,64.2,7221.6;-9087.8,64.2,7216.8;-9028,64.2,7211.9;",
            "-8968.1,64.2,7207.1;-8908.3,64.2,7202.2;-8848.5,64.2,7197.4;-8788.7,64.2,7192.6;-8728.9,64.2,7187.8;-8669.1,64.2,7183;-8609.4,64.2,7177.7;-8549.6,64.2,7172;-8489.9,64.2,7166.3;-8430.2,64.2,7160.7;-8370.4,64.2,7155;-8310.7,64.2,7149.4;",
            "-8251,64.2,7143.7;-8191.2,64.2,7138.1;-8131.5,64.2,7132.5;-8071.7,64.2,7126.8;-8012,64.2,7121.2;-7952.3,64.2,7115.6;-7892.5,64.2,7110;-7832.9,64.2,7103.2;-7773.4,64.2,7095.5;-7714,64.2,7087.2;-7654.6,64.2,7078.5;-7595.4,64.2,7069.1;",
            "-7536.2,64.2,7059.4;-7477,64.2,7049.3;-7418.2,64.2,7037.4;-7359.5,64.2,7025.2;-7300.7,64.2,7013;-7242.1,64.2,7000.4;-7183.8,64.2,6986.1;-7125.6,64.2,6971.6;-7067.4,64.2,6957;-7009.5,64.2,6941.2;-6952.1,64.2,6923.7;-6894.9,64.2,6905.6;",
            "-6837.7,64.2,6887.4;-6780.9,64.2,6868.1;-6724.8,64.2,6846.9;-6668.8,64.2,6825.3;-6612.8,64.2,6803.8;-6556.9,64.2,6782;-6501.8,64.2,6758.3;-6447,64.2,6733.7;-6392.5,64.2,6708.7;-6338,64.2,6683.6;-6284,64.2,6657.5;-6230.4,64.2,6630.5;",
            "-6177.5,64.2,6602.1;-6124.9,64.2,6573.3;-6072.7,64.2,6543.6;-6021.1,64.2,6513;-5970.1,64.2,6481.4;-5919.3,64.2,6449.6;-5868.4,64.2,6417.8;-5817.5,64.2,6385.9;-5766.7,64.2,6354.1;-5716.5,64.2,6321.3;-5666.8,64.2,6287.6;-5617.5,64.2,6253.4;",
            "-5568.6,64.2,6218.7;-5519.7,64.2,6183.9;-5470.8,64.2,6149.1;-5422.2,64.2,6113.8;-5374.8,64.2,6077.2;-5328.3,64.2,6039.2;-5282.3,64.2,6000.7;-5236.4,64.2,5962;-5190.5,64.2,5923.4;-5144.6,64.2,5884.8;-5099.4,64.2,5845.3;-5055.2,64.2,5804.7;",
            "-5012.1,64.2,5763;-4970.7,64.2,5719.5;-4929.8,64.2,5675.7;-4888.5,64.2,5632.2;-4847.4,64.2,5588.5;-4807.6,64.2,5543.5;-4767.8,64.2,5498.6;-4728.1,64.2,5453.6;-4688.5,64.2,5408.6;-4649.3,64.2,5363.1;-4610.2,64.2,5317.6;-4572.4,64.2,5271;",
            "-4535.4,64.2,5223.8;-4499,64.2,5176.1;-4463.8,64.2,5127.5;-4429.9,64.2,5078;-4396,64.2,5028.5;-4362.1,64.2,4979;-4328.2,64.2,4929.5;-4294.5,64.2,4879.8;-4262.4,64.2,4829.1;-4230.6,64.2,4778.3;-4199.4,64.2,4727;-4169.6,64.2,4675;",
            "-4139.7,64.2,4622.9;-4109.9,64.2,4570.8;-4080.1,64.2,4518.7;-4051.1,64.2,4466.3;-4023.3,64.2,4413.1;-3996.6,64.2,4359.4;-3970.2,64.2,4305.4;-3944,64.2,4251.5;-3917.8,64.2,4197.5;-3893.6,64.2,4142.6;-3871.1,64.2,4087;-3849.5,64.2,4031;",
            "-3828.1,64.2,3974.9;-3806.6,64.2,3918.9;-3785.2,64.2,3862.9;-3764.8,64.2,3806.5;-3745.8,64.2,3749.5;-3728.2,64.2,3692.2;-3711.4,64.2,3634.6;-3694.5,64.2,3577;-3677.7,64.2,3519.4;-3661.4,64.2,3461.7;-3647,64.2,3403.4;-3634.1,64.2,3344.8;",
            "-3623.2,64.2,3285.8;-3612.6,64.2,3226.8;-3602.1,64.2,3167.7;-3591.5,64.2,3108.6;-3581,64.2,3049.6;-3570.5,64.2,2990.5;-3560.2,64.2,2931.4;-3551.4,64.2,2872;-3543.2,64.2,2812.6;-3534.9,64.2,2753.2;-3527.8,64.2,2693.6;-3522.9,64.2,2633.8;",
            "-3518.5,64.2,2573.9;-3514.4,64.2,2514.1;-3510.4,64.2,2454.2;-3508,64.2,2394.3;-3506.6,64.2,2334.3;-3505.3,64.2,2274.3;-3504,64.2,2214.3;-3503.1,64.2,2154.3;-3503.4,64.2,2094.3;-3503.7,64.2,2034.3;-3504.1,64.2,1974.3;-3504.6,64.2,1914.3;",
            "-3505,64.2,1854.3;-3505.5,64.2,1794.3;-3506,64.2,1734.3;-3507.2,64.2,1674.3;-3509.4,64.2,1614.4;-3511.7,64.2,1554.4;-3515,64.2,1494.5;-3518.7,64.2,1434.6;-3522.4,64.2,1374.7;-3526.1,64.2,1314.9;-3529.7,64.2,1255;-3533.3,64.2,1195.1;",
            "-3536.4,67.9,1135.3;-3539.2,73.9,1075.6;-3541.2,79.9,1016;-3542.2,85.9,956.3;-3542.4,92,896.6;-3541.7,98,836.9;-3540.7,104.1,777.2;-3539.6,110.1,717.5;-3538.6,116.1,657.8;-3537.5,122.2,598.2;-3536.5,128.2,538.5;-3535.7,134.3,478.8;",
            "-3535.2,139.8,419;-3534.9,139.1,359;-3534.6,139.1,299;-3534.3,139.1,239;-3534.1,139.1,179;-3533.9,139.1,119;-3533.7,139.1,59;-3533.5,139.1,-1;-3533.3,139.1,-61;-3533.1,139.1,-121",
        }),
    },
}

local function decodePath(def)
    local pts = {}
    for x, y, z in string.gmatch(def.data, "(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)") do
        local vx, vy, vz = tonumber(x), tonumber(y), tonumber(z)
        if vx and vy and vz then
            pts[#pts + 1] = { n = #pts + 1, pos = Vector3.new(vx, vy, vz) }
        end
    end
    return pts
end

local function buildBuiltins()
    local out = {}
    for _, def in ipairs(BUILTIN_PATHS) do
        local pts = decodePath(def)
        if #pts >= 8 then
            local lane = finishLane(def.name, pts, def.closed, false)
            lane.builtin = true
            out[#out + 1] = lane
        end
    end
    return out
end

function World.BuildLanes()
    World.lanes = {}
    World.paths = {}
    World.laneWidth = 18
    local total = 0
    local folder = Workspace:FindFirstChild("TrafficLanes")
    if folder then
        for _, laneFolder in ipairs(folder:GetChildren()) do
            local pts = {}
            for _, wp in ipairs(laneFolder:GetChildren()) do
                local p = partOf(wp)
                if p then
                    local n = tonumber(wp.Name:match("%-?%d+"))
                    pts[#pts + 1] = { n = n or (#pts + 1), pos = p.Position, inst = p }
                end
            end
            if #pts >= 3 then
                table.sort(pts, function(a, b) return a.n < b.n end)
                World.lanes[#World.lanes + 1] = finishLane(laneFolder.Name, pts)
                total = total + #pts
            end
        end
        table.sort(World.lanes, function(a, b) return a.name < b.name end)
    end

    -- Drivable paths = the lanes themselves, plus the white line between each
    -- neighbouring pair (Lane 1.5, Lane 2.5, ...).  Riding a line puts traffic
    -- on BOTH sides of you without ever occupying a lane a car is driving in.
    local widthSum, widthN = 0, 0
    for i, lane in ipairs(World.lanes) do
        World.paths[#World.paths + 1] = lane
        local nxt = World.lanes[i + 1]
        if nxt then
            local blend = buildBlend(lane, nxt, string.format("Lane %.1f", i + 0.5))
            if blend then
                World.paths[#World.paths + 1] = blend
                widthSum, widthN = widthSum + blend.width, widthN + 1
            end
        end
    end
    if widthN > 0 then
        World.laneWidth = widthSum / widthN
    elseif World.srvWidth then
        -- No blends to measure, because TrafficLanes is not here yet.  The
        -- server already told us the real spacing, so keep it rather than
        -- falling back to the placeholder set at the top of this function.
        World.laneWidth = World.srvWidth
    end
    World.wpTotal = total

    -- Baked-in routes are always available, even with no TrafficLanes folder at
    -- all - that is the whole point of recording them.
    World.builtins = World.builtins or buildBuiltins()
    for _, lane in ipairs(World.builtins) do
        World.paths[#World.paths + 1] = lane
    end

    -- a path added this session survives map rebuilds too
    if World.recordedLane then World.paths[#World.paths + 1] = World.recordedLane end
    -- and so do the server's roads, which cost 1200 raycasts to build
    for _, lane in ipairs(World.roads or {}) do
        World.paths[#World.paths + 1] = lane
    end

    -- World.paths was just REPLACED, not updated.  Anything holding an index
    -- into the old array is now pointing at a different lane, or past the end
    -- of one.  route lives further down this file and cannot be touched from
    -- here, so publish a generation instead and let the drive loop re-acquire.
    --
    -- ONLY when the shape actually changed.  The 3s retry calls this over and
    -- over while TrafficLanes has not streamed in, and every bump costs the
    -- drive a re-acquire - which snaps the spline cursor to the nearest
    -- waypoint and lurches the car.  Identical shape means index i still names
    -- the same lane, so there is nothing to re-acquire.
    local sig = string.format("%d/%d/%d/%s/%s", #World.lanes, #World.paths, total,
        World.paths[1] and World.paths[1].name or "-",
        World.paths[#World.paths] and World.paths[#World.paths].name or "-")
    if sig ~= World.pathsSig then
        World.pathsSig = sig
        World.pathsGen = (World.pathsGen or 0) + 1
    end

    return #World.lanes, total
end

-- ---------------------------------------------------- LANES FROM THE SERVER
-- RF/PoliceRoadLanes hands back the road as three arrays of 412 {x,y,z}
-- triples.  That is the same geometry TrafficLanes holds, except it is always
-- there: it does not depend on a workspace folder having streamed in, which is
-- what left the dodge running on "no lane data" and hunting for walls.
--
-- Used ONLY for the lateral edge limit, never as a driving path.  Every Y in
-- the reply is the same 65.0147, a flat plan height rather than real terrain,
-- so anything that drove it would fly.  The band is a horizontal question, so
-- the limiter measures in XZ and the Y never matters.
function World.FetchPoliceLanes()
    local rs = game:GetService("ReplicatedStorage")
    local ok, rf = pcall(function() return rs:FindFirstChild("RF/PoliceRoadLanes", true) end)
    if not ok or not rf or not rf:IsA("RemoteFunction") then return 0 end
    local ok2, res = pcall(function() return rf:InvokeServer() end)
    if not ok2 or type(res) ~= "table" then return 0 end

    local out = {}
    for _, arr in ipairs(res) do
        if type(arr) == "table" and #arr >= 8 then
            local pts = {}
            for i, p in ipairs(arr) do
                if type(p) == "table" and tonumber(p[1]) and tonumber(p[3]) then
                    pts[#pts + 1] = { n = i, pos = Vector3.new(p[1], p[2] or 0, p[3]) }
                end
            end
            if #pts >= 8 then
                local a, b = pts[1].pos, pts[#pts].pos
                local gap = (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
                out[#out + 1] = { points = pts, loop = gap < 2000, name = "Police lane" }
            end
        end
    end
    if #out < 2 then return 0 end
    World.policeLanes = out

    -- Measured, not assumed.  It comes out at about 13.4 here; the default was
    -- 18, and every clearance derived from it was a fifth too generous.
    local a, b = out[1].points[1].pos, out[2].points[1].pos
    local w = (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
    -- Kept separately as well: World.BuildLanes resets laneWidth to its 18
    -- stud placeholder on every call, and when TrafficLanes has not streamed in
    -- there are no blends to measure it back from.  Without this the 3s retry
    -- threw away the real number three seconds after we asked for it.
    if w > 4 and w < 60 then
        World.srvWidth = w
        World.laneWidth = w
    end
    return #out
end

-- The server's road, turned into something the car can actually drive.
--
-- World.policeLanes already holds three ~412 point arrays of real road, and it
-- arrives whether or not workspace.TrafficLanes has streamed in - which is
-- exactly what makes it worth having.  It is rejected as a driving path for one
-- reason only: every Y in the reply is the same flat plan height, so anything
-- that drove it would fly.  Correcting Y is a raycast per point.
--
-- Four things this has to get right:
--   * ~1200 raycasts is a visible hitch, so it yields every 50
--   * route.groundParams is SHARED and mutated in place by the drive loop's own
--     casts every frame - a yielding pass that borrowed it would corrupt the
--     filter list mid-drive, so this owns its own
--   * a raycast only hits geometry that has streamed in, so a point that misses
--     keeps the plan height as a HINT; drivePosition re-grounds every frame
--     anyway, which is the same reason Normal ride height works at all
--   * named Road, never Lane - a saved config pointing at "Lane 1" must not
--     silently bind to a different line
function World.BuildRoads()
    if World.roads then return #World.roads end
    local src = World.policeLanes
    if type(src) ~= "table" or #src < 2 then return 0 end

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true          -- matching route.groundParams: a road over
    rp.FilterDescendantsInstances = { S.Car.Model, LocalPlayer.Character }

    local out, cast = {}, 0
    for li, lane in ipairs(src) do
        local pts, miss = {}, 0
        for i, p in ipairs(lane.points) do
            local hit = Workspace:Raycast(p.pos + Vector3.new(0, 120, 0),
                Vector3.new(0, -400, 0), rp)
            if hit then
                pts[#pts + 1] = { n = i, pos = Vector3.new(p.pos.X, hit.Position.Y, p.pos.Z) }
            else
                -- DROPPED, never kept.  The reply's Y is a flat plan height
                -- roughly 40 studs above the tarmac, and a point left at it is
                -- a vertical jolt when the car reaches it - and worse, since
                -- NearestIndex measures along the ground, a floating stretch
                -- reads as zero distance away and pulls re-acquires onto it.
                miss = miss + 1
            end
            cast = cast + 1
            if cast % 50 == 0 then task.wait() end
        end
        -- Streaming decides how much of this we can see, and at spawn the
        -- answer is almost none.  A road we only half found is worse than no
        -- road, so take it whole or not at all and try again later.
        local total = #lane.points
        if #pts >= 100 and miss <= total * 0.10 then
            out[#out + 1] = finishLane("Road " .. li, pts, lane.loop)
        end
    end
    -- Not cached on failure: the retry below runs again once more of the map
    -- is in, which is usually the moment the player has actually driven there.
    if #out < #src then return 0 end
    World.roads = out
    -- Appended rather than rebuilt: an existing route.laneIdx keeps pointing at
    -- the same lane, so nothing driving has to re-acquire.
    for _, lane in ipairs(out) do
        World.paths[#World.paths + 1] = lane
    end
    return #out
end

-- how close a traffic car has to be, laterally, to matter
function World.ScoreWidth()   return math.clamp(World.laneWidth * 0.75, 8, 26) end
function World.CollideWidth() return math.clamp(World.laneWidth * 0.32, 3, 9) end

function World.LaneByName(name)
    for i, l in ipairs(World.paths) do
        if l.name == name then return i, l end
    end
    return nil
end

-- nearest waypoint index on a lane
function World.NearestIndex(lane, pos)
    local bestI, bestD = 1, math.huge
    for i, p in ipairs(lane.points) do
        -- XZ only.  Ride height is not distance along a road: measured in 3D, a
        -- car hovering 150 studs up reads as 150 studs from every waypoint of
        -- every path, so scorePath's 130 stud gate rejected all of them and
        -- "Chase the busiest lane" quietly stopped working.  flatDist lives
        -- further down the file, so the arithmetic is inlined here.
        local dx, dz = p.pos.X - pos.X, p.pos.Z - pos.Z
        local d = math.sqrt(dx * dx + dz * dz)
        if d < bestD then bestI, bestD = i, d end
    end
    return bestI, bestD
end

-- Which way a lane runs at point i, flattened.  nil when it cannot be told.
function World.LaneDir(lane, i)
    local pts = lane.points
    if not pts or #pts < 2 then return nil end
    local a = pts[i]
    local b = pts[World.Step(lane, i, 1)]
    if not a or not b then return nil end
    local d = Vector3.new(b.pos.X - a.pos.X, 0, b.pos.Z - a.pos.Z)
    if d.Magnitude < 0.1 then return nil end
    return d.Unit
end

-- `dir` is optional, and every re-acquire during a drive should pass it.
--
-- Ranking on distance alone means a path running the OTHER WAY down the same
-- tarmac is a perfectly good candidate.  Land on one and the spline tangent
-- flips, A.Rotate turns the body to match, and the car does a 180 - then the
-- next re-acquire picks the original again and it turns back.  That was always
-- possible with the baked routes; adding three server roads over the same road
-- made it frequent.  scorePath has had this test since it was written; this is
-- the same idea, one layer down.
function World.NearestLane(pos, dir)
    local bestLane, bestIdx, bestD = nil, 1, math.huge
    for li, lane in ipairs(World.paths) do
        local i, d = World.NearestIndex(lane, pos)
        if d < bestD then
            local ok = true
            if dir then
                local ld = World.LaneDir(lane, i)
                ok = (ld == nil) or (ld:Dot(dir) > 0.3)
            end
            if ok then bestLane, bestIdx, bestD = li, i, d end
        end
    end
    -- Nothing runs our way at all: take the nearest regardless rather than
    -- returning nil, which would strand the drive with no lane to follow.
    if not bestLane and dir then return World.NearestLane(pos) end
    return bestLane, bestIdx, bestD
end

function World.Step(lane, i, step)
    local n = #lane.points
    local j = i + step
    if lane.loop then
        j = ((j - 1) % n) + 1
    else
        j = math.clamp(j, 1, n)
    end
    return j
end

function World.Traffic()
    if tick() - World.lastTraffic > 0.25 then
        World.lastTraffic = tick()
        World.traffic = {}
        local folder = Workspace:FindFirstChild("TrafficFolder")
        if folder then
            for _, c in ipairs(folder:GetChildren()) do
                local p = partOf(c)
                if p then World.traffic[#World.traffic + 1] = { inst = c, part = p } end
            end
        end
    end
    return World.traffic
end

--============================================================================
-- ESP
--============================================================================
local ESP = { pool = {}, targets = {}, highlights = {}, lastScan = 0 }
ESP.holder = new("Folder", { Name = "AT_Highlights", Parent = AdornHolder })

ESP.rayParams = RaycastParams.new()
ESP.rayParams.FilterType = Enum.RaycastFilterType.Exclude
ESP.rayParams.IgnoreWater = true

local function makeDrawing()
    local box = new("Frame", {
        BackgroundColor3 = THEME.Accent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Visible = false, ZIndex = 2, Parent = ScreenESP,
    })
    local bs = new("UIStroke", { Color = THEME.Accent, Thickness = 1.2, Transparency = 0, Parent = box })
    -- world overlays keep their own radius: the menu "Corner style" multiplier
    -- must not rescale an ESP box
    corner(box, 4, true)
    -- "Brackets + fill" ground-contact wash.  A UIGradient MULTIPLIES the fill,
    -- so the colour still comes from t.color; only the alpha ramp lives here.
    -- It is inert in the other two styles because the box sits at Transparency 1.
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = box,
    })
    -- Dark backing so a box survives a white road.  This stays a child Frame
    -- rather than a second UIStroke on `box`: Roblox does not reliably
    -- composite two UIStrokes on one GuiObject, and `box` already owns one.
    -- Offsets are whole pixels - UDim.Offset is an int, so a 1.5 here would be
    -- rounded by the engine and the inset would stop being symmetric.
    local shade = new("Frame", {
        Size = UDim2.new(1, 4, 1, 4), Position = UDim2.fromOffset(-2, -2), BackgroundTransparency = 1,
        ZIndex = 1, Parent = box,
    })
    new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.58, Parent = shade })
    corner(shade, 5, true)

    -- Eight corner arms, positioned by SCALE with an AnchorPoint, so they track
    -- the box for free: the render loop still writes only box.Position/Size.
    -- Being children of `box` they are also hidden by hideDrawing unchanged.
    local arm = {}
    for i = 1, 4 do
        local ax, ay = (i == 2 or i == 4) and 1 or 0, (i >= 3) and 1 or 0
        arm[#arm + 1] = new("Frame", {
            AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, 0, ay, 0),
            Size = UDim2.new(0.26, 0, 0, 2), BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0, Visible = false, ZIndex = 3, Parent = box,
        })
        arm[#arm + 1] = new("Frame", {
            AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, 0, ay, 0),
            Size = UDim2.new(0, 2, 0.26, 0), BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0, Visible = false, ZIndex = 3, Parent = box,
        })
    end

    -- The labels stay direct children of ScreenESP (re-parenting them under the
    -- box would change the per-frame positioning maths).  They get their own
    -- plate instead: AutomaticSize.X plus the existing centre AnchorPoints means
    -- the width just works and Size is never written again.
    local name = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = TH.get("Void"), BackgroundTransparency = 0.35,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.Text,
        Size = UDim2.fromOffset(0, 15), AutomaticSize = Enum.AutomaticSize.X, Visible = false,
        TextStrokeTransparency = 0.55, TextStrokeColor3 = Color3.new(0, 0, 0), ZIndex = 3, Parent = ScreenESP,
    })
    corner(name, 5, true)
    pad(name, 6, 6, 1, 1)
    local dist = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = TH.get("Void"), BackgroundTransparency = 0.35,
        Font = Enum.Font.RobotoMono, TextSize = 10, TextColor3 = THEME.Sub,
        Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, Visible = false,
        TextStrokeTransparency = 0.65, TextStrokeColor3 = Color3.new(0, 0, 0), ZIndex = 3, Parent = ScreenESP,
    })
    corner(dist, 5, true)
    pad(dist, 6, 6, 1, 1)

    local tracer = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
        BackgroundTransparency = 0.25, Size = UDim2.fromOffset(0, 1), Visible = false, ZIndex = 1, Parent = ScreenESP,
    })
    -- The tracer frame is already rotated along its own length, so a gradient on
    -- its local X axis tapers every tracer from faint-at-the-origin to solid-at-
    -- the-target for ONE instance and zero per-frame maths.  This is what stops
    -- 60 tracers reading as a screen full of spaghetti.
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.95),
            NumberSequenceKeypoint.new(0.35, 0.75),
            NumberSequenceKeypoint.new(1, 0.10),
        }),
        Parent = tracer,
    })

    -- col / fade / brk / lbl / dm are the change-gates for the render loop.
    -- Without them, 8 arms x 150 pooled drawings x 60fps is 72,000 writes/sec.
    return {
        box = box, stroke = bs, name = name, dist = dist, tracer = tracer, used = false,
        shade = shade, arm = arm, col = nil, fade = nil, brk = nil, lbl = nil, dm = nil,
    }
end

local function getDrawing(i)
    local d = ESP.pool[i]
    if not d then
        d = makeDrawing()
        ESP.pool[i] = d
    end
    return d
end

local function hideDrawing(d)
    if d.box.Visible then d.box.Visible = false end
    if d.name.Visible then d.name.Visible = false end
    if d.dist.Visible then d.dist.Visible = false end
    if d.tracer.Visible then d.tracer.Visible = false end
end

-- 3D box pool.  SelectionBox draws the edges of a real world-space box and
-- BoxHandleAdornment fills it; both follow the adornee, so nothing needs
-- projecting per frame.  Kept separate from the 2D drawing pool because the
-- styles are mutually exclusive and one pool must be able to go fully dark.
ESP.box3 = { sel = {}, fill = {}, used = 0 }

function ESP.Get3D(i)
    local b = ESP.box3.sel[i]
    if not b then
        b = new("SelectionBox", {
            Name = "AT_Box3", LineThickness = 0.045, SurfaceTransparency = 1,
            Transparency = 0.1, Visible = false, Parent = AdornHolder,
        })
        ESP.box3.sel[i] = b
    end
    local f = ESP.box3.fill[i]
    if not f then
        f = new("BoxHandleAdornment", {
            Name = "AT_Box3F", Transparency = 0.82, AlwaysOnTop = false, ZIndex = 0,
            Size = Vector3.new(1, 1, 1), Visible = false, Parent = AdornHolder,
        })
        ESP.box3.fill[i] = f
    end
    return b, f
end

function ESP.Hide3D(from)
    for i = from, #ESP.box3.sel do
        local b, f = ESP.box3.sel[i], ESP.box3.fill[i]
        if b and b.Visible then b.Visible = false b.Adornee = nil end
        if f and f.Visible then f.Visible = false f.Adornee = nil end
    end
end

-- ------------------------------------------------------------ TARGET SCANNER
local function addTarget(list, inst, kind, label, color)
    local p = partOf(inst)
    if not p then return end
    list[#list + 1] = { inst = inst, part = p, kind = kind, label = label, color = color }
end

function ESP.Scan()
    local list = {}
    local e = S.ESP

    if e.Cars then
        for _, m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") then
                local us = m.Name:find("_")
                if us then
                    local owner = m.Name:sub(1, us - 1)
                    local plr = Players:FindFirstChild(owner)
                    if plr and (plr ~= LocalPlayer or e.IncludeLocal) then
                        addTarget(list, m, "Car", m.Name:sub(us + 1) .. "  (" .. plr.DisplayName .. ")", ESPCOL.Car)
                    end
                end
            end
        end
    end

    if e.Traffic then
        for _, t in ipairs(World.Traffic()) do
            addTarget(list, t.inst, "Traffic", "Traffic", ESPCOL.Traffic)
        end
    end

    if e.Players then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer or e.IncludeLocal then
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    addTarget(list, char, "Player", plr.DisplayName, ESPCOL.Player)
                end
            end
        end
    end

    if e.Waypoints then
        -- Draw the paths that can actually be DRIVEN, not the game's waypoint
        -- parts: that means game lanes, the white lines between them, and any
        -- baked-in or recorded route.  Blends and recordings have no instance
        -- behind them, so these targets carry a plain position instead.
        local origin = Car.Position() or Camera.CFrame.Position
        local added = 0
        local activeName = S.Auto.ActivePathName

        local paths = {}
        for _, lane in ipairs(World.paths) do
            if lane.name == activeName then
                table.insert(paths, 1, lane)      -- active path first, never culled
            else
                paths[#paths + 1] = lane
            end
        end

        for li, lane in ipairs(paths) do
            local isActive = (lane.name == activeName)
            local col = isActive and THEME.Good or ESPCOL.Lane[((li - 1) % #ESPCOL.Lane) + 1]
            for _, p in ipairs(lane.points) do
                if added >= 110 then break end
                if (p.pos - origin).Magnitude < CONFIG.WaypointRange then
                    added = added + 1
                    list[#list + 1] = {
                        inst = p.inst, part = p.inst, pos = p.pos, kind = "Waypoint",
                        label = lane.name .. " #" .. tostring(p.n),
                        color = col, small = true, active = isActive,
                    }
                end
            end
        end
    end

    ESP.targets = list
end

-- ------------------------------------------------------------- HIGHLIGHTING
local function wantsHighlight(kind)
    local e = S.ESP
    if not (e.Highlights or e.Glow) then return false end
    if kind == "Waypoint" then return false end
    return true
end

function ESP.ClearHighlights()
    for inst, h in pairs(ESP.highlights) do
        pcall(function() h:Destroy() end)
    end
    ESP.highlights = {}
end

local function updateHighlights(sorted)
    local e = S.ESP
    local keep = {}
    if e.Master and (e.Highlights or e.Glow) then
        local n = 0
        for _, t in ipairs(sorted) do
            if n >= CONFIG.MaxHighlights then break end
            if wantsHighlight(t.kind) and t.inst then   -- virtual nodes have no adornee
                n = n + 1
                keep[t.inst] = t
                local h = ESP.highlights[t.inst]
                if not h or not h.Parent then
                    h = new("Highlight", { Name = "AT_HL", Adornee = t.inst, Parent = ESP.holder })
                    ESP.highlights[t.inst] = h
                end
                h.DepthMode = e.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
                h.OutlineColor = t.color
                h.FillColor = t.color
                if e.Glow then
                    -- n phase-offsets each target so 24 highlights breathe as a
                    -- travelling wave instead of strobing in lockstep.  The
                    -- shipped defaults (rate 3.00, depth 0.16) are the old
                    -- hardcoded numbers, so the speed and depth are unchanged -
                    -- only the per-target phase is new.
                    local pulse = 0.62 + math.sin(tick() * TH.opt.glowRate + n * 0.6) * TH.opt.glowDepth
                    h.FillTransparency = pulse
                    h.OutlineTransparency = e.Highlights and 0 or 0.55
                else
                    h.FillTransparency = 0.78
                    h.OutlineTransparency = 0
                end
            end
        end
    end
    for inst, h in pairs(ESP.highlights) do
        if not keep[inst] or not inst.Parent then
            pcall(function() h:Destroy() end)
            ESP.highlights[inst] = nil
        end
    end
end

-- ------------------------------------------------------------------- RENDER
local function refreshRayFilter()
    local ignore = { Camera }
    if LocalPlayer.Character then ignore[#ignore + 1] = LocalPlayer.Character end
    if S.Car.Model then ignore[#ignore + 1] = S.Car.Model end
    ESP.rayParams.FilterDescendantsInstances = ignore
end

local function visibleCheck(pos, targetInst)
    local origin = Camera.CFrame.Position
    local dir = pos - origin
    if dir.Magnitude < 1 then return true end
    local hit = Workspace:Raycast(origin, dir, ESP.rayParams)
    if not hit then return true end
    -- a virtual target (path node with no instance) is visible only if nothing
    -- at all stands between it and the camera
    if not targetInst then return false end
    return hit.Instance:IsDescendantOf(targetInst) or hit.Instance == targetInst
end

-- GetBoundingBox walks every part of a model, so cache the result relative to the
-- target primary part and just re-project it each frame
ESP.bbox = setmetatable({}, { __mode = "k" })

local function boundsOf(t)
    if not t.part then                       -- virtual node: a small marker box
        return CFrame.new(t.pos), Vector3.new(4, 4, 4)
    end
    if not t.inst or not t.inst:IsA("Model") then return t.part.CFrame, t.part.Size end
    local c = ESP.bbox[t.inst]
    if c then return t.part.CFrame * c.offset, c.size end
    local ok, cf, size = pcall(function()
        local a, b = t.inst:GetBoundingBox()
        return a, b
    end)
    if ok and cf and size then
        ESP.bbox[t.inst] = { offset = t.part.CFrame:ToObjectSpace(cf), size = size }
        return cf, size
    end
    return t.part.CFrame, t.part.Size
end

ESP.corners = {
    Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
    Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1),
}

bind(RunService.RenderStepped, function()
    local e = S.ESP
    if not e.Master then
        for _, d in ipairs(ESP.pool) do hideDrawing(d) end
        ESP.Hide3D(1)
        if next(ESP.highlights) then ESP.ClearHighlights() end
        return
    end

    if tick() - ESP.lastScan > CONFIG.ESPRefresh then
        ESP.lastScan = tick()
        ESP.Scan()
    end

    local camPos = Camera.CFrame.Position
    local vp = Camera.ViewportSize
    local og = TH.opt.originPt
    local originPt = (og == "Centre" and Vector2.new(vp.X * 0.5, vp.Y * 0.5))
        or (og == "Top" and Vector2.new(vp.X * 0.5, 0))
        or Vector2.new(vp.X * 0.5, vp.Y)

    -- resolved once per frame, compared per drawing, applied only on a change
    local style = TH.opt.boxStyle
    local is3D = (style == "3D" or style == "3D fill")
    local want3Fill = (style == "3D fill")
    -- a 3D style suppresses the whole 2D box; names and tracers are unaffected
    local wantArms = (not is3D) and (style ~= "Frame") or false
    local wantEdge = (not is3D) and (style ~= "Brackets") or false
    local wantFill = (not is3D) and (style == "Brackets + fill") or false
    local n3 = 0

    -- distance sort (cheap position read)
    local live = {}
    for _, t in ipairs(ESP.targets) do
        -- a target is either backed by a part, or is a bare world position
        local p = (t.part and t.part.Parent) and t.part.Position or (not t.part and t.pos or nil)
        if p then
            local d = (p - camPos).Magnitude
            if d <= e.MaxDistance then
                t.dist = d
                live[#live + 1] = t
            end
        end
    end
    table.sort(live, function(a, b) return a.dist < b.dist end)

    updateHighlights(live)

    if not e.ThroughWalls then refreshRayFilter() end

    local drawn = 0
    local occChecks = 0
    for _, t in ipairs(live) do
        if drawn >= CONFIG.MaxESPObjects then break end
        local cf, size = boundsOf(t)
        local center = cf.Position
        local sp, onScreen = Camera:WorldToViewportPoint(center)
        if onScreen and sp.Z > 0 then
            local show = true
            if not e.ThroughWalls and occChecks < 45 then
                occChecks = occChecks + 1
                show = visibleCheck(center, t.inst)
            end
            if show then
                -- project the bounding box
                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge
                local half = size * 0.5
                local any = false
                for _, c in ipairs(ESP.corners) do
                    local world = cf:PointToWorldSpace(Vector3.new(half.X * c.X, half.Y * c.Y, half.Z * c.Z))
                    local p, _ = Camera:WorldToViewportPoint(world)
                    if p.Z > 0 then
                        any = true
                        if p.X < minX then minX = p.X end
                        if p.Y < minY then minY = p.Y end
                        if p.X > maxX then maxX = p.X end
                        if p.Y > maxY then maxY = p.Y end
                    end
                end
                if any then
                    drawn = drawn + 1
                    local d = getDrawing(drawn)
                    local w = math.max(6, maxX - minX)
                    local h = math.max(6, maxY - minY)
                    if t.small then
                        w = math.clamp(w, 4, 26)
                        h = math.clamp(h, 4, 26)
                        minX, minY = sp.X - w / 2, sp.Y - h / 2
                    end

                    -- ---------------------------------------------- change gates
                    -- SHIP-BLOCKER: every colour below used to be reassigned per
                    -- drawing per frame.  With 8 bracket arms in the mix that is
                    -- 72,000 property writes a second at a full pool.  A pooled
                    -- slot reused for a different target simply fails the compare
                    -- and repaints once, so no explicit reset is needed.
                    if d.col ~= t.color then
                        d.col = t.color
                        d.stroke.Color = t.color
                        d.box.BackgroundColor3 = t.color
                        d.name.TextColor3 = t.color
                        d.tracer.BackgroundColor3 = t.color
                        for ai = 1, 8 do d.arm[ai].BackgroundColor3 = t.color end
                    end
                    if d.brk ~= style then
                        d.brk = style
                        d.stroke.Enabled = wantEdge
                        d.shade.Visible = wantEdge
                        d.box.BackgroundTransparency = wantFill and 0.82 or 1
                        for ai = 1, 8 do d.arm[ai].Visible = wantArms end

                        -- world-space box, adorned rather than projected
                        if is3D and t.inst and t.inst.Parent then
                            n3 = n3 + 1
                            local b3, f3 = ESP.Get3D(n3)
                            b3.Adornee = t.inst
                            b3.Color3 = t.color
                            b3.Visible = true
                            if want3Fill and t.part then
                                f3.Adornee = t.part
                                f3.Color3 = t.color
                                -- bounds are in the adornee's own space, so the
                                -- offset has to be expressed relative to it
                                f3.Size = size
                                f3.CFrame = t.part.CFrame:ToObjectSpace(cf)
                                f3.AlwaysOnTop = e.ThroughWalls
                                f3.Visible = true
                            elseif f3.Visible then
                                f3.Visible = false
                                f3.Adornee = nil
                            end
                        end
                    end
                    -- Depth fade: distant targets dissolve instead of popping off
                    -- at MaxDistance.  Quantised to 0.05 so a stationary target
                    -- costs nothing at all.
                    local fq = math.clamp((t.dist / e.MaxDistance) ^ 1.5 * 0.70, 0, 0.70)
                    fq = math.floor(fq * 20 + 0.5) / 20
                    if d.fade ~= fq then
                        d.fade = fq
                        d.stroke.Transparency = 0.15 + fq
                        d.name.TextTransparency = fq
                        d.name.BackgroundTransparency = math.min(1, 0.35 + fq * 0.85)
                        d.dist.TextTransparency = math.min(1, fq * 1.2)
                        d.dist.BackgroundTransparency = math.min(1, 0.35 + fq * 0.85)
                        d.tracer.BackgroundTransparency = 0.25 + fq
                    end

                    if e.Boxes then
                        d.box.Position = UDim2.fromOffset(minX, minY)
                        d.box.Size = UDim2.fromOffset(w, h)
                        d.box.Visible = (not is3D)
                    elseif d.box.Visible then
                        d.box.Visible = false
                    end

                    if e.Names then
                        -- uppercase allocates, so only re-derive it when the
                        -- label string actually changes
                        if d.lbl ~= t.label then
                            d.lbl = t.label
                            d.name.Text = string.upper(t.label)
                        end
                        d.name.Position = UDim2.fromOffset(minX + w / 2, minY - 2)
                        d.name.Visible = true
                    elseif d.name.Visible then
                        d.name.Visible = false
                    end

                    if e.Distance then
                        local dm = math.floor(t.dist * 0.28)
                        if d.dm ~= dm then
                            d.dm = dm
                            d.dist.Text = dm .. "m"
                        end
                        d.dist.Position = UDim2.fromOffset(minX + w / 2, minY + h + 2)
                        d.dist.Visible = true
                    elseif d.dist.Visible then
                        d.dist.Visible = false
                    end

                    if e.Lines then
                        local to = Vector2.new(sp.X, minY + h)
                        local delta = to - originPt
                        local len = delta.Magnitude
                        d.tracer.Position = UDim2.fromOffset((originPt.X + to.X) / 2, (originPt.Y + to.Y) / 2)
                        -- near targets get a heavier line, far ones a hairline:
                        -- depth read for one clamp
                        d.tracer.Size = UDim2.fromOffset(len, math.clamp(3 - t.dist / 600, 1, 3))
                        d.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                        d.tracer.Visible = true
                    elseif d.tracer.Visible then
                        d.tracer.Visible = false
                    end
                end
            end
        end
    end
    for i = drawn + 1, #ESP.pool do hideDrawing(ESP.pool[i]) end
    ESP.Hide3D(n3 + 1)
end)

--============================================================================
-- AUTOMATION
--============================================================================
local Auto = {}
local A = S.Auto

local route = {
    laneIdx = 1, wp = 1, Q = CFrame.identity, fwdLocal = Vector3.new(0, 0, -1),
    upLocal = Vector3.yAxis, lastSwitch = 0, stuckT = 0, flipT = 0, lastPos = nil,
    smoothMph = 0, yOffset = 2, calibrated = false,
    segIdx = 1, segT = 0,          -- spline cursor the driver walks along
    smoothY = nil, smoothNormal = nil,
}

CONFIG.MilesPerStud = 0.28 / 1609.34

--============================================================================
-- EARNINGS TRACKER
--============================================================================
-- Reads the HUD directly, found by measuring which labels actually move.
-- Rates are what tell you whether a farm setup is worth running.
local Earn = {
    cache = {}, base = {}, startedAt = 0, last = 0,
    lastMoney = nil, lastMoneyAt = nil, stalled = 0,
    money = 0, points = 0, xp = 0, streak = 0,
    moneyRate = 0, pointRate = 0,
    paths = {
        money  = { { "InGameHUD", "NewHUD", "MoneyHUD2", "MoneyHUD" }, "MoneyHUD" },
        points = { { "InGameHUD", "ComboUI", "Streak", "Points" }, "Points" },
        streak = { { "InGameHUD", "ComboUI", "Streak", "Message" }, "Message" },
        xp     = { { "InGameHUD", "LevelDisplay", "ProgressPercent" }, "ProgressPercent" },
    },
}

function Earn.Label(key)
    local cached = Earn.cache[key]
    if cached and cached.Parent then return cached end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local spec = Earn.paths[key]
    if not pg or not spec then return nil end

    local cur = pg
    for _, n in ipairs(spec[1]) do
        cur = cur and cur:FindFirstChild(n)
    end
    if not (cur and cur:IsA("TextLabel")) then
        local f = pg:FindFirstChild(spec[2], true)      -- layout moved? find by name
        cur = (f and f:IsA("TextLabel")) and f or nil
    end
    Earn.cache[key] = cur
    return cur
end

function Earn.Value(key)
    local lbl = Earn.Label(key)
    if not lbl then return nil end
    return tonumber((lbl.Text:gsub("[^%d]", "")))
end

function Earn.Reset()
    Earn.base = {}
    for key in pairs(Earn.paths) do
        Earn.base[key] = Earn.Value(key)
    end
    Earn.startedAt = tick()
    Earn.lastMoney, Earn.lastMoneyAt, Earn.stalled = nil, tick(), 0
    Earn.money, Earn.points, Earn.xp, Earn.streak = 0, 0, 0, 0
    Earn.moneyRate, Earn.pointRate = 0, 0
end

function Earn.Poll()
    if tick() - Earn.last < 0.5 then return end
    Earn.last = tick()
    if Earn.startedAt == 0 then Earn.Reset() return end

    local mins = (tick() - Earn.startedAt) / 60
    local m, p = Earn.Value("money"), Earn.Value("points")
    local x, st = Earn.Value("xp"), Earn.Value("streak")

    if m and Earn.base.money then
        if Earn.lastMoney and m ~= Earn.lastMoney then Earn.lastMoneyAt = tick() end
        Earn.lastMoney = m
        Earn.money = m - Earn.base.money
    end
    if p and Earn.base.points then Earn.points = p - Earn.base.points end
    if x and Earn.base.xp then Earn.xp = x - Earn.base.xp end
    Earn.streak = st or 0

    if mins > 0.05 then
        Earn.moneyRate = Earn.money / mins
        Earn.pointRate = Earn.points / mins
    end

    Earn.stalled = Earn.lastMoneyAt and (tick() - Earn.lastMoneyAt) or 0

    -- published for the progress box, which is built earlier in the file
    A.EarnMoney, A.EarnRate = Earn.money, Earn.moneyRate
    A.EarnStalled = Earn.stalled
    A.EarnPoints, A.EarnStreak = Earn.points, Earn.streak
end


-- ------------------------------------------------------------- CALIBRATION
function Auto.Calibrate()
    local root, model = S.Car.Root, S.Car.Model
    if not root or not root.Parent then return false end

    -- local forward: prefer the vehicle seat, then travel direction, then root -Z
    local L
    local seat = S.Car.Seat
    if seat and seat:IsA("BasePart") then
        L = root.CFrame:VectorToObjectSpace(seat.CFrame.LookVector)
    end
    local vel = root.AssemblyLinearVelocity
    if (not L or L.Magnitude < 0.1) and Vector3.new(vel.X, 0, vel.Z).Magnitude > 8 then
        L = root.CFrame:VectorToObjectSpace(Vector3.new(vel.X, 0, vel.Z).Unit)
    end
    if not L or L.Magnitude < 0.1 then L = Vector3.new(0, 0, -1) end
    L = Vector3.new(L.X, 0, L.Z)
    if L.Magnitude < 0.05 then L = Vector3.new(0, 0, -1) end
    L = L.Unit

    local U = Vector3.yAxis
    if root.CFrame.UpVector.Y > 0.6 then
        U = root.CFrame:VectorToObjectSpace(Vector3.yAxis)
    end
    if math.abs(U:Dot(L)) > 0.95 then U = Vector3.yAxis end

    route.fwdLocal = L
    route.upLocal = U
    local ok, q = pcall(function() return CFrame.lookAt(Vector3.zero, L, U):Inverse() end)
    route.Q = ok and q.Rotation or CFrame.identity

    if model then
        local ok2, _, size = pcall(function()
            local a, b = model:GetBoundingBox()
            return a, b
        end)
        route.yOffset = (ok2 and size) and math.max(1.5, size.Y * 0.5 + 0.4) or 2.5
    end
    route.calibrated = true
    return true
end

-- world-space forward of the car body
local function carForward()
    local root = S.Car.Root
    if not root then return Vector3.new(0, 0, -1) end
    local f = root.CFrame:VectorToWorldSpace(route.fwdLocal)
    f = Vector3.new(f.X, 0, f.Z)
    return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end

S.carForwardRef = carForward

-- rotation that points the car body along dir, rolled onto the road surface.
-- Passing the ground normal as `up` is what stops the car from being held level
-- on a slope and prying its own wheels off the road.
local function rotationFor(dir, up)
    up = up or Vector3.yAxis
    local f = dir - up * dir:Dot(up)
    if f.Magnitude < 0.01 then f = dir end
    local ok, cf = pcall(function()
        return CFrame.lookAt(Vector3.zero, f.Unit, up) * route.Q
    end)
    if ok then return cf end
    ok, cf = pcall(function()
        return CFrame.lookAt(Vector3.zero, dir, Vector3.yAxis) * route.Q
    end)
    return ok and cf or CFrame.identity
end

-- ------------------------------------------------------------------- GROUND
route.groundParams = RaycastParams.new()
route.groundParams.FilterType = Enum.RaycastFilterType.Exclude
route.groundParams.IgnoreWater = true

local function groundAt(pos)
    route.groundParams.FilterDescendantsInstances = { S.Car.Model, LocalPlayer.Character }
    return Workspace:Raycast(pos + Vector3.new(0, 14, 0), Vector3.new(0, -48, 0), route.groundParams)
end

-- ------------------------------------------------------------------ SPLINE
-- Waypoints give a polyline, and a polyline has corners.  At 200+ MPH a corner
-- is a visible snap, and asking the physics engine to chase one is what makes
-- the car wobble.  A Catmull-Rom spline through the same waypoints is smooth,
-- costs four lookups, and can be evaluated at an exact arc position - so the
-- car can be placed ON the line instead of steered toward it.
local function splinePoint(lane, i, t)
    local p0 = lane.points[World.Step(lane, i, -1)].pos
    local p1 = lane.points[i].pos
    local p2 = lane.points[World.Step(lane, i, 1)].pos
    local p3 = lane.points[World.Step(lane, i, 2)].pos
    local t2 = t * t
    local t3 = t2 * t
    return (p1 * 2
        + (p2 - p0) * t
        + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
        + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- True arc length of one spline segment, sampled once and cached on the lane.
-- Using the straight chord instead drifts the pacing by up to ~17% on bends,
-- which would make the car's real speed disagree with the commanded speed.
local function segArc(lane, i)
    local arc = lane.arc
    if not arc then arc = {} lane.arc = arc end
    local cached = arc[i]
    if cached then return cached end
    local j = World.Step(lane, i, 1)
    if j == i then arc[i] = 0 return 0 end
    local total, prev = 0, splinePoint(lane, i, 0)
    for k = 1, 4 do
        local p = splinePoint(lane, i, k * 0.25)
        total = total + (p - prev).Magnitude
        prev = p
    end
    arc[i] = total
    return total
end

-- walk `dist` studs forward from (i, t) along the lane, returning the new (i, t)
local function splineWalk(lane, i, t, dist)
    local guard = 0
    while dist > 0 and guard < 96 do
        guard = guard + 1
        local j = World.Step(lane, i, 1)
        if j == i then break end
        local segLen = segArc(lane, i)
        if segLen < 0.01 then
            i, t = j, 0
        else
            local remain = (1 - t) * segLen
            if dist >= remain then
                dist = dist - remain
                i, t = j, 0
            else
                t = t + dist / segLen
                dist = 0
            end
        end
    end
    return i, t
end

local function splineTangent(lane, i, t)
    local a = splinePoint(lane, i, t)
    local i2, t2 = splineWalk(lane, i, t, 6)
    local d = splinePoint(lane, i2, t2) - a
    d = Vector3.new(d.X, 0, d.Z)
    return (d.Magnitude > 0.01) and d.Unit or nil
end

-- One pass over nearby traffic.  This game pays for near misses, so traffic is
-- not something to get away from - only cars actually in our path are obstacles.
--   obstacle : studs to the nearest car we would hit
--   scoring  : cars ahead close enough to pay out as we pass them
--   density  : cars ahead at all
route.passTrack = setmetatable({}, { __mode = "k" })

local function trafficScan(pos, dir)
    local collideW, scoreW = World.CollideWidth(), World.ScoreWidth()
    -- once smart dodge has measured us, use the real number: guessing a third of
    -- a lane brakes for cars we would have cleared and ignores ones we would not
    if A.SmartDodge and route.dodgeHalf then collideW = route.dodgeHalf + 1.5 end
    local obstacle, scoring, density = 400, 0, 0
    for _, t in ipairs(World.Traffic()) do
        local p = t.part
        if p and p.Parent then
            local rel = p.Position - pos
            local along = rel:Dot(dir)
            if along > -40 and along < 300 then
                local lateral = (rel - dir * along).Magnitude
                if along > 2 and along < 260 then
                    density = density + 1
                    if lateral < collideW and along < obstacle then obstacle = along end
                    if lateral < scoreW then scoring = scoring + 1 end
                end
                -- alongside us right now = one near miss, counted once per car
                if math.abs(along) < 11 and lateral < scoreW then
                    if not route.passTrack[t.inst] then
                        route.passTrack[t.inst] = true
                        A.NearMiss = A.NearMiss + 1
                        route.lastPass = tick()
                    end
                elseif math.abs(along) > 34 then
                    route.passTrack[t.inst] = nil
                end
            end
        end
    end
    return obstacle, scoring, density
end

-- Lateral room to give the nearest car in our way, without leaving the path.
-- Returns studs to the right (negative = left), eased so it looks driven.
-- ------------------------------------------------------------- SMART DODGE
-- Measures real geometry instead of guessing at a slider. Every box is oriented,
-- so its width across the road is the sum of its three half-extents projected
-- onto the road's right vector - that is what lets this thread a gap a fixed
-- "dodge room" number would refuse.
local function extentAlong(cf, size, axis)
    local h = size * 0.5
    return math.abs(h.X * cf.RightVector:Dot(axis))
        + math.abs(h.Y * cf.UpVector:Dot(axis))
        + math.abs(h.Z * cf.LookVector:Dot(axis))
end

-- How wide WE are across the road, from our collision boxes. The two score
-- boxes are deliberately excluded: they are huge and measure passes, not metal.
local function localHalfWidth(right)
    local car, root = S.Car.Model, S.Car.Root
    if not car or not root then return 3 end
    if route.halfAt and (tick() - route.halfAt) < 1 and route.halfW then
        return route.halfW
    end
    local centre = root.Position
    local best, found = 0, false
    for _, d in ipairs(car:GetDescendants()) do
        if d:IsA("BasePart") then
            local nm = d.Name:lower()
            if nm ~= "traffichitboxleft" and nm ~= "traffichitboxright" then
                if d.CanCollide or nm:find("hitbox") or nm:find("collision") or nm:find("collider") then
                    found = true
                    local rel = (d.Position - centre):Dot(right)
                    best = math.max(best, math.abs(rel) + extentAlong(d.CFrame, d.Size, right))
                end
            end
        end
    end
    if not found then
        local ok, cf, size = pcall(function()
            local a, b = car:GetBoundingBox()
            return a, b
        end)
        best = (ok and cf) and extentAlong(cf, size, right) or 3
    end
    route.halfW, route.halfAt = best, tick()
    return best
end

-- ------------------------------------------------------------------- WALLS
-- The only thing outside the car that gets a say in where it may go.  An
-- earlier version derived a "road band" from the lane network as well, but with
-- one baked path and no usable TrafficLanes that band was measured from the car
-- rather than from the line, so the offset had nothing absolute to hold on to
-- and simply walked across the road.  The cap below is absolute; this only
-- tightens it.
local SIDE_PROBE = 90       -- studs of sideways wall check
route.sideParams = RaycastParams.new()
route.sideParams.FilterType = Enum.RaycastFilterType.Exclude
route.sideParams.IgnoreWater = true

-- A wall, not the floor: a banked road surface would otherwise read as a wall a
-- stud away and the car would refuse to move at all.
local function sideWall(root, right, sign, myHalf)
    local ignore = { S.Car.Model, LocalPlayer.Character }
    for _, n in ipairs({ "TrafficFolder", "PoliceAI", "PoliceHelicopters" }) do
        local f = Workspace:FindFirstChild(n)
        if f then ignore[#ignore + 1] = f end
    end
    route.sideParams.FilterDescendantsInstances = ignore
    -- two heights: a bumper-height ray goes over a low kerb or barrier, a
    -- roof-height one misses a short one, so take whichever finds something
    -- first and let the caller decide if it is close enough to believe
    local best = nil
    for _, h in ipairs({ 1.0, 4.5 }) do
        local origin = root.Position + Vector3.new(0, h, 0)
        local hit = Workspace:Raycast(origin, right * (sign * SIDE_PROBE), route.sideParams)
        if hit and math.abs(hit.Normal.Y) <= 0.85 then           -- not the ground
            local d = math.max(0, (hit.Position - origin).Magnitude - myHalf - 1)
            if best == nil or d < best then best = d end
        end
    end
    return best
end

-- Tighten the absolute cap with whatever solid is actually beside us.  A reading
-- under 6 studs is a kerb or our own bodywork, not a barrier, and is ignored -
-- otherwise a false hit pins the car to the line and no dodge ever happens.
local function wallCaps(right, myHalf, capLo, capHi, cur)
    local root = S.Car.Root
    if not root then return capLo, capHi end
    if not route.wallAt or (tick() - route.wallAt) > 0.25 then
        route.wallAt = tick()
        route.wallL = sideWall(root, right, -1, myHalf)
        route.wallR = sideWall(root, right,  1, myHalf)
    end
    if route.wallL and route.wallL >= 6 then capLo = math.max(capLo, cur - route.wallL) end
    if route.wallR and route.wallR >= 6 then capHi = math.min(capHi, cur + route.wallR) end
    if capHi < capLo then return cur, cur end
    return capLo, capHi
end

-- -------------------------------------------------------------- LANE EDGES
-- Never past the centre line of the outermost traffic lane.  World.lanes is the
-- real TrafficLanes folders only - no blends, no baked routes - so this is
-- literally "stay between Lane 1 and Lane 3", and the walls the car kept finding
-- are all on the far side of those.
--
-- Offsets come back measured FROM THE CAR.  On its own that would be no limit at
-- all, which is how the old road band wandered; it is only ever used to tighten
-- the absolute +/- Dodge room cap, so the two together cannot drift.
route.laneSeed = {}

-- XZ only, deliberately.  The server's lane reply carries a flat plan height
-- for every point, so a 3D distance against it would be wrong by however far
-- the real road has climbed - and the band is a horizontal question anyway.
local function flatDist(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function laneNearest(lane, key, at)
    local pts, n = lane.points, #lane.points
    local seed = route.laneSeed[key]
    if seed and seed >= 1 and seed <= n then
        local bestI, bestD = nil, math.huge
        for k = -60, 60 do
            local j = seed + k
            if lane.loop then j = ((j - 1) % n) + 1 end
            if j >= 1 and j <= n then
                local d = flatDist(pts[j].pos, at)
                if d < bestD then bestI, bestD = j, d end
            end
        end
        if bestI and bestD < 400 then
            route.laneSeed[key] = bestI
            return pts[bestI].pos, bestD
        end
    end
    -- full scan.  These lanes are 412 points, not 1582, so this is cheap.
    local bestI, bestD = 1, math.huge
    for i = 1, n do
        local d = flatDist(pts[i].pos, at)
        if d < bestD then bestI, bestD = i, d end
    end
    route.laneSeed[key] = bestI
    return pts[bestI].pos, bestD
end

local function laneEdges(pos, right)
    if route.edgeAt and (tick() - route.edgeAt) < 0.15 then
        if not route.edgeLo then return nil, nil end
        -- The scan is throttled, but the car keeps moving sideways between runs.
        -- Shift the cached offsets by how far it has gone since, or a cap held
        -- for a tenth of a second is already wrong by several studs.
        local drift = (pos - route.edgePos):Dot(right)
        return route.edgeLo - drift, route.edgeHi - drift
    end
    route.edgeAt, route.edgePos = tick(), pos
    -- The workspace folders when they exist, the server's own reply when they
    -- do not.  The second is what makes this work on a map where TrafficLanes
    -- never streamed in.
    local src = (#World.lanes >= 2) and World.lanes or (World.policeLanes or {})
    local lo, hi, n = math.huge, -math.huge, 0
    for li, lane in ipairs(src) do
        if lane.points and #lane.points > 1 then
            local p, d = laneNearest(lane, li, pos)
            if d < 400 then
                local off = (p - pos):Dot(right)
                lo, hi, n = math.min(lo, off), math.max(hi, off), n + 1
            end
        end
    end
    -- one lane is not a band, and no TrafficLanes at all means no opinion
    if n < 2 then
        route.edgeLo, route.edgeHi = nil, nil
    else
        route.edgeLo, route.edgeHi = lo, hi
    end
    return route.edgeLo, route.edgeHi
end

-- ------------------------------------------------------------- SMART DODGE
-- The smallest move that clears the next car, and nothing more.  Only the
-- nearest car in our way sets the target: an earlier version merged every car
-- inside a 1.7 second window into one blocked span, which on a busy road is the
-- whole width of it, so the "nearest opening" came out at the far kerb and the
-- car swerved the width of the road to reach it.  Traffic is dodged one car at
-- a time, the way it is actually driven.
local DODGE_HORIZON = 1.7   -- seconds of road we look over

-- Everything here is measured FROM THE CAR: 0 is where we are, `cur` is only
-- used to convert an answer back to the line.  Returns the target offset in LINE
-- coordinates, the room it leaves, and whether we are boxed in.
local function smartDodge(pos, dir, right, myHalf, speed, capLo, capHi, cur)
    local clear = A.DodgeClear or 0.5
    local reach = math.clamp(speed * DODGE_HORIZON, 60, 900)

    local near, nearLat, nearNeed, nearAlong, nearTti = nil, 0, 0, math.huge, math.huge
    local others, alongside = {}, false

    for _, t in ipairs(World.Traffic()) do
        local p = t.part
        if p and p.Parent then
            local rel = p.Position - pos
            local along = rel:Dot(dir)
            local lat = rel:Dot(right)
            -- capped at half a lane: partOf() can hand back an enlarged traffic
            -- or score hitbox rather than the body, and measuring THAT is how a
            -- dodge turns into a swerve across the road
            local ext = math.min(extentAlong(p.CFrame, p.Size, right),
                (World.laneWidth or 18) * 0.5)
            local need = ext + myHalf + clear
            if along > 2 and along < reach then
                others[#others + 1] = { lat = lat, need = need, along = along }
                if math.abs(lat) < need and along < nearAlong then
                    -- close at the difference in speed: traffic running with us
                    -- is a far slower problem than the raw gap suggests
                    local theirs = p.AssemblyLinearVelocity:Dot(dir)
                    near, nearLat, nearNeed = p, lat, need
                    nearAlong = along
                    nearTti = along / math.max(speed - theirs, 1)
                end
            elseif along > -40 and along <= 2 and math.abs(lat) < need then
                alongside = true            -- still level with one; hold the line
            end
        end
    end

    if not near then
        return nil, math.huge, false, alongside, math.huge
    end

    -- the two minimal escapes: just past their right edge, or just past their
    -- left.  One of these is always a small number, because we are only here
    -- when we are already inside their width.
    local dR, dL = nearLat + nearNeed + 0.05, nearLat - nearNeed - 0.05

    -- Would that offset put us into a car abreast of the one we are going round?
    -- Only cars level with it count.  Anything further down the road is a
    -- separate decision we will make when we get there - judging the whole queue
    -- at once is what produced the road-wide swerves.
    local function freeAt(d)
        local worst = math.huge
        for _, o in ipairs(others) do
            if math.abs(o.along - nearAlong) < 45 then
                local gap = math.abs(d - o.lat) - o.need
                if gap < 0 then return nil end
                worst = math.min(worst, gap)
            end
        end
        return worst
    end

    local opts = {}
    for _, d in ipairs({ dR, dL }) do
        local line = cur + d
        if line >= capLo and line <= capHi then
            local room = freeAt(d)
            if room then
                -- stay on the side we are already leaning, all else equal: that
                -- is what stops it flicking between two equally good answers
                local bias = (route.dodge or 0) * d > 0 and -1.5 or 0
                opts[#opts + 1] = { line = line, cost = math.abs(d) + bias, room = room }
            end
        end
    end
    if #opts == 0 then
        -- nowhere to go inside the cap: hold the line and let the brake work
        return math.clamp(cur, capLo, capHi), 0, true, alongside, nearTti
    end
    table.sort(opts, function(a, b) return a.cost < b.cost end)
    return opts[1].line, opts[1].room, false, alongside, nearTti
end

-- A cushion around OUR car, not around theirs.
--
-- The obvious version of this feature - grow or move a traffic car's hitbox so
-- it cannot reach us - does nothing the server scores, and this file already
-- contains the proof twice over.  Fun.SpinStep re-reads each car's pivot every
-- frame and writes back the SAME position with a new rotation, deliberately
-- never displacing it; and Collide re-asserts CanCollide every frame and counts
-- how many parts the game put back, a counter that exists because somebody
-- needed to know whether writes to traffic stick.  They do not.
--
-- So the cushion pushes the one car we genuinely own.  It returns an ABSOLUTE
-- offset in line coordinates - the place that would leave R studs of air - not
-- a delta.  That distinction is the whole design:
--
--   A relative target has no fixed point.  `cur + push` keeps the error pinned
--   at the full push no matter how far the car has already moved, so the rate
--   limiter runs flat out forever, the car creeps outward frame after frame,
--   and crossing smartDodge's `alongside` threshold flips the target formula
--   between relative and absolute at about 14Hz.  Measured: a 0.57 stud limit
--   cycle, and a car parked a stud inside a wall.
--
--   An absolute target converges and stops.  It is also what the planner has
--   always used - its target is anchored to a traffic car's own edge - which is
--   why the planner never reached the places the first version of this did.
--
-- Returns nil when nothing is close, or when cars on both sides cancel: being
-- boxed in is the existing dodgeBlocked brake's job, not this one's.
local function bubblePush(pos, dir, right, myHalf, speed, cur)
    local R = math.max(1, A.BubbleR or 10)
    local cap = A.BubblePush or 6
    -- A short window, because this is a last layer and not a planner: far
    -- enough ahead to react to someone drifting in, near enough behind to keep
    -- pushing while we are still level with them.
    local ahead = math.clamp(speed * 0.18, 25, 90)
    local wantL, wantR, n, closest = nil, nil, 0, math.huge
    for _, t in ipairs(World.Traffic()) do
        local p = t.part
        if p and p.Parent then
            local rel = p.Position - pos
            local along = rel:Dot(dir)
            if along > -18 and along < ahead then
                local lat = rel:Dot(right)
                -- capped at half a lane for the same reason smartDodge caps it:
                -- partOf() can hand back an enlarged traffic or score hitbox
                -- rather than the body, and measuring THAT is how a nudge
                -- becomes a swerve across the road
                local ext = math.min(extentAlong(p.CFrame, p.Size, right),
                    (World.laneWidth or 18) * 0.5)
                local gap = math.abs(lat) - ext - myHalf
                if gap < R then
                    if gap < closest then closest = gap end
                    n = n + 1
                    -- Their position in LINE coordinates, which does not move
                    -- when we do - that is what makes the target absolute.
                    local theirs = cur + lat
                    local need = R + ext + myHalf
                    if lat >= 0 then
                        local w = theirs - need             -- clear them to our left
                        if not wantL or w < wantL then wantL = w end
                    else
                        local w = theirs + need             -- clear them to our right
                        if not wantR or w > wantR then wantR = w end
                    end
                end
            end
        end
    end
    route.bubbleN = n
    route.bubbleGap = (closest == math.huge) and nil or closest
    if n == 0 or (wantL and wantR) then return nil end
    -- Bounded against the PATH, not against where we happen to be.  Measuring
    -- the strength slider from `cur` would have made it a per-frame step again,
    -- and a per-frame step is a creep: the car would walk out to the full Dodge
    -- room a few studs at a time.  Read it as "how far off the line the cushion
    -- may take you", which is also what the label says.
    return math.clamp(wantL or wantR, -cap, cap)
end

local function updateDodge(pos, dir, dt)
    local cur = route.dodge or 0
    if not A.Dodge and not A.Bubble then
        route.dodge = lerp(cur, 0, math.clamp(dt * 3, 0, 1))
        route.dodgeBlocked = false
        route.bubbleN, route.bubbleGap = 0, nil
        return route.dodge
    end
    local right = Vector3.new(-dir.Z, 0, dir.X)
    local speed = math.max(Car.Speed(), 1)
    local myHalf = localHalfWidth(right)

    -- One absolute cap, in LINE coordinates, for both modes.  This is the slider
    -- and it is what keeps the car on its path instead of touring the road.
    local capLo, capHi = -A.DodgeMax, A.DodgeMax
    -- then the lane network, which is what stops an edge-lane car being passed
    -- on the side where the wall is
    local eLo, eHi = laneEdges(pos, right)
    route.laneLock = (eLo ~= nil)
    if eLo and eHi then
        capLo, capHi = math.max(capLo, cur + eLo), math.min(capHi, cur + eHi)
        if capHi < capLo then capLo, capHi = cur, cur end
    end
    capLo, capHi = wallCaps(right, myHalf, capLo, capHi, cur)

    local target, room, boxed, alongside, tti

    -- The caps above always run, so the cushion below inherits them even when
    -- the planner is switched off entirely.
    if not A.Dodge then
        -- no planner: the cushion is the only thing steering
    elseif A.SmartDodge then
        target, room, boxed, alongside, tti =
            smartDodge(pos, dir, right, myHalf, speed, capLo, capHi, cur)
        route.dodgeRoom, route.dodgeHalf = room, myHalf
    else
        -- fixed-width dodge: one push of a set size past the nearest car in the
        -- way, no measuring.  Kept deliberately blunt so the two modes differ.
        local collideW = World.CollideWidth()
        local nearestAlong = math.huge
        tti, room = math.huge, math.huge
        for _, t in ipairs(World.Traffic()) do
            local p = t.part
            if p and p.Parent then
                local rel = p.Position - pos
                local along = rel:Dot(dir)
                local lat = rel:Dot(right)
                if along > 2 and along < math.clamp(speed * DODGE_HORIZON, 60, 900)
                    and along < nearestAlong and math.abs(lat) < collideW * 2.3 then
                    nearestAlong = along
                    local push = collideW * 2.6
                    target = cur + ((lat >= 0) and (lat - push) or (lat + push))
                    tti = along / math.max(speed, 1)
                elseif along > -40 and along <= 2 and math.abs(lat) < collideW * 2.3 then
                    alongside = true
                end
            end
        end
        if target then target = math.clamp(target, capLo, capHi) end
        boxed = false
    end
    route.dodgeBlocked = boxed or false

    -- Nothing in the way: back to the line, but not while we are still level
    -- with the car we just went round.
    if target == nil then
        -- The early return exists so we do not cut back into a car we are still
        -- level with, and that intent has to survive.  With the cushion on we
        -- hold the line instead of returning, so it can still push off them.
        if alongside and not A.Bubble then return route.dodge end
        if alongside then
            target = cur
        else
            target = math.clamp(0, capLo, capHi)
            tti = math.huge
        end
    end

    -- BEFORE the rate limiter and the clamp below, so the cushion is
    -- rate-limited and capped like everything else the planner produces.
    --
    -- route.laneLock is required, not optional.  Of the three caps only the
    -- lane band is a genuine absolute limit: wallCaps rebuilds its cap around
    -- the CURRENT offset from a reading cached for a quarter second, so it
    -- slides along with the car rather than pinning it, and it discards any
    -- reading under 6 studs - which is exactly when a wall matters.  With the
    -- lane band present the road is genuinely enforced; without it the only
    -- thing left is the Dodge room slider, and 14 studs of it is enough to put
    -- a wing inside a wall.  So the cushion simply does not run there.
    if A.Bubble and route.laneLock then
        local want = bubblePush(pos, dir, right, myHalf, speed, cur)
        -- Only ever FURTHER from the line than the planner asked, and only in
        -- the direction the cushion wants.  This is a last layer, not a second
        -- planner: it may never pull the car back toward what it is clearing.
        --
        -- Comparing against `target` rather than `cur` is what makes it settle.
        -- Against `cur` the test goes false the moment the car arrives, the
        -- planner's target takes over, the car falls back, and the cushion
        -- fires again - which is the oscillation this whole rewrite removes.
        if want and ((want > 0 and want > target) or (want < 0 and want < target)) then
            target = want
            -- treat it as urgent: the whole point is that something is close
            tti = math.min(tti or math.huge, 0.25)
        end
    else
        route.bubbleN, route.bubbleGap = 0, nil
    end

    -- Move only as fast as the gap demands.  Working out the rate from the time
    -- we actually have is what turns this from a swerve into a lane change: the
    -- move is timed to finish with room to spare, not thrown at full speed.
    local err = target - cur
    local rate
    if tti and tti < math.huge and tti > 0.01 then
        rate = math.clamp(math.abs(err) / (tti * 0.65), 6, 70)
    else
        rate = 10                                   -- easing home
    end
    local step = math.clamp(err, -rate * dt, rate * dt)
    if math.abs(err) < 1.5 then step = err * math.clamp(dt * 9, 0, 1) end

    route.dodge = math.clamp(cur + step, capLo, capHi)
    return route.dodge
end

-- Which drivable path will earn the most?  Score each one by how many cars it
-- will put alongside us, penalise anything sitting in the path, and favour the
-- white lines because they collect from the lane on either side.
local function scorePath(lane, pos, dir)
    local wi, d = World.NearestIndex(lane, pos)
    if d > 130 then return -1 end
    local nxt = World.Step(lane, wi, 1)
    local ldir = lane.points[nxt].pos - lane.points[wi].pos
    ldir = Vector3.new(ldir.X, 0, ldir.Z)
    if ldir.Magnitude < 0.1 then return -1 end
    ldir = ldir.Unit
    if dir and ldir:Dot(dir) < 0.3 then return -1 end   -- runs the other way

    local origin = lane.points[wi].pos
    local collideW, scoreW = World.CollideWidth(), World.ScoreWidth()
    local score, blocked = 0, false
    for _, t in ipairs(World.Traffic()) do
        local p = t.part
        if p and p.Parent then
            local rel = p.Position - origin
            local along = rel:Dot(ldir)
            if along > 0 and along < 300 then
                local lateral = (rel - ldir * along).Magnitude
                if lateral < collideW then
                    blocked = true
                elseif lateral < scoreW then
                    score = score + 1
                end
            end
        end
    end
    if lane.blend then score = score * 1.35 end
    if blocked then score = score * 0.35 end
    return score, wi
end

local function bestPath(pos, dir)
    local bestIdx, bestScore, bestWp = nil, -1, 1
    for li, lane in ipairs(World.paths) do
        local s, wi = scorePath(lane, pos, dir)
        if s > bestScore then bestIdx, bestScore, bestWp = li, s, wi end
    end
    return bestIdx, bestScore, bestWp
end

--============================================================================
-- AUTOMATION : PATH PREVIEW
--============================================================================
-- Drawn in screen space: projecting the waypoints costs nothing and, unlike
-- neon parts in the workspace, the game has no way to see it.
route.pathPool, route.pathMarker = {}, nil

local function getPathSeg(i)
    local f = route.pathPool[i]
    if not f then
        f = new("Frame", {
            Name = "path", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.Accent2,
            BorderSizePixel = 0, Size = UDim2.fromOffset(0, 4), Visible = false, ZIndex = 1,
            Parent = ScreenESP,
        })
        -- keep = true: a world overlay is not rescaled by the menu corner style
        corner(f, 2, true)
        route.pathPool[i] = f
    end
    return f
end

local function clearPath()
    for _, f in ipairs(route.pathPool) do
        if f.Visible then f.Visible = false end
    end
    if route.pathMarker and route.pathMarker.Visible then route.pathMarker.Visible = false end
end

local function drawPath(lane, idx, fromPos)
    if not lane then clearPath() return end

    local sp = Camera:WorldToViewportPoint(fromPos)
    local prevPt, prevOk = Vector2.new(sp.X, sp.Y), sp.Z > 0
    local used, i = 0, idx

    -- The route ramps in colour along its length instead of being one flat
    -- accent.  The ramp is the only per-segment colour work in the whole
    -- preview, so it is cached and rebuilt ONLY when the source colours move -
    -- which under RGB mode is 30 times a second, not 60, and never otherwise.
    -- THEME is mutated in place by the theme engine, so a plain Color3 compare
    -- is all the invalidation this needs.
    -- THEME.PathLine is nil until the Appearance tab pins it, in which case the
    -- ramp runs from the pinned colour instead of the accent family
    local pin = THEME.PathLine
    local rampA = pin or (A.Running and THEME.Accent2 or THEME.Accent)
    local rampB = pin and TH.mix(pin, THEME.Text, 0.35)
        or (A.Running and TH.get("Accent3") or THEME.Accent2)
    if route.rampA ~= rampA or route.rampB ~= rampB then
        route.rampA, route.rampB = rampA, rampB
        local r = route.ramp
        if not r then r = {} route.ramp = r end
        local span = math.max(1, CONFIG.PathNodes - 1)
        for k = 1, CONFIG.PathNodes do r[k] = TH.mix(rampA, rampB, (k - 1) / span) end
    end

    -- One travelling pulse index for the whole call: the route visibly flows
    -- toward the horizon for one integer compare per segment and no new instances.
    local pulseAt = math.floor((tick() * 14) % CONFIG.PathNodes)

    for step = 1, CONFIG.PathNodes do
        local p3 = Camera:WorldToViewportPoint(lane.points[i].pos)
        local ok = p3.Z > 0
        local pt = Vector2.new(p3.X, p3.Y)
        if ok and prevOk then
            local delta = pt - prevPt
            local len = delta.Magnitude
            if len > 1 then
                used = used + 1
                local f = getPathSeg(used)
                local ft = step / CONFIG.PathNodes
                -- eased, not linear: the route fades into the horizon rather
                -- than stepping down in even slabs
                local trans = 0.08 + (ft ^ 1.4) * 0.68
                local thick = 4 - ft * 2
                local pd = math.abs(step - pulseAt)
                if pd <= 2 then
                    trans = math.max(0, trans - (pd == 0 and 0.35 or pd == 1 and 0.22 or 0.10))
                    thick = thick + (pd == 0 and 2 or pd == 1 and 1 or 0.5)
                end
                f.Position = UDim2.fromOffset((prevPt.X + pt.X) * 0.5, (prevPt.Y + pt.Y) * 0.5)
                f.Size = UDim2.fromOffset(len, thick)
                f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                f.BackgroundColor3 = route.ramp[step] or rampA
                f.BackgroundTransparency = trans
                f.Visible = true
            end
        end
        prevPt, prevOk = pt, ok
        local j = World.Step(lane, i, 1)
        if j == i then break end
        i = j
    end

    for k = used + 1, #route.pathPool do
        if route.pathPool[k].Visible then route.pathPool[k].Visible = false end
    end

    -- Immediate target marker: a three-part reticle, built once.
    -- The spin moved off the frame and onto the ring's stroke gradient - a
    -- rotating circle reads as nothing, a rotating ARC reads as a scope locking
    -- on - and it is still exactly one property write per frame.  The ping is
    -- two repeating tweens armed once, so it costs nothing per frame at all.
    if not route.pathMarker then
        route.pathMarker = new("Frame", {
            Name = "route.pathMarker", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1, Visible = false, ZIndex = 2, Parent = ScreenESP,
        })
        local ring = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 2, Parent = route.pathMarker,
        })
        corner(ring, 999, true)
        route.markGrad = new("UIGradient", {
            -- only a bright arc of the ring is ever visible
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = stroke(ring, THEME.Good, 2, 0),
        })
        local core = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.fromOffset(4, 4), BackgroundColor3 = THEME.Good, BorderSizePixel = 0,
            ZIndex = 3, Parent = route.pathMarker,
        })
        corner(core, 2, true)
        route.ping = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ZIndex = 1, Parent = route.pathMarker,
        })
        corner(route.ping, 999, true)
        route.pingStroke = stroke(route.ping, THEME.Good, 1.5, 0.2)
    end

    -- Radar ping: expand + fade, repeating forever with a 0.35s gap between
    -- pulses.  It goes through FX.loopN so both tweens are REGISTERED in
    -- FX._loops - created straight through FX.tw they were invisible to the cap
    -- of four concurrent loops and FX.stopLoops could not cancel them, so they
    -- outlived both the Appearance "Reduced motion" toggle and Unload.
    --
    -- Arming lives here rather than in the build above precisely because they
    -- are cancellable now: one integer compare per frame against the loop
    -- generation brings the pulse back when motion returns, and it also arms a
    -- reticle that was built while motion was off - which the construction-time
    -- version could never do, leaving the ping dead for the whole session.
    if FX.motion then
        if route.pingGen ~= FX.loopGen then
            route.pingGen = FX.loopGen
            -- a repeating tween captures its start value when it is created, so
            -- the rest pose has to be restored before re-arming
            route.ping.Size = UDim2.fromOffset(18, 18)
            route.pingStroke.Transparency = 0.2
            FX.loopN(route.ping, 1.2, { Size = UDim2.fromOffset(46, 46) }, FX.E.snap, -1, false, 0.35)
            FX.loopN(route.pingStroke, 1.2, { Transparency = 1 }, FX.E.snap, -1, false, 0.35)
        end
    elseif route.pingGen then
        -- reduced motion: the halo rests hidden, which is the still frame the
        -- animated version ends every pulse on anyway
        route.pingGen = nil
        route.pingStroke.Transparency = 1
    end

    local m3 = Camera:WorldToViewportPoint(lane.points[idx].pos)
    if m3.Z > 0 then
        route.pathMarker.Position = UDim2.fromOffset(m3.X, m3.Y)
        route.markGrad.Rotation = (tick() * 45) % 360
        route.pathMarker.Visible = true
    elseif route.pathMarker.Visible then
        route.pathMarker.Visible = false
    end
end

--============================================================================
-- AUTOMATION : PROGRESSION BOX
--============================================================================
local Prog = {}
do
    -- fields of one table rather than 28 block-level locals: the main chunk
    -- pays a register for each of these for the whole block, and Luau caps a
    -- function at 200
    local PB = {}
    PB.bb = new("BillboardGui", {
        Name = "AT_Prog", Size = UDim2.fromOffset(252, 228), StudsOffset = Vector3.new(0, 5.5, 0),
        AlwaysOnTop = true, MaxDistance = 600, Enabled = false, LightInfluence = 0, Parent = AdornHolder,
    })
    -- LAYERING RULE: a ZIndex 0 child still paints in front of its own parent's
    -- BACKGROUND, so a drop shadow is only valid under a fully transparent
    -- wrapper.  That wrapper is the only reason this pod can have depth at all.
    PB.wrap = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Parent = PB.bb,
    })
    FX.shadow(PB.wrap, 26, 0.55)
    -- The fill is WHITE on purpose: a UIGradient multiplies BackgroundColor3, so
    -- a white plate lets the Carbon -> Bg -> Void ramp define the shade and keeps
    -- the top PB.edge catching light.
    PB.card = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.10, BorderSizePixel = 0, ZIndex = 1, Parent = PB.wrap,
    })
    TH.corner(PB.card, "card")
    TH.grad3(PB.card, "Carbon", "Bg", "Void", 90)
    -- white carrier: a UIGradient MULTIPLIES UIStroke.Color, so an accent fill
    -- under the accent ramp would square it and recolour the chase PB.edge
    PB.edge = new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.6, Transparency = 0.05, Parent = PB.card })
    -- Two PB.edge palettes.  The farm PB.edge is built through the registry so an
    -- accent change or RGB mode reaches it; the chase PB.edge is hardcoded and
    -- UNREGISTERED on purpose - a police chase must never be recoloured by a
    -- cosmetic setting, so Prog.Update detaches the gradient while chasing.
    PB.EDGE_KEYS = { "Accent", "Accent3", "Accent2" }
    PB.EDGE_CHASE = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, THEME.Warn),
        ColorSequenceKeypoint.new(0.35, THEME.Bad),
        ColorSequenceKeypoint.new(0.60, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1.00, THEME.Warn),
    })
    PB.edgeGrad = TH.grad3(PB.edge, "Accent", "Accent3", "Accent2")

    pad(PB.card, 12, 12, 10, 10)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = PB.card })

    -- ------------------------------------------------------------ header band
    PB.head = new("Frame", {
        Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = TH.get("Carbon"), BackgroundTransparency = 0.25,
        BorderSizePixel = 0, LayoutOrder = 1, Parent = PB.card,
    })
    TH.corner(PB.head, "well")
    -- Inset by 12px on purpose: `PB.head` is rounded and does NOT clip, so a
    -- full-width hairline would poke out past both bottom corners.
    new("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -12, 0, 1),
        BackgroundColor3 = TH.get("StrokeSoft"), BackgroundTransparency = 0.45,
        BorderSizePixel = 0, Parent = PB.head,
    })
    PB.dot = new("Frame", {
        Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = THEME.Good, BorderSizePixel = 0, Parent = PB.head,
    })
    TH.corner(PB.dot, "pill")
    PB.headTxt = new("TextLabel", {
        Position = UDim2.fromOffset(21, 0), Size = UDim2.new(1, -130, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = "AUTOMATION", TextSize = 10, TextColor3 = THEME.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = PB.head,
    })
    -- measurement channel: every number the tool read from the world is mono
    -- and Accent2, here and everywhere else
    PB.speedLbl = TH.bind(new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, -1), Size = UDim2.fromOffset(96, 18),
        BackgroundTransparency = 1, Font = Enum.Font.RobotoMono, Text = "0 MPH", TextSize = 15,
        TextColor3 = THEME.Accent2, TextXAlignment = Enum.TextXAlignment.Right, Parent = PB.head,
    }), "TextColor3", "Accent2")

    -- ------------------------------------------------------------- PB.logic line
    PB.logicRow = new("Frame", {
        Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, LayoutOrder = 2, Parent = PB.card,
    })
    TH.corner(TH.bind(new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(2, 9),
        BorderSizePixel = 0, Parent = PB.logicRow,
    }), "BackgroundColor3", "Accent"), "tick")
    PB.logic = new("TextLabel", {
        Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = "Idle", TextSize = 11, TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = PB.logicRow,
    })

    -- ----------------------------------------------------------- progress PB.bar
    PB.barBox = new("Frame", {
        Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 3, Parent = PB.card,
    })
    PB.barHolder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = THEME.Track, BorderSizePixel = 0, Parent = PB.barBox,
    })
    TH.corner(PB.barHolder, "tick")
    TH.stroke(PB.barHolder, "StrokeSoft", 1, 0.70)
    PB.bar = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = PB.barHolder,
    })
    TH.corner(PB.bar, "tick")
    TH.grad(PB.bar, "Accent", "Accent2", 0)
    -- the PB.head is anchored to the fill's right edge, so it rides the bar for free
    TH.corner(TH.bind(new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(2, 8),
        BorderSizePixel = 0, ZIndex = 2, Parent = PB.bar,
    }), "BackgroundColor3", "AccentGlow"), "tick")
    for ti = 0, 4 do
        new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(ti / 4, 0, 0, 8),
            Size = UDim2.fromOffset(1, 4), BackgroundColor3 = TH.get("Rail"),
            BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = PB.barBox,
        })
    end
    PB.pctLbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 13), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono, Text = "0%",
        TextSize = 10, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 4, Parent = PB.card,
    })

    -- ------------------------------------------------------ 2 x 2 instrument PB.grid
    PB.grid = new("Frame", {
        Size = UDim2.new(1, 0, 0, 128), BackgroundTransparency = 1, LayoutOrder = 5, Parent = PB.card,
    }, {
        new("UIGridLayout", {
            CellSize = UDim2.new(0.5, -3, 0, 40), CellPadding = UDim2.fromOffset(6, 4),
            SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = 2,
        }),
    })
    function PB.statTile(order)
        local f = new("Frame", {
            BackgroundColor3 = TH.get("Carbon"), BackgroundTransparency = 0.45,
            BorderSizePixel = 0, LayoutOrder = order, Parent = PB.grid,
        })
        TH.corner(f, "well")
        -- 3px vertical padding, not 4: it leaves the value exactly two 10px
        -- lines of room, which is what the stall message needs (see below)
        pad(f, 8, 8, 3, 3)
        local k = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, Font = Enum.Font.RobotoMono, Text = "",
            TextSize = 8, TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = f,
        })
        -- wrapped, not truncated: "STALLED 00:25 · press a key" is an
        -- instruction and must survive inside a half-width tile
        local v = new("TextLabel", {
            Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 1, -10), BackgroundTransparency = 1,
            Font = Enum.Font.RobotoMono, Text = "-", TextSize = 10, TextColor3 = THEME.Text,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f,
        })
        return k, v
    end
    PB.kEarn, PB.vEarn = PB.statTile(5)
    PB.kNear, PB.vNear = PB.statTile(6)
    PB.kTime, PB.vTime = PB.statTile(7)
    PB.kRun,  PB.vRun  = PB.statTile(8)
    PB.kDist, PB.vDist = PB.statTile(9)
    PB.kRate, PB.vRate = PB.statTile(10)
    PB.nearScale = new("UIScale", { Scale = 1, Parent = PB.vNear })
    PB.kEarn.Text = "EARNED"
    PB.kNear.Text = "NEAR MISSES"
    -- TIME AUTOMATING spans the whole session; RUN restarts every chase lap
    PB.kTime.Text = "TIME AUTOMATING"
    PB.kRun.Text  = "CURRENT RUN"
    PB.kDist.Text = "STUDS TRAVELLED"
    PB.kRate.Text = "SPEED"

    function Prog.SetAdornee(inst) PB.bb.Adornee = inst end
    function Prog.SetEnabled(v) PB.bb.Enabled = v end

    -- The same panel serves both automations: the police chase takes it over
    -- while it is running, otherwise it reports the lane farm.
    -- Prog.Update runs on Heartbeat at ~60 Hz.  Everything below that is not a
    -- position is therefore gated on an actual value change: a colour reassigned
    -- sixty times a second is free, but a tween or a string.format is not.
    function Prog.Update()
        local now = tick()
        local chasing = A.Chasing
        local live = chasing or A.Running
        local prog = chasing and (A.ChaseProgress or 0) or A.Progress

        -- The pod visibly spins up as the run completes; a chase pins it fast.
        -- This INTEGRATES a rate instead of doing (tick() * rate) % 360, which
        -- is the one form that cannot be used here: tick() is ~1.7e9, so the
        -- instant `prog` moves the multiplier the product jumps by billions and
        -- the gradient snaps to a random angle every single frame.
        local dt = math.min(0.05, now - (Prog.rotAt or now))
        Prog.rotAt = now
        Prog.rot = ((Prog.rot or 0) + dt * (chasing and 150 or (45 + 95 * prog))) % 360
        PB.edgeGrad.Rotation = Prog.rot

        if chasing ~= Prog.wasChase then
            Prog.wasChase = chasing
            PB.headTxt.Text = chasing and "POLICE CHASE" or "AUTOMATION"
            PB.headTxt.TextColor3 = chasing and THEME.Warn or THEME.Sub
            PB.kNear.Text = chasing and "CHASES DONE" or "NEAR MISSES"
            -- the near-miss gate is shared by two unrelated counters (laps vs
            -- misses); clearing it on the flip stops a stale compare freezing
            -- the value when the two numbers happen to coincide
            Prog.lastNear, Prog.lastNearRate = nil, nil
            if chasing then
                TH.g[PB.edgeGrad] = nil          -- detach: the chase PB.edge is never recoloured
                PB.edgeGrad.Color = PB.EDGE_CHASE
            else
                TH.g[PB.edgeGrad] = PB.EDGE_KEYS    -- reattach and repaint from the live accent
                TH.paintGrad(PB.edgeGrad)
            end
        end
        if live ~= Prog.wasLive then
            Prog.wasLive = live
            PB.dot.BackgroundColor3 = live and THEME.Good or THEME.Dim
        end
        -- breathes off the one shared clock rather than a per-pod looping tween
        PB.dot.BackgroundTransparency = live and (0.05 + 0.34 * (1 - (TH.pulse or 0))) or 0.55

        local mph = math.floor(A.Mph + 0.5)
        if mph ~= Prog.lastMph then
            Prog.lastMph = mph
            PB.speedLbl.Text = mph .. " MPH"
        end

        local lt = chasing and (A.ChaseNote or "") or A.Logic
        if PB.logic.Text ~= lt then PB.logic.Text = lt end

        -- lerp, never tw(): a tween here would allocate a TweenInfo and a Tween
        -- sixty times a second.  Four tokens, zero allocation, and it glides.
        PB.bar.Size = UDim2.new(lerp(PB.bar.Size.X.Scale, math.clamp(prog, 0, 1), 0.18), 0, 1, 0)

        local pct = math.floor(prog * 100 + 0.5)
        if pct ~= Prog.lastPct or chasing ~= Prog.pctChase then
            Prog.lastPct, Prog.pctChase = pct, chasing
            PB.pctLbl.Text = chasing and ("stage " .. pct .. "%") or (pct .. "%")
        end

        local stall = A.EarnStalled or 0
        if live and stall > 20 then
            local st = math.floor(stall)
            if Prog.lastStall ~= st then
                Prog.lastStall = st
                Prog.lastEarn = nil
                PB.vEarn.Text = string.format("STALLED %s  ·  press a key", fmtTime(st))
            end
            PB.vEarn.TextColor3 = THEME.Bad
        else
            local em, er = math.floor(A.EarnMoney or 0), math.floor(A.EarnRate or 0)
            -- Its own key.  This used to share Prog.lastRate with the speed
            -- tile below, so each one's cache hit froze the other's label.
            if Prog.lastEarn ~= em or Prog.lastMoneyRate ~= er then
                Prog.lastEarn, Prog.lastMoneyRate, Prog.lastStall = em, er, nil
                PB.vEarn.Text = string.format("$%s  ·  %s/min", fmtNum(em), fmtNum(er))
            end
            PB.vEarn.TextColor3 = ((A.EarnRate or 0) > 0) and THEME.Good or THEME.Sub
        end

        local secs = live and math.floor(now - A.StartedAt) or 0
        if secs ~= Prog.lastSec then
            Prog.lastSec = secs
            PB.vTime.Text = fmtTime(secs)
        end
        -- the per-run clock is the one that is allowed to reset
        local runSecs = (live and A.RunStartedAt and A.RunStartedAt > 0)
            and math.floor(now - A.RunStartedAt) or 0
        if runSecs ~= Prog.lastRun then
            Prog.lastRun = runSecs
            PB.vRun.Text = fmtTime(runSecs)
        end
        local rate = math.floor((A.Mph or 0) + 0.5)
        if rate ~= Prog.lastRate then
            Prog.lastRate = rate
            PB.vRate.Text = rate .. " MPH"
        end
        -- fmtNum floors internally, so formatting the already-floored `studs`
        -- prints exactly what fmtNum(A.Studs) printed, and cannot be handed a nil
        local studs = math.floor(A.Studs or 0)
        if studs ~= Prog.lastStuds then
            Prog.lastStuds = studs
            PB.vDist.Text = fmtNum(studs)
        end

        if chasing then
            local laps = A.ChaseLaps or 0
            if Prog.lastNear ~= laps then
                Prog.lastNear = laps
                PB.vNear.Text = tostring(laps)
            end
            PB.vNear.TextColor3 = THEME.Warn
        else
            local nm, nr = A.NearMiss, math.floor(A.NearRate + 0.5)
            if Prog.lastNear ~= nm or Prog.lastNearRate ~= nr then
                Prog.lastNear, Prog.lastNearRate = nm, nr
                PB.vNear.Text = string.format("%d  (%d/min)", nm, nr)
            end
            -- flash the near-miss row as points land; the pop is fired on the
            -- TRANSITION only, never on every frame of the 0.35s window.
            -- `lp > 0` suppresses a spurious pop on the very first update,
            -- where passAt is nil and lastPass has never been stamped.
            local lp = route.lastPass or 0
            if lp ~= Prog.passAt then
                Prog.passAt = lp
                if lp > 0 then
                    PB.nearScale.Scale = 1.12
                    FX.tw(PB.nearScale, 0.28, { Scale = 1 }, FX.E.snap)
                end
            end
            PB.vNear.TextColor3 = (now - lp < 0.35) and THEME.Good or THEME.Sub
        end
    end
end

--============================================================================
-- AUTOMATION : DRIVE MODES
--============================================================================
-- THE DRIVER  (places the car on the spline - exact at any speed)
-- A cursor moves along the curve at exactly the requested speed and the car is
-- put there.  No steering loop, so nothing to overshoot: accuracy does not
-- degrade as speed rises.  Only the ground height and the surface normal are
-- smoothed, because a raycast can jump between surfaces.
--
-- `hoverH` is the ride height above the ground the raycast found. The root
-- sits inside the body, so wheels-on-the-deck is A.NormalHeight (2), not 0; the
-- Hover slider passes its own number instead. Physics steering used to be the
-- alternative and was deleted -
-- it wobbled past ~200 MPH, which made the dodge aim at a car that was never
-- quite where the steering had promised to put it.
local function drivePosition(root, lane, speedStuds, dt, fly, hoverH)
    local model = S.Car.Model
    if not model then return end

    -- (re)acquire the cursor if it was invalidated or the car got moved away.
    -- HORIZONTAL, like the forward walk in syncRoute that it feeds.  A 3D test
    -- measures the ride height as well: route.cursorPos is on the road and the
    -- car is at ground + hover, so past ~90 studs of hover this was true EVERY
    -- frame.  The cursor got re-seeded each time while route.wp still advanced
    -- normally, so the car moved one whole waypoint per frame - about 2250 MPH
    -- on the baked route - with the speed readout still showing the commanded
    -- number, because that is written from the velocity we ask for.
    if not route.cursorPos or flatDist(route.cursorPos, root.Position) > 90 then
        route.segIdx, route.segT = route.wp, 0
        route.cursorPos = lane.points[route.wp].pos
        route.smoothY = nil
        route.smoothNormal = nil
    end

    route.segIdx, route.segT = splineWalk(lane, route.segIdx, route.segT, speedStuds * dt)
    local pos = splinePoint(lane, route.segIdx, route.segT)
    route.cursorPos = pos
    route.wp = route.segIdx

    local dir = splineTangent(lane, route.segIdx, route.segT) or carForward()

    -- slide sideways around traffic while staying on the line
    local dodge = route.dodge or 0
    if math.abs(dodge) > 0.01 then
        pos = pos + Vector3.new(-dir.Z, 0, dir.X) * dodge
    end

    local probe = groundAt(pos)
    local groundY = probe and probe.Position.Y or pos.Y
    local y = fly and (groundY + (hoverH or A.Hover)) or (groundY + route.yOffset)
    local nrm = (not fly and probe) and probe.Normal or Vector3.yAxis
    local a = math.clamp(dt * 14, 0, 1)
    route.smoothY = route.smoothY and lerp(route.smoothY, y, a) or y
    route.smoothNormal = route.smoothNormal and route.smoothNormal:Lerp(nrm, a).Unit or nrm

    local target = Vector3.new(pos.X, route.smoothY, pos.Z)
    local goalRoot
    if A.Rotate then
        goalRoot = CFrame.new(target) * rotationFor(dir, route.smoothNormal)
    else
        goalRoot = CFrame.new(target) * root.CFrame.Rotation   -- translate only
    end
    local offset = root.CFrame:ToObjectSpace(model:GetPivot())
    pcall(function() model:PivotTo(goalRoot * offset) end)

    -- keep the assembly reporting real motion so speedometers and any
    -- proximity scoring still see a moving car
    root.AssemblyLinearVelocity = dir * speedStuds
    root.AssemblyAngularVelocity = Vector3.zero
    return dir
end

--============================================================================
-- AUTOMATION : BRAIN
--============================================================================
local function computeProgress(lane, wp)
    if A.Goal == "Distance (mi)" then
        local miles = A.Studs * CONFIG.MilesPerStud
        return math.clamp(miles / math.max(0.1, A.GoalValue), 0, 1)
    elseif A.Goal == "Time (min)" then
        local mins = (tick() - A.StartedAt) / 60
        return math.clamp(mins / math.max(0.1, A.GoalValue), 0, 1)
    elseif A.Goal == "Near misses" then
        return math.clamp(A.NearMiss / math.max(1, A.GoalValue * 10), 0, 1)
    end
    if lane then return math.clamp((lane.cum[wp] or 0) / math.max(1, lane.length), 0, 1) end
    return 0
end

-- Points come from passing traffic closely, so an empty road is not a reason to
-- open up and a busy one is not a reason to slow down.  Only a car actually in
-- our path, or a corner, costs us speed.
local function smartSpeed(obstacle, curvature)
    local p = CONFIG.Profiles[A.Profile] or CONFIG.Profiles.Normal
    local obsF   = math.clamp(obstacle / 200, 0, 1)
    local curveF = 1 - math.clamp(curvature / 0.95, 0, 1)
    local conf = obsF * 0.45 + curveF * 0.55
    return lerp(p.min, p.max, math.clamp(conf, 0, 1))
end

-- re-acquire our position on the lane network
local function syncRoute(pos)
    -- The lane map can be rebuilt UNDER a running drive.  TrafficLanes streams
    -- in only once somebody has driven down there, so a session that starts
    -- automation early is driving a baked-in route when the real network
    -- appears - and World.BuildLanes replaces World.paths wholesale rather than
    -- adding to it.  Dropping both indices here sends us through the
    -- re-acquire below on the very next frame, instead of indexing a lane that
    -- no longer exists at that position and stopping the car dead.
    if route.pathsGen ~= World.pathsGen then
        route.pathsGen = World.pathsGen
        route.laneIdx, route.wp = nil, nil
        route.cursorPos = nil
        route.laneSeed = {}
    end
    local lane = World.paths[route.laneIdx]
    if A.Lane ~= "Auto" then
        local li = World.LaneByName(A.Lane)
        if li and li ~= route.laneIdx then
            route.laneIdx = li
            lane = World.paths[li]
            route.wp = World.NearestIndex(lane, pos)
            route.cursorPos = nil   -- spline cursor indexes a lane, re-acquire it
        end
    end
    if not lane then
        local li, wi = World.NearestLane(pos, carForward())
        if not li then return nil end
        route.laneIdx, route.wp = li, wi
        lane = World.paths[li]
    end
    -- A waypoint index is only ever valid for the lane it was taken from, and
    -- several paths above can hand us one from a different lane.  Indexing past
    -- the end returns nil and the .pos below is what actually killed the drive,
    -- so cost a re-acquire instead of an error whatever the cause.
    if not (lane.points and lane.points[route.wp]) then
        -- a lane with no points at all is not something NearestIndex can help
        -- with, and handing it one is how this guard would have errored itself
        if not lane.points then return nil end
        route.wp = World.NearestIndex(lane, pos)
        route.cursorPos = nil
        if not lane.points[route.wp] then return nil end
    end

    -- drifted off the lane entirely -> re-acquire (throttled: this is a full scan)
    -- Horizontal for the same reason as the cursor test: ride height is not drift.
    local d = flatDist(lane.points[route.wp].pos, pos)
    if d > 180 and (tick() - (route.lastAcquire or 0)) > 0.25 then
        route.lastAcquire = tick()
        if A.Lane == "Auto" then
            local li, wi = World.NearestLane(pos, carForward())
            if li then route.laneIdx, route.wp = li, wi lane = World.paths[li] end
        else
            route.wp = World.NearestIndex(lane, pos)
        end
        route.cursorPos = nil
    end
    -- walk the waypoint index forward past anything we have already passed
    local fwd = carForward()
    local guard = 0
    while guard < 40 do
        guard = guard + 1
        local p = lane.points[route.wp].pos
        local rel = p - pos
        local flat = Vector3.new(rel.X, 0, rel.Z)
        if flat.Magnitude < 16 or flat.Unit:Dot(fwd) < 0.15 then
            local nxt = World.Step(lane, route.wp, 1)
            if nxt == route.wp then break end
            route.wp = nxt
        else
            break
        end
    end

    -- Ran off the end of a path that was not flagged as a circuit.  Sitting on
    -- the last waypoint is exactly what "breaks after one lap" looks like, so
    -- wrap to the start instead; if the start is somewhere else entirely, the
    -- drift check above re-acquires a path on the next pass.
    if not lane.loop and route.wp >= #lane.points then
        -- horizontal: at 90+ studs of hover a 3D test never passed, so the car
        -- parked on the last waypoint of any path that is not a circuit
        if flatDist(lane.points[#lane.points].pos, pos) < 90 then
            route.wp = 1
            route.cursorPos = nil
            route.laps = (route.laps or 0) + 1
        end
    end

    return lane
end


local function autoFrame(dt)
    local root = S.Car.Root
    local hasCar = root and root.Parent
    local speedStuds = hasCar and Car.Speed() or 0
    A.Mph = toMph(speedStuds)

    local lane
    if hasCar and #World.paths > 0 then
        lane = syncRoute(root.Position)
    end
    -- published for the waypoint ESP so it can highlight the path in use
    A.ActivePathName = lane and lane.name or nil

    Earn.Poll()

    -- near-miss rate, for the readout
    if A.Running and A.StartedAt > 0 then
        local mins = (tick() - A.StartedAt) / 60
        A.NearRate = (mins > 0.05) and (A.NearMiss / mins) or 0
    end

    -- ---------------------------------------------------------- driving
    if A.Running then
        if not hasCar then
            A.Logic = "Waiting for vehicle"
        elseif not lane then
            A.Logic = "No traffic lanes found"
        else
            if not route.calibrated then Auto.Calibrate() end

            local pos = root.Position
            -- aim at a point on the smoothed line; the faster we go the further
            -- ahead we look, which is what keeps a steered car from oscillating
            local lookDist = math.clamp(speedStuds * 0.40, 30, 320)
            local aimIdx, aimT = splineWalk(lane, route.wp, 0, lookDist)
            local targetPos = splinePoint(lane, aimIdx, aimT)
            local dir = targetPos - pos
            dir = Vector3.new(dir.X, 0, dir.Z)
            dir = dir.Magnitude > 0.05 and dir.Unit or carForward()

            -- curvature over the next stretch
            local farIdx, farT = splineWalk(lane, aimIdx, aimT, 140)
            local farPos = splinePoint(lane, farIdx, farT)
            local d2 = farPos - targetPos
            d2 = Vector3.new(d2.X, 0, d2.Z)
            local curvature = 0
            if d2.Magnitude > 0.05 then
                curvature = math.acos(math.clamp(dir:Dot(d2.Unit), -1, 1))
            end

            local obstacle, scoring, density = trafficScan(pos, dir)

            -- Path choice: hunt for the line with the most traffic to brush past,
            -- rather than the emptiest lane.
            if A.Overtake and A.Lane == "Auto" and (tick() - route.lastSwitch) > 2.5 then
                local altIdx, altScore = bestPath(pos, dir)
                if altIdx and altIdx ~= route.laneIdx then
                    local curScore = scorePath(lane, pos, dir)
                    if altScore > math.max(0.5, curScore * 1.25) then
                        route.laneIdx = altIdx
                        lane = World.paths[altIdx]
                        route.wp = World.NearestIndex(lane, pos)
                        route.lastSwitch = tick()
                        route.cursorPos = nil
                        A.Logic = "Moving to " .. lane.name
                    end
                end
            end

            -- speed decision
            local targetMph
            if A.SpeedMode == "Static" then
                targetMph = A.StaticMph
                A.Logic = string.format("Static cruise · %s", lane.name)
            else
                targetMph = smartSpeed(obstacle, curvature)
                if curvature > 0.45 then
                    A.Logic = string.format("Corner ahead · easing to %d", math.floor(targetMph))
                elseif scoring > 0 then
                    A.Logic = string.format("%s · %d car%s in scoring range",
                        lane.name, scoring, scoring == 1 and "" or "s")
                else
                    A.Logic = string.format("%s · empty road, hunting traffic", lane.name)
                end
            end

            -- lateral avoidance first: whether a gap exists at all decides how
            -- hard we are willing to brake below
            local dodge = updateDodge(pos, dir, dt)

            -- brake only for something we would actually hit
            if obstacle < A.FollowGap and not A.NoBrake then
                local ratio = math.clamp(obstacle / math.max(1, A.FollowGap), 0, 1)
                targetMph = math.min(targetMph, math.max(12, targetMph * ratio))
                A.Logic = string.format("Car in path · %dst, easing off", math.floor(obstacle))
            elseif obstacle < A.FollowGap then
                A.Logic = string.format("Car in path · %dst, not braking", math.floor(obstacle))
            end
            -- no opening anywhere across the road: slow down rather than pick a
            -- gap we do not fit through
            if route.dodgeBlocked and not A.NoBrake then
                targetMph = math.min(targetMph, math.max(20, targetMph * 0.4))
                A.Logic = "Road blocked · no gap, easing off"
            end
            A.TargetMph = targetMph

            if (route.bubbleN or 0) > 0 and math.abs(dodge) > 0.5 then
                -- Say so explicitly: without this a cushion move is
                -- indistinguishable from a planner one, and the next bug
                -- report about "it swerved for no reason" is unreadable.
                A.Logic = string.format("Pushing off · %d car%s · %.1fst clear",
                    route.bubbleN, route.bubbleN == 1 and "" or "s",
                    route.bubbleGap or 0)
            elseif A.Dodge and math.abs(dodge) > 1 then
                if A.SmartDodge then
                    local room = route.dodgeRoom or 0
                    A.Logic = string.format("Threading · %.1fst %s · gap %s · %s",
                        math.abs(dodge), dodge > 0 and "right" or "left",
                        (room == math.huge) and "clear" or string.format("%.1f", room),
                        route.laneLock and "lane-locked" or "no lane data")
                else
                    A.Logic = string.format("Dodging · %.0fst %s", math.abs(dodge),
                        dodge > 0 and "right" or "left")
                end
            end

            -- stuck / flipped recovery
            if A.Recover then
                if speedStuds < 5 then
                    route.stuckT = route.stuckT + dt
                else
                    route.stuckT = 0
                end
                local upright = root.CFrame.UpVector.Y > 0.25
                if not upright then route.flipT = route.flipT + dt else route.flipT = 0 end

                if route.stuckT > 2.6 or route.flipT > 1.2 then
                    route.stuckT, route.flipT = 0, 0
                    A.Logic = "Recovering · re-seating on lane"
                    local wpPos = lane.points[route.wp].pos
                    local nxt = lane.points[World.Step(lane, route.wp, 1)].pos
                    local d = nxt - wpPos
                    d = Vector3.new(d.X, 0, d.Z)
                    local rdir = d.Magnitude > 0.05 and d.Unit or carForward()
                    local model = S.Car.Model
                    if model then
                        local probe = groundAt(wpPos)
                        local ry = probe and (probe.Position.Y + route.yOffset + 0.5)
                            or (wpPos.Y + route.yOffset + 1.5)
                        local goalRoot = CFrame.new(Vector3.new(wpPos.X, ry, wpPos.Z))
                            * rotationFor(rdir, probe and probe.Normal or nil)
                        local offset = root.CFrame:ToObjectSpace(model:GetPivot())
                        pcall(function() model:PivotTo(goalRoot * offset) end)
                    end
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    route.cursorPos = nil
                end
            end

            -- smooth and apply
            route.smoothMph = lerp(route.smoothMph, targetMph, math.clamp(dt * 2.6, 0, 1))
            local driveStuds = toStuds(route.smoothMph)

            -- One driver now.  The test is inverted deliberately: "Hover" is
            -- the only special case, so EVERY other value of A.Mode - including
            -- a stale "Physics Drive" out of an old config - still drives.  An
            -- equality test with an else would let a stale value fall through
            -- to nothing: no drive call, no dir, no velocity, while the HUD
            -- cheerfully reports "Running".
            -- Normal rides at A.NormalHeight, not at 0: the root sits inside
            -- the body, so putting it on the ground buries the bottom half of
            -- the car.  It is a flat number rather than route.yOffset - 0.4,
            -- because that derivation read the whole model's bounding box and
            -- came out consistently too tall.
            local d = drivePosition(root, lane, driveStuds, dt, true,
                (A.Mode == "Hover") and A.Hover
                or (A.NormalHeight or 2))
            if d then dir = d end

            -- odometer
            if route.lastPos then
                local moved = (pos - route.lastPos)
                local flat = Vector3.new(moved.X, 0, moved.Z).Magnitude
                -- Not a teleport.  A respawn or the chase's hop to the pad
                -- covers hundreds of studs between frames, and counting that
                -- as distance driven could finish a Distance goal on the spot.
                -- 200 is far past any real frame: 310 MPH is 8 studs a frame,
                -- and even 1000 MPH at 10 fps is under 160.
                if flat < 200 then A.Studs = A.Studs + flat end
            end
            route.lastPos = pos

            -- goal check.  NOT during a chase: a chase lap is not the user's
            -- drive goal, and Auto.Set deliberately does not reset the session
            -- counters while A.Chasing - so once the goal is met it stays met,
            -- and stopping the drive here just hands it straight back to the
            -- chase's own "if not A.Running then StartDriving()" half a tick
            -- later, forever.
            A.Progress = computeProgress(lane, route.wp)
            if not A.Chasing and A.Goal ~= "None" and A.Progress >= 1 then
                Auto.Set(false)
                if REF.autoToggle then REF.autoToggle:Set(false, true) end
                notify("Goal reached", string.format("%s target complete · %s studs driven",
                    A.Goal, fmtNum(A.Studs)), "good", 6)
            end
        end
    else
        route.lastPos = nil
        A.TargetMph = 0
        if lane then A.Progress = computeProgress(lane, route.wp) end
    end

    -- ------------------------------------------------------- automation ESP
    -- the path itself is drawn on RenderStepped so it tracks the camera exactly
    route.drawLane = (hasCar and lane) or nil

    if S.ESP.ProgressBox and hasCar then
        Prog.SetAdornee(root)
        Prog.SetEnabled(true)
        Prog.Update()
    else
        Prog.SetEnabled(false)
    end
end

bind(RunService.Heartbeat, autoFrame)

bind(RunService.RenderStepped, function()
    local root = S.Car.Root
    if S.ESP.PathPreview and route.drawLane and root and root.Parent then
        drawPath(route.drawLane, route.wp, root.Position)
    else
        clearPath()
    end
end)

function Auto.Set(on)
    A.Running = on
    if on then
        Car.Refresh()
        if not S.Car.Root then
            notify("No vehicle", "Could not find " .. LocalPlayer.Name .. "_<car> in the workspace.", "bad")
            A.Running = false
            if REF.autoToggle then REF.autoToggle:Set(false, true) end
            return
        end
        if #World.paths == 0 then World.BuildLanes() end
        if #World.paths == 0 then
            notify("No lanes", "workspace.TrafficLanes was not found - automation needs it.", "bad")
            A.Running = false
            if REF.autoToggle then REF.autoToggle:Set(false, true) end
            return
        end
        if S.Fly.Enabled then
            Fly.Set(false)
            if REF.flyToggle then REF.flyToggle:Set(false, true) end
        end
        Auto.Calibrate()
        route.stuckT, route.flipT = 0, 0
        route.cursorPos = nil
        route.lastPos = nil
        route.smoothMph = A.Mph
        -- A chase restarts Auto once per lap.  Session totals (earned, time
        -- automating, studs, near misses) belong to the whole chase session, so
        -- only a NON-chase start clears them; the per-run clock always restarts.
        if not A.Chasing then
            A.StartedAt = tick()
            A.Studs = 0
            A.NearMiss, A.NearRate = 0, 0
            Earn.Reset()
        end
        A.RunStartedAt = tick()
        A.Logic = "Starting up"

        -- start on whichever path pays best, unless one was picked by hand
        if A.Lane == "Auto" then
            local li, score = bestPath(S.Car.Root.Position, carForward())
            if li then
                route.laneIdx = li
                route.wp = World.NearestIndex(World.paths[li], S.Car.Root.Position)
            else
                local nl, nw = World.NearestLane(S.Car.Root.Position, carForward())
                if nl then route.laneIdx, route.wp = nl, nw end
            end
        else
            local li = World.LaneByName(A.Lane)
            local nl, nw = World.NearestLane(S.Car.Root.Position, carForward())
            route.laneIdx = li or nl or 1
            route.wp = World.NearestIndex(World.paths[route.laneIdx], S.Car.Root.Position)
        end
        -- Seeded from the CURRENT array, so the generation check in syncRoute
        -- does not immediately throw away the path bestPath just chose.
        route.pathsGen = World.pathsGen
        route.lastSwitch = tick()

        notify("Automation started", (World.paths[route.laneIdx] and World.paths[route.laneIdx].name or "?")
            .. "  ·  " .. (A.SpeedMode == "Static"
            and (tostring(math.floor(A.StaticMph)) .. " MPH") or (A.Profile .. " profile")), "good")
    else
        A.Logic = "Idle"
        Rig.Clear("auto")
        route.cursorPos = nil
    end
end

Car.onChanged[#Car.onChanged + 1] = function()
    route.calibrated = false
    route.cursorPos = nil
    Rig.Clear("auto")
    Rig.Clear("fly")
    if S.Car.Root then Auto.Calibrate() end
end

--============================================================================
-- WORLD CONTROL  (clear police / clear traffic)
--============================================================================
-- Two independent jobs.  Each watches a set of workspace folders and either
-- deletes new arrivals or anchors them, after an optional per-unit delay.
--   Delete : client-side Destroy, cannot be undone (they respawn server side).
--   Anchor : Anchored = true on every BasePart we touched, remembered so the
--            toggle can put it back.  Re-applied on every sweep because the
--            server can flip Anchored back.
--============================================================================
local WorldCtl = { jobs = {} }

local function newJob(name, folders, chain)
    local job = {
        name = name, folders = folders, chain = chain,
        enabled = false, delay = 0, mode = "Delete",
        count = 0, anchoredCount = 0,
        anchored = {}, seen = setmetatable({}, { __mode = "k" }), thread = nil,
    }
    WorldCtl.jobs[name] = job
    return job
end

-- Workspace.PoliceAI -> <unit> -> Body -> "LAPolice Car" -> Body
local jobPolice  = newJob("Police", { "PoliceAI", "PoliceHelicopters" }, { "Body", "LAPolice Car", "Body" })
local jobTraffic = newJob("Traffic", { "TrafficFolder" }, nil)

local function resolveChain(root, chain)
    local cur = root
    for _, nm in ipairs(chain) do
        local nxt = cur:FindFirstChild(nm) or cur:FindFirstChild(nm, true)
        if not nxt then return nil end
        cur = nxt
    end
    return cur
end

local function anchorUnder(node, store)
    local n = 0
    local function take(p)
        if p:IsA("BasePart") and not p.Anchored then
            store[p] = true
            p.Anchored = true
            n = n + 1
        end
    end
    if node:IsA("BasePart") then take(node) end
    for _, d in ipairs(node:GetDescendants()) do take(d) end
    return n
end

local function isProtected(inst)
    if inst == S.Car.Model then return true end
    if LocalPlayer.Character and (inst == LocalPlayer.Character or LocalPlayer.Character:IsDescendantOf(inst)) then
        return true
    end
    -- never touch a model that carries our username (our own vehicle)
    if inst.Name:lower():sub(1, #LocalPlayer.Name + 1) == LocalPlayer.Name:lower() .. "_" then return true end
    return false
end

local function processUnit(job, inst, isHeli)
    if not inst or not inst.Parent then return end
    if isProtected(inst) then return end

    if job.mode == "Delete" then
        local ok = pcall(function() inst:Destroy() end)
        if ok then job.count = job.count + 1 end
    else
        -- helicopters are not anchorable in this game, skip them entirely
        if isHeli then return end
        local node = (job.chain and resolveChain(inst, job.chain)) or inst
        local n = anchorUnder(node, job.anchored)
        if n > 0 then
            job.count = job.count + 1
            job.anchoredCount = job.anchoredCount + n
        end
    end
end

local function scheduleUnit(job, inst, isHeli)
    if job.delay <= 0 then
        processUnit(job, inst, isHeli)
    else
        task.delay(job.delay, function()
            if job.enabled then processUnit(job, inst, isHeli) end
        end)
    end
end

function WorldCtl.Stop(job)
    job.enabled = false
    job.thread = nil
    local restored = 0
    for p in pairs(job.anchored) do
        if p and p.Parent then
            pcall(function() p.Anchored = false end)
            restored = restored + 1
        end
    end
    job.anchored = {}
    job.anchoredCount = 0
    job.seen = setmetatable({}, { __mode = "k" })
    return restored
end

function WorldCtl.Start(job)
    if job.enabled then return end
    job.enabled = true
    job.count = 0
    job.seen = setmetatable({}, { __mode = "k" })

    local found = false
    for _, fname in ipairs(job.folders) do
        if Workspace:FindFirstChild(fname) then found = true end
    end
    if not found then
        notify(job.name .. " not found",
            "None of: " .. table.concat(job.folders, ", ") .. " exist in the workspace yet - watching for them.",
            "warn", 6)
    end

    job.gen = (job.gen or 0) + 1
    local myGen = job.gen
    job.thread = task.spawn(function()
        while job.enabled and job.gen == myGen do
            for _, fname in ipairs(job.folders) do
                local folder = Workspace:FindFirstChild(fname)
                if folder then
                    local isHeli = (fname == "PoliceHelicopters")
                    for _, child in ipairs(folder:GetChildren()) do
                        if not job.seen[child] then
                            job.seen[child] = true
                            scheduleUnit(job, child, isHeli)
                        end
                    end
                end
            end
            -- the server can un-anchor what we anchored, so hold it down
            if job.mode == "Anchor" then
                for p in pairs(job.anchored) do
                    if p and p.Parent then
                        if not p.Anchored then pcall(function() p.Anchored = true end) end
                    else
                        job.anchored[p] = nil
                    end
                end
            end
            task.wait(0.25)
        end
    end)
end

function WorldCtl.SetMode(job, mode)
    if job.mode == mode then return end
    -- leaving Anchor mode releases everything we held
    if job.mode == "Anchor" then
        for p in pairs(job.anchored) do
            if p and p.Parent then pcall(function() p.Anchored = false end) end
        end
        job.anchored = {}
        job.anchoredCount = 0
    end
    job.mode = mode
    job.seen = setmetatable({}, { __mode = "k" })  -- re-evaluate everything under the new mode
end

--============================================================================
-- WORLD CONTROL : TRAFFIC HITBOXES
--============================================================================
-- workspace.TrafficFolder -> <car> -> CoreHitbox is what you actually collide
-- with.  Shrinking it lets the car pass through traffic while everything still
-- renders normally.  Original sizes are kept so the toggle can put them back.
local TRAFFIC_HITBOX_SIZE = Vector3.new(1, 1, 1)        -- traffic CoreHitbox
-- TrafficHitboxLeft / Right, enlarged.  Presets rather than a slider so the
-- sizes stay exact and repeatable.
local SCORE_ORDER = { "1 · 30 x 15 x 30", "2 · 60 x 30 x 60", "3 · 150 x 150 x 150" }
local SCORE_SIZES = {
    [SCORE_ORDER[1]] = Vector3.new(30, 15, 30),
    [SCORE_ORDER[2]] = Vector3.new(60, 30, 60),
    [SCORE_ORDER[3]] = Vector3.new(150, 150, 150),
}
local SCORE_BOX_ORIGINAL  = Vector3.new(9.801773071289062, 0.10980954021215439, 14.289976119995117)
local SCORE_BOX_NAMES     = { TrafficHitboxLeft = true, TrafficHitboxRight = true }

-- true if a size is one of ours, so a re-run never records an enlarged box as
-- the original no matter which preset was left active
local function isScorePreset(s)
    for _, v in pairs(SCORE_SIZES) do
        if (s - v).Magnitude < 0.5 then return true end
    end
    return false
end

local Collide = {
    noTraffic = false, scoreBox = false,
    mode = "Pass through (keep size)", grow = 1, reverted = 0, watch = nil,
    origCan = setmetatable({}, { __mode = "k" }),
    scoreMode = SCORE_ORDER[1],
    origCollide = setmetatable({}, { __mode = "k" }),
    origScore   = setmetatable({}, { __mode = "k" }),
    trafficN = 0, localN = 0, scoreN = 0,
    gen = 0,
}

local function resize(p, size)
    if p.Size ~= size then pcall(function() p.Size = size end) end
end

local function remember(store, p, bigSize, knownOriginal)
    if store[p] == nil then
        local s = p.Size
        -- re-running the script while already enlarged must not record the
        -- enlarged size as the original
        if bigSize and (s - bigSize).Magnitude < 0.5 then s = knownOriginal end
        store[p] = s
    end
end

-- traffic side: workspace.TrafficFolder -> <car> -> CoreHitbox
local function trafficHitboxes(car)
    local out = {}
    local direct = car:FindFirstChild("CoreHitbox")
    if direct and direct:IsA("BasePart") then
        out[#out + 1] = direct
    else
        for _, d in ipairs(car:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "CoreHitbox" then out[#out + 1] = d end
        end
    end
    return out
end

-- our side: every collision box on the local car, minus the two scoring boxes
-- the two boxes the game measures close passes with
Collide.scoreFound, Collide.scoreScanAt = {}, 0
local function scoreBoxParts()
    local out = {}
    local car = S.Car.Model
    if car then
        for _, d in ipairs(car:GetDescendants()) do
            if d:IsA("BasePart") and SCORE_BOX_NAMES[d.Name] then out[#out + 1] = d end
        end
    end
    if #out > 0 then return out end
    for name, p in pairs(Collide.scoreFound) do
        if p and p.Parent then out[#out + 1] = p else Collide.scoreFound[name] = nil end
    end
    if #out == 0 and tick() - Collide.scoreScanAt > 5 then      -- full scan, used sparingly
        Collide.scoreScanAt = tick()
        for name in pairs(SCORE_BOX_NAMES) do
            local p = Workspace:FindFirstChild(name, true)
            if p and p:IsA("BasePart") then
                Collide.scoreFound[name] = p
                out[#out + 1] = p
            end
        end
    end
    return out
end

local function collideSweep()
    if Collide.noTraffic then
        local n = 0
        local mode = Collide.mode
        local folder = Workspace:FindFirstChild("TrafficFolder")
        if folder then
            for _, car in ipairs(folder:GetChildren()) do
                if car.Parent and not isProtected(car) then
                    -- CoreHitbox is not necessarily the only thing you can hit, so
                    -- every collidable part of the car goes non-collidable. Each
                    -- original is recorded so all of it can be put back.
                    if mode ~= "Shrink to 1" then
                        for _, d in ipairs(car:GetDescendants()) do
                            if d:IsA("BasePart") then
                                if Collide.origCan[d] == nil then Collide.origCan[d] = d.CanCollide end
                                if d.CanCollide then
                                    pcall(function() d.CanCollide = false end)
                                end
                            end
                        end
                    end
                    for _, p in ipairs(trafficHitboxes(car)) do
                        if mode == "Shrink to 1" then
                            remember(Collide.origCollide, p)
                            resize(p, TRAFFIC_HITBOX_SIZE)
                        else
                            -- CanCollide is what makes you bounce off; Size is what
                            -- the scoring overlap is measured against. Clearing the
                            -- first and leaving the second lets you drive straight
                            -- through a hitbox that is still big enough to count.
                            remember(Collide.origCollide, p)
                            if mode == "Pass through + enlarge" then
                                resize(p, Collide.origCollide[p] * Collide.grow)
                            else
                                resize(p, Collide.origCollide[p])
                            end
                        end
                        n = n + 1
                    end
                end
            end
        end
        Collide.trafficN = n
        -- Your OWN collision boxes are deliberately never touched: writing to
        -- them is what the September detection watches for, and unlike a local
        -- camera tweak those edits replicate.
    end

    if Collide.scoreBox then
        local want = SCORE_SIZES[Collide.scoreMode] or SCORE_SIZES[SCORE_ORDER[1]]
        local n3 = 0
        for _, p in ipairs(scoreBoxParts()) do
            if Collide.origScore[p] == nil then
                local s = p.Size
                if isScorePreset(s) then s = SCORE_BOX_ORIGINAL end
                Collide.origScore[p] = s
            end
            resize(p, want)
            n3 = n3 + 1
        end
        Collide.scoreN = n3
    end
end

local function restoreStore(store)
    local n = 0
    for p, size in pairs(store) do
        if p and p.Parent then
            pcall(function() p.Size = size end)
            n = n + 1
        end
        store[p] = nil
    end
    return n
end

-- Counts how many parts the game has put BACK to collidable since last frame.
-- A 0.25s sweep leaves a quarter second of solid car if the game is fighting
-- us; this re-asserts every frame and reports whether that is happening.
bind(RunService.Heartbeat, function()
    if not (Collide.noTraffic and Collide.mode ~= "Shrink to 1") then return end
    local fixed = 0
    for p, _ in pairs(Collide.origCan) do
        if p and p.Parent then
            if p.CanCollide then
                pcall(function() p.CanCollide = false end)
                fixed = fixed + 1
            end
        else
            Collide.origCan[p] = nil
        end
    end
    Collide.reverted = fixed
end)

function Collide.Strip(car)
    if not car or not car.Parent or isProtected(car) then return 0 end
    local n = 0
    for _, d in ipairs(car:GetDescendants()) do
        if d:IsA("BasePart") then
            if Collide.origCan[d] == nil then Collide.origCan[d] = d.CanCollide end
            if d.CanCollide then
                pcall(function() d.CanCollide = false end)
                n = n + 1
            end
        end
    end
    return n
end

function Collide.WatchFolder(on)
    if Collide.watch then Collide.watch:Disconnect() Collide.watch = nil end
    if not on then return end
    local folder = Workspace:FindFirstChild("TrafficFolder")
    if not folder then return end
    Collide.watch = folder.ChildAdded:Connect(function(car)
        if Collide.noTraffic and Collide.mode ~= "Shrink to 1" then
            task.defer(Collide.Strip, car)      -- let its parts replicate in first
        end
    end)
    CONN[#CONN + 1] = Collide.watch
end

local function collideEnsureLoop()
    if Collide.gen > 0 then return end
    Collide.gen = 1
    task.spawn(function()
        while Collide.noTraffic or Collide.scoreBox do
            local ok, err = pcall(collideSweep)
            if not ok then warn("[AdminTools] collide sweep:", err) end
            task.wait(0.25)
        end
        Collide.gen = 0     -- loop has exited, next enable starts a fresh one
    end)
end

function Collide.SetNoTraffic(on)
    Collide.noTraffic = on
    if on then
        if not Workspace:FindFirstChild("TrafficFolder") then
            notify("No traffic folder", "workspace.TrafficFolder does not exist yet - watching for it.", "warn", 6)
        end
        collideEnsureLoop()
        Collide.WatchFolder(true)
        return 0
    end
    Collide.WatchFolder(false)
    Collide.trafficN = 0
    for p, can in pairs(Collide.origCan) do
        if p and p.Parent then pcall(function() p.CanCollide = can end) end
        Collide.origCan[p] = nil
    end
    return restoreStore(Collide.origCollide)
end

function Collide.SetScoreBox(on)
    Collide.scoreBox = on
    if on then
        collideEnsureLoop()
        return 0
    end
    Collide.scoreN = 0
    return restoreStore(Collide.origScore)
end

--============================================================================
-- PLAYER PULSE
--============================================================================
-- A ring blooms outward from each footfall and slams downward on a jump. Purely
-- decorative. Rings are real world parts because a screen-space circle cannot
-- sit flat on the ground and read as a ring - so this is the one feature here
-- that writes to Workspace, and it is off by default.
local Pulse = {
    enabled = false, jumps = true, size = 1.0, life = 0.55,
    colour = Color3.fromRGB(120, 200, 255), rgb = false, includeLocal = true,
    pool = {}, live = {}, folder = nil, walkers = {}, hue = 0, count = 0,
}

function Pulse.Folder()
    if Pulse.folder and Pulse.folder.Parent then return Pulse.folder end
    Pulse.folder = new("Folder", { Name = "AT_Pulse", Parent = Workspace })
    return Pulse.folder
end

function Pulse.Take()
    local p = table.remove(Pulse.pool)
    if p and p.Parent then return p end
    return new("Part", {
        Name = "ring", Shape = Enum.PartType.Cylinder, Anchored = true,
        CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
        Material = Enum.Material.Neon, Size = Vector3.new(0.12, 1, 1),
        Transparency = 1, Parent = Pulse.Folder(),
    })
end

function Pulse.Spawn(pos, kind)
    if #Pulse.live >= 34 then return end            -- hard ceiling, not a target
    local p = Pulse.Take()
    -- a Cylinder's flat faces are on its X axis, so it has to be laid down
    p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    p.Color = Pulse.colour
    p.Transparency = 0.25
    p.Size = Vector3.new(0.12, 1, 1)
    p.Parent = Pulse.Folder()
    Pulse.live[#Pulse.live + 1] = { part = p, t = 0, kind = kind, y = pos.Y }
    Pulse.count = Pulse.count + 1
end

function Pulse.Step(dt)
    -- grow and fade whatever is alive, recycling finished rings
    for i = #Pulse.live, 1, -1 do
        local r = Pulse.live[i]
        r.t = r.t + dt
        local a = r.t / Pulse.life
        if a >= 1 or not r.part.Parent then
            r.part.Transparency = 1
            table.remove(Pulse.live, i)
            if #Pulse.pool < 40 then Pulse.pool[#Pulse.pool + 1] = r.part end
        else
            local ease = 1 - (1 - a) * (1 - a)              -- ease-out
            if r.kind == "jump" then
                -- a splash: wider, faster, and it drops as it spreads
                local w = (1 + 13 * ease) * Pulse.size
                r.part.Size = Vector3.new(0.12, w, w)
                r.part.CFrame = CFrame.new(r.part.Position.X, r.y - ease * 1.2, r.part.Position.Z)
                    * CFrame.Angles(0, 0, math.rad(90))
            else
                local w = (1 + 6 * ease) * Pulse.size
                r.part.Size = Vector3.new(0.12, w, w)
            end
            r.part.Transparency = 0.25 + 0.75 * a
        end
    end

    if not Pulse.enabled then return end
    if Pulse.rgb then
        Pulse.hue = (Pulse.hue + dt * 0.12) % 1
        Pulse.colour = Color3.fromHSV(Pulse.hue, 0.65, 1)
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer or Pulse.includeLocal then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum then
                local w = Pulse.walkers[plr]
                if not w then
                    w = { last = hrp.Position, stride = 0, wasJump = false }
                    Pulse.walkers[plr] = w
                end
                local moved = (hrp.Position - w.last)
                w.last = hrp.Position

                -- a step every ~2.6 studs of ground travel reads as a stride at
                -- default WalkSpeed without needing the animation events
                local flat = Vector3.new(moved.X, 0, moved.Z).Magnitude
                local grounded = hum.FloorMaterial ~= Enum.Material.Air
                if grounded and flat > 0 then
                    w.stride = w.stride + flat
                    if w.stride >= 2.6 then
                        w.stride = 0
                        Pulse.Spawn(hrp.Position - Vector3.new(0, hum.HipHeight + 0.4, 0), "step")
                    end
                end

                local jumping = (hum:GetState() == Enum.HumanoidStateType.Jumping)
                if Pulse.jumps and jumping and not w.wasJump then
                    Pulse.Spawn(hrp.Position - Vector3.new(0, hum.HipHeight + 0.2, 0), "jump")
                end
                w.wasJump = jumping
            end
        end
    end
end

function Pulse.Clear()
    for _, r in ipairs(Pulse.live) do pcall(function() r.part:Destroy() end) end
    for _, p in ipairs(Pulse.pool) do pcall(function() p:Destroy() end) end
    Pulse.live, Pulse.pool, Pulse.walkers = {}, {}, {}
    if Pulse.folder then
        pcall(function() Pulse.folder:Destroy() end)
        Pulse.folder = nil
    end
end

function Pulse.Set(on)
    Pulse.enabled = on
    if not on then Pulse.Clear() end
end

bind(RunService.Heartbeat, function(dt)
    if Pulse.enabled or #Pulse.live > 0 then
        local ok, err = pcall(Pulse.Step, dt)
        if not ok then warn("[AdminTools] pulse:", err) end
    end
end)

--============================================================================
-- FUN  (client side only, helps nothing, all reversible)
--============================================================================
-- Everything here records what it touched and puts it back. Lighting, gravity
-- and camera changes are local to this client and never replicate; the traffic
-- effects are cosmetic layers over cars the game carries on driving.
local Fun = {
    sky   = { on = false, rgb = false, hue = 0, speed = 0.06, saved = nil,
              colour = Color3.fromRGB(255, 214, 170), bright = 2, clock = 14, fog = false },
    spin  = { on = false, speed = 7, angle = 0, seen = 0, spun = 0 },
    disco = { on = false, hue = 0, speed = 0.5, pool = {} },
    balloon = { on = false, rate = 6 },
    head  = { on = false, scale = 3, saved = setmetatable({}, { __mode = "k" }) },
    grav  = { on = false, value = 40, saved = nil },
    cam   = { on = false, sway = 1, fov = 70, fovOn = false, bound = false, t = 0 },
    trail = { on = false, gap = 2.2, last = nil },
}

-- ------------------------------------------------------------------ SUN / SKY
function Fun.SkySave()
    if Fun.sky.saved then return end
    Fun.sky.saved = {
        ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness,
        OutdoorAmbient = Lighting.OutdoorAmbient, Ambient = Lighting.Ambient,
        ColorShift_Top = Lighting.ColorShift_Top, FogColor = Lighting.FogColor,
        ExposureCompensation = Lighting.ExposureCompensation,
    }
end

function Fun.SkyRestore()
    local sv = Fun.sky.saved
    if not sv then return end
    for k, v in pairs(sv) do pcall(function() Lighting[k] = v end) end
    Fun.sky.saved = nil
end

function Fun.SkyApply()
    local k = Fun.sky
    if not k.on then return end
    pcall(function()
        Lighting.ClockTime = k.clock
        Lighting.Brightness = k.bright
        -- ColorShift_Top is what actually tints sunlight; ambient carries that
        -- colour into shadow so the whole scene agrees with it
        Lighting.ColorShift_Top = k.colour
        Lighting.OutdoorAmbient = TH.mix(k.colour, Color3.fromRGB(70, 70, 80), 0.55)
        if k.fog then Lighting.FogColor = TH.mix(k.colour, Color3.new(0, 0, 0), 0.4) end
    end)
end

function Fun.SkySet(on)
    Fun.sky.on = on
    if on then Fun.SkySave() Fun.SkyApply() else Fun.SkyRestore() end
end

-- --------------------------------------------------------------- TRAFFIC SPIN
-- The game keeps driving these cars; only their yaw is overwritten each frame,
-- so they still follow the road while spinning like a top.
function Fun.SpinStep(dt)
    Fun.spin.angle = (Fun.spin.angle + Fun.spin.speed * dt) % (math.pi * 2)
    local a = Fun.spin.angle
    local folder = Workspace:FindFirstChild("TrafficFolder")
    if not folder then Fun.spin.seen, Fun.spin.spun = 0, 0 return end

    -- Read the folder DIRECTLY rather than World.Traffic(): that list is shared
    -- with the ESP and near-miss code, is rebuilt only every 0.25s, and drops
    -- anything partOf() cannot resolve - which is why only some of the street
    -- was spinning. PivotTo needs no part lookup at all.
    local kids = folder:GetChildren()
    local seen, spun = #kids, 0
    for i, inst in ipairs(kids) do
        if inst.Parent and not isProtected(inst) then
            local ok, piv = pcall(function() return inst:GetPivot() end)
            if ok and piv then
                -- phase offset per car, or the whole street spins in lockstep
                local okp = pcall(function()
                    inst:PivotTo(CFrame.new(piv.Position) * CFrame.Angles(0, a + i * 0.7, 0))
                end)
                if okp then spun = spun + 1 end
            end
        end
    end
    Fun.spin.seen, Fun.spin.spun = seen, spun
end

-- -------------------------------------------------------------- TRAFFIC DISCO
function Fun.DiscoStep(dt)
    local d = Fun.disco
    d.hue = (d.hue + dt * d.speed) % 1
    local folder = Workspace:FindFirstChild("TrafficFolder")
    local kids = folder and folder:GetChildren() or {}
    local used = 0
    for i, inst in ipairs(kids) do
        if used >= 60 then break end          -- Highlights are the limited resource here
        if inst.Parent then
            used = used + 1
            local h = d.pool[used]
            if not h or not h.Parent then
                h = new("Highlight", { Name = "AT_Disco", FillTransparency = 0.45,
                    OutlineTransparency = 0.2, Parent = AdornHolder })
                d.pool[used] = h
            end
            local c = Color3.fromHSV((d.hue + i * 0.07) % 1, 0.85, 1)
            h.Adornee = inst
            h.FillColor, h.OutlineColor = c, c
            h.Enabled = true
        end
    end
    for i = used + 1, #d.pool do
        if d.pool[i].Enabled then
            d.pool[i].Enabled = false
            d.pool[i].Adornee = nil
        end
    end
end

function Fun.DiscoClear()
    for _, h in ipairs(Fun.disco.pool) do pcall(function() h:Destroy() end) end
    Fun.disco.pool = {}
end

-- ------------------------------------------------------------ TRAFFIC BALLOON
function Fun.BalloonStep(dt)
    local folder = Workspace:FindFirstChild("TrafficFolder")
    if not folder then return end
    for _, inst in ipairs(folder:GetChildren()) do
        if inst.Parent and not isProtected(inst) then
            local ok, piv = pcall(function() return inst:GetPivot() end)
            if ok and piv then
                pcall(function() inst:PivotTo(piv + Vector3.new(0, Fun.balloon.rate * dt, 0)) end)
            end
        end
    end
end

-- ----------------------------------------------------------------- BIG HEADS
function Fun.HeadStep()
    local h = Fun.head
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            if not h.saved[head] then h.saved[head] = head.Size end
            local want = h.saved[head] * h.scale
            if (head.Size - want).Magnitude > 0.05 then
                pcall(function() head.Size = want end)
            end
        end
    end
end

function Fun.HeadRestore()
    for head, size in pairs(Fun.head.saved) do
        if head and head.Parent then pcall(function() head.Size = size end) end
    end
    Fun.head.saved = setmetatable({}, { __mode = "k" })
end

-- ------------------------------------------------------------------- GRAVITY
function Fun.GravSet(on)
    Fun.grav.on = on
    if on then
        Fun.grav.saved = Fun.grav.saved or Workspace.Gravity
        pcall(function() Workspace.Gravity = Fun.grav.value end)
    elseif Fun.grav.saved then
        pcall(function() Workspace.Gravity = Fun.grav.saved end)
        Fun.grav.saved = nil
    end
end

-- -------------------------------------------------------------------- CAMERA
-- Bound ABOVE the camera priority on purpose: the camera script writes CFrame
-- every frame, so anything applied before it is simply discarded.
function Fun.CamBind()
    local c = Fun.cam
    if c.bound then return end
    local ok = pcall(function()
        RunService:BindToRenderStep("AT_FunCam", Enum.RenderPriority.Camera.Value + 1, function(dt)
            c.t = c.t + dt
            local cam = Workspace.CurrentCamera
            if not cam then return end
            if c.fovOn then cam.FieldOfView = c.fov end
            if c.on and c.sway > 0 then
                local roll = math.sin(c.t * 1.7) * math.rad(6 * c.sway)
                local pitch = math.sin(c.t * 1.1) * math.rad(2.5 * c.sway)
                cam.CFrame = cam.CFrame * CFrame.Angles(pitch, 0, roll)
            end
        end)
    end)
    c.bound = ok
end

function Fun.CamUnbind()
    if not Fun.cam.bound then return end
    pcall(function() RunService:UnbindFromRenderStep("AT_FunCam") end)
    Fun.cam.bound = false
    local cam = Workspace.CurrentCamera
    if cam then pcall(function() cam.FieldOfView = 70 end) end
end

function Fun.CamSync()
    if Fun.cam.on or Fun.cam.fovOn then Fun.CamBind() else Fun.CamUnbind() end
end

-- ----------------------------------------------------------------- CAR TRAIL
function Fun.TrailStep()
    local root = S.Car.Root
    if not root or not root.Parent then return end
    local p = root.Position
    if Fun.trail.last and (p - Fun.trail.last).Magnitude < Fun.trail.gap then return end
    Fun.trail.last = p
    -- reuses the pulse ring pool, so this costs no new instances
    Pulse.colour = Color3.fromHSV((tick() * 0.25) % 1, 0.8, 1)
    Pulse.Spawn(p - Vector3.new(0, 2, 0), "step")
end

-- one driver for the lot; every branch is a table read when idle
bind(RunService.Heartbeat, function(dt)
    local ok, err = pcall(function()
        if Fun.sky.on and Fun.sky.rgb then
            Fun.sky.hue = (Fun.sky.hue + dt * Fun.sky.speed) % 1
            Fun.sky.colour = Color3.fromHSV(Fun.sky.hue, 0.55, 1)
            Fun.SkyApply()
        end
        -- ESP RGB is its own cycle, independent of the menu's RGB mode, and is
        -- throttled: TH.esp repaints a registry, so 60 Hz here is pure waste
        local o = TH.opt
        if o and o.espRGB then
            o.espT = (o.espT or 0) + dt
            if o.espT >= 0.05 then
                o.espT = 0
                o.espHue = ((o.espHue or 0) + 0.05 * (o.espRGBSpeed or 0.15)) % 1
                local h = o.espHue
                local function paint(cat, off)
                    local c = Color3.fromHSV((h + off) % 1, 0.78, 1)
                    if TH.esp then
                        TH.esp(cat, c)
                    else
                        local li = cat:match("^Lane(%d)$")
                        if li then ESPCOL.Lane[tonumber(li)] = c else ESPCOL[cat] = c end
                    end
                end
                paint("Car", 0)
                paint("Traffic", 0.12)
                paint("Player", 0.24)
                for i = 1, 4 do paint("Lane" .. i, 0.36 + (i - 1) * 0.06) end
            end
        end
        if Fun.spin.on then Fun.SpinStep(dt) end
        if Fun.disco.on then Fun.DiscoStep(dt) end
        if Fun.balloon.on then Fun.BalloonStep(dt) end
        if Fun.head.on then Fun.HeadStep() end
        if Fun.trail.on then Fun.TrailStep() end
    end)
    if not ok then warn("[AdminTools] fun:", err) end
end)

function Fun.AllOff()
    Fun.SkySet(false)
    Fun.spin.on, Fun.balloon.on, Fun.trail.on = false, false, false
    Fun.disco.on = false
    Fun.DiscoClear()
    Fun.head.on = false
    Fun.HeadRestore()
    Fun.GravSet(false)
    Fun.cam.on, Fun.cam.fovOn = false, false
    Fun.CamUnbind()
end

--============================================================================
-- TRAFFIC TRAIN
--============================================================================
-- Copies one traffic car N times and parks the copies alongside you, sweeping
-- the whole line fore and aft so each one crosses your scoring box over and
-- over.  Copies go in the original's own parent and are cloned verbatim, which
-- is what makes them score.
local Train = {
    enabled = false, sideMode = "Right",
    side = 9, height = 0, gap = 14, travel = 120, speedMph = 30, cloneCount = 20,
    phase = 0, dirSign = 1, count = 0, gen = 0, clones = {},
}

local function moveCar(inst, cf)
    pcall(function()
        if inst:IsA("Model") then inst:PivotTo(cf) else inst.CFrame = cf end
    end)
end

-- which side a given index sits on, and its slot within that row
function Train.SideFor(i)
    if Train.sideMode == "Both" then
        return (((i - 1) % 2 == 0) and 1 or -1), math.floor((i - 1) / 2)
    end
    return (Train.sideMode == "Left") and -1 or 1, i - 1
end

function Train.KillClones()
    for _, c in ipairs(Train.clones) do pcall(function() c:Destroy() end) end
    Train.clones = {}
end

-- Clone() silently DROPS any descendant with Archivable = false, which is how
-- you end up with an empty shell the game ignores.  Dex sets this before
-- duplicating, which is why duplicating by hand worked.
local function forceArchivable(inst, restore)
    if not inst.Archivable then
        restore[#restore + 1] = inst
        inst.Archivable = true
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if not d.Archivable then
            restore[#restore + 1] = d
            d.Archivable = true
        end
    end
end

function Train.MakeClones()
    Train.KillClones()
    local src
    for _, t in ipairs(World.Traffic()) do
        if t.inst and t.inst:IsA("Model") and not isProtected(t.inst) then src = t.inst break end
    end
    if not src then return 0, "no traffic car nearby to copy" end

    local restore = {}
    forceArchivable(src, restore)

    -- verbatim copy, same parent as the original: no anchoring, no CanCollide
    -- changes, no script removal.  Server Scripts never run on the client and
    -- LocalScripts do not run under workspace, so keeping them costs nothing
    -- and preserves whatever the scoring logic looks for.
    local parent = src.Parent or Workspace
    for _ = 1, Train.cloneCount do
        local ok, c = pcall(function() return src:Clone() end)
        if ok and c then
            c.Parent = parent
            Train.clones[#Train.clones + 1] = c
        end
    end

    for _, inst in ipairs(restore) do
        pcall(function() inst.Archivable = false end)
    end
    if #Train.clones == 0 then
        return 0, "Clone() returned nothing - the car may be protected"
    end
    return #Train.clones
end

local function trainStep(dt)
    local root = S.Car.Root
    if not root or not root.Parent then return end
    local fwd = carForward()
    local right = Vector3.new(-fwd.Z, 0, fwd.X)
    local speed = toStuds(Train.speedMph)

    Train.phase = Train.phase + Train.dirSign * speed * dt
    if Train.phase > Train.travel then
        Train.phase, Train.dirSign = Train.travel, -1
    elseif Train.phase < -Train.travel then
        Train.phase, Train.dirSign = -Train.travel, 1
    end

    local live = {}
    for _, c in ipairs(Train.clones) do
        if c.Parent then live[#live + 1] = c end
    end

    local perRow = (Train.sideMode == "Both") and math.ceil(#live / 2) or #live
    local centre = math.max(0, perRow - 1) * Train.gap * 0.5
    local lift = Vector3.new(0, Train.height, 0)

    for i, inst in ipairs(live) do
        local sign, slot = Train.SideFor(i)
        local p = root.Position + lift
            + right * (Train.side * sign)
            + fwd * (slot * Train.gap - centre + Train.phase)
        moveCar(inst, CFrame.lookAt(p, p + fwd))
        local part = partOf(inst)
        if part and part.Parent then
            part.AssemblyLinearVelocity = fwd * (speed * Train.dirSign)
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
    Train.count = #live
end

function Train.Set(on)
    Train.enabled = on
    Train.gen = Train.gen + 1
    local myGen = Train.gen
    if not on then
        Train.count = 0
        Train.KillClones()
        return
    end
    Train.phase, Train.dirSign = 0, 1
    local made, err = Train.MakeClones()
    if made == 0 then
        Train.enabled = false
        notify("Traffic train failed", tostring(err), "bad", 7)
        if REF.trainToggle then REF.trainToggle:Set(false, true) end
        return
    end
    notify("Clones spawned", made .. " copies of a traffic car", "good")
    task.spawn(function()
        while Train.enabled and Train.gen == myGen and ALIVE do
            local dt = task.wait()
            local ok, err = pcall(trainStep, dt or 1 / 60)
            if not ok then warn("[AdminTools] train:", err) end
        end
    end)
end

--============================================================================
-- AUTO POLICE CHASE
--============================================================================
-- Full loop: park at the chase start, take the 5 star option, buy it, fly the
-- route until the busted screen appears, skip it, repeat.  Every state has a
-- timeout so a missed prompt restarts the lap instead of hanging.
local Chase = {
    enabled = false, state = "idle", t = 0, laps = 0, gen = 0,
    start = CFrame.new(-3601.21387, 137.258865, -141.613022,
        -0.537719965, 0, -0.843123972,
        0, 1, 0,
        0.843123972, 0, -0.537719965),
    hover = 10, lift = 5, speed = 300, hold = true,
    smart = false, farmMph = 200, fastMph = 1000, cashTarget = 70000,
    cash = nil, phase = "-",
    holdCF = nil, holdParts = nil, landT = 0,
    padPos = nil, padName = nil,
    savedMode = nil, savedHover = nil, savedSpeedMode = nil, savedStatic = nil, note = "idle",
    stageP = { idle = 0, teleport = 0.1, difficulty = 0.35, driving = 0.75, skip = 0.95 },
    starFired = 0, buyFired = 0, starCands = 0, buyCands = 0,
    nextStar = 0, nextBuy = -1, skipFired = 0,
    -- direct start: the remote the difficulty button fires, found with
    -- ChaseCapture.  Plain integer, no offer token, no buffer.
    direct = true, stars = 5, pick = nil,
    netConns = {}, offerAt = nil, offers = 0, picks = 0,
    -- settled numbers straight off RE/Police/PoliceBusted
    run = { outcome = nil, cash = 0, penalty = 0, balance = nil,
            stars = nil, level = nil, at = nil },
    tally = { chases = 0, evaded = 0, busted = 0, cash = 0, penalty = 0, best = 0,
              secs = 0, sessionAt = nil },
    runStart = nil,
    -- Accrual probe.  Nobody knows yet whether the chase pays by time, by
    -- distance or by how close the police are, and those need different
    -- answers - so sample the counter against speed and measure it.
    acc = { last = nil, lastAt = nil, rate = 0, perStud = 0, samples = 0,
            mphSum = 0, best = 0 },
}

-- ReplicatedStorage.Packages.Remotes.Networking."RE/Police/PoliceDifficultyPick"
-- Searched by name rather than walked by path: the slashes are part of the
-- instance NAME, not a hierarchy, and the Packages layout is generated - a
-- recursive find survives it being reorganised.
function Chase.Pick()
    if Chase.pick and Chase.pick.Parent then return Chase.pick end
    local rs = game:GetService("ReplicatedStorage")
    local ok, found = pcall(function()
        return rs:FindFirstChild("RE/Police/PoliceDifficultyPick", true)
    end)
    Chase.pick = (ok and found) or nil
    return Chase.pick
end

-- Answer the offer.  Only works while one is live - the server drops it
-- otherwise, which is why there is no point calling this away from the pad.
function Chase.FireDirect()
    local remote = Chase.Pick()
    if not remote then return false, "PoliceDifficultyPick not found" end
    local ok = pcall(function()
        remote:FireServer(math.clamp(math.floor(Chase.stars), 1, 5))
    end)
    if ok then Chase.picks = Chase.picks + 1 end
    return ok, ok and "fired" or "FireServer failed"
end

-- The server announces both ends of a run on its own remotes, so listen to
-- those rather than reading the HUD.  The offer beats watching for a button
-- called Star5 to appear; the outcome beats scraping a cash label, because it
-- carries the real numbers the server settled on.
function Chase.WatchNet(on)
    for _, c in ipairs(Chase.netConns or {}) do
        pcall(function() c:Disconnect() end)
    end
    Chase.netConns = {}
    if not on then return false end
    local rs = game:GetService("ReplicatedStorage")
    local function grab(name)
        local ok, r = pcall(function() return rs:FindFirstChild(name, true) end)
        return (ok and r) or nil
    end

    local offer = grab("RE/Police/PoliceDifficultyOffer")
    if offer then
        local c = offer.OnClientEvent:Connect(function()
            Chase.offerAt = tick()
            Chase.offers = Chase.offers + 1
        end)
        Chase.netConns[#Chase.netConns + 1] = c
        CONN[#CONN + 1] = c
    end

    -- PoliceBusted carries the settled result whichever way the run ended:
    --   ("Escaped",  { Outcome = "EVADED", Cash, Penalty, Balance, Stars, Level })
    --   ("Cutscene", { Outcome = "BUSTED", Cash, Penalty, Balance, ... })
    local done = grab("RE/Police/PoliceBusted")
    if done then
        local c = done.OnClientEvent:Connect(function(_, data)
            if type(data) ~= "table" then return end
            local r = Chase.run
            r.outcome = tostring(data.Outcome or "?")
            r.cash    = tonumber(data.Cash) or 0
            r.penalty = tonumber(data.Penalty) or 0
            r.balance = tonumber(data.Balance) or r.balance
            r.stars   = tonumber(data.Stars) or r.stars
            r.level   = tonumber(data.Level) or r.level
            r.at      = tick()
            r.secs    = Chase.runStart and (tick() - Chase.runStart) or nil
            -- Cash per minute is the only number that says whether a change
            -- actually helped.  A bigger payout over a longer run is not a win.
            r.rate    = (r.secs and r.secs > 5) and (r.cash / (r.secs / 60)) or nil

            local t = Chase.tally
            if r.secs then t.secs = t.secs + r.secs end
            t.chases  = t.chases + 1
            t.cash    = t.cash + r.cash
            t.penalty = t.penalty + r.penalty
            if r.cash > t.best then t.best = r.cash end
            if r.outcome == "EVADED" then t.evaded = t.evaded + 1
            else t.busted = t.busted + 1 end

        end)
        Chase.netConns[#Chase.netConns + 1] = c
        CONN[#CONN + 1] = c
    end
    return #Chase.netConns > 0
end

function Chase.Gui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

function Chase.Find(name, parent)
    local root = parent or Chase.Gui()
    if not root then return nil end
    local ok, found = pcall(function() return root:FindFirstChild(name, true) end)
    return ok and found or nil
end

-- visible means every GuiObject above it is visible and its ScreenGui enabled
function Chase.Shown(inst)
    if not inst or not inst.Parent then return false end
    local cur = inst
    while cur and cur ~= game do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("LayerCollector") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

-- Every clickable candidate for a named element: the thing itself if it is a
-- button, any button inside it, or the nearest button above it.  Games label
-- the visual and put the handler on a child or parent just as often.
function Chase.Buttons(name, root)
    local found = Chase.Find(name, root)
    local out = {}
    if not found then return out, nil end
    if found:IsA("GuiButton") then out[#out + 1] = found end
    for _, d in ipairs(found:GetDescendants()) do
        if d:IsA("GuiButton") then out[#out + 1] = d end
    end
    if #out == 0 then
        local p = found.Parent
        while p and p ~= game do
            if p:IsA("GuiButton") then out[#out + 1] = p break end
            p = p.Parent
        end
    end
    return out, found
end

-- Fire whatever the game connected, no synthetic mouse needed.  Signals are
-- tried in order and we STOP at the first one that had listeners, so a handler
-- wired to Click and Down does not get run twice.
function Chase.ClickButton(btn)
    if not btn or typeof(getconnections) ~= "function" then return 0 end
    for _, sig in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }) do
        local ok, conns = pcall(function() return getconnections(btn[sig]) end)
        if ok and conns and #conns > 0 then
            local n = 0
            for _, c in pairs(conns) do
                if c.Fire then
                    pcall(function() c:Fire() end)
                    n = n + 1
                end
            end
            if n > 0 then return n end
        end
    end
    if typeof(firesignal) == "function" then
        local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
        if ok then return 1 end
    end
    return 0
end

function Chase.Click(name, root)
    local btns = Chase.Buttons(name, root)
    local fired = 0
    for _, b in ipairs(btns) do
        fired = fired + Chase.ClickButton(b)
    end
    return fired, #btns
end

-- Where the chase starts: workspace.PoliceSystem.PolicePad, sat on top of the
-- pad and faced along the nearest drivable path so it drives away correctly.
-- Falls back to the fixed CFrame if the pad is not in the world.
-- Where the pad IS, resolved once and remembered for the session.
--
-- It used to be re-read on every lap, and that is what broke the second run:
-- PolicePad is a container, so partOf() returned whichever BasePart the
-- recursive search reached first.  A chase adds and removes parts under there,
-- so after one run that search could land on a different part - or on a pad
-- belonging to another circle - and the car was placed wherever that part was.
-- The centre is taken from the whole model's bounding box rather than one
-- descendant, which does not move when the contents change.
function Chase.PadPos()
    if Chase.padPos then return Chase.padPos end
    local sys = Workspace:FindFirstChild("PoliceSystem")
    local pad = sys and sys:FindFirstChild("PolicePad", true)
    if not pad then return nil end
    local pos
    if pad:IsA("Model") then
        local ok, cf = pcall(function() return (pad:GetBoundingBox()) end)
        pos = ok and cf and cf.Position or nil
        if not pos then
            local p = partOf(pad)
            pos = p and p.Position or nil
        end
    else
        local p = partOf(pad)
        pos = p and p.Position or nil
    end
    if not pos then return nil end
    Chase.padPos, Chase.padName = pos, pad:GetFullName()
    return pos
end

function Chase.StartCF()
    local pos = Chase.PadPos()
    if not pos then
        -- Workspace.PoliceSystem is not streamed in when the farm is switched
        -- on from the far side of the map, so aim at the recorded start.  That
        -- is not a wasted trip - landing there is what brings the real pad into
        -- streaming range - but it is NOT the pad, and the difficulty state
        -- needs to know that so it can park properly the moment one resolves.
        Chase.padGuess = true
        return Chase.start + Vector3.new(0, Chase.lift, 0)
    end
    Chase.padGuess = false

    -- Pad position plus the offset, nothing else.  Adding half the part height
    -- put the car on TOP of the pad's collision volume when that volume is
    -- tall, which is how it ended up parked in the sky refusing to fall.
    local top = pos + Vector3.new(0, Chase.lift, 0)
    local li, wi = World.NearestLane(top)
    if li then
        local lane = World.paths[li]
        local nxt = World.Step(lane, wi, 1)
        local d = lane.points[nxt].pos - lane.points[wi].pos
        d = Vector3.new(d.X, 0, d.Z)
        if d.Magnitude > 0.1 then
            return CFrame.new(top) * rotationFor(d.Unit)
        end
    end
    return CFrame.new(top) * Chase.start.Rotation
end

function Chase.Teleport()
    -- The game can respawn the car between laps, which leaves S.Car.Model
    -- pointing at a destroyed model.  The live loop only re-scans once a second,
    -- far too slow for a state machine that teleports the instant it enters this
    -- state, so take the cost of a rescan here.
    Car.Refresh()
    local model, root = S.Car.Model, S.Car.Root
    if not model or not model.Parent or not root or not root.Parent then return false end
    local offset = root.CFrame:ToObjectSpace(model:GetPivot())
    -- drop in from slightly above so the car settles onto the pad instead of
    -- landing inside it
    -- anything still attached from a previous lap would hold the car in the
    -- air: a fly rig pins all three axes, so clear both before moving
    Rig.Clear("auto")
    Rig.Clear("fly")
    local startCF = Chase.StartCF()
    local ok = pcall(function() model:PivotTo(startCF * offset) end)
    if ok then
        Chase.holdCF, Chase.holdParts, Chase.landT = nil, nil, 0
        root.AssemblyLinearVelocity = Vector3.new(0, -8, 0)   -- nudge it into the drop
        root.AssemblyAngularVelocity = Vector3.zero
    end
    return ok
end

-- Held every frame while we wait for the prompt: the car keeps whatever
-- downward speed it has so it still lands on the pad, but cannot slide, roll or
-- carry momentum from the last lap into a wall.
function Chase.Hold(dt)
    local root, model = S.Car.Root, S.Car.Model
    if not root or not root.Parent or not model then return end

    -- the engine is still making torque, so stop asking it to
    local seat = S.Car.Seat
    if seat and seat:IsA("VehicleSeat") and seat.Parent then
        pcall(function()
            seat.ThrottleFloat, seat.SteerFloat = 0, 0
            seat.Throttle, seat.Steer = 0, 0
        end)
    end

    if Chase.holdCF then
        -- Landed: pin the pose outright.  Zeroing the root assembly alone was
        -- not enough - a car's wheels are their own assemblies and keep driving
        -- it, so every part gets stopped and the whole model is put back each
        -- frame.  Nothing can creep, roll or be shunted out of the zone.
        local offset = root.CFrame:ToObjectSpace(model:GetPivot())
        pcall(function() model:PivotTo(Chase.holdCF * offset) end)
        for _, d in ipairs(Chase.holdParts or {}) do
            if d.Parent then
                d.AssemblyLinearVelocity = Vector3.zero
                d.AssemblyAngularVelocity = Vector3.zero
            end
        end
        return
    end

    -- still dropping onto the pad: gravity only, no slide and no spin
    local v = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
    root.AssemblyAngularVelocity = Vector3.zero

    Chase.landT = (Chase.landT or 0) + (dt or 1 / 60)
    if (Chase.landT > 0.35 and math.abs(v.Y) < 3) or Chase.landT > 3 then
        Chase.holdCF = root.CFrame
        local parts = {}
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then parts[#parts + 1] = d end
        end
        Chase.holdParts = parts      -- cached so the freeze costs no traversal
    end
end

-- PlayerGui.InGameHUD["Chase UI"].ChaseCash reads like "$0" / "$12,500"
function Chase.Cash()
    local hud = Chase.Find("InGameHUD")
    local ui = (hud and Chase.Find("Chase UI", hud)) or Chase.Find("Chase UI") or Chase.Find("ChaseUI")
    local lbl = ui and Chase.Find("ChaseCash", ui)
    if not lbl or not lbl:IsA("TextLabel") then return nil end
    local digits = (lbl.Text:gsub("[^%d]", ""))
    return tonumber(digits)
end

-- Is the counter paid by the second or by the stud?  One sample every half
-- second against the speed we were doing tells us, and that decides whether
-- farm speed is a lever at all or just noise.
function Chase.Sample()
    local a = Chase.acc
    local now, cash = tick(), Chase.Cash()
    if not cash then return end
    -- The readout's only source.  It used to be written solely by
    -- Chase.SmartSpeed, which returns early when Smart farmer is off, so the
    -- "Chase cash" row read "-" for the entire chase unless that toggle was on.
    -- This function already scrapes the number every tick, so it is free here.
    Chase.cash = cash
    if not a.lastAt then
        a.last, a.lastAt = cash, now
        return
    end
    local dt = now - a.lastAt
    if dt < 0.5 then return end
    local gained = cash - a.last
    a.last, a.lastAt = cash, now
    if gained <= 0 then return end

    local mph = Car.Speed() * CONFIG.MphPerStud
    local r = gained / dt
    -- smoothed, because the counter ticks in lumps rather than continuously
    a.rate = (a.rate > 0) and (a.rate * 0.7 + r * 0.3) or r
    if a.rate > a.best then a.best = a.rate end
    -- dollars per stud travelled.  Flat against speed means time pays and the
    -- speed slider is pointless here; rising with speed means distance pays.
    local studs = math.max(1, Car.Speed() * dt)
    a.perStud = (a.perStud > 0) and (a.perStud * 0.7 + (gained / studs) * 0.3)
        or (gained / studs)
    a.samples = a.samples + 1
    a.mphSum = a.mphSum + mph
end

-- Smart farmer: hold a safe speed until the run has banked everything it can,
-- then stop caring about the cash and go flat out.
function Chase.SmartSpeed()
    if not Chase.smart then return end
    local cash = Chase.Cash()
    Chase.cash = cash or Chase.cash
    local want = (cash and cash >= Chase.cashTarget) and Chase.fastMph or Chase.farmMph
    if A.StaticMph ~= want then A.StaticMph = want end
    Chase.setMph = want
    Chase.phase = (want == Chase.fastMph) and "banked" or "farming"
end

function Chase.Result()
    local ui = Chase.Find("PoliceBustedUI")
    if not ui then return nil, nil end
    local bounds = Chase.Find("ResultBounds", ui)
    local canvas = bounds and Chase.Find("ResultCanvas", bounds)
    local first = canvas and Chase.Find("First", canvas)
    return first, ui
end

function Chase.StartDriving()
    -- ONCE PER RUN, all of it.  This function is re-entered from the "driving"
    -- state on any tick where A.Running has dropped - Auto.Set(true) bails and
    -- leaves it false when the car or the lane map is momentarily missing,
    -- which is exactly what a teleport to the pad can cause.
    --
    -- Everything inside this guard was being redone on that re-entry.  The
    -- settings snapshot was the damaging one: on the second pass A.Mode is
    -- already "Hover" at the chase height, so it recorded the CHASE's own
    -- settings as "what the user had" and StopDriving faithfully restored them,
    -- which is how a finished chase left the car flying.  The run clock and the
    -- accrual probe were the quiet ones: restarting them left "Last run rate"
    -- and "Accrual" reading a fraction of a second and never settling.
    --
    -- StopDriving is the only thing that clears savedMode, so nil means "no run
    -- is in progress".
    if Chase.savedMode == nil then
        Chase.runStart = tick()
        Chase.acc = { last = nil, lastAt = nil, rate = 0, perStud = 0, samples = 0,
                      mphSum = 0, best = 0 }
        Chase.cash = nil
        Chase.savedMode, Chase.savedHover = A.Mode, A.Hover
        Chase.savedSpeedMode, Chase.savedStatic = A.SpeedMode, A.StaticMph
    end
    Chase.holdCF, Chase.holdParts = nil, nil     -- let go of the pad
    A.Mode, A.Hover = "Hover", Chase.hover
    A.SpeedMode, A.StaticMph = "Static", Chase.smart and Chase.farmMph or Chase.speed
    -- What the chase last wrote, so StopDriving can tell its own value from one
    -- the user has set since.  The smart farmer moves this during the run, so
    -- it has to be updated there too.
    Chase.setMph = A.StaticMph
    Chase.phase = Chase.smart and "farming" or "chasing"
    route.cursorPos = nil
    Rig.Clear("auto")
    Auto.Set(true)              -- deliberately not touching the menu toggle
end

function Chase.StopDriving()
    if A.Running then Auto.Set(false) end
    -- Smart farmer finishes a run at up to 1000 MPH. Clearing the rig leaves all
    -- that momentum on the assembly, which throws the car across the map and can
    -- despawn it, so every part is stopped dead the moment the run is over.
    local root, model = S.Car.Root, S.Car.Model
    if root and root.Parent then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if model then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                d.AssemblyLinearVelocity = Vector3.zero
                d.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end
    local seat = S.Car.Seat
    if seat and seat:IsA("VehicleSeat") and seat.Parent then
        pcall(function()
            seat.ThrottleFloat, seat.SteerFloat = 0, 0
            seat.Throttle, seat.Steer = 0, 0
        end)
    end
    -- Restore only what the chase is STILL holding.  If the live value is no
    -- longer the one the chase forced, something newer wrote it - a config
    -- load, or the recommended-setup button - and our snapshot is stale, so
    -- putting it back would silently undo what the user just did.
    if Chase.savedMode and A.Mode == "Hover" then A.Mode = Chase.savedMode end
    if Chase.savedHover and A.Hover == Chase.hover then A.Hover = Chase.savedHover end
    if Chase.savedSpeedMode and A.SpeedMode == "Static" then A.SpeedMode = Chase.savedSpeedMode end
    -- Chase.setMph is what the chase last wrote, including the smart farmer's
    -- mid-run changes, so this test is as reliable as the three above it.
    if Chase.savedStatic and A.StaticMph == Chase.setMph then A.StaticMph = Chase.savedStatic end
    Chase.savedMode, Chase.savedHover = nil, nil
    Chase.savedSpeedMode, Chase.savedStatic, Chase.setMph = nil, nil, nil
    -- the run is over; leaving these set kept the last run's cash and phase on
    -- screen as though a chase were still live
    Chase.cash, Chase.phase = nil, "-"
end

Chase.steps = {
    -- state          timeout  what to do each tick
    teleport = 3, difficulty = 40, driving = 900, skip = 20,
}

function Chase.Step(dt)
    Chase.t = Chase.t + dt
    local st = Chase.state
    A.Chasing = true
    A.ChaseNote = st .. " · " .. Chase.note
    A.ChaseLaps = Chase.laps
    A.ChaseProgress = Chase.stageP[st] or 0
    A.ChaseCash = Chase.cash

    if st == "idle" or st == "teleport" then
        if not S.Car.Model then
            Chase.note = "waiting for a vehicle - you must be in your car"
            return
        end
        Chase.StopDriving()

        -- No direct attempt here.  Firing Pick cold was tested and the server
        -- ignores it: the offer only exists while the car is on the pad, and
        -- nothing the client can call creates one.  Trying anyway just cost
        -- 1.5 seconds a lap.  The direct call still replaces the button press
        -- once we are parked and the offer has actually arrived.
        Chase.offerAt = nil
        -- Stay here until the car is actually ON the pad.  This used to move on
        -- whatever happened, so a teleport that failed - or landed somewhere
        -- else - was followed by a pointless 40 second wait for a prompt that
        -- was never going to appear, and the lap was lost.
        if not Chase.Teleport() then
            Chase.note = "no usable vehicle to move - waiting"
            return
        end
        Chase.starFired, Chase.buyFired = 0, 0
        Chase.nextStar, Chase.nextBuy = 0.6, -1     -- let the prompt appear first
        Chase.state, Chase.t = "difficulty", 0
        Chase.note = "parked at the start, waiting for the difficulty prompt"

    elseif st == "difficulty" then
        -- One goal-driven state instead of a star -> buy chain: keep pressing
        -- whatever is on screen until the chase actually starts.  Nothing here
        -- depends on a prompt appearing within a particular tick.
        local ui = Chase.Find("Chase UI") or Chase.Find("ChaseUI")
        local meter = ui and Chase.Find("MeterArt", ui)
        if Chase.Shown(meter) then
            Chase.StartDriving()
            Chase.state, Chase.t = "driving", 0
            Chase.note = "chase live, flying the route"
            return
        end

        -- Whatever the reason - a failed pivot, the game moving us, the car
        -- respawning - if we are not on the pad the prompt will never come, so
        -- go back and park again rather than burning the 40 second timeout.
        --
        -- Arriving on a GUESS is the one case 1.5s is too slow for: the pad had
        -- not streamed in, so we aimed at the recorded start and cannot know
        -- where we landed until one resolves.  That earns a shorter wait and
        -- nothing else - the distance test below still decides.  Re-parking
        -- unconditionally was worse than the problem: the recorded start is
        -- usually on the pad anyway, so it teleported a correctly parked car a
        -- second time, and at t > 1 that lands one tick after the Buy click and
        -- discards the offer it had just answered.
        local pad, root = Chase.PadPos(), S.Car.Root
        if pad and root and root.Parent and Chase.t > (Chase.padGuess and 1 or 1.5) then
            local off = (root.Position - pad)
            if math.abs(off.Y) > 120 or Vector3.new(off.X, 0, off.Z).Magnitude > 140 then
                Chase.state, Chase.t = "teleport", 0
                Chase.note = string.format("drifted %d studs off the pad, re-parking",
                    math.floor(off.Magnitude))
                return
            end
        end

        -- The offer landing is the real "you may pick now" signal, so answer it
        -- the moment it arrives rather than waiting for the next 1.6s tick.
        if Chase.direct and Chase.offerAt and Chase.t >= (Chase.nextStar or 0) then
            Chase.FireDirect()
            Chase.nextStar = Chase.t + 1.2
            Chase.note = string.format("offer answered · %d pick%s",
                Chase.picks, Chase.picks == 1 and "" or "s")
        end

        local gui = Chase.Find("CopChaseDifficulty")
        if gui then
            -- Button clicking is now the FALLBACK: it still runs when direct is
            -- off, when the remote cannot be found, or when no offer has been
            -- seen - a prompt that appeared without one is worth pressing.
            local needClick = (not Chase.direct) or (not Chase.Pick()) or (not Chase.offerAt)
            if needClick and Chase.t >= (Chase.nextStar or 0) then
                local fired, cands = Chase.Click("Star5", gui)
                Chase.starFired = Chase.starFired + fired
                Chase.starCands = cands
                Chase.nextBuy = Chase.t + 0.4
                Chase.nextStar = Chase.t + 1.6
            end
            if (Chase.nextBuy or -1) > 0 and Chase.t >= Chase.nextBuy then
                local fired, cands = Chase.Click("Buy", gui)
                Chase.buyFired = Chase.buyFired + fired
                Chase.buyCands = cands
                Chase.nextBuy = -1
            end
            Chase.note = string.format("prompt up · star %d/%d · buy %d/%d",
                Chase.starFired, Chase.starCands or 0, Chase.buyFired, Chase.buyCands or 0)
        else
            Chase.note = "waiting for CopChaseDifficulty"
        end

        if Chase.t > Chase.steps.difficulty then
            -- Forget the cached pad.  It is resolved once per session, so a
            -- position measured off a half-streamed model would otherwise be
            -- wrong for every remaining lap - and "the prompt never came" is
            -- what that looks like from here.
            Chase.padPos = nil
            Chase.state, Chase.t = "teleport", 0
            Chase.note = (Chase.starFired + Chase.buyFired == 0)
                and "no buttons responded - the chase UI is named differently"
                or "prompt did not lead to a chase, re-parking"
        end

    elseif st == "driving" then
        local first = Chase.Result()
        if Chase.Shown(first) then
            Chase.StopDriving()
            Chase.laps = Chase.laps + 1
            Chase.holdCF, Chase.holdParts, Chase.landT = nil, nil, 0
            Chase.state, Chase.t = "skip", 0
            Chase.note = "busted screen up, skipping"
        elseif Chase.t > Chase.steps.driving then
            Chase.state, Chase.t = "teleport", 0
            Chase.note = "chase ran long, restarting"
        else
            if not A.Running then Chase.StartDriving() end
            Chase.Sample()
            if Chase.smart then
                Chase.SmartSpeed()
                Chase.note = string.format("%s · $%s · %d MPH", Chase.phase,
                    Chase.cash and fmtNum(Chase.cash) or "?", math.floor(A.StaticMph))
            else
                Chase.note = string.format("chase running %s", fmtTime(Chase.t))
            end
        end

    elseif st == "skip" then
        local first, ui = Chase.Result()
        if not Chase.Shown(first) then
            Chase.state, Chase.t = "teleport", 0
            Chase.note = "lap " .. Chase.laps .. " done, going again"
            return
        end
        if ui then Chase.skipFired = Chase.skipFired + Chase.Click("Skip", ui) end
        if Chase.t > Chase.steps.skip then
            Chase.state, Chase.t = "teleport", 0
            Chase.note = "skip did not take, re-parking"
        end
    end
end

-- the state machine ticks at 5Hz, far too slow to catch a car carrying speed,
-- so the pad hold runs every frame instead
bind(RunService.Heartbeat, function(dt)
    -- "skip" is included so the car cannot drift or be flung while the result
    -- screen is up; without it a 1000 MPH finish carries on travelling
    if Chase.enabled and Chase.hold
        and (Chase.state == "difficulty" or Chase.state == "skip") then
        local ok, err = pcall(Chase.Hold, dt)
        if not ok then warn("[AdminTools] chase hold:", err) end
    end
end)

function Chase.Set(on)
    Chase.enabled = on
    Chase.gen = Chase.gen + 1
    local myGen = Chase.gen
    if not on then
        -- Only tear the drive down if the chase was the thing driving.  The two
        -- "put everything back" buttons call this as part of their sweep, and
        -- an unguarded StopDriving stopped a drive the user started themselves
        -- and zeroed the velocity of every part on the car.
        if Chase.savedMode ~= nil or A.Chasing then Chase.StopDriving() end
        Chase.WatchNet(false)
        Chase.state, Chase.note = "idle", "idle"
        A.Chasing, A.ChaseProgress = false, 0
        -- The row is a readout as much as a control: the chase drives through
        -- Auto.Set without touching it, so after the farm stopped the car it
        -- kept reading ON, and the first click to fix it did nothing because
        -- the toggle's own Value had never changed.  Silent, so this cannot
        -- re-enter the callback that called us.
        if REF.autoToggle then REF.autoToggle:Set(A.Running, true) end
        return true
    end
    if not S.Car.Model then
        Chase.enabled = false
        return false, "you have to be in your car"
    end
    if typeof(getconnections) ~= "function" then
        Chase.enabled = false
        return false, "this executor has no getconnections, so the prompts cannot be clicked"
    end
    Chase.state, Chase.t, Chase.laps = "teleport", 0, 0
    Chase.padPos = nil          -- re-resolve the pad once per session, not per lap
    Chase.offers, Chase.picks, Chase.offerAt = 0, 0, nil
    -- The whole tally, not just the clock.  Every readout built from it is
    -- framed per session ("Session net", "Projected / hour"), and dividing an
    -- all-time total by a clock that restarts on each enable inflated the rate
    -- every time the farm was switched off and on again.
    Chase.tally = { chases = 0, evaded = 0, busted = 0, cash = 0, penalty = 0,
                    best = 0, secs = 0, sessionAt = tick() }
    Chase.WatchNet(true)
    -- session totals belong to the whole chase, so they are cleared here and
    -- never again by the per-lap Auto.Set
    A.StartedAt = tick()
    A.Studs = 0
    A.NearMiss, A.NearRate = 0, 0
    Earn.Reset()
    task.spawn(function()
        local last = tick()
        while Chase.enabled and Chase.gen == myGen and ALIVE do
            local now = tick()
            local dt = now - last
            last = now
            local ok, err = pcall(Chase.Step, dt)
            if not ok then warn("[AdminTools] chase:", err) end
            task.wait(0.2)
        end
    end)
    return true
end

--============================================================================
-- MIMIC  (Network tab)
--============================================================================
-- Replays another player's movement on a delay by following the trail they
-- left, not by chasing where they are now.  The keep-away radius is what stops
-- the delay turning into a rear-ending: if the delayed point has crept inside
-- the radius (they braked), we walk further back down their trail instead.
local Mimic = {
    enabled = false, targetName = "", delay = 2, radius = 25, hover = 0,
    rotate = true, trail = {}, maxTrail = 900,
    gen = 0, dist = 0, note = "idle", holding = false,
}

function Mimic.Target()
    local plr = Players:FindFirstChild(Mimic.targetName)
    if not plr or plr == LocalPlayer then return nil, nil end
    local prefix = plr.Name:lower() .. "_"
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") then
            local n = m.Name:lower()
            if #n > #prefix and n:sub(1, #prefix) == prefix then
                return m, partOf(m)
            end
        end
    end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then return char, hrp end
    return nil, nil
end

function Mimic.Record(part)
    local trail = Mimic.trail
    local now = tick()
    local last = trail[#trail]
    if not last or (part.Position - last.pos).Magnitude > 0.6 or (now - last.t) > 0.12 then
        trail[#trail + 1] = { t = now, pos = part.Position }
    end
    if #trail > Mimic.maxTrail then          -- trim in bulk, never per frame
        local keep = {}
        for i = 120, #trail do keep[#keep + 1] = trail[i] end
        Mimic.trail = keep
    end
end

-- newest sample at or before `want`
function Mimic.IndexAt(want)
    local trail = Mimic.trail
    local lo, hi = 1, #trail
    if hi == 0 then return nil end
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if trail[mid].t <= want then lo = mid else hi = mid - 1 end
    end
    return lo
end

function Mimic.Step(dt)
    local model, part = Mimic.Target()
    if not part or not part.Parent then
        Mimic.note = "target not in the world"
        return
    end
    Mimic.Record(part)

    local root, mine = S.Car.Root, S.Car.Model
    if not root or not root.Parent or not mine then
        Mimic.note = "no vehicle of your own"
        return
    end

    local trail = Mimic.trail
    local i = Mimic.IndexAt(tick() - Mimic.delay)
    if not i or i < 1 then
        Mimic.note = string.format("building trail (%d samples)", #trail)
        return
    end

    -- hold back down the trail until we are clear of where they are NOW
    local here = part.Position
    Mimic.holding = false
    while i > 1 and (trail[i].pos - here).Magnitude < Mimic.radius do
        i = i - 1
        Mimic.holding = true
    end

    local pos = trail[i].pos
    Mimic.dist = (pos - here).Magnitude
    if Mimic.dist < Mimic.radius * 0.6 then
        Mimic.note = "too close, waiting for room"
        return                                   -- never drive into them
    end

    -- heading from the next sample along, so we face the way they went
    local nxt = trail[math.min(i + 1, #trail)]
    local dir = nxt.pos - pos
    dir = Vector3.new(dir.X, 0, dir.Z)
    dir = (dir.Magnitude > 0.05) and dir.Unit or carForward()

    local goal = CFrame.new(pos + Vector3.new(0, Mimic.hover, 0))
        * (Mimic.rotate and rotationFor(dir) or root.CFrame.Rotation)
    local offset = root.CFrame:ToObjectSpace(mine:GetPivot())
    pcall(function() mine:PivotTo(goal * offset) end)

    -- report the speed they were doing at that point, so gauges read sensibly
    local prev = trail[math.max(i - 1, 1)]
    local span = math.max(0.01, nxt.t - prev.t)
    root.AssemblyLinearVelocity = dir * ((nxt.pos - prev.pos).Magnitude / span)
    root.AssemblyAngularVelocity = Vector3.zero

    Mimic.note = string.format("%s · %.0f studs back%s", Mimic.targetName, Mimic.dist,
        Mimic.holding and " (holding)" or "")
end

function Mimic.Set(on)
    Mimic.enabled = on
    Mimic.gen = Mimic.gen + 1
    local myGen = Mimic.gen
    if not on then
        Mimic.note = "idle"
        return true
    end
    if Mimic.targetName == "" or not Players:FindFirstChild(Mimic.targetName) then
        Mimic.enabled = false
        return false, "pick a player first"
    end
    if not S.Car.Model then
        Mimic.enabled = false
        return false, "you need to be in your car"
    end
    Mimic.trail = {}
    Mimic.note = "building trail"
    task.spawn(function()
        while Mimic.enabled and Mimic.gen == myGen and ALIVE do
            local dt = task.wait()
            local ok, err = pcall(Mimic.Step, dt or 1 / 60)
            if not ok then warn("[AdminTools] mimic:", err) end
        end
    end)
    return true
end

--============================================================================
-- HITBOX OVERLAYS  (Visuals tab)
--============================================================================
-- Traffic hitbox : a wireframe box on every traffic CoreHitbox, so you can see
--                  what you are actually going to collide with.
-- Score hitbox   : ONE box covering TrafficHitboxLeft and TrafficHitboxRight
--                  together, i.e. the radius a pass has to fall inside.
local HitView = { pool = {}, scoreAdorn = nil, last = 0 }

local function hitViewBox(i)
    local sb = HitView.pool[i]
    if not sb then
        sb = new("SelectionBox", {
            Name = "AT_HitView", LineThickness = TH.opt.wireThick + 0.01, SurfaceTransparency = 1,
            Transparency = 0.15, Color3 = TH.get("ESP:Traffic"), Visible = false, Parent = AdornHolder,
        })
        -- baked at construction, so without the registry these could never
        -- follow an ESP colour change.  Throttled to 4 Hz by TH.rate.
        TH.bind(sb, "Color3", "ESP:Traffic")
        HitView.pool[i] = sb
    end
    return sb
end

local function updateHitViews()
    -- traffic hitboxes
    local used = 0
    if S.ESP.TrafficHitbox then
        local folder = Workspace:FindFirstChild("TrafficFolder")
        local camPos = Camera.CFrame.Position
        if folder then
            for _, car in ipairs(folder:GetChildren()) do
                if car.Parent and used < 60 then
                    for _, p in ipairs(trafficHitboxes(car)) do
                        if (p.Position - camPos).Magnitude < 900 then
                            used = used + 1
                            local sb = hitViewBox(used)
                            sb.Adornee = p
                            sb.Visible = true
                        end
                    end
                end
            end
        end
    end
    for k = used + 1, #HitView.pool do
        local sb = HitView.pool[k]
        if sb.Visible then sb.Visible = false sb.Adornee = nil end
    end

    -- combined scoring box
    local root = S.Car.Root
    if not HitView.scoreAdorn then
        -- 0.82 is all but invisible against a bright road; 0.72 reads as a
        -- volume without hiding what is inside it
        HitView.scoreAdorn = new("BoxHandleAdornment", {
            Name = "AT_ScoreView", Color3 = TH.get("ESP:Car"), Transparency = 0.72,
            AlwaysOnTop = true, ZIndex = 1, Visible = false,
            Size = Vector3.new(1, 1, 1), Parent = AdornHolder,
        })
        TH.bind(HitView.scoreAdorn, "Color3", "ESP:Car")
    end
    local adorn = HitView.scoreAdorn
    if S.ESP.ScoreHitbox and root and root.Parent then
        local parts = scoreBoxParts()
        if #parts > 0 then
            local mn, mx
            for _, p in ipairs(parts) do
                local cf, sz = p.CFrame, p.Size
                for _, c in ipairs(ESP.corners) do
                    local world = cf:PointToWorldSpace(
                        Vector3.new(sz.X * 0.5 * c.X, sz.Y * 0.5 * c.Y, sz.Z * 0.5 * c.Z))
                    local lp = root.CFrame:PointToObjectSpace(world)
                    if mn then
                        mn = Vector3.new(math.min(mn.X, lp.X), math.min(mn.Y, lp.Y), math.min(mn.Z, lp.Z))
                        mx = Vector3.new(math.max(mx.X, lp.X), math.max(mx.Y, lp.Y), math.max(mx.Z, lp.Z))
                    else
                        mn, mx = lp, lp
                    end
                end
            end
            if mn then
                adorn.Adornee = root
                adorn.Size = mx - mn
                adorn.CFrame = CFrame.new((mn + mx) * 0.5)
                adorn.Visible = true
                return
            end
        end
    end
    if adorn.Visible then adorn.Visible = false end
end

bind(RunService.Heartbeat, function()
    if tick() - HitView.last < 0.2 then return end
    HitView.last = tick()
    if S.ESP.TrafficHitbox or S.ESP.ScoreHitbox or #HitView.pool > 0 then
        local ok, err = pcall(updateHitViews)
        if not ok then warn("[AdminTools] hit view:", err) end
    end
end)

function WorldCtl.FolderStatus(job)
    local parts = {}
    for _, fname in ipairs(job.folders) do
        parts[#parts + 1] = (Workspace:FindFirstChild(fname) and "+" or "-") .. fname
    end
    return table.concat(parts, "  ")
end

--============================================================================
-- ANTI-AFK
--============================================================================
-- Resetting Roblox's idle timer needs VirtualUser, which is the same family of
-- protected service as VirtualInputManager - and THAT one crashes this client
-- when instantiated.  So it is off by default and only ever reached for when
-- the toggle is switched on, never at load.
-- Two mechanisms, because the VirtualUser one got this account kicked:
--   Block idle signal - severs whatever is listening to Player.Idled, so the
--     idle kick never fires.  No synthetic input, no protected service.
--   VirtualUser click - the classic method, kept because it was here, but it
--     touches a protected service and is what caused the kick.
local AntiAfk = {
    enabled = false, mode = "Block idle signal", conn = nil, vu = nil,
    fired = 0, blocked = 0, gen = 0,
}

function AntiAfk.GetVU()
    if AntiAfk.vu ~= nil then return AntiAfk.vu or nil end
    local existing = game:FindFirstChildOfClass("VirtualUser")
    if existing then AntiAfk.vu = existing return existing end
    local ok, svc = pcall(function() return game:GetService("VirtualUser") end)
    AntiAfk.vu = (ok and svc) or false
    return AntiAfk.vu or nil
end

-- kill every listener on Player.Idled; they get re-added, so this repeats
function AntiAfk.BlockIdle()
    if typeof(getconnections) ~= "function" then return nil end
    local n = 0
    pcall(function()
        for _, c in pairs(getconnections(LocalPlayer.Idled)) do
            if c.Disable then
                pcall(function() c:Disable() end)
            elseif c.Disconnect then
                pcall(function() c:Disconnect() end)
            end
            n = n + 1
        end
    end)
    return n
end

function AntiAfk.Set(on)
    AntiAfk.enabled = on
    AntiAfk.gen = AntiAfk.gen + 1
    local myGen = AntiAfk.gen
    if AntiAfk.conn then AntiAfk.conn:Disconnect() AntiAfk.conn = nil end
    if not on then return true end

    -- matched loosely so a config saved under the old label still selects it
    if AntiAfk.mode:find("VirtualUser", 1, true) then
        local vu = AntiAfk.GetVU()
        if not vu then
            AntiAfk.enabled = false
            return false, "VirtualUser is unavailable in this executor"
        end
        AntiAfk.conn = LocalPlayer.Idled:Connect(function()
            local ok = pcall(function()
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
            if ok then AntiAfk.fired = AntiAfk.fired + 1 end
        end)
        CONN[#CONN + 1] = AntiAfk.conn
        return true
    end

    local first = AntiAfk.BlockIdle()
    if first == nil then
        AntiAfk.enabled = false
        return false, "this executor has no getconnections - try VirtualUser mode"
    end
    AntiAfk.blocked = first
    task.spawn(function()
        while AntiAfk.enabled and AntiAfk.gen == myGen and ALIVE do
            task.wait(20)
            if AntiAfk.enabled and AntiAfk.gen == myGen then
                local n = AntiAfk.BlockIdle()
                if n then AntiAfk.blocked = n end
            end
        end
    end)
    return true
end

--============================================================================
-- ACTIVITY KEEPALIVE
--============================================================================
-- Separate problem from Roblox's idle kick: this game withholds points, XP and
-- money unless it thinks you are driving.  The most likely gate is the vehicle
-- seat's own throttle, because that is the property the real control script
-- writes and the obvious thing for scoring code to read.  Writing it ourselves
-- is not synthetic OS input - it is the same property, set by the seat's
-- occupant, and it replicates exactly the same way.
local Keep = {
    vim = nil,
    -- anti auto-play AFK: one real click every 30s while automation is driving
    click = { on = false, gen = 0, count = 0, x = 0, y = 0, pickedAt = 0,
              hit = 0, last = "-" },
}

-- A plain table stands in for an InputObject.  Handlers that read fields off it
-- are satisfied; handlers that call methods on it error, and that error is
-- caught per listener so one picky script cannot stop the rest.
-- Somewhere on screen with nothing pressable under it.  The click has to land on
-- empty space: the point is to move the game's input clock, not to operate its
-- UI, and a stray press on a real button several hundred times is its own bug.
function Keep.SafeSpot()
    local c = Keep.click
    if c.x ~= 0 and (tick() - (c.pickedAt or 0)) < 10 then return c.x, c.y end
    local cam = Workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local tries = {
        { 0.50, 0.50 },   -- dead centre first, as asked
        { 0.50, 0.38 },
        { 0.30, 0.45 },
        { 0.70, 0.45 },
        { 0.50, 0.62 },
    }
    for _, t in ipairs(tries) do
        local x, y = math.floor(vp.X * t[1]), math.floor(vp.Y * t[2])
        local clear = true
        if pg then
            local ok, objs = pcall(function() return pg:GetGuiObjectsAtPosition(x, y) end)
            if ok and objs then
                for _, o in ipairs(objs) do
                    -- our own menu lives here too when it is mounted in PlayerGui
                    if o:IsA("GuiButton") or o:IsA("TextBox") then clear = false break end
                end
            end
        end
        if clear then
            c.x, c.y, c.pickedAt = x, y, tick()
            return x, y
        end
    end
    c.x, c.y, c.pickedAt = math.floor(vp.X * 0.5), math.floor(vp.Y * 0.5), tick()
    return c.x, c.y
end

-- Are we actually sat in the car?  Clicking while stood in a menu or spawn area
-- is exactly the case this is not supposed to cover.
function Keep.InCar()
    local car = S.Car.Model
    if not car or not car.Parent then return false end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if seat and seat:IsDescendantOf(car) then return true end
    -- some vehicles weld the character on instead of seating it
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local root = S.Car.Root
    if hrp and root then return (hrp.Position - root.Position).Magnitude < 30 end
    return false
end

-- A REAL mouse click, the only in-engine way to click empty space.
-- Probe 7 crashed on GetService("VirtualInputManager") back in September, so an
-- earlier version of this refused to create the service. That turned out to be
-- the wrong conclusion - it works - so the service is fetched normally, cached,
-- and down/up are sent back to back with no wait between them.
function Keep.VIM()
    if Keep.vim ~= nil then return Keep.vim or nil end
    local existing = game:FindFirstChildOfClass("VirtualInputManager")
    if existing then Keep.vim = existing return existing end
    local ok, svc = pcall(function() return game:GetService("VirtualInputManager") end)
    Keep.vim = (ok and svc) or false
    return Keep.vim or nil
end

function Keep.RealClick()
    local vim = Keep.VIM()
    if not vim then return false, "VirtualInputManager unavailable" end
    local x, y = Keep.SafeSpot()
    local ok = pcall(function()
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok, ok and string.format("click @ %d,%d", x, y) or "SendMouseButtonEvent failed"
end

-- Anti auto-play AFK.  One click every 30 seconds, but only while something is
-- actually driving and we are in the car - idling in a menu is the one case this
-- must not cover.  The clock only runs while those hold, so stopping automation
-- does not bank up a burst of clicks for when it resumes.
local KEEP_CLICK_EVERY = 30

function Keep.PlaySet(on)
    local c = Keep.click
    c.on = on
    c.gen = c.gen + 1
    local myGen = c.gen
    if not on then
        c.last = "off"
        return true
    end
    c.count, c.hit, c.last = 0, 0, "waiting for automation"
    task.spawn(function()
        local due = 0
        while c.on and c.gen == myGen and ALIVE do
            task.wait(1)
            if not (c.on and c.gen == myGen) then break end
            local driving = A.Running or A.Chasing
            if not driving then
                c.last, due = "automation idle", 0
            elseif not Keep.InCar() then
                c.last, due = "not in the car", 0
            else
                local now = tick()
                if now >= due then
                    local ok, why = Keep.RealClick()
                    c.count = c.count + 1
                    c.hit, c.last = ok and 1 or 0, why
                    due = now + KEEP_CLICK_EVERY
                end
            end
        end
    end)
    return true
end


--============================================================================
-- CONFIG SAVE / LOAD
--============================================================================
local HttpService = game:GetService("HttpService")
local Config = { prefix = "AdminTools_cfg_", last = "-" }

-- ------------------------------------------------------------- MIGRATION
-- A saved config keys every control as "<section title>/<control text>", so
-- renaming anything in the menu silently breaks every config anyone has saved.
-- Stage 1 decoupled the saved name from the displayed one, which handles most
-- renames for free.  This handles the rest: a section whose KEY genuinely has
-- to move, and a stored VALUE whose meaning changes.
--
-- Bump SCHEMA whenever an entry is added below.  A file already at the current
-- schema is passed through untouched, so migration runs exactly once per file.
Config.SCHEMA = 3

-- ["old section/control"] = "new section/control"
-- DELIBERATELY EMPTY.  Entries are added in the SAME change that performs the
-- rename, never before: a key rewritten to a section that does not exist yet
-- simply fails to match CONTROLS, and the control silently keeps its default.
Config.KeyMap = {
    -- Schema 3: the Automation "Session" section held two settings and nine
    -- readouts.  The readouts moved out, and what remained is a run goal - so
    -- the section key moved with it.  These are the only two keys in the whole
    -- overhaul that change; every other rename is display-only.
    ["Session/Goal"]        = "Run goal/Goal",
    ["Session/Goal amount"] = "Run goal/Goal amount",
    -- The Fun tab's "Traffic" section shared a key namespace with the World
    -- tab's "Traffic" section.  Nothing collided yet, but the next "Delay" or
    -- "Type" row added to either would have silently hijacked the other.
    ["Traffic/Traffic bayblade"] = "Traffic pranks/Traffic bayblade",
    ["Traffic/Spin speed"]       = "Traffic pranks/Spin speed",
    ["Traffic/Traffic disco"]    = "Traffic pranks/Traffic disco",
    ["Traffic/Disco speed"]      = "Traffic pranks/Disco speed",
    ["Traffic/Traffic balloons"] = "Traffic pranks/Traffic balloons",
    ["Traffic/Float speed"]      = "Traffic pranks/Float speed",
}

-- ["Section/Control"] = function(value, wholeFile) -> newValue
-- For stored values whose meaning changes, e.g. a dropdown option being
-- renamed or split.  Also empty until something needs it.  A value map has to
-- live here rather than in a control's callback, because Config.Apply walks
-- pairs() in arbitrary order and a callback cannot rely on another key in the
-- same file having landed yet.
Config.ValMap = {
    -- Schema 2: "Physics Drive" / "Waypoint Drive" / "Path Flight" collapsed to
    -- "Normal" / "Hover".  This HAS to live here rather than in the dropdown's
    -- callback, because deciding between the two needs the hover height out of
    -- the SAME file - and Config.Apply walks pairs() in arbitrary order, so a
    -- callback cannot rely on that key having landed yet.
    ["Engine/Method"] = function(v, whole)
        if v == "Path Flight" then
            -- Path Flight at hover 0 was already Normal in everything but name
            return ((tonumber(whole["Engine/Hover height"]) or 0) > 0)
                and "Hover" or "Normal"
        end
        if v ~= "Normal" and v ~= "Hover" then return "Normal" end
        return v
    end,
}

function Config.Migrate(tbl)
    local was = tonumber(tbl["@schema"]) or 0
    if was >= Config.SCHEMA then return tbl, 0 end
    local out, moved = {}, 0
    for k, v in pairs(tbl) do
        if k:sub(1, 1) == "@" then
            -- Reserved envelope keys are CARRIED, never renamed.  They used to
            -- be dropped here, which is invisible today only because the early
            -- return above skips this loop for a file already at SCHEMA - the
            -- next schema bump would have silently deleted "@simple" from every
            -- saved config on disk.
            out[k] = v
        else
            local nk = Config.KeyMap[k]
            if nk then moved = moved + 1 else nk = k end
            out[nk] = v
        end
    end
    for key, fn in pairs(Config.ValMap) do
        if out[key] ~= nil then
            local ok, nv = pcall(fn, out[key], out)
            if ok and nv ~= nil then out[key] = nv end
        end
    end
    out["@schema"] = Config.SCHEMA
    return out, moved
end

-- Keys for controls that only exist in the dev build.  Without this the public
-- build warns "unknown keys skipped" on EVERY load of a config saved from dev,
-- which trains people to ignore the one message that would catch a botched
-- rename.
-- "Activity keepalive/" is here because that whole feature was removed: it
-- duplicated Automation > Anti-AFK, and its synthetic input never reached
-- the game anyway.  Existing configs still carry its four keys.
Config.ignorePrefix = { "Path recorder/", "Spy/", "Environment/",
                        "Activity keepalive/",
                        -- the duplicate hue dials; the real picker is on Theme
                        "ESP Colour/" }

-- Individually retired keys.  Deliberately removed is not the same as broken,
-- and the "matched nothing" warning only means anything if it stays rare.
Config.ignoreKey = {
    ["ESP Colours/Box style"]     = true,   -- duplicate of Markers/Box style
    ["ESP Colours/Tracer origin"] = true,   -- duplicate of Markers/Tracer origin
}

function Config.Ignored(id)
    if id:sub(1, 1) == "@" then return true end
    if UI.noSave[id] then return true end       -- exists, just not persisted
    if Config.ignoreKey[id] then return true end
    for _, p in ipairs(Config.ignorePrefix) do
        if id:sub(1, #p) == p then return true end
    end
    return false
end

function Config.Collect()
    local out = {}
    for id, api in pairs(CONTROLS) do
        local v = api.Value
        if typeof(v) == "EnumItem" then
            out[id] = "enum:" .. v.Name
        elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
            out[id] = v
        end
    end
    out["@schema"] = Config.SCHEMA
    -- Reserved, so Config.Ignored skips it on the way back in and it can never
    -- collide with a control key.  Written unconditionally as a real boolean:
    -- an absent key means "no preference", which is not the same as "off".
    --
    -- Note what is NOT here.  Collect reads api.Value and never looks at what
    -- is on screen, so every row Simple mode hides still saves its value.  That
    -- is the whole reason Simple mode is forbidden from writing values: this
    -- function plus a blind writefile would turn a view switch into data loss.
    out["@simple"] = (S.Simple == true)
    return out
end

function Config.Apply(tbl)
    -- here rather than in Config.Load, so the autoload path and every future
    -- caller get migration for free
    local moved
    -- Read the view preference off the RAW table.  Migrate rebuilds it and only
    -- promises to carry the envelope forward; taking the value here is immune
    -- to whatever a future schema does to that rule.
    local simple = tbl["@simple"]
    tbl, moved = Config.Migrate(tbl)
    local applied, unknown = 0, 0
    -- lets a callback tell "the user did this" from "a config restored this"
    Config.applying = true
    for id, v in pairs(tbl) do
        local api = CONTROLS[id]
        if Config.Ignored(id) then
            -- reserved or dev-only: neither applied nor worth warning about
        elseif api then
            if type(v) == "string" and v:sub(1, 5) == "enum:" then
                local okk, kc = pcall(function() return Enum.KeyCode[v:sub(6)] end)
                v = okk and kc or nil
            end
            -- applied loudly on purpose: the callbacks are what turn features on
            if v ~= nil and pcall(function() api:Set(v) end) then
                applied = applied + 1
            end
        else
            unknown = unknown + 1
        end
    end
    Config.applying = false
    -- LAST, and outside the applying window.  Window.SetSimple walks every row
    -- writing HIDE_SIMPLE, and six of the callbacks the loop above just fired
    -- write HIDE_COND on some of the same frames.  Different bits, so they
    -- compose either way - but doing it here means the sidebar and the
    -- selection slab settle exactly once instead of mid-restore.
    if simple ~= nil and Window.SetSimple then
        Window.SetSimple(simple == true)
    end
    return applied, unknown, moved
end

-- The tested driving setup, keyed by CONFIG KEY rather than by live handle.
-- The RESET APPEARANCE button keys off an array of api handles and has drifted
-- every time a control moved; a key cannot drift, because it is the same string
-- the saved file uses and Config.KeyMap already knows how to follow a rename.
--
-- These fifteen values are the S.Auto defaults, not new numbers - so this is a
-- REPAIR button ("put it back"), never a preset ("make it different").
Config.RECOMMENDED = {
    ["Engine/Method"]           = "Normal",
    ["Engine/Hover height"]     = 0,
    ["Engine/Lane"]             = "Auto",
    ["Engine/Dodge traffic"]    = true,
    ["Engine/Smart dodge"]      = true,
    ["Engine/Clearance"]        = 0.5,
    ["Engine/Dodge room"]       = 14,
    ["Engine/No braking"]       = true,
    ["Engine/Brake distance"]   = 70,
    ["Engine/Hunt traffic"]     = true,
    ["Engine/Rotate with path"] = true,
    ["Engine/Stuck recovery"]   = true,
    ["Speed/Speed mode"]        = "Static",
    ["Speed/Static speed"]      = 310,
    ["ESP/ESP master"]          = false,
}

-- Safe to write values from, unlike Simple mode: this runs from a button press
-- the user confirmed, not from inside Config.Apply, and it goes through the
-- same api:Set every restore uses.  Set is called WITHOUT the silent flag on
-- purpose - a silent Set moves the widget while the variable behind it keeps
-- its old value, which is the exact bug the comment on api:Set records.
function Config.ApplyRecommended()
    local n, miss = 0, {}
    for k, v in pairs(Config.RECOMMENDED) do
        local id = Config.KeyMap[k] or k
        local api = CONTROLS[id]
        if api and pcall(function() api:Set(v) end) then
            n = n + 1
        else
            -- a key that stopped resolving must not vanish into a smaller
            -- number; that is how a repair button rots unnoticed
            miss[#miss + 1] = id
        end
    end
    return n, miss
end

function Config.Save(name)
    if typeof(writefile) ~= "function" then return false, "no writefile in this executor" end
    local ok, json = pcall(function() return HttpService:JSONEncode(Config.Collect()) end)
    if not ok then return false, "could not encode settings" end
    local ok2, err = pcall(writefile, Config.prefix .. name .. ".json", json)
    return ok2, ok2 and nil or tostring(err)
end

function Config.Load(name)
    if typeof(readfile) ~= "function" then return false, "no readfile in this executor" end
    local file = Config.prefix .. name .. ".json"
    if typeof(isfile) == "function" then
        local okf, exists = pcall(isfile, file)
        if okf and not exists then return false, "no config called " .. name end
    end
    local ok, text = pcall(readfile, file)
    if not ok then return false, "could not read " .. file end
    local ok2, tbl = pcall(function() return HttpService:JSONDecode(text) end)
    if not ok2 or type(tbl) ~= "table" then return false, "config file is not valid JSON" end
    local applied, unknown, moved = Config.Apply(tbl)
    return true, applied, unknown, moved
end

function Config.Delete(name)
    local file = Config.prefix .. name .. ".json"
    if typeof(delfile) ~= "function" then return false, "no delfile in this executor" end
    local ok, err = pcall(delfile, file)
    return ok, ok and nil or tostring(err)
end

function Config.List()
    local out = {}
    if typeof(listfiles) == "function" then
        local ok, files = pcall(listfiles, ".")
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                local n = tostring(f):match("([^\\/]+)%.json$")
                if n and n:sub(1, #Config.prefix) == Config.prefix then
                    out[#out + 1] = n:sub(#Config.prefix + 1)
                end
            end
        end
    end
    table.sort(out)
    return out
end

--============================================================================
-- BOOT SCAN  (real numbers for the loading screen to report)
--============================================================================
-- MOBILE: Loading screen disabled
-- Loading.Start()
Car.Refresh()
World.BuildLanes()

--============================================================================
-- UI : TABS
--============================================================================
local TABS = {}
-- DRIVING first, because that is what the tool is for and what a lost user is
-- looking for.  EXTRAS (order >= 85) is everything you can ignore and still
-- have a working script.  A tab's name is never part of a config key, so
-- renaming and reordering these costs nothing.
TABS.auto   = addTab("Drive", "01", 1)
TABS.earn   = addTab("Earn", "02", 2)
TABS.car    = addTab("My car", "03", 3)
TABS.world  = addTab("Traffic", "04", 4)
TABS.vis    = addTab("Markers", "05", 86)
TABS.fun    = addTab("Fun", "06", 87)
TABS.set    = addTab("Settings", "07", 88)

headerButton(-14, "X", THEME.Bad, function() Window.SetOpen(false) end)
-- Captured: Simple mode hides the Theme tab, and a shortcut to a hidden tab is
-- a dead button.
Window.lookBtn = headerButton(-52, "*", THEME.Accent, function()
    if TABS.look then TABS.look.Select() end
end)

--============================================================================
-- TAB 1 : CAR
--============================================================================
do
    local sec = UI.Section(TABS.car.page, "Current car", 1, "Vehicle")
    REF.carName = UI.Info(sec, "Current car", S.Car.Name)
    REF.carSpeed = UI.Info(sec, "Live speed", "0 MPH")
    -- Lifted out of the button because Simple mode hides this whole tab, and
    -- "no vehicle" is the first thing that goes wrong for a new user.  The
    -- Start here section calls the SAME function rather than carrying a copy.
    function Car.Rescan()
        S.Car.Model = nil
        Car.Refresh()
        World.BuildLanes()
        if S.Car.Model then
            notify("Vehicle found", S.Car.Model.Name, "good")
        else
            notify("No vehicle", "Nothing matching " .. LocalPlayer.Name .. "_<car>", "warn")
        end
    end
    UI.Button(sec, "RESCAN WORKSPACE", function() Car.Rescan() end, 10)

    local sec2 = UI.Section(TABS.car.page, "Boost", 2)
    REF.boostKey = UI.Keybind(sec2, {
        Text = "Boost key", Desc = "Hold to push the car along its facing direction",
        Default = S.Keys.Boost,
        Callback = function(kc) S.Keys.Boost = kc end,
    })
    UI.Slider(sec2, {
        Text = "Boost power", Min = 20, Max = 900, Default = S.Boost.Power, Step = 5, Suffix = "",
        Callback = function(v) S.Boost.Power = v end,
    })

    local sec3 = UI.Section(TABS.car.page, "Fly the car by hand", 3, "Flight")
    REF.flyToggle = UI.Toggle(sec3, {
        Text = "Fly with WASD", Key = "Car fly",
        Tags = "fly flight manual wasd hover free", Desc = "WASD + Space / Ctrl, steered by the camera",
        Default = false,
        Callback = function(v) Fly.Set(v) end,
    })
    UI.Slider(sec3, {
        Text = "Fly speed", Min = 20, Max = 600, Default = S.Fly.Speed, Step = 5, Suffix = " st/s",
        Callback = function(v) S.Fly.Speed = v end,
    })

    local sec4 = UI.Section(TABS.car.page, "Spin", 5, "Chaos")
    REF.spinToggle = UI.Toggle(sec4, {
        Text = "Spin my car", Key = "Bayblade",
        Tags = "bayblade beyblade spin rotate", Desc = "Spins the car assembly on its Y axis",
        Default = false,
        Callback = function(v) setSpin(v) end,
    })
    UI.Slider(sec4, {
        Text = "Spin speed", Min = 5, Max = 120, Default = S.Spin.Speed, Step = 1, Suffix = " rad/s",
        Callback = function(v) S.Spin.Speed = v end,
    })
end

--============================================================================
-- TAB 2 : VISUALS
--============================================================================
do
    local sec = UI.Section(TABS.vis.page, "My car's look", 1, "Render")
    UI.Toggle(sec, {
        Text = "Wireframe my car", Key = "Car wireframe",
        Tags = "wireframe outline skeleton mesh", Desc = "Edge-renders every part of your car",
        Default = false,
        Callback = function(v) Wire.Set(v) end,
    })
    UI.Toggle(sec, {
        Text = "Hide the solid body", Key = "Hide bodywork",
        Tags = "hide invisible bodywork transparent", Desc = "Wireframe only - hides the solid mesh locally",
        Default = false,
        Callback = function(v) S.Wire.HideBody = v end,
    })

    local sec2 = UI.Section(TABS.vis.page, "See-through markers", 2, "ESP")
    REF.espMaster = UI.Toggle(sec2, {
        Text = "Turn markers on", Key = "ESP master",
        Tags = "esp see through wallhack marker box tracer lag fps", Desc = "Turns every target category below on or off",
        Default = false,
        Callback = function(v)
            S.ESP.Master = v
            if not v then ESP.ClearHighlights() end
        end,
    })
    UI.Toggle(sec2, { Text = "Cars", Desc = "Every player car except yours", Default = S.ESP.Cars,
        Callback = function(v) S.ESP.Cars = v end })
    UI.Toggle(sec2, { Text = "Traffic", Default = S.ESP.Traffic,
        Callback = function(v) S.ESP.Traffic = v end })
    UI.Toggle(sec2, { Text = "Players", Default = S.ESP.Players,
        Callback = function(v) S.ESP.Players = v end })
    UI.Toggle(sec2, {
        Text = "Lane waypoints",
        Desc = "Nodes of every drivable path, built-ins included · active one in green",
        Default = S.ESP.Waypoints, Callback = function(v) S.ESP.Waypoints = v end,
    })

    local sec3 = UI.Section(TABS.vis.page, "What the markers look like", 3, "ESP Style")
    UI.Toggle(sec3, { Text = "Lines", Desc = "Tracers from the bottom of the screen", Default = S.ESP.Lines,
        Callback = function(v) S.ESP.Lines = v end })
    UI.Toggle(sec3, { Text = "Boxes", Default = S.ESP.Boxes, Callback = function(v) S.ESP.Boxes = v end })
    UI.Toggle(sec3, { Text = "Highlights", Default = S.ESP.Highlights,
        Callback = function(v) S.ESP.Highlights = v if not v then ESP.ClearHighlights() end end })
    UI.Toggle(sec3, { Text = "Glow", Desc = "Pulsing fill on highlighted targets", Default = S.ESP.Glow,
        Callback = function(v) S.ESP.Glow = v if not v then ESP.ClearHighlights() end end })
    UI.Toggle(sec3, { Text = "See through walls", Key = "Visible through walls",
        Tags = "walls through xray occlude see", Default = S.ESP.ThroughWalls,
        Callback = function(v) S.ESP.ThroughWalls = v end })
    UI.Toggle(sec3, { Text = "Include me", Key = "Include local player",
        Tags = "me myself local player include own", Desc = "Also draw your own car and character",
        Default = S.ESP.IncludeLocal, Callback = function(v) S.ESP.IncludeLocal = v end })
    UI.Toggle(sec3, { Text = "Names", Default = S.ESP.Names, Callback = function(v) S.ESP.Names = v end })
    UI.Toggle(sec3, { Text = "Distance", Default = S.ESP.Distance, Callback = function(v) S.ESP.Distance = v end })
    UI.Slider(sec3, { Text = "Stop drawing past", Key = "Max distance",
        Tags = "distance range far max draw", Min = 200, Max = 6000, Default = S.ESP.MaxDistance, Step = 50,
        Suffix = " st", Callback = function(v) S.ESP.MaxDistance = v end })

    -- Box shape and ESP colour used to live only in the Appearance tab, which is
    -- not where anyone looks for them. These drive exactly the same state, so
    -- either tab works and neither is a copy of the other.
    local secBX = UI.Section(TABS.vis.page, "Box style", 4)
    UI.Dropdown(secBX, {
        Text = "Box style",
        Options = { "Brackets", "Frame", "Brackets + fill", "3D", "3D fill" },
        Default = "Frame", Order = 1,
        Callback = function(v)
            if TH and TH.opt then TH.opt.boxStyle = v end
        end,
    })
    UI.Dropdown(secBX, {
        Text = "Tracer origin", Options = { "Bottom", "Centre", "Top" },
        Default = "Bottom", Order = 2,
        Callback = function(v)
            if TH and TH.opt then TH.opt.originPt = v end
        end,
    })
    UI.Note(secBX, "Brackets, Frame and fill are flat on your screen. 3D draws real boxes that turn with the car.", THEME.Accent2)

    -- The colour controls used to be duplicated here AND on the Theme tab,
    -- both writing the same setter with neither syncing the other - so a
    -- config load restored whichever key pairs() reached last.  One home now.
    local secCOL = UI.Section(TABS.vis.page, "Marker colours", 26)
    UI.Button(secCOL, "OPEN COLOUR SETTINGS", function()
        if TABS.look and TABS.look.Select then TABS.look.Select() end
    end)
    UI.Note(secCOL, "Every marker colour, the full picker and RGB live on the Theme tab.", THEME.Accent2)

    local secHB = UI.Section(TABS.vis.page, "Hitbox overlay", 6, "Hitboxes")
    UI.Toggle(secHB, {
        Text = "Show traffic hitboxes", Key = "Traffic hitbox",
        Tags = "hitbox box outline wireframe traffic",
        Desc = "Draws a wireframe around every traffic car's hitbox",
        Default = S.ESP.TrafficHitbox,
        Callback = function(v) S.ESP.TrafficHitbox = v end,
    })
    UI.Toggle(secHB, {
        Text = "Show my score hitbox", Key = "Score hitbox",
        Tags = "hitbox score box outline wireframe mine",
        Desc = "Draws the box you score passes with - drawing only, nothing is changed",
        Default = S.ESP.ScoreHitbox,
        Callback = function(v) S.ESP.ScoreHitbox = v end,
    })
    UI.Note(secHB, "Draws the real parts, so it shows whatever the World tab has resized them to.", THEME.Accent2)

    local secPU = UI.Section(TABS.vis.page, "Player pulse", 7)
    UI.Toggle(secPU, {
        Text = "Player pulse", Desc = "A ring blooms from every footfall",
        Default = false,
        Callback = function(v) Pulse.Set(v) end,
    })
    UI.Toggle(secPU, {
        Text = "Jump splash", Desc = "A wider ring slams downward on a jump",
        Default = Pulse.jumps, Callback = function(v) Pulse.jumps = v end,
    })
    UI.Toggle(secPU, {
        Text = "Include me", Default = Pulse.includeLocal,
        Callback = function(v) Pulse.includeLocal = v end,
    })
    UI.Slider(secPU, {
        Text = "Ring size", Min = 0.3, Max = 4, Default = Pulse.size, Step = 0.1, Decimals = 1,
        Format = function(v) return string.format("%.1fx", v) end,
        Callback = function(v) Pulse.size = v end,
    })
    UI.Slider(secPU, {
        Text = "Ring life", Min = 0.2, Max = 2, Default = Pulse.life, Step = 0.05, Decimals = 2,
        Format = function(v) return string.format("%.2fs", v) end,
        Callback = function(v) Pulse.life = v end,
    })
    UI.Note(secPU, "Rings are real world parts. Colour and RGB for them live in the Appearance tab.", THEME.Warn)

    local sec4 = UI.Section(TABS.auto.page, "Autoplay overlays", 5, "Automation ESP")
    UI.Toggle(sec4, {
        Text = "Show progress panel", Key = "Progression box",
        Tags = "progress panel box overlay hud stats", Desc = "Live panel above your car - works even with markers off",
        Default = S.ESP.ProgressBox, Callback = function(v) S.ESP.ProgressBox = v end,
    })
    UI.Toggle(sec4, {
        Text = "Show the route", Key = "Path preview",
        Tags = "path route preview line show", Desc = "Draws the route the automation will follow",
        Default = S.ESP.PathPreview,
        Callback = function(v)
            S.ESP.PathPreview = v
            if not v then clearPath() end
        end,
    })
end

--============================================================================
-- TAB 3 : AUTOMATION
--============================================================================
do
    local function laneOptionList()
        local opts = { "Auto" }
        for _, l in ipairs(World.paths) do opts[#opts + 1] = l.name end
        return opts
    end
    local laneOptions = laneOptionList()
    REF.laneOptionList = laneOptionList

    local secA = UI.Section(TABS.set.page, "Keep earning while parked", 10, "Anti-AFK")
    REF.afkPlay = UI.Toggle(secA, {
        Text = "Click for me every 30s", Key = "Anti-Auto play AFK",
        Tags = "afk idle kick kicked away keepalive stay online click",
        Desc = "One real click every 30s while automation drives and you are in the car",
        Default = A.AfkClick, Order = 1,
        Callback = function(v)
            A.AfkClick = v
            Keep.PlaySet(v)
        end,
    })
    REF.afkClickInfo = UI.Info(secA, "Clicks fired", "off", 2)

    local sec = UI.Section(TABS.auto.page, "Autoplay", 1, "Engine")
    -- Old option strings map onto the two that survive.  A config saved before
    -- this change still carries one of them, and Config.Apply calls Set without
    -- validating against Options, so the dropdown would happily wear a dead
    -- string.  This catches it on arrival.
    A.ModeAlias = { ["Physics Drive"] = "Normal", ["Waypoint Drive"] = "Normal",
                    ["Path Flight"] = "Hover" }
    REF.methodDrop = UI.Dropdown(sec, {
        Text = "Drive style", Key = "Method", Order = 1,
        Tags = "method mode physics drive waypoint path flight normal hover fly",
        Options = { "Normal", "Hover" },
        Default = A.ModeAlias[A.Mode] or A.Mode,
        Desc = "Normal keeps the wheels on the road. Hover lifts the car.",
        Callback = function(v)
            -- One bounce, then it terminates: ModeAlias["Normal"] is nil.  Safe
            -- because api:Set writes Value and the label BEFORE calling back, so
            -- the inner Set's writes land last.
            local fix = A.ModeAlias[v]
            if fix then return REF.methodDrop:Set(fix) end
            A.Mode = v
            Rig.Clear("auto")
            route.cursorPos = nil
            -- Seed the height from wherever Normal is riding, so switching to
            -- Hover holds station instead of dropping the car to the floor.
            -- Only when it has never been set; a chosen height is never touched.
            if v == "Hover" and (A.Hover or 0) <= 0 then
                A.Hover = A.NormalHeight or 2
                if REF.hoverSlider then REF.hoverSlider:Set(A.Hover, true) end
            end
            if REF.hoverSlider then
                UI.setVis(REF.hoverSlider.Frame, UI.HIDE_COND, v ~= "Hover")
            end
        end,
    })
    -- Order 3, not 15: this explains Drive style and How high to float, and at
    -- 15 it sat below the dodge sliders while still saying "the height below".
    REF.engNote1 = UI.Note(sec, "Normal keeps the wheels on the road. Hover lifts the car to the height below - handy over broken ground, and what the police chase uses.", THEME.Accent2, 3)
    REF.autoToggle = UI.Toggle(sec, {
        Text = "Drive for me", Key = "Run automation",
        Tags = "auto autoplay automation start run drive farm",
        Desc = "Drives the route on its own and farms distance",
        -- 2, not 1: Drive style is also 1, and a tie leaves the order on screen
        -- to whichever row happened to be built first.
        Default = false, Order = 2, NoSave = true,
        Callback = function(v)
            -- The chase owns the drive while it runs and re-arms it within
            -- 0.2s, so switching this off mid-chase used to do nothing
            -- whatsoever.  Stopping the drive means stopping the farm.
            if not v and A.Chasing and Chase.enabled then
                Chase.Set(false)
                if REF.chaseToggle then REF.chaseToggle:Set(false, true) end
                notify("Chase farm stopped",
                    "Drive for me was switched off, and the police chase farm needs it.",
                    "warn", 6)
            end
            Auto.Set(v)
        end,
    })
    REF.laneDrop = UI.Dropdown(sec, {
        Text = "Which road to drive", Key = "Lane",
        Tags = "lane road route path line which",
        Options = laneOptions, Default = A.Lane, Order = 4,
        Callback = function(v)
            A.Lane = v
            route.cursorPos = nil
        end,
    })
    UI.Toggle(sec, { Text = "Chase the busiest lane", Key = "Hunt traffic",
        Tags = "hunt overtake busiest most traffic cars lane switch",
        Desc = "On Auto, move to whichever line has the most cars to pass",
        Default = A.Overtake, Order = 30, Callback = function(v) A.Overtake = v end })
    UI.Toggle(sec, { Text = "Un-stick me automatically", Key = "Stuck recovery",
        Tags = "stuck recover unstick flipped reset respawn",
        Desc = "Puts the car back on the road when it stalls or flips",
        Default = A.Recover, Order = 32, Callback = function(v) A.Recover = v end })
    REF.hoverSlider = UI.Slider(sec, {
        Text = "How high to float", Key = "Hover height",
        Tags = "hover height float fly altitude ride",
        Min = 0, Max = 250, Default = A.Hover, Step = 1, Suffix = " st",
        Order = 3, Callback = function(v) A.Hover = v end,
    })
    UI.setVis(REF.hoverSlider.Frame, UI.HIDE_COND, A.Mode ~= "Hover")
    UI.Toggle(sec, { Text = "Point the car where it's going", Key = "Rotate with path",
        Tags = "rotate turn face heading direction body",
        Desc = "Turns the body to face the route · off keeps its heading",
        Default = A.Rotate, Order = 31, Callback = function(v) A.Rotate = v end })
    UI.Toggle(sec, { Text = "Steer around traffic", Key = "Dodge traffic",
        Tags = "dodge avoid swerve steer around traffic crash",
        Desc = "Swerves around cars in the way, then settles back on the line",
        Default = A.Dodge, Order = 10, Callback = function(v) A.Dodge = v end })
    REF.dodgeRoom = UI.Slider(sec, { Text = "Most it may swerve", Key = "Dodge room",
        Tags = "dodge room width swerve far lateral",
        Min = 3, Max = 100, Default = A.DodgeMax,
        Step = 1, Suffix = " st", Order = 13, Callback = function(v) A.DodgeMax = v end })
    REF.smartDodge = UI.Toggle(sec, {
        Text = "Measure each car", Key = "Smart dodge",
        Tags = "smart dodge measure exact hitbox precise gap",
        Desc = "Moves the exact width needed to clear the car, instead of a fixed push",
        Default = A.SmartDodge, Order = 11,
        Callback = function(v)
            A.SmartDodge = v
            -- Dodge room caps both modes now: it is the only thing keeping the
            -- car on its path, so it stays on screen either way
            if REF.dodgeClear then
                UI.setVis(REF.dodgeClear.Frame, UI.HIDE_COND, not v)
            end
        end,
    })
    REF.dodgeClear = UI.Slider(sec, {
        Text = "Gap to leave", Key = "Clearance",
        Tags = "clearance gap air margin space close",
        Min = 0, Max = 3, Default = A.DodgeClear, Step = 0.05, Decimals = 2,
        Format = function(v) return string.format("%.2f st", v) end, Order = 12,
        Callback = function(v) A.DodgeClear = v end,
    })
    UI.setVis(REF.dodgeClear.Frame, UI.HIDE_COND, not A.SmartDodge)
    -- Explicit 14: nextOrder() hands this 1, tying it with Drive style and Drive
    -- for me, which is why it rendered as the third row of the section instead
    -- of underneath the dodge sliders it describes.
    UI.Note(sec, "Dodge room is the most studs either mode may leave the path. Smart dodge moves the least that clears the next car; clearance is the air it leaves.", THEME.Accent2, 14)
    REF.bubble = UI.Toggle(sec, {
        Text = "Keep space around me", Key = "Push off traffic", Order = 17,
        Tags = "bubble cushion push space room personal close traffic touch",
        Desc = "Eases the car sideways when traffic gets close - works with steering off too",
        Default = A.Bubble,
        Callback = function(v)
            A.Bubble = v
            if REF.bubbleR then UI.setVis(REF.bubbleR.Frame, UI.HIDE_COND, not v) end
            if REF.bubbleP then UI.setVis(REF.bubbleP.Frame, UI.HIDE_COND, not v) end
        end,
    })
    REF.bubbleR = UI.Slider(sec, {
        Text = "Space to keep", Key = "Push starts at", Order = 18,
        Tags = "bubble cushion size radius distance close space",
        Min = 2, Max = 40, Default = A.BubbleR, Step = 1, Suffix = " st",
        Callback = function(v) A.BubbleR = v end,
    })
    REF.bubbleP = UI.Slider(sec, {
        Text = "How hard it pushes", Key = "Push strength", Order = 19,
        Tags = "bubble cushion push strength force hard",
        Min = 1, Max = 20, Default = A.BubblePush, Step = 1, Suffix = " st",
        Callback = function(v) A.BubblePush = v end,
    })
    UI.setVis(REF.bubbleR.Frame, UI.HIDE_COND, not A.Bubble)
    UI.setVis(REF.bubbleP.Frame, UI.HIDE_COND, not A.Bubble)
    UI.Note(sec, "Moves YOUR car, never the traffic - edits to their hitboxes never reach the server. Capped by Dodge room, and it only runs where the lane map says the road is, so it cannot push you off it.", THEME.Accent2, 19)
    REF.noBrake = UI.Toggle(sec, { Text = "Never slow down", Key = "No braking",
        Tags = "brake braking slow stop never speed",
        Desc = "Ignores traffic completely and keeps the speed up",
        Default = A.NoBrake, Order = 20, Callback = function(v)
            A.NoBrake = v
            -- it makes the distance below meaningless, so stop showing it
            if REF.brakeDist then
                UI.setVis(REF.brakeDist.Frame, UI.HIDE_COND, v)
            end
        end })
    REF.brakeDist = UI.Slider(sec, { Text = "Start slowing at", Key = "Brake distance",
        Tags = "brake distance slow follow gap stop",
        Min = 20, Max = 250, Default = A.FollowGap, Step = 5, Suffix = " st",
        Order = 21, Callback = function(v) A.FollowGap = v end })
    UI.setVis(REF.brakeDist.Frame, UI.HIDE_COND, A.NoBrake)
    UI.Note(sec, "Only cars in your path count as obstacles - traffic beside you is what pays.", THEME.Accent2, 7)

    -- 4th arg pins the saved key.  It was the displayed title before, so
    -- "Speed" was one display rename away from orphaning every saved speed.
    local sec2 = UI.Section(TABS.auto.page, "Speed", 2, "Speed")
    local staticSlider, profileDrop
    UI.Dropdown(sec2, {
        Text = "Speed mode", Options = { "Smart", "Static" }, Default = A.SpeedMode, Order = 1,
        Callback = function(v)
            A.SpeedMode = v
            if staticSlider then
                UI.setVis(staticSlider.Frame, UI.HIDE_COND, v ~= "Static")
            end
            if profileDrop then
                UI.setVis(profileDrop.Frame, UI.HIDE_COND, v ~= "Smart")
            end
        end,
    })
    staticSlider = UI.Slider(sec2, {
        Text = "Static speed", Min = 10, Max = 1000, Default = A.StaticMph, Step = 5, Suffix = " MPH",
        Order = 2, Callback = function(v) A.StaticMph = v end,
    })
    profileDrop = UI.Dropdown(sec2, {
        Text = "Smart profile", Options = { "Slow", "Normal", "Fast", "Insane" }, Default = A.Profile,
        Order = 3, Callback = function(v) A.Profile = v end,
    })
    local hint = UI.Info(sec2, "Range", "-")
    hint.Frame.LayoutOrder = 4
    UI.setVis(staticSlider.Frame, UI.HIDE_COND, A.SpeedMode ~= "Static")
    UI.setVis(profileDrop.Frame, UI.HIDE_COND, A.SpeedMode ~= "Smart")
    REF.speedHint = hint

    local sec3 = UI.Section(TABS.auto.page, "Stop when I've done enough", 3, "Run goal")
    -- Readouts get their own plate below the thing that sets them.
    local sec3b = UI.Section(TABS.auto.page, "Live stats", 4)
    local goalSlider
    UI.Dropdown(sec3, {
        Text = "Stop after", Key = "Goal", Order = 1,
        Tags = "goal target stop finish distance time near misses",
        Options = { "None", "Distance (mi)", "Time (min)", "Near misses" }, Default = A.Goal,
        Callback = function(v)
            A.Goal = v
            if goalSlider then
                UI.setVis(goalSlider.Frame, UI.HIDE_COND, v == "None")
            end
        end,
    })
    goalSlider = UI.Slider(sec3, {
        Text = "How much", Key = "Goal amount", Order = 2,
        Tags = "goal amount how much distance time passes",
        Min = 1, Max = 240, Default = A.GoalValue, Step = 1,
        Format = function(v)
            if A.Goal == "Near misses" then return tostring(math.floor(v * 10)) .. " passes" end
            if A.Goal == "Time (min)" then return tostring(math.floor(v)) .. " min" end
            return tostring(math.floor(v)) .. " mi"
        end,
        Callback = function(v) A.GoalValue = v end,
    })
    UI.setVis(goalSlider.Frame, UI.HIDE_COND, A.Goal == "None")

    REF.iState = UI.Info(sec3b, "State", "Idle")
    REF.iState.Frame.LayoutOrder = 3
    REF.iLogic = UI.Info(sec3b, "Logic", "-")
    REF.iLogic.Frame.LayoutOrder = 4
    REF.iSpeed = UI.Info(sec3b, "Speed / target", "0 / 0")
    REF.iSpeed.Frame.LayoutOrder = 5
    REF.iMoney = UI.Info(sec3b, "Earned", "-")
    REF.iMoney.Frame.LayoutOrder = 55
    REF.iPts = UI.Info(sec3b, "Points / streak", "-")
    REF.iPts.Frame.LayoutOrder = 56
    REF.iNear = UI.Info(sec3b, "Near misses", "0")
    REF.iNear.Frame.LayoutOrder = 6
    REF.iProg = UI.Info(sec3b, "Progress", "0%")
    REF.iProg.Frame.LayoutOrder = 7
    REF.iTime = UI.Info(sec3b, "Time automating", "00:00")
    REF.iTime.Frame.LayoutOrder = 8
    REF.iDist = UI.Info(sec3b, "Studs travelled", "0")
    REF.iDist.Frame.LayoutOrder = 9

    local sec4 = UI.Section(TABS.auto.page, "Road map", 6, "World")
    REF.iLanes = UI.Info(sec4, "Traffic lanes", string.format("%d lanes / %d waypoints", #World.lanes, World.wpTotal or 0))
    REF.iPaths = UI.Info(sec4, "Drivable paths", tostring(#World.paths))
    do
        local names = {}
        for _, l in ipairs(World.builtins or {}) do
            names[#names + 1] = string.format("%s (%d)", l.name, #l.points)
        end
        UI.Info(sec4, "Built-in routes", #names > 0 and table.concat(names, ", ") or "none")
    end
    REF.iWidth = UI.Info(sec4, "Lane width", string.format("%.1f studs", World.laneWidth))
    REF.iTraffic = UI.Info(sec4, "Traffic nearby", "0")
    UI.Button(sec4, "REBUILD LANE MAP", function()
        local l, w = World.BuildLanes()
        REF.syncLaneUI(true)
        notify("Lane map rebuilt", string.format("%d lanes, %d waypoints, %d drivable paths",
            l, w, #World.paths), "good")
    end, 10)
    UI.Note(sec4, "Lane 1.5 and 2.5 are the white lines between lanes: traffic both sides, no lane to share.", THEME.Accent2)

    -- The Lane list is built from whatever paths exist, so if TrafficLanes has
    -- not streamed in when the script runs it would otherwise show only "Auto"
    -- forever.  Keep it in step with the map instead.
    local lastPathCount = -1
    function REF.syncLaneUI(force)
        local n = #World.paths
        if not force and n == lastPathCount then return end
        lastPathCount = n
        REF.iLanes:Set(string.format("%d lanes / %d waypoints%s",
            #World.lanes, World.wpTotal or 0,
            (World.policeLanes and #World.policeLanes >= 2)
                and ("  ·  +" .. #World.policeLanes .. " from server") or ""))
        REF.iPaths:Set(tostring(n))
        REF.iWidth:Set(string.format("%.1f studs", World.laneWidth))
        if REF.laneDrop then REF.laneDrop:SetOptions(REF.laneOptionList()) end
    end
    REF.syncLaneUI(true)

    -- keep retrying for the real lane folders (built-in routes always exist, so
    -- the retry has to key off World.lanes, not World.paths)
    task.spawn(function()
        -- Ask the server for the road once, up front.  It answers whether or
        -- not TrafficLanes has streamed in, so the dodge has an edge limit from
        -- the first second instead of waiting on a folder that may never come.
        local n = 0
        pcall(function() n = World.FetchPoliceLanes() end)
        if n > 0 then
            REF.syncLaneUI(true)
            notify("Road map received", string.format(
                "%d lanes from the server · %.1f stud spacing", n, World.laneWidth), "good", 6)
            -- Turn them into drivable paths too.  This yields, so it runs
            -- after the readouts above rather than holding them up.
            --
            -- In a loop, because the first attempt is made at spawn where
            -- almost nothing has streamed in and it will simply decline.  It
            -- succeeds once the player has been near the road, which is also
            -- exactly when the roads become worth having.
            -- OFF FOR 3.12.0.  The builder and everything it feeds are
            -- finished and fixed, but this feature is hours old and has
            -- already produced two visible faults on a release day: a 180 at
            -- every re-acquire (paths running the other way down the same
            -- tarmac) and a vertical jolt (points the raycast never grounded).
            -- Both are fixed above; neither has been driven.  It stays dark
            -- until there is time to test it properly.
            -- To re-enable: delete the `false and` below.
            task.spawn(function()
                while false and ALIVE and not World.roads do
                    local r = 0
                    pcall(function() r = World.BuildRoads() end)
                    if r > 0 then
                        REF.syncLaneUI(true)
                        notify("Roads ready", r .. " server roads added to Which road"
                            .. " to drive. They work without the map folder.", "good", 7)
                        return
                    end
                    task.wait(20)
                end
            end)
        end
        while ALIVE do
            if #World.lanes == 0 then
                pcall(World.BuildLanes)
                if #World.lanes > 0 then
                    REF.syncLaneUI(true)
                    notify("Lane map found", string.format("%d lanes · %d drivable paths",
                        #World.lanes, #World.paths), "good", 6)
                end
            end
            REF.syncLaneUI(false)
            task.wait(3)
        end
    end)

    -- Lives on Earn, not Drive.  Drive is "make the car go"; Earn is "make the
    -- car make money".  Re-parenting is one token and no config key mentions
    -- the tab, so every "Auto police chase/..." key survives untouched.
    local secC = UI.Section(TABS.earn.page, "Police chase farm", 1, "Auto police chase")
    -- Readouts live apart from settings.  UI.Info never registers a control, so
    -- moving all thirteen of them costs no migration and no key.
    local secCS = UI.Section(TABS.earn.page, "Chase stats", 2)
    REF.chaseToggle = UI.Toggle(secC, {
        Text = "Farm police chases", Key = "Auto police chase", Order = 1,
        Tags = "police chase cop farm money earn pursuit", NoSave = true,
        Desc = "Parks, takes the wanted level, flies the route, repeats",
        Default = false,
        Callback = function(v)
            local ok, err = Chase.Set(v)
            if v and not ok then
                notify("Chase failed", tostring(err), "bad", 8)
                if REF.chaseToggle then REF.chaseToggle:Set(false, true) end
            elseif v then
                notify("Auto chase started", "Sit back - it drives itself between prompts.", "good")
            end
        end,
    })
    UI.Toggle(secC, {
        Text = "Accept the offer automatically", Key = "Answer the offer directly",
        Order = 12, Tags = "offer accept direct remote prompt button",
        Desc = "Answers the difficulty prompt itself instead of hunting for a button",
        Default = Chase.direct,
        Callback = function(v)
            -- Just the flag.  This used to call Chase.WatchNet(v), which
            -- disconnects EVERY listener - including PoliceBusted, the feed
            -- that every result readout depends on.  Both firing sites already
            -- test Chase.direct, so nothing needs to be unhooked.
            Chase.direct = v
        end,
    })
    UI.Slider(secC, {
        Text = "Wanted level", Key = "Stars", Order = 2,
        Tags = "stars wanted level difficulty heat",
        Min = 1, Max = 5, Default = Chase.stars, Step = 1,
        Callback = function(v) Chase.stars = v end,
    })
    REF.chaseDirect = UI.Info(secCS, "Offers / picks", "-", 13)
    REF.chaseOutcome = UI.Info(secCS, "Last run", "-", 5)
    REF.chaseNet = UI.Info(secCS, "Session net", "-", 4)
    REF.chaseRecord = UI.Info(secCS, "Evaded / busted", "-", 6)
    REF.chaseBal = UI.Info(secCS, "Balance / level", "-", 7)
    REF.chaseBest = UI.Info(secCS, "Best run / target", "-", 8)
    REF.chaseRate = UI.Info(secCS, "Last run rate", "-", 9)
    REF.chaseHour = UI.Info(secCS, "Projected / hour", "-", 10)
    REF.chaseAcc = UI.Info(secCS, "Accrual", "-", 11)
    REF.chaseEta = UI.Info(secCS, "Time to cap", "-", 12)
    UI.Slider(secC, {
        Text = "Drop height on the pad", Key = "Spawn lift", Order = 11,
        Tags = "spawn lift drop height pad teleport",
        Min = -20, Max = 40, Default = Chase.lift, Step = 1, Suffix = " st",
        Callback = function(v) Chase.lift = v end,
    })
    REF.chaseState = UI.Info(secCS, "State", "idle", 1)
    REF.chaseLaps = UI.Info(secCS, "Chases completed", "0", 2)
    UI.Toggle(secC, {
        Text = "Freeze me on the pad", Key = "Hold on pad", Order = 10,
        Tags = "hold pad freeze roll zone stay",
        Desc = "Freezes the car where it lands so it cannot roll out of the zone",
        Default = Chase.hold,
        Callback = function(v) Chase.hold = v end,
    })
    REF.chaseSpeed = UI.Slider(secC, {
        Text = "Speed during the chase", Key = "Chase speed", Order = 6,
        Tags = "chase speed mph fast",
        Min = 10, Max = 1000, Default = Chase.speed, Step = 5, Suffix = " MPH",
        Callback = function(v)
            Chase.speed = v
            if A.Chasing and A.Running and not Chase.smart then A.StaticMph = v end
        end,
    })
    local function smartVis()
        local on = Chase.smart
        if REF.chaseSpeed then UI.setVis(REF.chaseSpeed.Frame, UI.HIDE_COND, on) end
        if REF.farmSpeed then UI.setVis(REF.farmSpeed.Frame, UI.HIDE_COND, not on) end
        if REF.cashTarget then UI.setVis(REF.cashTarget.Frame, UI.HIDE_COND, not on) end
    end
    UI.Toggle(secC, {
        Text = "Cruise then sprint", Key = "Smart farmer", Order = 3,
        Tags = "smart farmer cruise sprint cash target",
        Desc = "Cruise until the run has banked its maximum, then go flat out",
        Default = Chase.smart,
        Callback = function(v)
            Chase.smart = v
            smartVis()
            if v and A.Chasing and A.Running then Chase.SmartSpeed() end
        end,
    })
    REF.farmSpeed = UI.Slider(secC, {
        Text = "Cruise speed", Key = "Farm speed", Order = 4,
        Tags = "farm cruise speed mph slow",
        Min = 10, Max = 1000, Default = Chase.farmMph, Step = 5, Suffix = " MPH",
        Callback = function(v) Chase.farmMph = v end,
    })
    REF.cashTarget = UI.Slider(secC, {
        Text = "Stop at this much cash", Key = "Cash target", Order = 5,
        Tags = "cash target money stop cap limit",
        Min = 5000, Max = 200000, Default = Chase.cashTarget, Step = 1000,
        Format = function(v) return "$" .. fmtNum(v) end,
        Callback = function(v) Chase.cashTarget = v end,
    })
    smartVis()
    REF.chasePad = UI.Info(secCS, "Start pad", "-", 14)
    REF.chaseClicks = UI.Info(secCS, "Clicks fired", "-", 15)
    REF.chaseCash = UI.Info(secCS, "Chase cash", "-", 3)
    -- Explicit orders: nextOrder() hands these 1 and 2, which the farm toggle
    -- and the wanted-level slider already own. 0 puts the precondition above
    -- everything, 90 puts the explanation at the bottom.
    UI.Note(secC, "Sit in your car first.", THEME.Warn, 0)
    UI.Note(secC, "Teleports to the pad, flies the route, then puts your Method and Hover back.", THEME.Accent2, 90)
end

--============================================================================
-- TAB 4 : WORLD
--============================================================================
do
    local function clearBlock(page, job, title, order, heliNote)
        local sec = UI.Section(page, title, order)

        local toggle = UI.Toggle(sec, {
            Text = "Clear " .. string.lower(job.name), NoSave = true,
            Desc = "Sweeps every " .. string.lower(job.name) .. " unit, including ones that spawn later",
            Default = false,
            Callback = function(v)
                if v then
                    WorldCtl.Start(job)
                    notify("Clearing " .. string.lower(job.name),
                        job.mode .. (job.delay > 0 and (" · " .. string.format("%.1fs", job.delay) .. " delay") or " · instant"),
                        "good")
                else
                    local restored = WorldCtl.Stop(job)
                    if restored > 0 then
                        notify("Released " .. string.lower(job.name), restored .. " parts un-anchored", "good")
                    end
                end
            end,
        })

        UI.Slider(sec, {
            Text = "Delay", Min = 0, Max = 10, Default = 0, Step = 0.5, Decimals = 1,
            Format = function(v) return v <= 0 and "instant" or string.format("%.1fs", v) end,
            Callback = function(v) job.delay = v end,
        })

        UI.Dropdown(sec, {
            Text = "Type", Options = { "Delete", "Anchor" }, Default = job.mode,
            Callback = function(v) WorldCtl.SetMode(job, v) end,
        })

        if heliNote then
            UI.Note(sec, "Helicopters cannot be anchored. Anchor leaves them alone, Delete removes them.")
        end
        UI.Note(sec, "Delete is client side - units return if the server respawns them. Anchor reverts on toggle off.", THEME.Dim)

        local status = UI.Info(sec, "Folders", WorldCtl.FolderStatus(job))
        local count = UI.Info(sec, "Cleared this session", "0")
        return { toggle = toggle, status = status, count = count }
    end

    REF.police  = clearBlock(TABS.world.page, jobPolice, "Police", 1, true)
    REF.traffic = clearBlock(TABS.world.page, jobTraffic, "Traffic", 2, false)

    local secH = UI.Section(TABS.world.page, "Drive through traffic", 4, "Collision")
    REF.hitboxToggle = UI.Toggle(secH, {
        Text = "Pass through traffic", Key = "No traffic collision",
        Tags = "collision pass through ghost noclip crash", NoSave = true,
        Desc = "Drive through traffic - mode below decides how; your own boxes are untouched",
        Default = false,
        Callback = function(v)
            local restored = Collide.SetNoTraffic(v)
            if v then
                notify("Traffic collision off", Collide.mode, "good")
            elseif restored and restored > 0 then
                notify("Traffic collision on", restored .. " hitboxes restored", "good")
            end
        end,
    })
    REF.scoreToggle = UI.Toggle(secH, {
        Text = "Grow my score hitbox (BANNABLE)", Key = "Score hitbox (Will be kicked)",
        Tags = "kick ban banned detect risky score box grow bigger", NoSave = true,
        Desc = "Detected by the game - AdminTools will not turn this on",
        Default = false,
        Callback = function(v)
            if not v then
                local restored = Collide.SetScoreBox(false)
                if restored and restored > 0 then
                    notify("Score hitbox restored", restored .. " boxes back to original size", "good")
                end
                return
            end
            -- REFUSE.  Collide.SetScoreBox and everything under it is untouched;
            -- we simply never call it with true.  Kept for future findings.
            if Config.applying then
                if REF.scoreToggle then REF.scoreToggle:Set(false, true) end
                return
            end
            -- silent is load-bearing: a non-silent Set re-enters this callback
            -- and recurses.  The delay lets the knob finish its tween first, so
            -- it reads as "refused" rather than "nothing happened".
            task.delay(0.18, function()
                if REF.scoreToggle then REF.scoreToggle:Set(false, true) end
            end)
            UI.Modal({
                Kind = "bad", Confirm = "I UNDERSTAND",
                Title = "This one gets you kicked",
                Body  = "Growing the score hitbox is detected by the game and will "
                     .. "get you kicked from the server, so AdminTools will not turn "
                     .. "it on. The code is still here for future findings - it just "
                     .. "cannot be enabled.",
            })
        end,
    })
    UI.Dropdown(secH, {
        Text = "Traffic mode",
        Options = { "Pass through (keep size)", "Pass through + enlarge", "Shrink to 1" },
        Default = Collide.mode,
        Callback = function(v)
            -- switching modes has to hand back whatever the old one held, or the
            -- next sweep records an already-modified value as the original
            local was = Collide.noTraffic
            if was then Collide.SetNoTraffic(false) end
            Collide.mode = v
            if was then Collide.SetNoTraffic(true) end
        end,
    })
    UI.Slider(secH, {
        Text = "Enlarge by", Min = 1, Max = 8, Default = 1, Step = 0.1, Decimals = 1,
        Format = function(v) return string.format("%.1fx", v) end,
        Callback = function(v) Collide.grow = v end,
    })
    UI.Note(secH, "Shrink stops you colliding but leaves the box too small to reach your score box. Pass through keeps the size and still collects.", THEME.Accent2)
    UI.Note(secH, "Leave at 1x unless you have tested it - a bigger box may also be a bigger crash zone.", THEME.Warn)
    UI.Dropdown(secH, {
        Text = "Score box size", Options = SCORE_ORDER, Default = Collide.scoreMode,
        Callback = function(v)
            Collide.scoreMode = v
            -- the sweep re-applies within 250ms, no need to toggle off and on
            if Collide.scoreBox then notify("Score box", "Now " .. v, "good", 4) end
        end,
    })
    REF.hitboxCount = UI.Info(secH, "Traffic collision", "0")
    REF.scoreCount = UI.Info(secH, "Score boxes", "0")
    UI.Button(secH, "PRINT CAR PART NAMES", function()
        local car = S.Car.Model
        if not car then
            notify("No vehicle", "Nothing to list.", "warn")
            return
        end
        local n = 0
        print("---- AdminTools: BaseParts in " .. car.Name .. " ----")
        for _, d in ipairs(car:GetDescendants()) do
            if d:IsA("BasePart") then
                n = n + 1
                print(string.format("  %-28s %s", d.Name, tostring(d.Size)))
            end
        end
        print("---- " .. n .. " parts ----")
        notify("Printed to console", n .. " parts listed in the executor console", "good")
    end, 20)
    UI.Note(secH, "All client side. Every original size is restored when its toggle goes off.")

    local secT = UI.Section(TABS.world.page, "Clone traffic beside me", 5, "Traffic train")
    REF.trainToggle = UI.Toggle(secT, {
        Text = "Make copies beside me", Key = "Traffic train",
        Tags = "clone train copies points xp money pay earn", NoSave = true,
        Desc = "Lines every traffic car up beside you and sweeps them past, over and over",
        Default = false,
        Callback = function(v)
            -- Train.Set runs FIRST and unchanged, so a UI problem can never cost
            -- someone the feature they just asked for.
            Train.Set(v)
            if not v or Config.applying then return end
            if not Train.notified then
                -- modal once per session, toast after.  Gating the same person
                -- ten times for a feature they are deliberately using is how you
                -- teach them that this tool's dialogs are noise - which would
                -- undermine the score-hitbox one that actually matters.
                Train.notified = true
                UI.Modal({
                    Kind = "warn", Confirm = "GOT IT",
                    Title = "This no longer pays",
                    Body  = "The game was updated. Cloning traffic beside you no "
                         .. "longer gives Points, XP or Money. It still works, and it "
                         .. "is on - this is just so you know it will not earn you "
                         .. "anything.",
                })
            else
                notify("Traffic clones on", "Still no Points, XP or Money.", "warn")
            end
        end,
    })
    UI.Dropdown(secT, {
        Text = "Spawn side", Options = { "Right", "Left", "Both" }, Default = Train.sideMode,
        Callback = function(v) Train.sideMode = v end,
    })
    UI.Slider(secT, { Text = "Side offset", Min = 2, Max = 40, Default = Train.side, Step = 1, Suffix = " st",
        Callback = function(v) Train.side = v end })
    UI.Slider(secT, { Text = "Height offset", Min = -40, Max = 120, Default = Train.height, Step = 1, Suffix = " st",
        Callback = function(v) Train.height = v end })
    UI.Slider(secT, { Text = "Clone count", Min = 5, Max = 200, Default = Train.cloneCount, Step = 1,
        Callback = function(v) Train.cloneCount = v end })
    UI.Slider(secT, { Text = "Car gap", Min = 4, Max = 60, Default = Train.gap, Step = 1, Suffix = " st",
        Callback = function(v) Train.gap = v end })
    UI.Slider(secT, { Text = "Sweep travel", Min = 20, Max = 400, Default = Train.travel, Step = 10, Suffix = " st",
        Callback = function(v) Train.travel = v end })
    UI.Slider(secT, { Text = "Sweep speed", Min = 5, Max = 1000, Default = Train.speedMph, Step = 5, Suffix = " MPH",
        Callback = function(v) Train.speedMph = v end })
    REF.trainCount = UI.Info(secT, "Cars in train", "0")
    UI.Note(secT, "Offset and height have to land the cars inside your score box - turn on Score hitbox to see it.", THEME.Warn)

    local sec = UI.Section(TABS.world.page, "Put the world back", 6, "Sweep")
    UI.Button(sec, "RELEASE EVERYTHING", function()
        local n = WorldCtl.Stop(jobPolice) + WorldCtl.Stop(jobTraffic)
        local h = (Collide.SetNoTraffic(false) or 0) + (Collide.SetScoreBox(false) or 0)
        Train.Set(false)
        Chase.Set(false)
        if REF.chaseToggle then REF.chaseToggle:Set(false, true) end
        if REF.police then REF.police.toggle:Set(false, true) end
        if REF.traffic then REF.traffic.toggle:Set(false, true) end
        if REF.hitboxToggle then REF.hitboxToggle:Set(false, true) end
        if REF.scoreToggle then REF.scoreToggle:Set(false, true) end
        if REF.trainToggle then REF.trainToggle:Set(false, true) end
        pcall(function() Fun.AllOff() end)       -- sky, gravity, camera, heads
        notify("Everything off", string.format(
            "%d parts un-anchored · %d hitboxes restored · sweeps, clones and visual "
            .. "effects all stopped", n, h), "good", 7)
    end)
    UI.Note(sec, "Deleted or anchored traffic still reads as a clear gap, so Smart speed opens right up.", THEME.Accent2)
end

--============================================================================
-- TAB 6 : SETTINGS
--============================================================================
do
    local secD = UI.Section(TABS.set.page, "Community", 2)
    UI.Button(secD, "COPY DISCORD INVITE", function() copyInvite() end)
    UI.Note(secD, CONFIG.Discord, THEME.Accent2)

    local secI = UI.Section(TABS.set.page, "Interface", 0)   -- the menu key lives here
    REF.menuKey = UI.Keybind(secI, {
        Text = "Menu toggle key", Default = S.Keys.Menu,
        Callback = function(kc) S.Keys.Menu = kc end,
    })

    local sec = UI.Section(TABS.set.page, "Stop Roblox kicking me", 11, "Session")
    REF.afkToggle = UI.Toggle(sec, {
        Text = "Block the idle kick", Key = "Anti-AFK",
        Tags = "afk idle kick kicked away keepalive stay online", Desc = "Nudges the idle timer so the 20 minute kick never lands",
        Default = false,
        Callback = function(v)
            local ok, err = AntiAfk.Set(v)
            if v and not ok then
                notify("Anti-AFK failed", tostring(err), "bad", 8)
                if REF.afkToggle then REF.afkToggle:Set(false, true) end
            elseif v then
                notify("Anti-AFK on", "Idle kicks will be answered automatically.", "good")
            end
        end,
    })
    UI.Dropdown(sec, {
        Text = "Idle method", Options = { "Block idle signal", "VirtualUser click" },
        Default = AntiAfk.mode,
        Callback = function(v)
            AntiAfk.mode = v
            if AntiAfk.enabled then            -- restart under the new method
                AntiAfk.Set(false)
                local ok, err = AntiAfk.Set(true)
                if not ok then
                    notify("Anti-AFK failed", tostring(err), "bad", 8)
                    if REF.afkToggle then REF.afkToggle:Set(false, true) end
                end
            end
        end,
    })
    REF.afkInfo = UI.Info(sec, "Idle listeners cut", "0")
    UI.Note(sec, "Block idle signal cuts Player.Idled outright and is the safe one. VirtualUser click is the older fallback.", THEME.Accent2)

    local sec2 = UI.Section(TABS.set.page, "Config", 1)
    local function cfgNames()
        local list = Config.List()
        if #list == 0 then list = { "(none saved)" } end
        return list
    end

    REF.cfgName = UI.Input(sec2, {
        Text = "Config name", Default = "default", Placeholder = "default", NoSave = true,
    })
    REF.cfgList = UI.Dropdown(sec2, {
        Text = "Saved configs", Options = cfgNames(), NoSave = true,
        Callback = function(v)
            if v and v ~= "(none saved)" and REF.cfgName then REF.cfgName:Set(v) end
        end,
    })
    local function refreshList()
        if REF.cfgList then REF.cfgList:SetOptions(cfgNames()) end
    end

    UI.Button(sec2, "SAVE CONFIG", function()
        local name = REF.cfgName.Value
        local ok, err = Config.Save(name)
        if ok then
            Config.last = "saved " .. name
            refreshList()
            notify("Config saved", name .. ".json  ·  " .. #Config.List() .. " on disk", "good")
        else
            notify("Save failed", tostring(err), "bad", 8)
        end
    end)
    UI.Button(sec2, "LOAD CONFIG", function()
        local name = REF.cfgName.Value
        local ok, applied, unknown, moved = Config.Load(name)
        if ok then
            Config.last = "loaded " .. name
            -- unknown is now a real signal rather than noise: reserved keys and
            -- dev-only controls are filtered out, so anything left means a key
            -- in the file genuinely matches nothing in the menu
            notify("Config loaded", string.format("%d settings applied%s%s", applied,
                (moved or 0) > 0 and (" · " .. moved .. " updated to the new layout") or "",
                (unknown or 0) > 0 and (" · " .. unknown .. " keys matched nothing") or ""),
                (unknown or 0) > 0 and "warn" or "good", 7)
        else
            notify("Load failed", tostring(applied), "bad", 8)
        end
    end)
    UI.Button(sec2, "DELETE CONFIG", function()
        local name = REF.cfgName.Value
        local ok, err = Config.Delete(name)
        refreshList()
        notify(ok and "Config deleted" or "Delete failed", ok and name or tostring(err),
            ok and "good" or "bad")
    end)
    UI.Button(sec2, "REFRESH LIST", function()
        refreshList()
        notify("Config list", #Config.List() .. " configs found", "good")
    end)

    UI.Button(sec2, "UNLOAD ADMINTOOLS", function()
        if Unload then Unload() end
    end, 20)
    REF.cfgInfo = UI.Info(sec2, "Tracked controls", "0")
    REF.cfgLast = UI.Info(sec2, "Last action", "-")
    UI.Note(sec2, "Saves the whole menu to AdminTools_cfg_<name>.json. A config named 'autoload' applies on the next run.")
end

--============================================================================
-- TAB 8 : NETWORK
--============================================================================
do
    local sec = UI.Section(TABS.car.page, "Follow another player", 7, "Mimic player")
    UI.Note(sec, "Follows the line they drove a few seconds ago, not where they are right now.", THEME.Accent2, 0)

    local function playerNames()
        local list = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then list[#list + 1] = plr.Name end
        end
        table.sort(list)
        if #list == 0 then list = { "(nobody else here)" } end
        return list
    end

    REF.mimicTarget = UI.Dropdown(sec, {
        Text = "Target", Options = playerNames(), Default = playerNames()[1], Order = 1,
        Callback = function(v)
            Mimic.targetName = (v ~= "(nobody else here)") and v or ""
            Mimic.trail = {}
        end,
    })
    UI.Button(sec, "REFRESH PLAYER LIST", function()
        REF.mimicTarget:SetOptions(playerNames())
        notify("Players", #Players:GetPlayers() - 1 .. " others in the server", "good", 4)
    end, 2)

    REF.mimicToggle = UI.Toggle(sec, {
        Text = "Follow them", Key = "Mimic movement",
        Tags = "mimic follow copy trail player", Desc = "Drive their route on a delay", Default = false, Order = 3,
        Callback = function(v)
            local ok, err = Mimic.Set(v)
            if v and not ok then
                notify("Mimic failed", tostring(err), "bad", 7)
                if REF.mimicToggle then REF.mimicToggle:Set(false, true) end
            end
        end,
    })
    UI.Slider(sec, {
        Text = "Delay", Min = 0.2, Max = 10, Default = Mimic.delay, Step = 0.1, Decimals = 1,
        Format = function(v) return string.format("%.1fs", v) end, Order = 4,
        Callback = function(v) Mimic.delay = v end,
    })
    UI.Slider(sec, {
        Text = "Keep away", Min = 5, Max = 200, Default = Mimic.radius, Step = 1, Suffix = " st",
        Order = 5, Callback = function(v) Mimic.radius = v end,
    })
    UI.Slider(sec, {
        Text = "Height offset", Min = -20, Max = 100, Default = Mimic.hover, Step = 1, Suffix = " st",
        Order = 6, Callback = function(v) Mimic.hover = v end,
    })
    UI.Toggle(sec, {
        Text = "Face the same way", Key = "Match rotation",
        Tags = "rotation face heading match", Default = Mimic.rotate, Order = 7,
        Callback = function(v) Mimic.rotate = v end,
    })

    REF.mimicState = UI.Info(sec, "State", "idle")
    REF.mimicState.Frame.LayoutOrder = 8
    REF.mimicTrail = UI.Info(sec, "Trail", "0 samples")
    REF.mimicTrail.Frame.LayoutOrder = 9
    UI.Note(sec, "Distance is held against where they are now, not where they were.")
end

--============================================================================
-- TAB 9 : APPEARANCE
--============================================================================
-- Every control on this page is an ordinary UI.* control, so the existing
-- Config.Save / Config.Load / autoload machinery persists the whole look with
-- no changes to Config at all.  Colours are exposed as 6-char hex STRINGS
-- because Config.Collect silently drops a raw Color3.
--
-- REGISTER BUDGET - read before adding a local anywhere in this block.
-- Luau caps a function at 200 simultaneously-live local registers, and a
-- do...end block does NOT get its own register file: its locals stack on top of
-- the enclosing chunk's until the block closes.  The merged main chunk is
-- already carrying ~162 locals when this block opens, so every local declared
-- at THIS block's own level is held for the whole ~900-line build.  The rules
-- that keep it safe:
--   * helpers and state live on the two tables AP and CH, never as loose locals
--   * each of the seven sections is wrapped in its own nested do...end, so only
--     one section's locals are live at a time
--   * only genuinely cross-section values (page, ENGINE, MOTION, E, AP, CH,
--     resets, track, C) sit at block level - nine of them.
do
    -- Reuse the tab if the window-chrome region already registered it, otherwise
    -- create it here.  Order 90 sorts last on either the legacy 1..8 tab scale or
    -- the chrome region's 10..90 scale, so this block is order-independent.
    TABS.look = TABS.look or addTab("Theme", "08", 90)
    local page = TABS.look.page

    -- Nine 31px tabs plus eight 5px gaps need 319px; the legacy holder is 310.
    -- The chrome region replaces it with a ScrollingFrame, so only grow it when
    -- that has not happened.  The sidebar footer starts at y=332, so 322 clears.
    if tabHolder and not tabHolder:IsA("ScrollingFrame") and tabHolder.Size.Y.Offset < 322 then
        local sz = tabHolder.Size
        tabHolder.Size = UDim2.new(sz.X.Scale, sz.X.Offset, sz.Y.Scale, 322)
    end

    -- ------------------------------------------------------------ engine shims
    -- This page is the only one that is useless without the TH/FX engine, so it
    -- degrades to a drawable-but-inert tab instead of throwing during the menu
    -- build (which would take the entire window down with it).
    local ENGINE = (type(TH) == "table") and (type(TH.bind) == "function")
    local MOTION = (type(FX) == "table") and (type(FX.tw) == "function")
    local E      = MOTION and FX.E or nil

    -- AP is this tab's toolbox: twelve helpers plus the two pieces of state they
    -- own.  Twelve loose locals would cost twelve registers held for the whole
    -- block (see REGISTER BUDGET above); one table costs one.
    local AP = {
        -- animation entries lifted out of FX.anim by AP.park, keyed by slot
        parked  = {},
        -- the preset chips every colour picker on this page offers
        presets = { "9660FF", "00D6FF", "FF5CC8", "34E28A", "FFB030", "FF486C", "FFFFFF", "6CC4FF" },
    }

    function AP.K(name, fallback) return THEME[name] or THEME[fallback] end

    -- radius through TH so the "Corner style" dropdown rescales these too
    function AP.rc(inst, token, px)
        if ENGINE and TH.corner then return TH.corner(inst, token) end
        return corner(inst, px)
    end
    -- The engine-less fallback forwards rep/rev/delayT too: `tw` grew those three
    -- parameters in the theme region, and dropping them there would lose every
    -- stagger AND let a delayed tween start on top of the tween it was meant to
    -- follow - which is exactly what the two-tween hex-reject shake below needs.
    function AP.ftw(inst, t, props, ease, rep, rev, delayT)
        if MOTION then return FX.tw(inst, t, props, ease, rep, rev, delayT) end
        return tw(inst, t, props, nil, nil, rep, rev, delayT)
    end
    function AP.stagger(i, step, cap)
        if MOTION and FX.delay then return FX.delay(i, step, cap) end
        return 0
    end

    function AP.hexOf(c)
        if ENGINE and TH.hex then return TH.hex(c) end
        return string.format("%02X%02X%02X",
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    function AP.unhex(s)
        if ENGINE and TH.unhex then return TH.unhex(s) end
        if type(s) ~= "string" then return nil end
        local h = s:gsub("%s", ""):gsub("^#", "")
        if #h ~= 6 or h:match("%X") then return nil end
        local n = tonumber(h, 16)
        if not n then return nil end
        return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    end

    -- Accept a single Instance or an array of them so the chrome author can
    -- publish whichever is convenient.
    function AP.setVis(ref, v)
        if not ref then return end
        if typeof(ref) == "Instance" then
            ref.Visible = v
        elseif type(ref) == "table" then
            for _, inst in ipairs(ref) do
                if typeof(inst) == "Instance" then inst.Visible = v end
            end
        end
    end

    -- FX.anim is one flat array walked by the single shared driver.  "Parking"
    -- lifts chosen entries out of it, so switching an idle animation off costs
    -- the hot loop nothing at all rather than adding a per-entry test.
    --
    -- The instance filter is NOT optional decoration: three different instances
    -- share kind "glow" (the two ambient blooms AND the header badge halo) and
    -- two share kind "sweep" (the header rail AND the loader shine), so parking
    -- by kind alone would switch off chrome this toggle does not own.
    function AP.inSet(only, inst)
        if only == nil then return true end                 -- no filter requested
        if typeof(only) == "Instance" then return only == inst end
        if type(only) == "table" then
            for i = 1, #only do if only[i] == inst then return true end end
        end
        return false
    end
    -- A caller that HAS a handle list must pass it; a caller whose handles are
    -- missing must not call park at all, or the nil filter would lift every
    -- entry of that kind out of the driver.
    function AP.park(slot, off, kind, only)
        if not MOTION or type(FX.anim) ~= "table" then return end
        if off then
            local keep, moved = {}, AP.parked[slot] or {}
            for i = 1, #FX.anim do
                local a = FX.anim[i]
                if a and (kind == nil or a.kind == kind) and AP.inSet(only, a.inst) then
                    moved[#moved + 1] = a
                else
                    keep[#keep + 1] = a
                end
            end
            AP.parked[slot] = moved
            FX.anim = keep
        else
            local back = AP.parked[slot]
            if back then
                for i = 1, #back do FX.anim[#FX.anim + 1] = back[i] end
                AP.parked[slot] = nil
            end
        end
    end
    function AP.parkedEach(slot, fn)
        local p = AP.parked[slot]
        if not p then return end
        for i = 1, #p do
            if p[i].inst then pcall(fn, p[i].inst) end
        end
    end

    function AP.themeSet(key, col)
        if ENGINE and TH.set then TH.set(key, col) end
    end
    function AP.espSet(cat, col)
        if ENGINE and TH.esp then TH.esp(cat, col) return end
        -- engine-less fallback: still write ESPCOL IN PLACE (Lane is indexed
        -- cyclically by #ESPCOL.Lane, so it must never be reassigned or emptied)
        local li = cat:match("^Lane(%d)$")
        if li then ESPCOL.Lane[tonumber(li)] = col else ESPCOL[cat] = col end
    end

    -- ---------------------------------------------------------- chrome handles
    -- These are the handles the window-chrome region publishes for exactly this
    -- tab (Window.hero / Window.rail / Window.wash / Window.brackets /
    -- Window.spark).  They are captured ONCE here into one table rather than six
    -- locals (same register reason as AP), and every consumer below is
    -- nil-guarded, so if the chrome region is not present the matching toggle
    -- simply has nothing to hide instead of erroring.
    local CH = {
        hero  = Window.hero     or REF.hSpeedBox,
        rail  = Window.rail     or REF.headRail,
        wash  = Window.wash     or REF.ambient,
        brack = Window.brackets or REF.brackets,
        spark = Window.spark    or REF.fpsSpark,
        railg = REF.headLineGrad,           -- the sweep gradient riding on rail
    }

    --========================================================== COLOUR PICKER ==
    -- Built entirely from Frames.  A Roblox instance can own only ONE UIGradient,
    -- which is why the saturation/value square is three stacked layers (hue fill,
    -- white->clear across, clear->black down) instead of one clever gradient.

    -- ONE shared drag state for every picker on the page.  UI.Slider already opens
    -- two global UserInputService connections PER INSTANCE (54 of them at 27
    -- sliders); eight pickers doing the same would add sixteen more.  These two
    -- cover any number of pickers.
    if not UI.pickConns then
        UI.pickConns = true
        bind(UserInputService.InputChanged, function(i)
            if UI.pick and (i.UserInputType == Enum.UserInputType.MouseMovement
                         or i.UserInputType == Enum.UserInputType.Touch) then
                UI.pick.api._drag(i.Position, UI.pick.kind)
            end
        end)
        bind(UserInputService.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                if UI.pick then
                    local p = UI.pick
                    UI.pick = nil
                    p.api._commit()
                end
            end
        end)
    end

    function UI.Color(parent, o)
        -- holder is the layout participant and api.Frame; registerControl is still
        -- handed the SECTION, so the ATSection lookup that config saving depends
        -- on is untouched.
        local holder = new("Frame", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, ClipsDescendants = true,
            LayoutOrder = o.Order or nextOrder(parent), Parent = parent,
        })
        local api = { Frame = holder, Value = "FFFFFF" }

        -- baseRow returns row, stroke, rail, scale.  Under the legacy one-return
        -- baseRow the last three come back nil, which every use below guards.
        local row, rowStroke, rowRail, scale = baseRow(holder, 36, 1, UI.tone and UI.tone.Color)
        -- The baseRow type rail is retired on this row: the live colour rail below
        -- takes its place.  Hiding it is not enough - it is also dropped from the
        -- row's hover record, or the shared hover treatment would light it again.
        if rowRail then rowRail.BackgroundTransparency = 1 end
        if UI.rowfx and UI.rowfx[row] then UI.rowfx[row].rail = nil end
        if not scale then scale = new("UIScale", { Scale = 1, Parent = row }) end
        local title = rowTitle(row, o.Text, nil, 150)

        -- this row always owns its own type rail rather than reusing baseRow's: a
        -- baseRow rail may be TH-bound to a palette key, and the next repaint would
        -- stomp the live colour written here every time the accent moved
        -- left at the default ZIndex on purpose: under ZIndexBehavior.Sibling a
        -- raised Frame would sit over the row's TextButton and eat clicks
        local colRail = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(0, 2, 1, -10), BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0, Parent = row,
        })
        AP.rc(colRail, "tick", 2)

        local hexLbl = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -58, 0.5, 0),
            Size = UDim2.fromOffset(68, 14), BackgroundTransparency = 1,
            Font = Enum.Font.RobotoMono, Text = "#------", TextSize = 10, TextColor3 = THEME.Dim,
            TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
        })
        local swatch = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(36, 22), BackgroundColor3 = AP.K("Track", "Track"),
            BorderSizePixel = 0, Parent = row,
        })
        AP.rc(swatch, "well", 6)
        stroke(swatch, AP.K("StrokeSoft", "Stroke"), 1, 0.5)
        local fill = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0, Parent = swatch,
        })
        AP.rc(fill, "chip", 4)

        local chev = nil
        if MOTION and FX.chev then
            chev = FX.chev(row, "Sub")
            chev.Position = UDim2.new(1, -132, 0.5, 0)   -- clear of the hex + swatch
        end
        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = row,
        })
        if MOTION and FX.press then FX.press(btn, scale) end

        -- ---------------------------------------------------------------- panel
        local panel = new("Frame", {
            Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = AP.K("Carbon", "Panel"), BackgroundTransparency = 0.40,
            BorderSizePixel = 0, ClipsDescendants = true, Parent = holder,
        })
        AP.rc(panel, "card", 10)
        stroke(panel, AP.K("StrokeSoft", "Stroke"), 1, 0.55)
        pad(panel, 12, 12, 12, 12)

        local sv = new("Frame", {                                -- layer 1: pure hue
            Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(176, 104),
            BackgroundColor3 = Color3.fromHSV(0, 1, 1), BorderSizePixel = 0, Parent = panel,
        })
        AP.rc(sv, "well", 6)
        local satL = new("Frame", {                              -- layer 2: saturation
            Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0, ZIndex = 2, Parent = sv,
        }, {
            new("UIGradient", {
                Rotation = 0,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
                }),
            }),
        })
        local valL = new("Frame", {                              -- layer 3: value
            Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0, ZIndex = 3, Parent = sv,
        }, {
            new("UIGradient", {
                Rotation = 90,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0),
                }),
            }),
        })
        AP.rc(satL, "well", 6)
        AP.rc(valL, "well", 6)

        -- two nested frames because one instance carries one UIStroke, and the
        -- cursor needs a white ring readable on white AND a dark ring on black
        local svCur = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10),
            BackgroundTransparency = 1, ZIndex = 5, Parent = sv,
        })
        corner(svCur, 5, true)                                   -- keep: never rescaled
        stroke(svCur, Color3.new(1, 1, 1), 2, 0)
        local svCurIn = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.fromOffset(7, 7), BackgroundTransparency = 1, ZIndex = 5, Parent = svCur,
        })
        corner(svCurIn, 4, true)
        stroke(svCurIn, AP.K("Void", "Bg"), 1, 0.2)
        local svBtn = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 6, Parent = sv,
        })

        local hueBar = new("Frame", {
            Position = UDim2.fromOffset(186, 0), Size = UDim2.fromOffset(18, 104),
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = panel,
        })
        AP.rc(hueBar, "well", 6)
        do
            local ks = {}
            for i = 0, 6 do ks[i + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)) end
            new("UIGradient", { Color = ColorSequence.new(ks), Rotation = 90, Parent = hueBar })
        end
        local hueKnob = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0),
            Size = UDim2.fromOffset(22, 5), BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0, ZIndex = 4, Parent = hueBar,
        })
        corner(hueKnob, 2, true)
        stroke(hueKnob, AP.K("Void", "Bg"), 1, 0.25)
        local hueBtn = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = hueBar,
        })

        local box = new("TextBox", {
            Position = UDim2.fromOffset(220, 0), Size = UDim2.fromOffset(96, 22),
            BackgroundColor3 = AP.K("Track", "Track"), BorderSizePixel = 0,
            Font = Enum.Font.RobotoMono, Text = "FFFFFF", TextSize = 11, TextColor3 = THEME.Text,
            PlaceholderText = "RRGGBB", PlaceholderColor3 = THEME.Dim,
            ClearTextOnFocus = false, Parent = panel,
        })
        AP.rc(box, "well", 6)
        stroke(box, AP.K("StrokeSoft", "Stroke"), 1, 0.45)

        local rgbTxt = new("TextLabel", {
            Position = UDim2.fromOffset(220, 28), Size = UDim2.fromOffset(200, 14),
            BackgroundTransparency = 1, Font = Enum.Font.RobotoMono, Text = "R 000  G 000  B 000",
            TextSize = 10, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel,
        })
        local chipsHolder = new("Frame", {
            Position = UDim2.fromOffset(220, 50), Size = UDim2.fromOffset(98, 46),
            BackgroundTransparency = 1, Parent = panel,
        }, {
            new("UIGridLayout", {
                CellSize = UDim2.fromOffset(20, 20), CellPadding = UDim2.fromOffset(6, 6),
                FillDirection = Enum.FillDirection.Horizontal,
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
        })
        new("TextLabel", {
            Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 12),
            BackgroundTransparency = 1, Font = Enum.Font.RobotoMono,
            Text = "DRAG THE FIELD  ·  TYPE A HEX  ·  PICK A PRESET", TextSize = 9,
            TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel,
        })

        -- ------------------------------------------------------------ live state
        local h, sat, val = 0, 0, 1
        local live, boxFocused = 0, false
        local chipStrokes, chipSel = {}, nil

        local function currentColor() return Color3.fromHSV(h, sat, val) end

        local function paint(fireCb)
            local c = currentColor()
            sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)   -- only the hue layer moves
            svCur.Position = UDim2.new(sat, 0, 1 - val, 0)
            hueKnob.Position = UDim2.new(0.5, 0, h, 0)
            fill.BackgroundColor3 = c
            colRail.BackgroundColor3 = c
            local hx = AP.hexOf(c)
            api.Value = hx
            hexLbl.Text = "#" .. hx
            if not boxFocused then box.Text = hx end
            rgbTxt.Text = string.format("R %03d  G %03d  B %03d",
                math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
            -- only rewrite the preset chips when the SELECTED one changes: paint()
            -- runs every drag frame and 8 stroke rewrites a frame is pure waste
            local sel = nil
            for i = 1, #chipStrokes do
                if chipStrokes[i].hex == hx then sel = i break end
            end
            if sel ~= chipSel then
                if chipSel then
                    local s0 = chipStrokes[chipSel].s
                    s0.Thickness, s0.Transparency = 1, 0.35
                    s0.Color = AP.K("StrokeSoft", "Stroke")
                end
                if sel then
                    local s1 = chipStrokes[sel].s
                    s1.Thickness, s1.Transparency = 2, 0
                    s1.Color = THEME.Text
                end
                chipSel = sel
            end
            if fireCb and o.Callback then pcall(o.Callback, c) end
        end

        function api._drag(pos, kind)
            if kind == "sv" then
                sat = math.clamp((pos.X - sv.AbsolutePosition.X) / math.max(1, sv.AbsoluteSize.X), 0, 1)
                val = 1 - math.clamp((pos.Y - sv.AbsolutePosition.Y) / math.max(1, sv.AbsoluteSize.Y), 0, 1)
            else
                h = math.clamp((pos.Y - hueBar.AbsolutePosition.Y) / math.max(1, hueBar.AbsoluteSize.Y), 0, 1)
            end
            -- TH.setAccent repaints ~70 registry records plus gradients; firing it
            -- 60x/sec while dragging is the one place this design can stutter
            local now, fire = tick(), false
            if o.Live and (now - live) >= 0.05 then
                live, fire = now, true
            end
            paint(fire)
        end
        function api._commit() paint(true) end

        function api:Set(v, silent)
            local c = (typeof(v) == "Color3") and v or AP.unhex(v)
            if not c then return end
            local hh, ss, vv = Color3.toHSV(c)
            -- toHSV collapses hue to 0 for greys; keeping the old hue stops the
            -- rail knob jumping to red the moment someone picks the white preset
            if ss > 0.001 then h = hh end
            sat, val = ss, vv
            paint(not silent)
        end
        function api:Get() return currentColor() end

        for i, hx in ipairs(AP.presets) do
            local pc = AP.unhex(hx) or Color3.new(1, 1, 1)
            local cf = new("Frame", {
                BackgroundColor3 = pc, BorderSizePixel = 0, LayoutOrder = i, Parent = chipsHolder,
            })
            AP.rc(cf, "chip", 4)
            chipStrokes[i] = { s = stroke(cf, AP.K("StrokeSoft", "Stroke"), 1, 0.35), hex = hx }
            local cb = new("TextButton", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = cf,
            })
            bind(cb.MouseButton1Click, function() api:Set(pc) end)
        end

        -- ------------------------------------------------------------- expansion
        local staged = { sv, hueBar, box, rgbTxt, chipsHolder }
        local homes = {}
        for i, inst in ipairs(staged) do homes[i] = inst.Position end

        local open = false
        local function setOpen(v)
            if open == v then return end
            open = v
            AP.ftw(holder, 0.28, { Size = UDim2.new(1, 0, 0, v and 200 or 36) }, E and E.snap)
            AP.ftw(panel, 0.28, { Size = UDim2.new(1, 0, 0, v and 156 or 0) }, E and E.snap)
            if chev then AP.ftw(chev, 0.24, { Rotation = v and 180 or 0 }, E and E.snap) end
            if v then
                for i, inst in ipairs(staged) do
                    inst.Position = homes[i] + UDim2.fromOffset(0, 8)
                    AP.ftw(inst, 0.30, { Position = homes[i] }, E and E.drop, nil, nil, AP.stagger(i, 0.028, 8))
                end
            end
        end
        local function closeSelf() setOpen(false) end

        -- The SHARED hover treatment, exactly as Toggle / Slider / Dropdown /
        -- Input / Keybind use it, so this is not the one row in the menu that
        -- feels hand-made.  The type rail is the only part held back: on this row
        -- it carries the live colour, so it was dropped from the hover record at
        -- construction rather than being animated to the tone key.
        hoverFx(row, rowStroke, nil, title, UI.tone and UI.tone.Color)

        bind(btn.MouseButton1Click, function()
            if open then
                setOpen(false)
                if UI.openPanel == closeSelf then UI.openPanel = nil end
            else
                -- one expanded panel at a time, same idiom as UI.listening
                if type(UI.openPanel) == "function" then pcall(UI.openPanel) end
                UI.openPanel = closeSelf
                setOpen(true)
            end
        end)
        bind(svBtn.InputBegan, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                UI.pick = { api = api, kind = "sv" }
                api._drag(i.Position, "sv")
            end
        end)
        bind(hueBtn.InputBegan, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                UI.pick = { api = api, kind = "hue" }
                api._drag(i.Position, "hue")
            end
        end)
        bind(box.Focused, function() boxFocused = true end)
        bind(box.FocusLost, function()
            boxFocused = false
            local c = AP.unhex(box.Text)
            if c then
                api:Set(c)
            else
                box.Text = api.Value
                -- a shake says "rejected" without burning a notification slot.
                -- The return leg is DELAYED past the end of the outward leg
                -- (0.07 > 0.06) so the two never fight over Position; both the
                -- durations and the delay scale together under FX.rate, and
                -- AP.ftw now forwards the delay on the engine-less path too.
                local home = box.Position
                AP.ftw(box, 0.06, { Position = home + UDim2.fromOffset(3, 0) })
                AP.ftw(box, 0.06, { Position = home }, nil, nil, nil, 0.07)
            end
        end)

        api:Set(o.Default or Color3.new(1, 1, 1), true)
        registerControl(parent, o, api)
        return api
    end

    --=================================================================== CONTENT
    -- resets / track / C are the only values that genuinely cross section
    -- boundaries, so they are the only ones that stay out here.  Everything each
    -- section owns lives inside that section's own do...end.
    local resets = {}                       -- { api, defaultValue } for RESET APPEARANCE
    local function track(api, default)
        resets[#resets + 1] = { api, default }
        return api
    end
    local C = {}                            -- the colour-picker apis, by role

    -- ------------------------------------------------------------ 1 : THEME ---
    do
        local sec1 = UI.Section(page, "Theme", 1)
        local PRESET_THEMES = {
            Arc       = { Color3.fromRGB(150,  96, 255), Color3.fromRGB(  0, 214, 255), Color3.fromRGB(255,  92, 200) },
            Vaporwave = { Color3.fromRGB(255,  92, 200), Color3.fromRGB(124,  96, 255), Color3.fromRGB( 92, 240, 255) },
            Toxic     = { Color3.fromRGB(168, 255,  96), Color3.fromRGB(  0, 214, 255), Color3.fromRGB(255, 226,  92) },
            Ember     = { Color3.fromRGB(255, 124,  64), Color3.fromRGB(255, 196,  92), Color3.fromRGB(255,  72, 108) },
            Ice       = { Color3.fromRGB(108, 196, 255), Color3.fromRGB(168, 232, 255), Color3.fromRGB(150,  96, 255) },
            Mono      = { Color3.fromRGB(214, 220, 240), Color3.fromRGB(154, 163, 192), Color3.fromRGB(255, 255, 255) },
        }

        UI.Dropdown(sec1, {
            Text = "Preset", Options = { "Arc", "Vaporwave", "Toxic", "Ember", "Ice", "Mono" },
            Default = "Arc", Order = 1,
            -- NoSave: Config.Apply iterates with pairs(), so a restored preset and a
            -- restored explicit accent would fight over who wins
            NoSave = true,
            Callback = function(v)
                local p = PRESET_THEMES[v]
                if not p then return end
                if ENGINE and TH.setAccent then TH.setAccent(p[1], p[2], p[3]) end
                if C.a1 then C.a1:Set(p[1], true) end
                if C.a2 then C.a2:Set(p[2], true) end
                if C.a3 then C.a3:Set(p[3], true) end
            end,
        })
        REF.lookAccent = UI.Info(sec1, "Active accent", "#" .. AP.hexOf(THEME.Accent), 2)
        UI.Note(sec1, "Presets overwrite the three accent colours below. Everything on this tab is "
            .. "saved with your config.", THEME.Accent2, 3)
    end

    -- ----------------------------------------------------------- 2 : ACCENT ---
    do
        local sec2 = UI.Section(page, "Accent", 2)
        C.a1 = UI.Color(sec2, {
            Text = "Primary accent", Default = THEME.Accent, Order = 1, Live = true,
            Callback = function(c) AP.themeSet("Accent", c) end,
        })
        C.a2 = UI.Color(sec2, {
            Text = "Secondary accent", Default = THEME.Accent2, Order = 2,
            Callback = function(c) AP.themeSet("Accent2", c) end,
        })
        C.a3 = UI.Color(sec2, {
            Text = "Peak accent", Default = AP.K("Accent3", "Accent2"), Order = 3,
            Callback = function(c) AP.themeSet("Accent3", c) end,
        })

        do
            local prow = baseRow(sec2, 32, 4)
            rowTitle(prow, "Gradient", nil, 180)
            -- Indexed by hand: this is the one row in the file built straight
            -- from baseRow, so without this it is absent from UI.index and from
            -- UI.vis - and both aliveness passes read a missing mask as "this
            -- child is visible", which pinned the whole Accent section on
            -- screen against every filter.
            UI.indexRow(sec2, "Gradient", prow, "prose", "gradient ramp preview accent")
            local pwrap = new("Frame", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.fromOffset(150, 10), BackgroundTransparency = 1, Parent = prow,
            })
            -- the glow needs a fully transparent parent, or a ZIndex 0 child still
            -- paints in front of its own parent's background and becomes a wash
            if MOTION and FX.glow then FX.glow(pwrap, 26, 0.86, "AccentGlow") end
            local pbar = new("Frame", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0, Parent = pwrap,
            })
            AP.rc(pbar, "pill", 5)
            -- white fill on purpose: UIGradient MULTIPLIES BackgroundColor3, so white
            -- shows the three accent stops at full strength
            if ENGINE and TH.grad3 then
                TH.grad3(pbar, "Accent", "Accent3", "Accent2", 0)
            else
                grad(pbar, THEME.Accent, THEME.Accent2, 0)
            end
        end

        track(UI.Slider(sec2, {
            Text = "Window opacity", Min = 70, Max = 100, Default = 94, Step = 1, Suffix = "%", Order = 5,
            -- the readability escape hatch: on a bright map slide this to 100
            Callback = function(v) winRoot.BackgroundTransparency = (100 - v) / 100 end,
        }), 94)
        track(UI.Slider(sec2, {
            Text = "Glow strength", Min = 0, Max = 150, Default = 100, Step = 5, Suffix = "%", Order = 6,
            Callback = function(v) if ENGINE then TH.opt.glowMul = v / 100 end end,
        }), 100)
        track(UI.Toggle(sec2, {
            Text = "Window rim light", Desc = "A band of accent travelling the window edge",
            Default = true, Order = 7,
            -- "rim" is the one kind with a single owner (Window.rimGrad), so no
            -- instance filter is needed here.
            Callback = function(v)
                AP.park("rim", not v, "rim")
                -- park the band at stop 0 so the edge still reads as Accent, not mid-sweep
                if not v then AP.parkedEach("rim", function(g) g.Rotation = 0 end) end
            end,
        }), true)
        UI.Button(sec2, "COPY HEX", function()
            local hx = "#" .. AP.hexOf(THEME.Accent)
            if typeof(setclipboard) == "function" then
                pcall(setclipboard, hx)
                notify("Copied", hx, "good", 3)
            else
                notify("No clipboard", "This executor has no setclipboard: " .. hx, "warn", 5)
            end
        end, 8)
    end

    -- -------------------------------------------------------------- 3 : RGB ---
    do
        local sec3 = UI.Section(page, "RGB", 3)
        track(UI.Toggle(sec3, {
            Text = "RGB mode", Desc = "Cycles both accents around the wheel forever",
            Default = false, Order = 1,
            Callback = function(v) if ENGINE then TH.opt.rgb = v end end,
        }), false)
        track(UI.Slider(sec3, {
            Text = "Cycle speed", Min = 2, Max = 100, Default = 12, Step = 1, Order = 2,
            Format = function(v) return string.format("%.0fs / loop", 100 / math.max(1, v)) end,
            Callback = function(v) if ENGINE then TH.opt.speed = v / 100 end end,
        }), 12)
        track(UI.Slider(sec3, {
            Text = "Hue spread", Min = 2, Max = 50, Default = 18, Step = 1, Suffix = "%", Order = 3,
            Callback = function(v) if ENGINE then TH.opt.spread = v / 100 end end,
        }), 18)
        track(UI.Slider(sec3, {
            Text = "Saturation", Min = 40, Max = 100, Default = 86, Step = 1, Suffix = "%", Order = 4,
            Callback = function(v) if ENGINE then TH.opt.sat = v / 100 end end,
        }), 86)
        track(UI.Slider(sec3, {
            Text = "Repaint rate", Min = 10, Max = 60, Default = 30, Step = 5, Suffix = " hz", Order = 5,
            Callback = function(v) if ENGINE then TH.tickRate = 1 / math.max(1, v) end end,
        }), 30)
        track(UI.Toggle(sec3, {
            Text = "Also cycle ESP colours", Desc = "Off by default: it costs you category at a glance",
            Default = false, Order = 6,
            Callback = function(v) if ENGINE then TH.opt.espRgb = v end end,
        }), false)
        UI.Note(sec3, "Repaints in slices, so the cost stays flat. Greys and state colours never cycle.", THEME.Warn, 7)
    end

    -- ---------------------------------------------------------- 4 : SURFACE ---
    do
        local sec4 = UI.Section(page, "Surface", 4)
        local CORNER_MUL = { Machined = 0.55, Default = 1.0, Round = 1.7 }
        UI.Dropdown(sec4, {
            Text = "Corner style", Options = { "Machined", "Default", "Round" }, Default = "Default", Order = 1,
            Callback = function(v)
                if ENGINE and TH.setRadius then TH.setRadius(CORNER_MUL[v] or 1) end
            end,
        })
        track(UI.Toggle(sec4, {
            Text = "Ambient wash", Desc = "Two soft accent pools behind the content area",
            Default = true, Order = 2,
            -- Window.wash is passed as the instance filter: the header badge halo
            -- shares kind "glow" and is NOT this toggle's to switch off.
            Callback = function(v)
                if v then
                    AP.setVis(CH.wash, true)
                    if CH.wash then AP.park("wash", false) end
                else
                    if CH.wash then AP.park("wash", true, "glow", CH.wash) end
                    AP.setVis(CH.wash, false)
                end
            end,
        }), true)
        track(UI.Toggle(sec4, {
            Text = "Corner brackets", Desc = "The four L-marks around the content area",
            Default = true, Order = 3,
            Callback = function(v) AP.setVis(CH.brack, v) end,
        }), true)
        -- Window.glow is a SIBLING of winRoot, so it is not hidden with the window.
        -- This toggle deliberately does NOT call Window.syncFx.  syncFx's last
        -- statement is `TH.uiOn, FX.on = v, v`, and UI.Toggle fires its default-true
        -- callback through task.defer - which lands during the LOADING SCREEN, while
        -- winRoot is still hidden.  Routing this through syncFx would therefore
        -- switch both engines off and freeze every animation on the loader until the
        -- window first opened.  Writing the flag and the one Visible this toggle owns
        -- is all it needs; the chrome region's winRoot Visible/Position/Size bindings
        -- stay the only callers of syncFx.
        Window.glowOn = true
        track(UI.Toggle(sec4, {
            Text = "Window glow", Default = true, Order = 4,
            Callback = function(v)
                Window.glowOn = v
                if Window.glow then Window.glow.Visible = v and winRoot.Visible end
            end,
        }), true)
        if type(Window.syncFx) ~= "function" then
            bind(winRoot:GetPropertyChangedSignal("Visible"), function()
                if Window.glow then Window.glow.Visible = Window.glowOn and winRoot.Visible end
            end)
        end
        track(UI.Slider(sec4, {
            Text = "Shadow depth", Min = 0, Max = 100, Default = 58, Step = 5, Suffix = "%", Order = 5,
            Callback = function(v)
                -- Window.shadowRest is published so the open animation can settle on
                -- the user's depth instead of the hardcoded 0.42
                Window.shadowRest = 1 - v / 100
                if Window.shadow and winRoot.Visible then
                    Window.shadow.ImageTransparency = Window.shadowRest
                end
            end,
        }), 58)
    end

    -- ----------------------------------------------------------- 5 : MOTION ---
    do
        local sec5 = UI.Section(page, "Motion", 5)
        track(UI.Slider(sec5, {
            Text = "Animation speed", Min = 50, Max = 150, Default = 100, Step = 5, Suffix = "%", Order = 1,
            Callback = function(v) if MOTION then FX.rate = v / 100 end end,
        }), 100)
        track(UI.Toggle(sec5, {
            Text = "Idle shimmer", Desc = "The rim, sweeps and LEDs; off stops the window re-rasterising",
            Default = true, Order = 2,
            Callback = function(v) if ENGINE then TH.opt.shimmer = v end end,
        }), true)
        track(UI.Toggle(sec5, {
            Text = "Row stagger", Default = true, Order = 3,
            Callback = function(v) if MOTION then FX.stagger = v end end,
        }), true)
        track(UI.Toggle(sec5, {
            Text = "Value flash", Desc = "Readouts pulse the accent when a number changes",
            Default = true, Order = 4,
            Callback = function(v) if MOTION then FX.flashOn = v end end,
        }), true)
        track(UI.Toggle(sec5, {
            Text = "Toast countdown bar", Default = true, Order = 5,
            Callback = function(v) if MOTION then FX.toastBar = v end end,
        }), true)
        track(UI.Toggle(sec5, {
            Text = "Reduced motion", Desc = "Everything snaps instead of tweening",
            Default = false, Order = 6,
            Callback = function(v)
                if MOTION then
                    FX.motion = not v
                    if v and FX.stopLoops then pcall(FX.stopLoops) end
                end
            end,
        }), false)
    end

    -- ----------------------------------------------------- 6 : ESP COLOURS ---
    do
        local sec6 = UI.Section(page, "ESP Colours", 6)
        local ESP_DEF = {
            Car = ESPCOL.Car, Traffic = ESPCOL.Traffic, Player = ESPCOL.Player,
            Lane1 = ESPCOL.Lane[1], Lane2 = ESPCOL.Lane[2], Lane3 = ESPCOL.Lane[3], Lane4 = ESPCOL.Lane[4],
        }
        -- per-category RGB opt-in.  TH.espCycle is looked up on TH at call time, so
        -- replacing the field here is enough - TH.step is never touched.  The
        -- defaults below reproduce the shipped espCycle exactly (Car, Traffic and
        -- Player cycle; lanes do not), so nothing changes until the user asks.
        local espCyc = { Car = true, Traffic = true, Player = true, Lane = false }
        if ENGINE and TH.esp then
            TH.rate["ESP:Player"] = 0.25
            for i = 1, 4 do TH.rate["ESP:Lane" .. i] = 0.30 end
            function TH.espCycle(hu)
                local s = TH.opt.sat
                local vv = math.max(TH.opt.val, 0.72)       -- readability floor, do not remove
                if espCyc.Car     then TH.esp("Car",     Color3.fromHSV(hu, s, vv)) end
                if espCyc.Traffic then TH.esp("Traffic", Color3.fromHSV((hu + 0.12) % 1, s, vv)) end
                if espCyc.Player  then TH.esp("Player",  Color3.fromHSV((hu + 0.24) % 1, s, vv)) end
                if espCyc.Lane then
                    for i = 1, 4 do
                        TH.esp("Lane" .. i, Color3.fromHSV((hu + 0.36 + (i - 1) * 0.06) % 1, s, vv))
                    end
                end
            end
        end

        C.eCar = UI.Color(sec6, { Text = "Cars", Default = ESPCOL.Car, Order = 1,
            Callback = function(c) AP.espSet("Car", c) end })
        C.eTra = UI.Color(sec6, { Text = "Traffic", Default = ESPCOL.Traffic, Order = 2,
            Callback = function(c) AP.espSet("Traffic", c) end })
        C.ePlr = UI.Color(sec6, { Text = "Players", Default = ESPCOL.Player, Order = 3,
            Callback = function(c) AP.espSet("Player", c) end })
        C.eL1 = UI.Color(sec6, { Text = "Lane 1", Default = ESPCOL.Lane[1], Order = 4,
            Callback = function(c) AP.espSet("Lane1", c) end })
        C.eL2 = UI.Color(sec6, { Text = "Lane 2", Default = ESPCOL.Lane[2], Order = 5,
            Callback = function(c) AP.espSet("Lane2", c) end })
        C.eL3 = UI.Color(sec6, { Text = "Lane 3", Default = ESPCOL.Lane[3], Order = 6,
            Callback = function(c) AP.espSet("Lane3", c) end })
        C.eL4 = UI.Color(sec6, { Text = "Lane 4", Default = ESPCOL.Lane[4], Order = 7,
            Callback = function(c) AP.espSet("Lane4", c) end })

        track(UI.Toggle(sec6, { Text = "Cycle cars", Default = true, Order = 8,
            Callback = function(v) espCyc.Car = v end }), true)
        track(UI.Toggle(sec6, { Text = "Cycle traffic", Default = true, Order = 9,
            Callback = function(v) espCyc.Traffic = v end }), true)
        track(UI.Toggle(sec6, { Text = "Cycle players", Default = true, Order = 10,
            Callback = function(v) espCyc.Player = v end }), true)
        track(UI.Toggle(sec6, {
            Text = "Cycle waypoints", Desc = "Lane colours join the sweep too",
            Default = false, Order = 11,
            Callback = function(v) espCyc.Lane = v end,
        }), false)

        track(UI.Slider(sec6, {
            Text = "Glow pulse rate", Min = 10, Max = 80, Default = 30, Step = 1, Order = 12,
            Format = function(v) return string.format("%.1f", v / 10) end,
            Callback = function(v) if ENGINE then TH.opt.glowRate = v / 10 end end,
        }), 30)
        track(UI.Slider(sec6, {
            Text = "Glow depth", Min = 0, Max = 40, Default = 16, Step = 1, Order = 13,
            Format = function(v) return string.format("%.2f", v / 100) end,
            Callback = function(v) if ENGINE then TH.opt.glowDepth = v / 100 end end,
        }), 16)
        track(UI.Slider(sec6, {
            Text = "Wireframe thickness", Min = 2, Max = 12, Default = 4, Step = 1, Order = 14,
            Format = function(v) return string.format("%.3f", v / 100) end,
            Callback = function(v) if ENGINE then TH.opt.wireThick = v / 100 end end,
        }), 4)

        -- seeded here because a slider/dropdown's build-time apply is silent, so the
        -- callbacks below never run until the user touches them
        if ENGINE then
            TH.opt.boxStyle = TH.opt.boxStyle or "Frame"
            TH.opt.originPt = TH.opt.originPt or "Bottom"
        end
        -- Box style and Tracer origin used to be duplicated here.  They are on
        -- the Markers tab, which is where the rest of the marker shape lives;
        -- two dropdowns writing one setting meant a config load restored
        -- whichever pairs() reached last.
        UI.Button(sec6, "RESET ESP COLOURS", function()
            C.eCar:Set(ESP_DEF.Car)
            C.eTra:Set(ESP_DEF.Traffic)
            C.ePlr:Set(ESP_DEF.Player)
            C.eL1:Set(ESP_DEF.Lane1)
            C.eL2:Set(ESP_DEF.Lane2)
            C.eL3:Set(ESP_DEF.Lane3)
            C.eL4:Set(ESP_DEF.Lane4)
            notify("ESP colours", "Back to the shipped palette.", "good", 3)
        end, 17)
        UI.Note(sec6, "Colours are captured at scan time, so a change lands within 0.3 seconds.", nil, 18)
    end

    -- --------------------------------------------------------- 7 : IDENTITY ---
    do
        -- the remaining coloured visuals: these were following fixed palette keys
        -- with no control of their own
        do
            local sec6b = UI.Section(page, "More Colours", 8)
            C.eWire = UI.Color(sec6b, { Text = "Wireframe", Default = THEME.Wire, Order = 1,
                Callback = function(c)
                    THEME.Wire = c
                    if ENGINE and TH.set then TH.set("Wire", c) end
                end })
            C.ePath = UI.Color(sec6b, { Text = "Path preview", Default = THEME.Accent2, Order = 2,
                Callback = function(c)
                    THEME.PathLine = c
                    if ENGINE and TH.set then TH.set("PathLine", c) end
                end })
            C.ePulse = UI.Color(sec6b, { Text = "Player pulse", Default = Pulse.colour, Order = 3,
                Callback = function(c) Pulse.colour = c Pulse.rgb = false end })
            C.eSun = UI.Color(sec6b, { Text = "Sunlight", Default = Fun.sky.colour, Order = 25,
                Callback = function(c)
                    Fun.sky.colour = c
                    Fun.sky.rgb = false          -- a manual pick wins over the cycle
                    Fun.SkyApply()
                end })
            UI.Toggle(sec6b, {
                Text = "Pulse RGB", Desc = "Cycles the footfall rings through the spectrum",
                Default = false, Order = 4,
                Callback = function(v) Pulse.rgb = v end,
            })
            UI.Toggle(sec6b, {
                Text = "Wireframe follows accent", Default = false, Order = 5,
                Callback = function(v)
                    if not (ENGINE and TH.set) then return end
                    -- rejoining the accent family is what makes RGB mode drive it
                    TH.accentKey = TH.accentKey or {}
                    TH.accentKey.Wire = v or nil
                    if v then TH.set("Wire", THEME.Accent2) end
                end,
            })
            UI.Note(sec6b, "ESP categories have their own RGB opt-in above. These follow the theme "
                .. "unless you pin them here.")
        end

        local sec7 = UI.Section(page, "Identity", 9)
        track(UI.Toggle(sec7, {
            Text = "Header speed readout", Desc = "The big MPH tachometer in the title bar",
            Default = true, Order = 1,
            Callback = function(v) AP.setVis(CH.hero, v) end,
        }), true)
        track(UI.Toggle(sec7, {
            Text = "Telemetry rail", Desc = "The animated hairline under the header",
            Default = true, Order = 2,
            -- filtered to the header's own sweep gradient: the loader shine shares
            -- kind "sweep" and must not be dragged in and out of the driver here.
            Callback = function(v)
                if CH.railg then AP.park("rail", not v, "sweep", CH.railg) end
                AP.setVis(CH.rail, v)
            end,
        }), true)
        track(UI.Toggle(sec7, {
            Text = "FPS sparkline", Default = true, Order = 3,
            Callback = function(v) AP.setVis(CH.spark, v) end,
        }), true)

        local function boundCount()
            if not ENGINE or type(TH.b) ~= "table" then return 0, 0 end
            local n = 0
            for _, a in pairs(TH.b) do n = n + math.floor(#a / 3) end
            return n, #(TH.ag or {})
        end
        REF.lookBound = UI.Info(sec7, "Bound instances", "-", 4)

        UI.Button(sec7, "RESET APPEARANCE", function()
            if ENGINE and TH.reset then TH.reset() end
            for _, item in ipairs(resets) do
                pcall(function() item[1]:Set(item[2]) end)
            end
            if C.a1 then C.a1:Set(THEME.Accent, true) end
            if C.a2 then C.a2:Set(THEME.Accent2, true) end
            if C.a3 then C.a3:Set(AP.K("Accent3", "Accent2"), true) end
            notify("Appearance", "Theme, motion and surface options restored.", "good", 4)
        end, 5)

        -- One refresh path for both live readouts.  TH.hook fires on an explicit
        -- colour change only - the RGB sweep uses TH.write + slicePaint and never
        -- calls hooks, so this is not a per-frame cost.
        local function refreshReadouts()
            if REF.lookAccent then
                -- AccentGlow, not Accent: the raw accent measures ~3.4:1 on a row and
                -- the palette rule is that Accent never carries text
                REF.lookAccent:Set("#" .. AP.hexOf(THEME.Accent), AP.K("AccentGlow", "Accent2"))
            end
            if REF.lookBound then
                local n, g = boundCount()
                REF.lookBound:Set(string.format("%d props  ·  %d grad", n, g))
            end
        end
        refreshReadouts()
        if ENGINE and TH.hook then TH.hook(refreshReadouts) end
    end
end

--============================================================================
-- TAB 10 : FUN
--============================================================================
do
    local page = TABS.fun.page

    -- ------------------------------------------------------------------ sun
    do
        local sec = UI.Section(page, "Sun", 1)
        UI.Note(sec, "Lighting is per-client. Nobody else sees it, and every value is restored.", THEME.Accent2, 0)
        UI.Toggle(sec, {
            Text = "Sun changer", Desc = "Takes over the sky until you turn it off",
            Default = false, Order = 1,
            Callback = function(v) Fun.SkySet(v) end,
        })
        UI.Slider(sec, {
            Text = "Time of day", Min = 0, Max = 24, Default = 14, Step = 0.25, Decimals = 2,
            Format = function(v)
                local h = math.floor(v)
                return string.format("%02d:%02d", h, math.floor((v - h) * 60))
            end,
            Order = 2,
            Callback = function(v) Fun.sky.clock = v Fun.SkyApply() end,
        })
        UI.Slider(sec, {
            Text = "Brightness", Min = 0, Max = 10, Default = 2, Step = 0.1, Decimals = 1,
            Order = 3, Callback = function(v) Fun.sky.bright = v Fun.SkyApply() end,
        })
        UI.Toggle(sec, {
            Text = "Tint the fog too", Default = false, Order = 4,
            Callback = function(v) Fun.sky.fog = v Fun.SkyApply() end,
        })
        UI.Toggle(sec, {
            Text = "Sun RGB", Desc = "Cycles the sunlight through the spectrum",
            Default = false, Order = 5,
            Callback = function(v) Fun.sky.rgb = v end,
        })
        UI.Slider(sec, {
            Text = "RGB speed", Min = 0.01, Max = 0.5, Default = 0.06, Step = 0.01, Decimals = 2,
            Order = 6, Callback = function(v) Fun.sky.speed = v end,
        })
        UI.Note(sec, "Sun colour has its own picker in Appearance under More Colours.")
    end

    -- -------------------------------------------------------------- traffic
    do
        local sec = UI.Section(page, "Traffic pranks", 2, "Traffic pranks")
        UI.Toggle(sec, {
            Text = "Traffic bayblade", Desc = "Spins every traffic car while it carries on driving",
            Default = false, Order = 1,
            Callback = function(v) Fun.spin.on = v end,
        })
        UI.Slider(sec, {
            Text = "Spin speed", Min = 1, Max = 40, Default = 7, Step = 1, Suffix = " rad/s",
            Order = 2, Callback = function(v) Fun.spin.speed = v end,
        })
        UI.Toggle(sec, {
            Text = "Traffic disco", Desc = "Every car a different colour, all of them cycling",
            Default = false, Order = 3,
            Callback = function(v)
                Fun.disco.on = v
                if not v then Fun.DiscoClear() end
            end,
        })
        UI.Slider(sec, {
            Text = "Disco speed", Min = 0.1, Max = 3, Default = 0.5, Step = 0.1, Decimals = 1,
            Order = 4, Callback = function(v) Fun.disco.speed = v end,
        })
        REF.spinCount = UI.Info(sec, "Spinning", "-")
        REF.spinCount.Frame.LayoutOrder = 45
        UI.Toggle(sec, {
            Text = "Traffic balloons", Desc = "The whole street quietly floats away",
            Default = false, Order = 5,
            Callback = function(v) Fun.balloon.on = v end,
        })
        UI.Slider(sec, {
            Text = "Float speed", Min = 1, Max = 60, Default = 6, Step = 1, Suffix = " st/s",
            Order = 6, Callback = function(v) Fun.balloon.rate = v end,
        })
        UI.Note(sec, "Bayblade only spins them. Balloons move them for real, so the game may re-place them.", THEME.Warn)
    end

    -- --------------------------------------------------------------- people
    do
        local sec = UI.Section(page, "People", 3)
        UI.Toggle(sec, {
            Text = "Big head mode", Desc = "Everyone, including you",
            Default = false, Order = 1,
            Callback = function(v)
                Fun.head.on = v
                if not v then Fun.HeadRestore() end
            end,
        })
        UI.Slider(sec, {
            Text = "Head scale", Min = 0.2, Max = 10, Default = 3, Step = 0.1, Decimals = 1,
            Format = function(v) return string.format("%.1fx", v) end,
            Order = 2,
            Callback = function(v)
                -- restore first: the saved size is the ORIGINAL, so rescaling
                -- from the current size would compound every time you drag
                if Fun.head.on then Fun.HeadRestore() end
                Fun.head.scale = v
            end,
        })
        UI.Note(sec, "Tiny heads work too - drag it below 1.")
    end

    -- --------------------------------------------------------------- physics
    do
        local sec = UI.Section(page, "Physics", 4)
        UI.Toggle(sec, {
            Text = "Moon gravity", Desc = "Client-side gravity, so only your car floats",
            Default = false, Order = 1,
            Callback = function(v) Fun.GravSet(v) end,
        })
        UI.Slider(sec, {
            Text = "Gravity", Min = 0, Max = 400, Default = 40, Step = 5,
            Format = function(v) return string.format("%d (earth 196)", v) end,
            Order = 2,
            Callback = function(v)
                Fun.grav.value = v
                if Fun.grav.on then pcall(function() Workspace.Gravity = v end) end
            end,
        })
        UI.Note(sec, "Low gravity plus a boost is the single funniest thing in here.", THEME.Accent2)
    end

    -- ---------------------------------------------------------------- camera
    do
        local sec = UI.Section(page, "Camera", 5)
        UI.Toggle(sec, {
            Text = "Drunk camera", Desc = "The view rolls and pitches on its own",
            Default = false, Order = 1,
            Callback = function(v) Fun.cam.on = v Fun.CamSync() end,
        })
        UI.Slider(sec, {
            Text = "Sway", Min = 0.1, Max = 5, Default = 1, Step = 0.1, Decimals = 1,
            Format = function(v) return string.format("%.1fx", v) end,
            Order = 2, Callback = function(v) Fun.cam.sway = v end,
        })
        UI.Toggle(sec, {
            Text = "Custom FOV", Desc = "Fisheye at one end, telescope at the other",
            Default = false, Order = 3,
            Callback = function(v) Fun.cam.fovOn = v Fun.CamSync() end,
        })
        UI.Slider(sec, {
            Text = "Field of view", Min = 20, Max = 120, Default = 70, Step = 1, Suffix = " deg",
            Order = 4, Callback = function(v) Fun.cam.fov = v end,
        })
        UI.Toggle(sec, {
            Text = "Rainbow car trail", Desc = "Leaves a ring behind you as you drive",
            Default = false, Order = 5,
            Callback = function(v) Fun.trail.on = v end,
        })
        UI.Note(sec, "Reuses the Player pulse rings, so it puts parts in the workspace too.")
    end

    -- ------------------------------------------------------------------ off
    do
        local sec = UI.Section(page, "Turn all this off", 6, "Panic")
        UI.Button(sec, "TURN EVERYTHING OFF", function()
            Fun.AllOff()
            -- and the world side, so this button means what it says wherever
            -- the user happens to find it
            pcall(function()
                WorldCtl.Stop(jobPolice); WorldCtl.Stop(jobTraffic)
                Collide.SetNoTraffic(false); Collide.SetScoreBox(false)
                Train.Set(false); Chase.Set(false)
            end)
            notify("Everything off", "Sky, gravity, camera, traffic, clones and "
                .. "sweeps all restored.", "good", 7)
        end)
        UI.Note(sec, "Puts everything back: sky, gravity, camera, heads, traffic, clones and sweeps. Toggles above may still read as on.")
    end
end

--============================================================================
-- SIMPLE MODE
--============================================================================
-- A VIEW, NOT A PRESET.  It decides which rows are on screen and never writes a
-- control's value.  That is not taste: Config.Collect reads api.Value with no
-- idea what is visible and Config.Save is a blind writefile with no backup, so
-- a mode that flipped values would let [tune] -> [Simple] -> [SAVE] destroy a
-- tuned config with nothing to restore from.
--
-- It does not need to write anything either.  The automation defaults at the
-- top of this file ARE the tuned setup, so a fresh launch in Simple mode is
-- already the configuration that tested at 98%.
--
-- State lives on Window.* and S.Simple rather than in block locals: the main
-- chunk sits near Luau's 200-register ceiling and an open do...end block draws
-- from the same pool.
do
    -- Keys are the SAME strings a config saves under, "<section>/<control>", so
    -- one vocabulary serves both.  Controls key on o.Key where it is pinned;
    -- Infos, Notes and Buttons key on their visible text (UI.indexRow).
    --
    -- This MUST be walked against UI.index and never against CONTROLS.  The two
    -- most important rows in the whole mode - "Drive for me" and "Farm police
    -- chases" - are NoSave, so they never reach CONTROLS at all and a
    -- CONTROLS-driven walk would hide the on switch and the money switch.
    Window.simpleShow = {
        -- DRIVE ------------------------------------------------------------
        ["Engine/Run automation"]               = true,  -- the on switch
        ["Speed/Speed mode"]                    = true,  -- parent of both rows below
        ["Speed/Static speed"]                  = true,  -- the child live at launch
        ["Speed/Smart profile"]                 = true,  -- the other child; see below
        ["Speed/Range"]                         = true,  -- the only MPH on screen under Smart
        -- Saved keys, so a goal set months ago is still live.  Hidden, it
        -- stops the drive for no visible reason and cannot be cleared.
        ["Run goal/Goal"]                       = true,
        ["Run goal/Goal amount"]                = true,
        ["Live stats/State"]                    = true,
        ["Live stats/Speed / target"]           = true,
        ["Live stats/Earned"]                   = true,
        ["Live stats/Points / streak"]          = true,
        ["Live stats/Progress"]                 = true,
        ["World/Traffic lanes"]                 = true,
        ["World/REBUILD LANE MAP"]              = true,  -- the only fix for "No lane map"
        ["Automation ESP/Progression box"]      = true,  -- feedback once the menu is shut
        -- EARN -------------------------------------------------------------
        ["Auto police chase/Auto police chase"] = true,
        ["Auto police chase/Sit in your car first."] = true,  -- the one precondition
        ["Chase stats/State"]                   = true,
        ["Chase stats/Chases completed"]        = true,
        ["Chase stats/Session net"]             = true,
        ["Chase stats/Chase cash"]              = true,
        -- SETTINGS ---------------------------------------------------------
        ["Interface/Menu toggle key"]           = true,  -- lose this and the menu is gone
        ["Session/Anti-AFK"]                    = true,  -- the one default that is wrong here
        ["Session/Idle method"]                 = true,  -- the fix its failure toast names
        -- NOT a duplicate of Session/Anti-AFK.  That one stops the 20 minute
        -- idle KICK; this one is what keeps the game PAYING while automation
        -- drives.  Simple mode shows two rows that report earnings, so hiding
        -- the thing that keeps them moving was the worst of both.
        ["Anti-AFK/Anti-Auto play AFK"]         = true,
        ["Config/Config name"]                  = true,
        ["Config/Saved configs"]                = true,
        ["Config/SAVE CONFIG"]                  = true,
        ["Config/LOAD CONFIG"]                  = true,
        ["Config/UNLOAD ADMINTOOLS"]            = true,  -- the only way out of the script
        ["Community/COPY DISCORD INVITE"]       = true,
    }
    -- Why "Speed mode" survives a mode built to remove dials: it is the PARENT
    -- of Static speed and Smart profile, and feature logic already hides
    -- whichever of the two is not in play.  Hide a parent whose child is
    -- conditionally hidden and a config saved on "Smart" leaves NO speed
    -- control on screen at all - so both children are allow-listed with it.
    -- The same rule is why Method/Hover height, Smart dodge/Clearance, No
    -- braking/Brake distance, Goal/Goal amount and Smart farmer/its three
    -- children are each hidden as a unit, never half.
    Window.simpleTabs = { [TABS.auto] = true, [TABS.earn] = true, [TABS.set] = true }
    Window.simpleOnly, Window.simpleOnlyAt = {}, {}

    -- ------------------------------------------------- the Simple-only landing
    do
        local sec = UI.Section(TABS.auto.page, "Start here", 0, "Start here")
        Window.simpleOnly[1], Window.simpleOnlyAt[sec] = sec, true
        UI.Note(sec, "Everything is already set up. Turn on Drive for me below, "
            .. "or Farm police chases on the Earn tab. Turn SIMPLE MODE off in the "
            .. "sidebar to see every setting.", THEME.Accent2)
        UI.Button(sec, "RESCAN FOR MY CAR", function() Car.Rescan() end)
        UI.Button(sec, "USE THE RECOMMENDED SETUP", function()
            UI.Modal({
                Title = "Put driving back to the tested setup?",
                Body = "Normal drive style, 310 MPH, steer around traffic, never "
                    .. "slow down - and markers off. Anything you changed on those "
                    .. "rows is replaced.",
                -- The cancel button says what cancelling KEEPS.  "Cancel" next
                -- to "PUT IT BACK" asks the reader to work out which one is the
                -- safe answer, which is the opposite of this mode's job.
                Kind = "warn", Confirm = "PUT IT BACK", Cancel = "KEEP MY SETTINGS",
                OnConfirm = function()
                    local n, miss = Config.ApplyRecommended()
                    notify("Recommended setup",
                        n .. " settings put back to the tested values."
                        .. (#miss > 0 and ("  ·  " .. #miss .. " did not match") or ""),
                        #miss > 0 and "warn" or "good", 6)
                end,
            })
        end)
    end

    -- ----------------------------------------------------- the sidebar switch
    -- At the TOP of the tab strip, above the DRIVING caption (LayoutOrder -1
    -- against its 0).  Not in the header: the hero readout's -104 offset is
    -- sized for exactly two header buttons, and a third would sit on top of the
    -- speed figure.  A labelled pill in the nav is also what a first-time user
    -- actually finds, which is the entire point of the mode.
    do
        local row = new("TextButton", {
            Name = "SimpleToggle",
            Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 30),
            BackgroundColor3 = THEME.Row, BackgroundTransparency = 0.45,
            Text = "", AutoButtonColor = false, Parent = sidebar,
        })
        TH.corner(row, "row")
        local rs = stroke(row, THEME.StrokeSoft, 1, 0.55)
        local lbl = new("TextLabel", {
            Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -52, 1, 0),
            BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "SIMPLE MODE",
            TextSize = 9, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
        })
        local track = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(30, 16), BackgroundColor3 = THEME.Track,
            BorderSizePixel = 0, Parent = row,
        })
        TH.corner(track, "chip")
        local ts = stroke(track, THEME.StrokeSoft, 1, 0.45)
        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.fromOffset(11, 11), BackgroundColor3 = THEME.Rail,
            BorderSizePixel = 0, ZIndex = 2, Parent = track,
        })
        TH.corner(knob, "tick")
        stroke(knob, THEME.StrokeSoft, 1, 0.45)

        function Window.simplePaint(on)
            -- The label names the mode you are IN, not the one the switch would
            -- take you to.  "SIMPLE MODE" sitting next to an OFF knob reads as
            -- "simple mode is unavailable" to exactly the reader this is for.
            lbl.Text = on and "SIMPLE MODE" or "ADVANCED MODE"
            FX.tw(knob,  0.22, { Position = UDim2.new(0, on and 16 or 3, 0.5, 0),
                                 BackgroundColor3 = on and Color3.new(1, 1, 1) or THEME.Rail })
            FX.tw(track, 0.18, { BackgroundColor3 = on and THEME.AccentWash or THEME.Track })
            FX.tw(ts,    0.18, { Color = on and THEME.Accent or THEME.StrokeSoft,
                                 Transparency = on and 0.20 or 0.45 })
            FX.tw(row,   0.20, { BackgroundColor3 = on and THEME.AccentWash or THEME.Row,
                                 BackgroundTransparency = on and 0.10 or 0.45 })
            FX.tw(rs,    0.20, { Color = on and THEME.Accent or THEME.StrokeSoft,
                                 Transparency = on and 0.30 or 0.55 })
            FX.tw(lbl,   0.20, { TextColor3 = on and THEME.Text or THEME.Sub })
        end
        bind(row.MouseButton1Click, function()
            -- Toggle from what the pill is SHOWING, not from the saved
            -- preference.  A live query suspends Simple mode without touching
            -- the preference, so during a search the two disagree by design -
            -- and reading the preference made the first click paint nothing
            -- while quietly flipping the saved value the wrong way.
            local want = not Window.simpleApplied
            -- Clear the query so this click decides the view rather than
            -- fighting the filter for it.  The Text handler runs deferred, and
            -- by the time it does S.Simple already holds `want`, so its own
            -- restore agrees with this one.
            if Window.searchBox and Window.searchBox.Text ~= "" then
                Window.searchBox.Text = ""
            end
            Window.SetSimple(want)
            notify(want and "Simple mode on" or "Advanced mode on",
                want and "Just the rows you need. Nothing was turned off - "
                    .. "every setting is still running as you left it."
                or "Every tab and every setting is back.", "good", 5)
        end)
    end

    -- ------------------------------------------------------- the switch itself
    -- `keepPref` applies a view WITHOUT changing what the user chose.  Search
    -- needs it: while a query is live Simple mode steps aside entirely, and
    -- when the query clears the user's own preference has to come back exactly
    -- as they left it.  Nothing else should pass it.
    function Window.SetSimple(on, keepPref)
        on = on and true or false
        -- Idempotent AND cheap.  Config.Apply calls this on every LOAD CONFIG,
        -- and the pass below zeroes every page CanvasPosition - so without the
        -- guard, loading a config scrolls all eight tabs back to the top even
        -- when the view did not change.  simpleApplied starts nil, so the first
        -- call always runs.  It is also what keeps a keystroke cheap: only the
        -- first character of a query actually runs this pass.
        -- BEFORE the early return.  While a query is live the applied view and
        -- the saved preference disagree on purpose, so "the view is already
        -- what you asked for" says nothing about whether the preference has
        -- been recorded.  With the write after the guard, a config carrying
        -- @simple = false loaded during a search was applied to nothing and
        -- never stored, and clearing the search put the old value back.
        if not keepPref then S.Simple = on end
        if Window.simpleApplied == on then return end
        Window.simpleApplied = on

        -- An expanded dropdown would come back open behind a row that is now
        -- hidden, with UI.openPanel still pointing at its closer.
        if type(UI.openPanel) == "function" then pcall(UI.openPanel) end
        UI.openPanel = nil

        -- 1. rows, controls and prose alike.  UI.index is the only list that
        --    holds both.
        for _, e in ipairs(UI.index) do
            local keep = (e.sec == "Start here") or Window.simpleShow[e.key]
                or e.simple == true
            UI.setVis(e.frame, UI.HIDE_SIMPLE, on and not keep)
        end

        -- 2. sections with nothing left in them.  A section holder keeps its
        --    caption child (LayoutOrder -100) whatever happens to its rows, so
        --    an emptied section would otherwise sit there as a titled blank.
        --
        --    The test reads the HIDE_SIMPLE bit, never .Visible.  A row hidden
        --    by feature logic (HIDE_COND) must not make its section look dead,
        --    or Speed would vanish the instant its other child was hidden - and
        --    it would never come back, because nothing re-runs this pass when a
        --    COND bit changes.
        local seen = {}
        for _, e in ipairs(UI.index) do
            local h = e.secFrame
            if h and not seen[h] and not Window.simpleOnlyAt[h] then
                seen[h] = true
                local alive = false
                for _, ch in ipairs(h:GetChildren()) do
                    if ch:IsA("GuiObject") and ch.LayoutOrder ~= -100
                        and bit32.band(UI.vis[ch] or 0, UI.HIDE_SIMPLE) == 0 then
                        alive = true
                        break
                    end
                end
                UI.setVis(h, UI.HIDE_SIMPLE, on and not alive)
            end
        end

        -- 3. the mirror image: furniture that exists ONLY in Simple mode
        for _, f in ipairs(Window.simpleOnly) do
            UI.setVis(f, UI.HIDE_SIMPLE, not on)
        end

        -- 4. tabs.  Plates renumber so Simple reads 01/02/03 instead of
        --    01/02/07; the original string is held nowhere else, so cache it on
        --    first use rather than recomputing it from the tab order.
        local shown, order = 0, {}
        for i, t in ipairs(tabs) do order[i] = t end
        table.sort(order, function(a, b) return a.btn.LayoutOrder < b.btn.LayoutOrder end)
        for _, t in ipairs(order) do
            t.glyph0 = t.glyph0 or t.glyph.Text
            local keep = (not on) or (Window.simpleTabs[t] or false)
            UI.setVis(t.btn, UI.HIDE_SIMPLE, not keep)
            if on and keep then
                shown = shown + 1
                t.glyph.Text = string.format("%02d", shown)
            else
                t.glyph.Text = t.glyph0
            end
            -- Hiding rows shrinks the page's automatic canvas but never moves
            -- CanvasPosition, so a page left scrolled down comes back blank.
            if t.page and t.page:IsA("ScrollingFrame") then
                t.page.CanvasPosition = Vector2.new()
            end
        end

        -- 5. chrome.  A shortcut to a hidden tab is a dead button, and with
        --    three tabs on screen the group captions are labelling nothing.
        if Window.lookBtn then UI.setVis(Window.lookBtn, UI.HIDE_SIMPLE, on) end
        if Window.driveCap then UI.setVis(Window.driveCap, UI.HIDE_SIMPLE, on) end
        if Window.extrasCap then UI.setVis(Window.extrasCap, UI.HIDE_SIMPLE, on) end

        -- 6. move off a tab that just disappeared.  LAST, after the strip has
        --    been told its final shape: Select() ends by tweening the slab to
        --    where the row is NOW, and running that before the tabs were hidden
        --    baked the OLD layout into a 0.22s tween that then overwrote the
        --    correction below.  Nothing is lost by waiting - hiding a button
        --    does not change which tab is active, and select() only
        --    early-returns for the tab it is already on, which cannot be the
        --    one being hidden.
        if on and Window.activeTab and not Window.simpleTabs[Window.activeTab] then
            TABS.auto.Select()
        end
        if Window.simplePaint then Window.simplePaint(on) end

        -- AbsolutePosition has not caught up with the reflow yet.  Same 0.06s
        -- the window-shown handler uses, for the same reason - and slabTo now
        -- cancels any tween Select() may still be running.
        task.delay(0.06, function()
            if Window.activeTab then Window.slabTo(Window.activeTab, false) end
        end)
    end

    -- Eleven of the keys above point at an Info, Note or Button.  Those key on
    -- VISIBLE TEXT (UI.indexRow) with no o.Key escape hatch, so a copy-edit to a
    -- label silently drops that row out of Simple mode - including UNLOAD
    -- ADMINTOOLS, the only way out of the script.  Fail loud, once, at build.
    do
        local live, dead = {}, {}
        for _, e in ipairs(UI.index) do live[e.key] = true end
        for k in pairs(Window.simpleShow) do
            if not live[k] then dead[#dead + 1] = k end
        end
        if #dead > 0 then
            warn("[AdminTools] Simple mode allow-list: " .. #dead
                .. " key(s) match no row - " .. table.concat(dead, ", "))
        end
    end

    Window.SetSimple(S.Simple)
end


--============================================================================
-- SEARCH
--============================================================================
-- The bar lives in the CONTENT pane, reaching back over its own padding with a
-- negative offset.  Not the header: the hero readout's -104 is arithmetically
-- coupled to BOTH header buttons, and there is a 40px gap to work with.  Not
-- the sidebar either: that is the selection slab's geometry, which is a
-- sibling of the strip with hand-computed offsets, and has already produced
-- two regressions in this file.  Here, every page keeps Size (1,0,1,0) and
-- Position (0,0) and nothing about UI.Page changes.
do
    -- Synonyms expand the QUERY, not the index.  This is the whole answer to
    -- "let people search in their own words without authoring a tag on every
    -- row": a layman word names a CONCEPT, not a control.  "lag" has to reach
    -- every marker control at once, and no per-row field can do that because
    -- no single row owns the word.  o.Tags stays as the per-row escape hatch.
    UI.syn = {
        -- VISUALS.  "visuals" is the word people reach for, and not one control
        -- in the menu is called that.
        visual   = "esp marker box tracer highlight glow wireframe outline see through draws",
        visuals  = "esp marker box tracer highlight glow wireframe outline see through draws",
        esp      = "esp marker box tracer highlight glow see through wallhack outline",
        marker   = "esp marker box tracer highlight glow see through outline",
        markers  = "esp marker box tracer highlight glow see through outline",
        wallhack = "esp see through walls marker box highlight xray",
        xray     = "see through walls esp marker highlight",
        chams    = "highlight glow esp marker box",
        outline  = "box wireframe outline hitbox esp marker",
        overlay  = "esp marker progress panel box overlay hud",
        hud      = "progress panel overlay stats readout speed",
        show     = "esp marker show draw panel overlay progress",
        display  = "esp marker show draw panel overlay window",
        draw     = "esp marker box tracer highlight draws",
        tracer   = "line tracer esp marker",
        tracers  = "line tracer esp marker",
        hitbox   = "hitbox box score collision wireframe traffic",
        hitboxes = "hitbox box score collision wireframe traffic",

        -- PERFORMANCE
        lag      = "esp marker box tracer highlight glow render fps ambient motion",
        laggy    = "esp marker box tracer highlight glow render fps ambient motion",
        fps      = "fps render esp marker glow ambient motion sparkline",
        stutter  = "fps render esp marker glow ambient motion",
        smooth   = "motion fps render",
        performance = "fps render esp marker glow ambient motion",

        -- MONEY
        money    = "money cash earn points reward chase police farm goal balance",
        cash     = "money cash earn points reward chase police farm balance",
        earn     = "money cash earn points reward chase police farm",
        earning  = "money cash earn points reward chase police farm parked",
        earnings = "money cash earn points reward chase police farm",
        income   = "money cash earn points reward chase farm rate hour",
        profit   = "money cash earn net balance chase farm",
        rich     = "money cash earn chase farm balance",
        farm     = "farm chase police money cash earn points",
        farming  = "farm chase police money cash earn points",
        grind    = "farm chase police money cash earn points automation",
        xp       = "points score level reward earn",
        points   = "points score level reward earn streak",
        reward   = "money cash points reward earn",
        payout   = "money cash earn chase rate hour",

        -- POLICE
        police   = "police chase cop star wanted pursuit farm pad busted",
        cop      = "police chase cop star wanted pursuit farm pad",
        cops     = "police chase cop star wanted pursuit farm pad",
        chase    = "police chase cop star wanted pursuit farm pad",
        chases   = "police chase cop star wanted pursuit farm pad",
        wanted   = "wanted star level police chase heat",
        star     = "wanted star level police chase",
        stars    = "wanted star level police chase",
        heat     = "wanted star level police chase",
        pursuit  = "police chase cop wanted pursuit",
        busted   = "busted evaded police chase result outcome",
        evade    = "busted evaded police chase result escape",
        escape   = "busted evaded police chase result",
        jail     = "busted police chase penalty",

        -- DRIVING
        auto     = "auto automation autoplay drive driving farm engine run route",
        autopilot = "auto automation autoplay drive driving run route",
        autoplay = "auto automation autoplay drive driving run route",
        automation = "auto automation autoplay drive driving run route",
        bot      = "auto automation autoplay drive driving run",
        drive    = "drive driving auto automation route lane path run",
        driving  = "drive driving auto automation route lane path run",
        steer    = "steer dodge swerve traffic rotate path",
        cruise   = "cruise speed farm smart sprint",

        -- SPEED
        speed    = "speed mph fast slow static smart profile cruise",
        fast     = "fast speed mph static profile insane sprint",
        faster   = "fast speed mph static profile insane",
        quick    = "fast speed mph static profile",
        mph      = "speed mph static profile range",
        slow     = "slow speed mph brake braking static profile",
        slower   = "slow speed mph brake braking static profile",
        brake    = "brake braking slow distance stop traffic",
        braking  = "brake braking slow distance stop traffic",
        boost    = "boost speed key hold push",
        nitro    = "boost speed key hold push",

        -- FLIGHT
        fly      = "fly hover float height flight noclip",
        flying   = "fly hover float height flight",
        flight   = "fly hover float height flight",
        hover    = "hover float height fly flight",
        float    = "hover float height fly flight",
        air      = "hover float height fly flight",
        height   = "height hover float lift offset",
        altitude = "height hover float lift",
        noclip   = "fly hover collision through walls",

        -- CRASHES
        crash    = "crash dodge collision hitbox clearance brake swerve stuck",
        crashes  = "crash dodge collision hitbox clearance brake swerve stuck",
        crashing = "crash dodge collision hitbox clearance brake swerve stuck",
        dodge    = "dodge swerve steer traffic clearance room smart brake",
        avoid    = "dodge swerve steer traffic clearance room brake collision",
        swerve   = "dodge swerve room clearance traffic",
        collide  = "collision hitbox traffic through pass",
        collision = "collision hitbox traffic through pass",
        bump     = "collision hitbox traffic crash dodge",
        wall     = "wall walls through xray clearance room lane edge dodge",
        walls    = "wall walls through xray clearance room lane edge dodge",
        clearance = "clearance gap room dodge smart air",
        gap      = "gap clearance room dodge distance keep away",

        -- AFK
        afk      = "afk idle kick keepalive click stay online earning parked",
        idle     = "afk idle kick keepalive click stay online parked",
        kick     = "kick ban detect score hitbox afk idle",
        kicked   = "kick ban detect score hitbox afk idle",
        away     = "afk idle kick keepalive parked away stay",
        keepalive = "afk idle kick keepalive click stay online",
        disconnect = "afk idle kick keepalive stay online",
        timeout  = "afk idle kick keepalive stay online",
        parked   = "afk idle parked earning keepalive pad hold",

        -- SAFETY
        ban      = "ban kick detect score hitbox bannable",
        banned   = "ban kick detect score hitbox bannable",
        detect   = "detect detection ban kick hitbox exposed",
        safe     = "safe ban kick detect hitbox idle",
        risky    = "ban kick detect hitbox bannable",

        -- CONFIG
        config   = "save load config settings file autoload delete",
        configs  = "save load config settings file autoload delete",
        save     = "save load config settings file autoload",
        load     = "save load config settings file autoload",
        preset   = "preset config save load theme palette",
        presets  = "preset config save load theme palette",
        setting  = "config save load settings",
        settings = "config save load settings",
        backup   = "save config file",
        default  = "default reset config recommended",
        defaults = "default reset config recommended",
        reset    = "reset default restore recommended config",
        restore  = "reset default restore recommended config",

        -- LOOK
        theme    = "colour color theme accent palette rgb hue preset look style",
        colour   = "colour color theme accent palette rgb hue swatch",
        color    = "colour color theme accent palette rgb hue swatch",
        colours  = "colour color theme accent palette rgb hue swatch",
        colors   = "colour color theme accent palette rgb hue swatch",
        accent   = "accent colour color theme palette rgb",
        rgb      = "rgb colour color accent cycle hue",
        hue      = "rgb colour color accent cycle hue",
        palette  = "palette colour color theme accent preset",
        look     = "look theme colour accent style window menu",
        appearance = "look theme colour accent style window menu glow",
        skin     = "look theme colour accent palette preset",
        pretty   = "look theme colour accent glow motion",
        dark     = "theme colour palette preset",
        ui       = "window menu look theme interface scale",
        gui      = "window menu look theme interface scale",
        menu     = "window menu look theme interface key toggle scale",
        interface = "window menu look theme interface key toggle scale",
        window   = "window menu look theme scale glow shadow",
        transparency = "transparency glass window opacity",
        opacity  = "transparency glass window opacity",
        blur     = "glow shadow ambient wash window",
        size     = "scale window size height width",
        scale    = "scale window size",

        -- KEYS
        key      = "key keybind bind menu toggle shortcut boost",
        keys     = "key keybind bind menu toggle shortcut boost",
        keybind  = "key keybind bind menu toggle shortcut",
        bind     = "key keybind bind menu toggle shortcut",
        hotkey   = "key keybind bind menu toggle shortcut",
        shortcut = "key keybind bind menu toggle",
        hide     = "hide menu toggle key window close",

        -- MAP
        map      = "map lane road route waypoint path rebuild traffic",
        lane     = "lane road route path map waypoint line",
        lanes    = "lane road route path map waypoint line",
        road     = "lane road route path map waypoint",
        roads    = "lane road route path map waypoint",
        route    = "route lane road path map waypoint preview",
        routes   = "route lane road path map waypoint",
        path     = "path route lane road map waypoint preview",
        paths    = "path route lane road map waypoint",
        waypoint = "waypoint lane path route node map",
        rebuild  = "rebuild map lane road refresh scan",

        -- TRAFFIC
        traffic  = "traffic cars npc clone train prank bayblade hitbox collision",
        npc      = "traffic cars npc clone",
        cars     = "traffic cars car vehicle clone player",
        vehicle  = "car vehicle model garage rescan current",
        vehicles = "car vehicle model garage rescan",
        clone    = "clone train traffic copy",
        train    = "clone train traffic",
        prank    = "prank spin bayblade disco balloon traffic fun",
        pranks   = "prank spin bayblade disco balloon traffic fun",
        spin     = "spin bayblade rotate chaos",
        anchor   = "anchor freeze delete traffic police remove",
        delete   = "delete remove clear traffic police anchor",
        remove   = "delete remove clear traffic police anchor",

        -- STUCK
        stuck    = "stuck recovery unstick flip respawn recover",
        unstuck  = "stuck recovery unstick flip respawn recover",
        flip     = "flip stuck recovery upside respawn",
        respawn  = "respawn stuck recovery rescan vehicle",

        -- STOPPING
        stop     = "stop goal target finish panic off unload limit",
        off      = "stop panic off unload everything turn",
        disable  = "stop panic off unload turn everything",
        panic    = "stop panic off unload everything turn",
        quit     = "unload stop off close",
        exit     = "unload stop off close",
        unload   = "unload stop off close admintools",
        goal     = "goal target finish enough amount",
        target   = "goal target finish enough amount cash",
        limit    = "goal target finish enough amount",

        -- PLAYERS
        player   = "player players follow mimic target name",
        players  = "player players follow mimic target name",
        follow   = "follow mimic player target trail delay",
        mimic    = "follow mimic player target trail delay",
        friend   = "player follow mimic target",

        -- HELP
        help     = "discord invite report bug link copy support",
        discord  = "discord invite report bug link copy",
        invite   = "discord invite link copy",
        bug      = "discord invite report bug link",
        support  = "discord invite report bug link",

        -- STATS
        stats    = "stats live progress score level balance rate readout session",
        info     = "stats live progress readout state logic",
        numbers  = "stats live progress rate readout balance",
        progress = "progress stats live goal panel route",
        session  = "session stats net live total",
    }

    -- One term matches a row if the row's haystack contains it - or, when the
    -- term is a synonym key, any ONE of the words it expands to.  Several terms
    -- must all match, so typing more words narrows rather than widens.
    local function hit(hay, term)
        -- The literal term FIRST, always.  A synonym may only ever widen a
        -- word, never replace it: `wall` expands to the dodge vocabulary, and
        -- testing only the expansion meant the most obvious possible query for
        -- "See through walls" hid that very control and returned six unrelated
        -- rows instead.  This also makes every future syn entry safe to write
        -- without auditing whether it contains its own key.
        if hay:find(term, 1, true) then return true end
        local alts = UI.syn[term]
        if not alts then return false end
        for w in alts:gmatch("%S+") do
            -- Expansion words match at a WORD START, not anywhere in the
            -- haystack.  Plain substring made "points" find "waypoints", which
            -- dragged every marker row into a search for "money".  The literal
            -- term above keeps substring matching on purpose, so "marker"
            -- still finds "markers" and "lane" still finds "lanes".
            if hay:find("%f[%w]" .. w) then return true end
        end
        return false
    end

    local function matches(hay, terms)
        for i = 1, #terms do
            if not hit(hay, terms[i]) then return false end
        end
        return true
    end

    -- ------------------------------------------------------------- the bar
    local bar = new("Frame", {
        Name = "SearchBar", Position = UDim2.fromOffset(0, -40),
        Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1,
        ZIndex = 3, Parent = content,
    })
    local well = new("Frame", {
        Size = UDim2.new(1, -32, 1, 0), BackgroundColor3 = THEME.Track,
        BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3, Parent = bar,
    })
    TH.corner(well, "well")
    local ws = stroke(well, THEME.StrokeSoft, 1, 0.55)
    new("TextLabel", {
        Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(28, 34),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "FIND",
        TextSize = 9, TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, Parent = well,
    })
    local count = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(150, 14), BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono, Text = "", TextSize = 9, TextColor3 = THEME.Dim,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4, Parent = well,
    })
    Window.searchBox = new("TextBox", {
        Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -212, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "",
        PlaceholderText = "Search settings - try dodge, speed, police, lag",
        PlaceholderColor3 = THEME.Dim, TextSize = 11, TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        ZIndex = 4, Parent = well,
    })
    local clear = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(26, 26), BackgroundColor3 = THEME.Row,
        BackgroundTransparency = 0.25, Text = "X", Font = Enum.Font.GothamBold,
        TextSize = 11, TextColor3 = THEME.Sub, AutoButtonColor = false,
        ZIndex = 4, Parent = bar,
    })
    TH.corner(clear, "chip")
    stroke(clear, THEME.StrokeSoft, 1, 0.50)

    -- A blank filtered page with no explanation is worse than no search at all
    -- for the person this is built for, so say so and hand them a way back in.
    Window.noHits = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30),
        Size = UDim2.new(0, 400, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.30,
        BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = content,
    })
    TH.corner(Window.noHits, "card")
    TH.grad(Window.noHits, "Panel", "Carbon", 90)
    stroke(Window.noHits, THEME.StrokeSoft, 1, 0.50)
    pad(Window.noHits, 16, 14, 14, 16)
    local nhText = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "",
        TextSize = 11, TextColor3 = THEME.Sub, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = Window.noHits,
    })

    -- ---------------------------------------------------------- the filter
    function Window.RunSearch(q)
        q = tostring(q or ""):lower():match("^%s*(.-)%s*$") or ""
        Window.searchQ = q
        -- Hiding a dropdown's holder while its panel is open would leave
        -- UI.openPanel pointing at a closer nobody can reach.
        if type(UI.openPanel) == "function" then pcall(UI.openPanel) end
        UI.openPanel = nil

        if #q < 2 then
            for _, e in ipairs(UI.index) do
                UI.setVis(e.frame, UI.HIDE_SEARCH, false)
                if e.secFrame then UI.setVis(e.secFrame, UI.HIDE_SEARCH, false) end
            end
            Window.noHits.Visible = false
            count.Text = (#q == 1) and "keep typing" or ""
            -- Stage 9 owns this bit.  Hand the view back exactly as the user
            -- left it - keepPref, so their saved choice is untouched.
            Window.SetSimple(S.Simple, true)
            return
        end

        -- While a query is live Simple mode steps aside completely.  The
        -- alternative is a trap: a Simple user searches "dodge", finds nothing
        -- because Simple had hidden the slider, and concludes the feature does
        -- not exist - the same "it does not work" both features exist to stop.
        -- Revealing a gated control this way is safe: the popups in stage 5
        -- gate on the callback, whatever route reached it.
        Window.SetSimple(false, true)

        local terms = {}
        for w in q:gmatch("%S+") do terms[#terms + 1] = w end

        -- A section whose own name matched shows ALL of its rows.  Three of the
        -- twelve Autoplay rows is not enough to actually configure the feature,
        -- and this is the difference between a filter people use and one they
        -- fight.
        local secHit, seen = {}, {}
        for _, e in ipairs(UI.index) do
            local h = e.secFrame
            if h and not seen[h] then
                seen[h] = true
                if matches((e.sec .. " " .. (e.secTitle or "")):lower(), terms) then
                    secHit[h] = true
                end
            end
        end

        local total, live = 0, {}
        for _, e in ipairs(UI.index) do
            local show = (e.secFrame and secHit[e.secFrame]) or matches(e.hay, terms)
            UI.setVis(e.frame, UI.HIDE_SEARCH, not show)
            -- Count only what will actually RENDER.  Clearing the search bit
            -- does not make a row visible: HIDE_SIMPLE still hides the
            -- Simple-only landing card in both modes, and HIDE_COND still hides
            -- whatever the feature logic is hiding.  Counting those produced a
            -- positive match count with every pane blank AND suppressed the
            -- no-results card, which is precisely what that card exists for.
            local other = bit32.bnot(UI.HIDE_SEARCH)
            if show
                and bit32.band(UI.vis[e.frame] or 0, other) == 0
                and bit32.band(e.secFrame and UI.vis[e.secFrame] or 0, other) == 0 then
                total = total + 1
                if e.page then live[e.page] = (live[e.page] or 0) + 1 end
            end
        end

        -- sections with nothing left in them, tested on the SEARCH bit alone so
        -- a row the feature logic happens to be hiding cannot empty a section
        seen = {}
        for _, e in ipairs(UI.index) do
            local h = e.secFrame
            if h and not seen[h] then
                seen[h] = true
                local alive = false
                for _, ch in ipairs(h:GetChildren()) do
                    if ch:IsA("GuiObject") and ch.LayoutOrder ~= -100
                        and bit32.band(UI.vis[ch] or 0, UI.HIDE_SEARCH) == 0 then
                        alive = true
                        break
                    end
                end
                UI.setVis(h, UI.HIDE_SEARCH, not alive)
            end
        end

        -- Jump ONLY when the tab you are on has nothing.  Rows must never
        -- reorder and the page must never move out from under someone
        -- mid-word; an empty page you chose is better than a page you did not.
        if total > 0 and Window.activeTab and (live[Window.activeTab.page] or 0) == 0 then
            for _, t in ipairs(tabs) do
                if (live[t.page] or 0) > 0 then t.Select() break end
            end
        end

        local tabsWith = 0
        for _, t in ipairs(tabs) do
            if (live[t.page] or 0) > 0 then tabsWith = tabsWith + 1 end
        end
        count.Text = (total == 0) and "no matches"
            or string.format("%d in %d tab%s", total, tabsWith, tabsWith == 1 and "" or "s")

        Window.noHits.Visible = (total == 0)
        if total == 0 then
            nhText.Text = 'Nothing matches "' .. q .. '".\n\n'
                .. "Try one of these instead:  dodge  ·  speed  ·  police  ·  "
                .. "lag  ·  afk  ·  config  ·  colour"
        end
        for _, t in ipairs(tabs) do
            if t.page and t.page:IsA("ScrollingFrame") then
                t.page.CanvasPosition = Vector2.new()
            end
        end
    end

    bind(Window.searchBox:GetPropertyChangedSignal("Text"), function()
        Window.RunSearch(Window.searchBox.Text)
    end)
    -- Escape comes through FocusLost's second return, NOT InputBegan: the
    -- global key handler returns early whenever a text box has focus.
    bind(Window.searchBox.FocusLost, function(_, why)
        if why and why.KeyCode == Enum.KeyCode.Escape then Window.searchBox.Text = "" end
    end)
    bind(Window.searchBox.Focused, function()
        FX.tw(ws, FX.T.hov, { Color = TH.get("Accent"), Transparency = 0.25 })
    end)
    bind(Window.searchBox.FocusLost, function()
        FX.tw(ws, FX.T.out, { Color = THEME.StrokeSoft, Transparency = 0.55 })
    end)
    bind(clear.MouseButton1Click, function() Window.searchBox.Text = "" end)
    bind(clear.MouseEnter, function()
        FX.tw(clear, FX.T.hov, { BackgroundTransparency = 0.10, TextColor3 = THEME.Text })
    end)
    bind(clear.MouseLeave, function()
        FX.tw(clear, FX.T.out, { BackgroundTransparency = 0.25, TextColor3 = THEME.Sub })
    end)
end


TABS.auto.Select()

--============================================================================
-- INPUT
--============================================================================
bind(UserInputService.InputBegan, function(i, gp)
    if UI.listening then return end
    if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    -- only ignore keys while an actual text box has focus; gameProcessedEvent is
    -- unreliable here because driving games sink WASD/Shift through CAS
    if UserInputService:GetFocusedTextBox() then return end
    if i.KeyCode == S.Keys.Menu then
        Window.Toggle()
    elseif i.KeyCode == S.Keys.Boost then
        S.boostHeld = true
    end
end)

bind(UserInputService.InputEnded, function(i)
    if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == S.Keys.Boost then
        S.boostHeld = false
    end
end)

bind(UserInputService.WindowFocusReleased, function()
    S.boostHeld = false
end)

bind(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    if Workspace.CurrentCamera then Camera = Workspace.CurrentCamera end
end)

--============================================================================
-- LIVE UPDATE LOOP
--============================================================================
S.fpsAcc, S.fpsFrames, S.fpsValue = 0, 0, 0
S.uiAcc, S.carAcc = 0, 0

-- The two header gradients were driven by hand at the top of this loop.  They
-- move to the shared driver instead, with the SAME constants (40 deg/sec spin,
-- 0.25 sweeps/sec) so the header looks exactly as it did.  The only difference
-- is that the driver throttles to 30 Hz and stops while the menu is hidden.
--
-- FX.once, not FX.add: the header region may well register these itself, and
-- this line is only here so that removing the two hand-rolled writes above can
-- never silently leave a dead header.  Whichever call lands first wins.
FX.once(REF.hMarkGrad,    "spin",  40)
FX.once(REF.headLineGrad, "sweep", 0.25)

-- Claim the pump BEFORE the connection exists, in the same statement run: the
-- loader's own RenderStepped connection (created earlier in this chunk, and
-- still live for the whole boot) pumps TH.step/FX.step only while this is
-- false.  Without it both connections pumped the same frame with the same dt,
-- which ran the theme clock, the RGB hue and every idle animation at ~2x for
-- the entire loading screen.  No frame can render between this line and the
-- bind below - the main chunk does not yield here - so the handover is clean.
TH.driven = true

bind(RunService.RenderStepped, function(dt)
    -- The ONE shared idle driver.  Both engines throttle themselves to 30 Hz
    -- internally and early-return entirely when the window is closed, so this
    -- costs two comparisons a frame at rest.  Every new per-frame visual need
    -- goes through FX.add - a bare RunService:Connect would not be in CONN and
    -- would therefore survive Unload and stack on a re-run.
    --
    -- FX.on / TH.uiOn are NOT read from winRoot.Visible here.  This bind is
    -- created at load time, before the boot routine runs, so pulling the flag
    -- every frame would hold both engines off for the whole loading screen and
    -- override anything the loader had switched on.  They stay pushed.
    TH.step(dt)
    FX.step(dt)

    S.fpsAcc = S.fpsAcc + dt
    S.fpsFrames = S.fpsFrames + 1
    if S.fpsAcc >= 0.5 then
        S.fpsValue = math.floor(S.fpsFrames / S.fpsAcc + 0.5)
        S.fpsAcc, S.fpsFrames = 0, 0
        -- footer sparkline rides the cadence that already exists here; nothing
        -- extra is sampled and nothing runs per frame.
        if Window.pushFps then Window.pushFps(S.fpsValue) end
    end

    S.carAcc = S.carAcc + dt
    if S.carAcc >= 1 then
        S.carAcc = 0
        Car.Refresh()
    end

    S.uiAcc = S.uiAcc + dt
    if S.uiAcc < 0.1 then return end
    S.uiAcc = 0

    local mph = A.Mph
    if REF.carName then REF.carName:Set(S.Car.Name, S.Car.Model and THEME.Accent2 or THEME.Bad) end
    if REF.carSpeed then REF.carSpeed:Set(string.format("%d MPH", math.floor(mph + 0.5))) end

    REF.fCar.Text = S.Car.Model and S.Car.Name or "not found"
    REF.fCar.TextColor3 = S.Car.Model and THEME.Sub or THEME.Bad
    REF.fSpeed.Text = string.format("%d MPH", math.floor(mph + 0.5))
    REF.fAuto.Text = A.Running and "RUNNING" or "idle"
    REF.fAuto.TextColor3 = A.Running and THEME.Good or THEME.Dim
    REF.fFps.Text = tostring(S.fpsValue)
    -- the header keycap hint would otherwise go stale the moment the menu key
    -- is rebound in Settings
    if REF.hKeyChip then REF.hKeyChip.Text = keyName(S.Keys.Menu) end

    if REF.iState then
        REF.iState:Set(A.Running
            and ("Running · " .. (A.Chasing and "Chase flight" or A.Mode))
            or "Idle", A.Running and THEME.Good or THEME.Dim)
        REF.iLogic:Set(A.Logic, THEME.Text)
        REF.iSpeed:Set(string.format("%d / %d MPH", math.floor(mph + 0.5), math.floor(A.TargetMph + 0.5)))
        REF.iMoney:Set(((Earn.stalled or 0) > 20)
            and string.format("STALLED %s - idle cutoff", fmtTime(Earn.stalled))
            or string.format("$%s  ·  $%s/min", fmtNum(Earn.money), fmtNum(Earn.moneyRate)),
            ((Earn.stalled or 0) > 20) and THEME.Bad
            or ((Earn.moneyRate > 0) and THEME.Good or THEME.Sub))
        REF.iPts:Set(string.format("%s  ·  x%d streak  ·  %s/min",
            fmtNum(Earn.points), Earn.streak, fmtNum(Earn.pointRate)))
        REF.iNear:Set(string.format("%d  ·  %d/min", A.NearMiss, math.floor(A.NearRate + 0.5)),
            (tick() - (route.lastPass or 0) < 0.4) and THEME.Good or THEME.Accent2)
        REF.iProg:Set(string.format("%d%%", math.floor(A.Progress * 100 + 0.5)))
        REF.iTime:Set(A.Running and fmtTime(tick() - A.StartedAt) or "00:00")
        REF.iDist:Set(fmtNum(A.Studs))
        REF.iTraffic:Set(tostring(#World.Traffic()))
    end

    for _, pair in ipairs({ { REF.police, jobPolice }, { REF.traffic, jobTraffic } }) do
        local ui, job = pair[1], pair[2]
        if ui then
            ui.status:Set(WorldCtl.FolderStatus(job))
            local txt = tostring(job.count) .. " units"
            if job.mode == "Anchor" then txt = txt .. " · " .. job.anchoredCount .. " parts" end
            ui.count:Set(txt, job.enabled and THEME.Good or THEME.Sub)
        end
    end
    if REF.afkClickInfo then
        local c = Keep.click
        REF.afkClickInfo:Set(c.on and string.format("%d · %s", c.count, tostring(c.last)) or "off",
            c.on and ((c.count or 0) > 0 and THEME.Good or THEME.Sub) or THEME.Sub)
    end
    if REF.afkInfo then
        REF.afkInfo:Set(AntiAfk.mode ~= "Block idle signal"
            and (AntiAfk.fired .. " nudges") or (AntiAfk.blocked .. " cut"),
            AntiAfk.enabled and THEME.Good or THEME.Sub)
        local n = 0
        for _ in pairs(CONTROLS) do n = n + 1 end
        REF.cfgInfo:Set(tostring(n))
        REF.cfgLast:Set(Config.last)
    end
    if REF.mimicState then
        REF.mimicState:Set(Mimic.note, Mimic.enabled and THEME.Good or THEME.Sub)
        REF.mimicTrail:Set(string.format("%d samples · %.0f st back", #Mimic.trail, Mimic.dist))
    end
    if REF.chaseState then
        REF.chaseState:Set(Chase.enabled and (Chase.state .. " · " .. Chase.note) or "idle",
            Chase.enabled and THEME.Good or THEME.Sub)
        REF.chaseLaps:Set(tostring(Chase.laps))
        REF.chaseCash:Set(Chase.cash and string.format("$%s · %s", fmtNum(Chase.cash), Chase.phase)
            or (Chase.smart and "waiting for ChaseCash" or "off"),
            (Chase.phase == "banked") and THEME.Good or THEME.Sub)
        REF.chaseClicks:Set(string.format("star %d · buy %d · skip %d",
            Chase.starFired, Chase.buyFired, Chase.skipFired),
            (Chase.starFired + Chase.buyFired > 0) and THEME.Good or THEME.Warn)
        -- Every number here is the server's own, off PoliceBusted, not read
        -- back off a HUD label that rounds and formats.
        if REF.chaseOutcome then
            local r = Chase.run
            if not r.outcome then
                REF.chaseOutcome:Set("no run finished yet", THEME.Sub)
            else
                local evaded = r.outcome == "EVADED"
                REF.chaseOutcome:Set(string.format("%s · $%s earned · $%s fine",
                    r.outcome, fmtNum(r.cash), fmtNum(r.penalty)),
                    evaded and THEME.Good or THEME.Warn)
            end
        end
        if REF.chaseRate then
            local r = Chase.run
            REF.chaseRate:Set(r.rate
                and string.format("$%s/min · %s · %d star%s", fmtNum(math.floor(r.rate)),
                    fmtTime(r.secs or 0), r.stars or 0, (r.stars == 1) and "" or "s")
                or "-", r.rate and THEME.Good or THEME.Sub)
        end
        if REF.chaseHour then
            -- measured over EVERY run this session including the dead time
            -- between them, so it is the number you actually earn per hour
            local t2 = Chase.tally
            local span = t2.sessionAt and (tick() - t2.sessionAt) or 0
            REF.chaseHour:Set((span > 60 and t2.chases > 0)
                and string.format("$%s/hr over %s", fmtNum(math.floor(
                    (t2.cash - t2.penalty) / (span / 3600))), fmtTime(span))
                or "-", THEME.Accent2)
        end
        if REF.chaseAcc then
            local a = Chase.acc
            local avgMph = (a.samples > 0) and (a.mphSum / a.samples) or 0
            REF.chaseAcc:Set(a.rate > 0
                and string.format("$%.0f/s  ·  $%.2f/stud  @ %d MPH",
                    a.rate, a.perStud, math.floor(avgMph))
                or "-", a.rate > 0 and THEME.Good or THEME.Sub)
        end
        if REF.chaseEta then
            local a, cash = Chase.acc, Chase.cash
            local left = cash and (Chase.cashTarget - cash) or nil
            REF.chaseEta:Set((left and left > 0 and a.rate > 0)
                and string.format("%s at this rate", fmtTime(left / a.rate))
                or (cash and left and left <= 0 and "capped" or "-"),
                THEME.Accent2)
        end
        if REF.chaseNet then
            local t = Chase.tally
            local net = t.cash - t.penalty
            REF.chaseNet:Set(t.chases == 0 and "-"
                or string.format("$%s over %d run%s", fmtNum(net), t.chases,
                    t.chases == 1 and "" or "s"),
                net > 0 and THEME.Good or THEME.Sub)
        end
        if REF.chaseRecord then
            local t = Chase.tally
            REF.chaseRecord:Set(t.chases == 0 and "-"
                or string.format("%d / %d  (%.0f%% clean)", t.evaded, t.busted,
                    100 * t.evaded / math.max(1, t.chases)),
                (t.evaded >= t.busted) and THEME.Good or THEME.Warn)
        end
        if REF.chaseBest then
            local t2 = Chase.tally
            REF.chaseBest:Set(t2.best > 0
                and string.format("$%s · target $%s", fmtNum(t2.best),
                    fmtNum(Chase.cashTarget))
                or "-", t2.best > 0 and THEME.Good or THEME.Sub)
        end
        if REF.chaseBal then
            local r = Chase.run
            REF.chaseBal:Set((r.balance and string.format("$%s", fmtNum(r.balance)) or "-")
                .. (r.level and ("  ·  lvl " .. r.level) or ""), THEME.Accent2)
        end
        if REF.chaseDirect then
            if not Chase.direct then
                REF.chaseDirect:Set("off · clicking buttons", THEME.Sub)
            elseif not Chase.Pick() then
                REF.chaseDirect:Set("Pick remote not found", THEME.Bad)
            else
                REF.chaseDirect:Set(string.format("%d offer%s · %d pick%s",
                    Chase.offers, Chase.offers == 1 and "" or "s",
                    Chase.picks, Chase.picks == 1 and "" or "s"),
                    Chase.picks > 0 and THEME.Good or THEME.Sub)
            end
        end
        -- report the LOCKED target, not a fresh lookup: the point of caching it
        -- is that the two can disagree, and the one that matters is this one
        local pp = Chase.padPos
        if pp then
            REF.chasePad:Set(string.format("%.0f, %.0f, %.0f · locked",
                pp.X, pp.Y, pp.Z), THEME.Good)
        elseif Workspace:FindFirstChild("PoliceSystem") then
            REF.chasePad:Set("not resolved yet", THEME.Warn)
        else
            REF.chasePad:Set("PoliceSystem MISSING - using fallback", THEME.Bad)
        end
    end
    if REF.spinCount then
        REF.spinCount:Set(Fun.spin.on
            and string.format("%d of %d in folder", Fun.spin.spun or 0, Fun.spin.seen or 0)
            or "off", Fun.spin.on and THEME.Good or THEME.Sub)
    end
    if REF.trainCount then
        REF.trainCount:Set(tostring(Train.count), Train.enabled and THEME.Good or THEME.Sub)
    end
    if REF.hitboxCount then
        REF.hitboxCount:Set(Collide.noTraffic
            and string.format("%d boxes · %d re-solidified", Collide.trafficN, Collide.reverted or 0)
            or "0",
            Collide.noTraffic and ((Collide.reverted or 0) > 0 and THEME.Warn or THEME.Good) or THEME.Sub)
        REF.scoreCount:Set(tostring(Collide.scoreN),
            Collide.scoreBox and ((Collide.scoreN > 0) and THEME.Good or THEME.Bad) or THEME.Sub)
    end

    if REF.speedHint then
        if A.SpeedMode == "Static" then
            REF.speedHint:Set(string.format("locked %d MPH", math.floor(A.StaticMph)))
        else
            local p = CONFIG.Profiles[A.Profile] or CONFIG.Profiles.Normal
            REF.speedHint:Set(string.format("%d - %d MPH adaptive", p.min, p.max))
        end
    end
end)

--============================================================================
-- UNLOAD
--============================================================================
Unload = function()
    ALIVE = false
    pcall(function() Auto.Set(false) end)
    pcall(function() Fly.Set(false) end)
    pcall(function() setSpin(false) end)
    pcall(function() Wire.Set(false) end)
    pcall(function() ESP.ClearHighlights() end)
    pcall(function() WorldCtl.Stop(jobPolice) end)
    pcall(function() WorldCtl.Stop(jobTraffic) end)
    pcall(function() Fun.AllOff() end)
    pcall(function() Pulse.Set(false) end)
    pcall(function() Chase.Set(false) end)
    pcall(function() Mimic.Set(false) end)
    pcall(function() Keep.PlaySet(false) end)
    pcall(function() AntiAfk.Set(false) end)
    pcall(function() Train.Set(false) end)
    pcall(function() Collide.SetNoTraffic(false) end)
    pcall(function() Collide.SetScoreBox(false) end)
    -- Stop the RGB driver and drop every registry reference before the GUI roots
    -- go, so a re-run starts from an empty engine instead of inheriting records
    -- that point at destroyed instances.
    TH.opt.rgb = false
    pcall(FX.stopLoops)
    FX.anim, TH.b, TH.ag, TH.hooks = {}, {}, {}, {}
    -- the search index holds a frame reference per row; a re-run must start
    -- empty or it accumulates a second menu's worth of dead entries
    UI.index, UI.noSave, UI.modal = {}, {}, nil
    for _, c in ipairs(CONN) do pcall(function() c:Disconnect() end) end
    CONN = {}
    Rig.Clear("auto")
    Rig.Clear("fly")
    pcall(function() ScreenMain:Destroy() end)
    pcall(function() ScreenESP:Destroy() end)
    pcall(function() AdornHolder:Destroy() end)
    -- Release the presence session for this run.  Provided by the loader, so
    -- it is absent when the script is executed on its own; the guard makes
    -- that a no-op and the server-side expiry covers it either way.
    -- Runs last so a slow request can never delay the visible teardown.
    pcall(function()
        local endSession = ENV.AdminToolsEndSession
        if type(endSession) == "function" then endSession() end
    end)
    ENV.AdminTools = nil
end

ENV.AdminTools = {
    Unload = Unload,
    State = S,
    Version = CONFIG.Version,
    Window = Window,
    Auto = Auto,
    World = World,
    -- Used by the loader for "a new version is out" and owner notices, so
    -- those messages appear in the script's styling rather than a bare
    -- Roblox prompt. Absent when the script runs standalone.
    Modal = UI.Modal,
}

--============================================================================
-- BOOT
--============================================================================
task.spawn(function()
    -- MOBILE: Loading screen disabled
    -- Loading.Step("Initialising services", 0.10, 0.30)
    -- Loading.Step("Scanning workspace", 0.26, 0.26)
    -- Loading.Step(S.Car.Model and ("Vehicle found: " .. S.Car.Name) or "No vehicle found yet", 0.44, 0.34)
    -- Loading.Step(string.format("Mapping traffic lanes · %d lanes · %d nodes", #World.lanes, World.wpTotal or 0), 0.55, 0.30)
    -- Loading.Step(string.format("Building racing lines · %d drivable paths", #World.paths), 0.70, 0.30)
    -- Loading.Step("Arming ESP renderer", 0.78, 0.26)
    -- Loading.Step("Building interface", 0.92, 0.26)
    -- Loading.Finish()

    -- Loader out, THEN the prompt, THEN the menu.  Waiting on the Loader frame
    -- actually being gone rather than on a fixed sleep: Finish schedules its
    -- dissolve through FX, so the length of it moves with the animation rate.
    -- MOBILE: Skip loader wait since no loader screen
    -- local t0 = tick()
    -- while ScreenMain:FindFirstChild("Loader") and (tick() - t0) < 4 do task.wait() end
    task.wait(0.05)
    -- MOBILE: Discord promo disabled
    -- Promo.Show(5)

    -- Read ONLY the view preference before the window is shown.  The full
    -- restore still happens below, but autoload lands after SetOpen - so
    -- without this a user who turned Simple mode off watches the whole menu
    -- re-lay itself out a moment after it appears, which reads as a bug.
    if typeof(isfile) == "function" and typeof(readfile) == "function" then
        pcall(function()
            local f = Config.prefix .. "autoload.json"
            if isfile(f) then
                local t = HttpService:JSONDecode(readfile(f))
                if type(t) == "table" then
                    -- An absent key means the config predates Simple mode. Its
                    -- owner has already set this tool up, and dropping them
                    -- into a reduced menu looks like the update deleted half
                    -- the features. Only a genuinely fresh install - no
                    -- autoload.json at all - starts in Simple mode.
                    Window.SetSimple(t["@simple"] == true)
                end
            end
        end)
    end

    -- Create mobile toggle button (always on mobile)
    task.spawn(function()
        task.wait(0.1)
        local toggleFab = MobileToggle.Create(ScreenMain)
        print("[MobileToggle] Button created: " .. tostring(toggleFab) .. " - Size: " .. tostring(toggleFab.Size))
        
        -- Direct connect for toggle click
        local clickConnection = toggleFab.MouseButton1Click:Connect(function()
            print("[MobileToggle] Click detected!")
            MobileToggle.ToggleWindow()
        end)
        
        -- Press animation with feedback
        toggleFab.MouseButton1Down:Connect(function()
            print("[MobileToggle] Button pressed")
            if Window and Window.scale then
                FX.tw(toggleFab, 0.08, { BackgroundTransparency = 0.15 })
            end
        end)
        toggleFab.MouseButton1Up:Connect(function()
            print("[MobileToggle] Button released")
            if Window and Window.scale then
                FX.tw(toggleFab, 0.12, { BackgroundTransparency = 0 })
            end
        end)
        
        notify("Toggle Button Ready", "Bottom-right button ready to use", "good", 3)
    end)

    Window.SetOpen(true)
    notify(CONFIG.Brand .. " Mobile loaded", "Press " .. keyName(S.Keys.Menu) .. " or tap button to toggle menu", "good", 7)
    if #World.lanes == 0 then
        notify("No lane map", "workspace.TrafficLanes was not found. Automation is disabled until it is.", "warn", 8)
    end
    if not S.Car.Model then
        notify("No vehicle", S.Simple
            and "Spawn a car, then press RESCAN FOR MY CAR under Start here."
            or "Spawn a car, then hit RESCAN WORKSPACE on the My car tab.", "warn", 8)
    end
    -- a config named "autoload" is applied automatically on every run
    if typeof(isfile) == "function" then
        local okf, exists = pcall(isfile, Config.prefix .. "autoload.json")
        if okf and exists then
            local ok, applied = Config.Load("autoload")
            if ok then
                Config.last = "autoloaded"
                notify("Config autoloaded", applied .. " settings applied from autoload.json", "good", 7)
            end
        end
    end
    if GUI_MOUNT == "playergui" then
        notify("Exposed UI", "Your executor has no gethui/protect_gui, so the menu sits in PlayerGui "
            .. "where the game can see it. Expect detection.", "bad", 12)
    elseif GUI_MOUNT == "coregui" then
        notify("Partially exposed", "Mounted in plain CoreGui - a game script can enumerate it. "
            .. "gethui() was unavailable.", "warn", 10)
    end
end)

