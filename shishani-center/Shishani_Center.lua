script_name("ШиШаНи Центр")
script_author("ШиШаНи")
script_version("1.0")

require "lib.moonloader"

local sampev = require "lib.samp.events"
local keys = require "vkeys"
local imgui = require "mimgui"
local inicfg = require "inicfg"
local encoding = require "encoding"
local ffi = require "ffi"

encoding.default = "CP1251"
local u8 = encoding.UTF8
local new = imgui.new

ffi.cdef[[
    short __stdcall GetAsyncKeyState(int vKey);
]]

local CONFIG_NAME = "MarCelloy"
local defaults = {
    settings = {
        fampoint = true,
        faminfo = true,
        my_lowhp = true,
        my_hp_threshold = 200,
        fastf = true,
        fastf_delay = 95,
        fastshift = true,
        fastshift_delay = 95,
        fastshift_hold_key = 160, -- VK_LSHIFT by default; output is always VK_LSHIFT
        player_lowhp = true,
        player_hp_threshold = 200,
        player_hp_distance = 20,
        hp_broadcast = false,
        hide_hp_messages = false,
        location_key = 9,
        overlay_key = 84,
        overlay_enabled = false,
        overlay_x = 72,
        overlay_y = 42,
        sc_speed = 1.0,
        prov_hits_enabled = true,
        prov_run_enabled = true,
        prov_run_threshold = 55
    }
}

local cfg = inicfg.load(defaults, CONFIG_NAME)
inicfg.save(cfg, CONFIG_NAME)

local menuOpen = new.bool(false)
local fastMenuOpen = new.bool(false)
local scMenuOpen = new.bool(false)
local scSpeed = math.max(0.1, math.min(10.0, tonumber(cfg.settings.sc_speed) or 1.0))
scSpeed = math.floor(scSpeed * 10 + 0.5) / 10
local scSpeedSlider = new.float(scSpeed)
local hpBroadcastEnabled = new.bool(cfg.settings.hp_broadcast == true)
local hideHpMessages = new.bool(cfg.settings.hide_hp_messages == true)
local trackedFamily = {}
local lastBroadcastHp = nil
local hpBroadcastQueue = {}
local lastHpBroadcastAt = 0
local fampointEnabled = new.bool(cfg.settings.fampoint ~= false)
local faminfoEnabled = new.bool(cfg.settings.faminfo ~= false)
local myLowHpEnabled = new.bool(cfg.settings.my_lowhp ~= false)
local myHpThreshold = new.int(tonumber(cfg.settings.my_hp_threshold) or 200)
local fastFEnabled = new.bool(cfg.settings.fastf ~= false)
local fastFDelay = new.int(tonumber(cfg.settings.fastf_delay) or 95)
local fastShiftEnabled = new.bool(cfg.settings.fastshift ~= false)
local fastShiftDelay = new.int(tonumber(cfg.settings.fastshift_delay) or 95)
local fastShiftHoldKey = new.int(tonumber(cfg.settings.fastshift_hold_key) or 160)
if fastShiftHoldKey[0] < 3 or fastShiftHoldKey[0] > 254 then fastShiftHoldKey[0] = 160 end
local capturingFastShiftKey = false
local playerLowHpEnabled = new.bool(cfg.settings.player_lowhp ~= false)
local playerHpThreshold = new.int(tonumber(cfg.settings.player_hp_threshold) or 200)
local playerHpDistance = new.int(tonumber(cfg.settings.player_hp_distance) or 20)
local locationKey = new.int(tonumber(cfg.settings.location_key) or 9)
local capturingLocationKey = false
local overlayKey = new.int(tonumber(cfg.settings.overlay_key) or 84)
local capturingOverlayKey = false
local keyCaptureArmed = false
local overlayEnabled = new.bool(cfg.settings.overlay_enabled == true)
local overlayVisible = true
local overlayX = new.int(tonumber(cfg.settings.overlay_x) or 72)
local overlayY = new.int(tonumber(cfg.settings.overlay_y) or 42)
local locationKeyNames = {
    [8]="Backspace",[9]="Tab",[13]="Enter",[16]="Шифт",[17]="Ctrl",[18]="Alt",[20]="CapsLock",
    [27]="Esc",[32]="Space",[33]="Page Up",[34]="Page Down",[35]="End",[36]="Home",
    [37]="Left",[38]="Up",[39]="Right",[40]="Down",[45]="Insert",[46]="Delete",
    [112]="F1",[113]="F2",[114]="F3",[115]="F4",[116]="F5",[117]="F6",
    [118]="F7",[119]="F8",[120]="F9",[121]="F10",[122]="F11",[123]="F12",
    [160]="Left Shift",[161]="Right Shift",[162]="Left Ctrl",[163]="Right Ctrl",
    [164]="Left Alt",[165]="Right Alt",[186]=";",[187]="=",[188]=",",
    [189]="-",[190]=".",[191]="/",[192]="`",[219]="[",[220]="\\",
    [221]="]",[222]="'"
}
local function getKeyName(vk)
    if locationKeyNames[vk] then return locationKeyNames[vk] end
    if vk >= 48 and vk <= 57 then return string.char(vk) end
    if vk >= 65 and vk <= 90 then return string.char(vk) end
    if vk >= 96 and vk <= 105 then return "Num "..tostring(vk-96) end
    return "VK "..tostring(vk)
end

local cardTitle = new.char[64]()
local cardText = new.char[256]()
local cards = {}
local cardsFile = getWorkingDirectory() .. "\\config\\MarCelloy_cards.txt"

local pendingReportText = nil
local waitingReportDialog = false

local messageCooldown = 60
local lastMessageTime = 0
local myLowHpSent = false
local lastMyHpCheck = 0
local lastPlayerHpScan = 0
local playerLowState = {}

local VK_F = 0x46
local VK_LSHIFT = 0xA0
local GTA_KEY_ENTER_EXIT = 15

local function saveSettings()
    cfg.settings.hp_broadcast = hpBroadcastEnabled[0]
    cfg.settings.hide_hp_messages = hideHpMessages[0]
    cfg.settings.fampoint = fampointEnabled[0]
    cfg.settings.faminfo = faminfoEnabled[0]
    cfg.settings.my_lowhp = myLowHpEnabled[0]
    cfg.settings.my_hp_threshold = myHpThreshold[0]
    cfg.settings.fastf = fastFEnabled[0]
    cfg.settings.fastf_delay = fastFDelay[0]
    cfg.settings.fastshift = fastShiftEnabled[0]
    cfg.settings.fastshift_delay = fastShiftDelay[0]
    cfg.settings.fastshift_hold_key = fastShiftHoldKey[0]
    cfg.settings.player_lowhp = playerLowHpEnabled[0]
    cfg.settings.player_hp_threshold = playerHpThreshold[0]
    cfg.settings.player_hp_distance = playerHpDistance[0]
    cfg.settings.location_key = locationKey[0]
    cfg.settings.overlay_key = overlayKey[0]
    cfg.settings.overlay_enabled = overlayEnabled[0]
    cfg.settings.overlay_x = overlayX[0]
    cfg.settings.overlay_y = overlayY[0]
    cfg.settings.sc_speed = scSpeed
    inicfg.save(cfg, CONFIG_NAME)
end


-- The original working animation list and application loop, with no extra names.
local scAnimations = {
    'FightA_1', 'FightA_2', 'FightA_3', 'FightA_block', 'FightA_G', 'FightA_M', 'FIGHTIDLE',
    'FightShB', 'FightShF', 'FightSh_BWD', 'FightSh_FWD', 'FightSh_Left', 'FightSh_Right',
    'FightB_1', 'FightB_2', 'FightB_3', 'FightB_block', 'FightB_G', 'FightB_IDLE', 'FightB_M',
    'HitB_1', 'HitB_2', 'HitB_3',
    'FightC_1', 'FightC_2', 'FightC_3', 'FightC_block', 'FightC_blocking',
    'FightC_G', 'FightC_IDLE', 'FightC_M', 'FightC_Spar', 'HitC_1', 'HitC_2', 'HitC_3',
    'FightD_1', 'FightD_2', 'FightD_3', 'FightD_bock', 'FightD_G', 'FightD_IDLE', 'FightD_M',
    'HitD_1', 'HitD_2', 'HitD_3',
    'FightKick', 'FightKick_B', 'Hit_fightkick', 'Hit_fightkick_B', 'GUN_BUTT'
}

local function scSetSpeed(value)
    local ten = math.floor((tonumber(value) or 1.0) * 10 + 0.5)
    ten = math.max(1, math.min(100, ten))
    scSpeed = ten / 10
    scSpeedSlider[0] = scSpeed
    saveSettings()
end

local function scApplySpeed()
    -- Identical to fightSpeed_MAIK_WORKING.lua: apply all animation rates each frame.
    if doesCharExist(PLAYER_PED) then
        for i = 1, #scAnimations do
            setCharAnimSpeed(PLAYER_PED, scAnimations[i], scSpeed)
        end
    end
end

local function physicalKeyDown(vk)
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function pressFastF()
    setGameKeyState(GTA_KEY_ENTER_EXIT, 255)
    wait(0)
    setGameKeyState(GTA_KEY_ENTER_EXIT, 0)
end

-- Simulate left Shift taps inside the game while physically holding left Shift.
-- Does not send Windows-wide keyboard events.
local function pressFastShift()
    setVirtualKeyDown(VK_LSHIFT, false)
    wait(0)
    setVirtualKeyDown(VK_LSHIFT, true)
    wait(0)
    setVirtualKeyDown(VK_LSHIFT, false)
end


-- Integrated original 'PROVAKATOR USKOROK.lua' speed checker.
-- Encapsulated so it does not replace the existing /mem script callbacks.
local prov = (function()
    local M = {}
local MIN_HITS = 8                 -- 7 intervals; quicker to collect than 9 hits
local MIN_VALID_MS = 185          -- reject duplicated network/HUD events
local RESET_AFTER_MS = 900       -- gap above this starts a new series
local SOURCE_DUPLICATE_MS = 140  -- cross-source event debounce
local ALERT_COOLDOWN_MS = 12000
local MAX_HISTORY = 350
local HISTORY_FILE = getWorkingDirectory() .. '\\config\\Seller_HitSpeed_history.tsv'

local enabled = new.bool(cfg.settings.prov_hits_enabled ~= false)
local runEnabled = new.bool(cfg.settings.prov_run_enabled ~= false)
local runThreshold = new.int(math.max(55, math.min(120, tonumber(cfg.settings.prov_run_threshold) or 55)))
local menuOpen = new.bool(false)
local hitStates = {}
local recentLines = {}
local recentEvents = {}
local textdrawHistory = {}
local history = {}
local staleLineCleanup = 0
local runStates = {}
local runHistory = {}
local RUN_HISTORY_FILE = getWorkingDirectory() .. '\\config\\Shishani_run_history.tsv'
local MAX_RUN_HISTORY = 250
local runDiag = {received = 0, qualified = 0, rejected = 0, last = '-'}
local uiError = nil
local uiErrorCount = 0
local lastUiErrorAt = 0
local diag = {rpcTake = 0, rpcGive = 0, hud = 0, accepted = 0, ignored = 0, lastReason = 'Нет событий', lastSource = '-'}

-- UTF-8 is used directly by mimgui; CP1251 is used ONLY for SA-MP chat.
local COL_YELLOW = imgui.ImVec4(1.00, 0.78, 0.14, 1.00)
local COL_RED = imgui.ImVec4(1.00, 0.40, 0.35, 1.00)
local COL_GRAY = imgui.ImVec4(0.69, 0.70, 0.73, 1.00)
local COL_GREEN = imgui.ImVec4(0.40, 0.86, 0.56, 1.00)

local function ru(text)
    return text -- MoonLoader's client text uses CP1251 here
end

local function clean(value)
    return tostring(value or ''):gsub('[\t\r\n]', ' ')
end

local function normName(name)
    return tostring(name or ''):gsub('_', ' '):gsub('^%s+', ''):gsub('%s+$', ''):lower()
end

local function weaponLabel(id)
    local weapons = {
        [0] = 'Кулаки', [1] = 'Кастет', [2] = 'Клюшка', [3] = 'Дубинка',
        [4] = 'Нож', [5] = 'Бита', [6] = 'Лопата', [7] = 'Кий',
        [8] = 'Катана', [9] = 'Бензопила', [14] = 'Цветы', [15] = 'Трость'
    }
    return weapons[id] or ('ID ' .. tostring(id))
end

local function speedLevel(ms)
    -- Reference bands: x1.1 = 380-395; x1.2 = 350-365;
    -- x1.3 = 316-330; x1.3+ = 315 ms or less.
    -- The gaps are assigned to the NEAREST reference band:
    -- 373-379 => x1.1, 366-372 => x1.2;
    -- 340-349 => x1.2, 331-339 => x1.3.
    if ms > 395 then return 'normal' end
    if ms >= 373 then return 'x1.1' end
    if ms >= 340 then return 'x1.2' end
    if ms >= 316 then return 'x1.3' end
    return 'x1.3+'
end

local function safeNickForUi(name)
    -- SA-MP nicknames normally contain Latin characters, digits and '_'.
    return clean(name)
end

local function serialize(entry)
    return table.concat({
        clean(entry.stamp), clean(entry.name), tostring(entry.weapon),
        string.format('%.1f', entry.avg), clean(entry.level),
        tostring(entry.hits), tostring(entry.fastCount),
        tostring(entry.minMs), tostring(entry.maxMs)
    }, '\t')
end

local function addToMemory(entry)
    history[#history + 1] = entry
    while #history > MAX_HISTORY do table.remove(history, 1) end
end

local function persistHistory()
    local f = io.open(HISTORY_FILE, 'wb')
    if not f then return false end
    for _, e in ipairs(history) do f:write(serialize(e), '\n') end
    f:close()
    return true
end

local function loadHistory()
    local f = io.open(HISTORY_FILE, 'rb')
    if not f then return end
    for line in f:lines() do
        local items = {}
        for field in (line .. '\t'):gmatch('(.-)\t') do items[#items + 1] = field end
        if #items >= 9 then
            addToMemory({
                stamp = items[1], name = items[2], weapon = tonumber(items[3]) or 0,
                avg = tonumber(items[4]) or 0, level = items[5],
                hits = tonumber(items[6]) or MIN_HITS, fastCount = tonumber(items[7]) or 0,
                minMs = tonumber(items[8]) or 0, maxMs = tonumber(items[9]) or 0
            })
        end
    end
    f:close()
end

local function chatAlert(e)
    -- Порядок: игрок | оружие | точный интервал (мс) | оценка xN.
    local msg = ru('{FFD22D}[ШиШаНи] {FFFFFF}Игрок {FD446F}') .. clean(e.name)
        .. ru('{FFFFFF} | Оружие: ') .. ru(weaponLabel(e.weapon))
        .. ru(' | Интервал: ') .. string.format('%.1f', e.avg) .. ru(' мс')
        .. ru(' | ') .. tostring(e.level) .. ru(' |')
    sampAddChatMessage(msg, 0xFFFFFF)
end

local function fireAlert(name, weapon, avg, hits, fastCount, minMs, maxMs)
    local e = {
        stamp = os.date('%d.%m.%Y %H:%M:%S'),
        name = clean(name), weapon = weapon, avg = avg, level = speedLevel(avg),
        hits = hits, fastCount = fastCount, minMs = minMs, maxMs = maxMs
    }
    addToMemory(e)
    persistHistory()
    chatAlert(e)
end

local function measure(times)
    local intervals = {}
    local total, fastCount, minMs, maxMs = 0, 0, 99999, 0
    for i = 2, #times do
        local dt = times[i] - times[i - 1]
        intervals[#intervals + 1] = dt
        total = total + dt
        if dt <= 395 then fastCount = fastCount + 1 end
        minMs = math.min(minMs, dt)
        maxMs = math.max(maxMs, dt)
    end
    table.sort(intervals)
    local n = #intervals
    local avg = total / n
    local median = (intervals[math.floor((n + 1) / 2)] + intervals[math.ceil((n + 1) / 2)]) / 2
    return avg, median, fastCount, minMs, maxMs
end

local function recordHit(name, weapon, source)
    if not enabled[0] or not name or name == '' then return end
    weapon = tonumber(weapon) or -1
    if weapon < 0 or weapon > 15 then return end
    local now = getGameTimer()
    local key = normName(name) .. ':' .. tostring(weapon)

    -- Damage informer and RPC can describe the same single hit.
    local lastEvent = recentEvents[key]
    if lastEvent and now >= lastEvent and now - lastEvent < SOURCE_DUPLICATE_MS then
        diag.ignored = diag.ignored + 1
        diag.lastReason = 'Повтор события (' .. tostring(source) .. ')'
        return
    end

    local state = hitStates[key]
    if not state then
        state = {name = name, weapon = weapon, times = {}, lastHit = nil,
                 lastAlert = -1000000, avg = nil, level = 'normal', updated = now,
                 lastSource = source, suspicious = false}
        hitStates[key] = state
    end

    if state.lastHit then
        local diff = now - state.lastHit
        if diff >= 0 and diff < MIN_VALID_MS then
            diag.ignored = diag.ignored + 1
            diag.lastReason = 'Слишком близкие события: ' .. tostring(diff) .. ' мс'
            return
        end
        if diff < 0 or diff > RESET_AFTER_MS then
            state.times = {}
            diag.lastReason = 'Новая серия после паузы'
        end
    end

    recentEvents[key] = now
    state.lastHit = now
    state.updated = now
    state.name = name
    state.lastSource = source
    state.times[#state.times + 1] = now
    while #state.times > MIN_HITS do table.remove(state.times, 1) end
    diag.accepted = diag.accepted + 1
    diag.lastSource = source
    diag.lastReason = 'Принято ' .. tostring(#state.times) .. '/' .. tostring(MIN_HITS) .. ' ударов'
    if #state.times < MIN_HITS then return end

    local avg, median, fastCount, minMs, maxMs = measure(state.times)
    -- Use median for speed tiers: a single network delay must not obscure
    -- 395/360/330/315 ms. Mean and consistency still guard false positives.
    local level = speedLevel(median)
    local needFast = math.ceil((MIN_HITS - 1) * 0.70)
    local suspicious = level ~= 'normal' and fastCount >= needFast
                    and avg <= 405 and minMs >= MIN_VALID_MS and maxMs <= 600
    state.avg, state.median, state.level = avg, median, level
    state.suspicious = suspicious
    state.fastCount, state.minMs, state.maxMs = fastCount, minMs, maxMs
    state.reason = suspicious and 'Серия подтверждена' or
        string.format('Недостаточно: %d/%d быстрых, среднее %.0f мс', fastCount, MIN_HITS - 1, avg)
    diag.lastReason = state.reason

    if suspicious and (now - state.lastAlert >= ALERT_COOLDOWN_MS) then
        state.lastAlert = now
        -- Persist and show the ROBUST median; not a single fastest hit.
        fireAlert(name, weapon, median, #state.times, fastCount, minMs, maxMs)
    end
end

local function stripColors(text)
    return tostring(text or ''):gsub('{%x%x%x%x%x%x}', '')
end

local function parseDamageLine(text)
    local line = stripColors(text)
    -- Supports: Zahar Katamaran - Бита(5) -70.90 (301.07)
    -- These lines MUST come from real SAMP textdraw/chat events.
    local name, weapon, damage = line:match('^%s*(.-)%s+%-%s+.-%((%d+)%)%s*%-(%d+%.?%d*)%s*%(')
    if not name or not tonumber(damage) or tonumber(damage) <= 0 then return end
    local now = getGameTimer()
    local fingerprint = clean(line)
    local prev = recentLines[fingerprint]
    if prev and now >= prev and now - prev < SOURCE_DUPLICATE_MS then
        diag.ignored = diag.ignored + 1
        return
    end
    recentLines[fingerprint] = now
    diag.hud = diag.hud + 1
    recordHit(name, tonumber(weapon), 'damage_informer')
end

local function splitHudLines(text)
    local lines = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        if line ~= '' then lines[#lines + 1] = line end
    end
    return lines
end

local function processHud(key, value)
    if type(value) ~= 'string' or value == '' then return end
    local current = value:gsub('~n~', '\n')
    local previous = textdrawHistory[key]
    if previous == current then return end
    textdrawHistory[key] = current

    local old = {}
    if previous then
        for _, line in ipairs(splitHudLines(previous)) do
            old[line] = (old[line] or 0) + 1
        end
    end
    local fresh = {}
    for _, line in ipairs(splitHudLines(current)) do
        if old[line] and old[line] > 0 then
            old[line] = old[line] - 1
        else
            fresh[#fresh + 1] = line
        end
    end
    -- A first-time TextDraw may contain historical lines. Don't interpret
    -- many lines appearing in a single frame as multiple simultaneous hits.
    if not previous and #fresh > 1 then
        parseDamageLine(fresh[#fresh])
    else
        for _, line in ipairs(fresh) do parseDamageLine(line) end
    end
end

function M.onSendTakeDamage(playerId, damage, weaponId, bodyPart)
    if tonumber(damage) and damage > 0 then
        diag.rpcTake = diag.rpcTake + 1
        local name = 'ID ' .. tostring(playerId)
        if sampIsPlayerConnected(playerId) then
            name = sampGetPlayerNickname(playerId) or name
        end
        recordHit(name, weaponId, 'take_damage')
    end
end

function M.onSendGiveDamage(playerId, damage, weaponId, bodyPart)
    if tonumber(damage) and damage > 0 then
        diag.rpcGive = diag.rpcGive + 1
        recordHit('YOU', weaponId, 'give_damage')
    end
end

function M.onServerMessage(color, text)
    if type(text) == 'string' then
        for line in (text:gsub('~n~', '\n') .. '\n'):gmatch('(.-)\n') do
            parseDamageLine(line)
        end
    end
end

function M.onTextDrawSetString(textdrawId, text)
    processHud('textdraw:' .. tostring(textdrawId), text)
end

function M.onShowTextDraw(textdrawId, data)
    if data and type(data.text) == 'string' then
        processHud('textdraw:' .. tostring(textdrawId), data.text)
    end
end

function M.onTextDrawHide(textdrawId)
    textdrawHistory['textdraw:' .. tostring(textdrawId)] = nil
end



    -- Separate running-speed check. An animation and steady horizontal motion
    -- are necessary. 55 km/h alone can be legitimate; this is NOT proof of cheats.
    local RUN_MIN_DURATION = 1600
    local RUN_MIN_SAMPLES = 9
    local RUN_MAX_GAP = 500
    local RUN_MAX_Z_STEP = 0.55
    local RUN_MAX_STEP_KMH = 115
    local RUN_COOLDOWN = 15000
    local RUN_ALLOWED = {
        RUN_PLAYER=true, RUN_CIVI=true, RUN_GANG1=true,
        RUN_FAT=true, RUN_FATOLD=true, RUN_OLD=true, RUN_WUZI=true,
        RUN_ROCKET=true, RUN_ARMED=true, RUN_1ARMED=true,
        RUN_CSAW=true, RUN_RIGHT=true, SWAT_RUN=true,
        SPRINT_CIVI=true, SPRINT_PANIC=true, SPRINT_WUZI=true,
        WOMAN_RUN=true, WOMAN_RUNPANIC=true, JOG_MALEA=true, JOG_MALEB=true
    }
    local function runAnim(playerId, animationId)
        if not animationId or type(sampGetAnimationNameAndFile) ~= 'function' then return nil end
        local ok, a, b = pcall(sampGetAnimationNameAndFile, tonumber(animationId) or 0)
        if not ok then return nil end
        local name = (type(a) == 'string' and RUN_ALLOWED[a:upper()] and a)
                  or (type(b) == 'string' and RUN_ALLOWED[b:upper()] and b)
        if name then return name end
        return nil
    end
    local function saveRunHistory()
        local f = io.open(RUN_HISTORY_FILE, 'wb')
        if not f then return end
        for _, e in ipairs(runHistory) do
            f:write(clean(e.stamp), '\t', clean(e.name), '\t',
                string.format('%.1f', e.speed), '\t', clean(e.anim), '\n')
        end
        f:close()
    end
    local function loadRunHistory()
        local f = io.open(RUN_HISTORY_FILE, 'rb')
        if not f then return end
        for line in f:lines() do
            local stamp, name, speed, anim = line:match('^(.-)\t(.-)\t([%d%.]+)\t(.+)$')
            if stamp and name and tonumber(speed) then
                runHistory[#runHistory+1] = {stamp=stamp,name=name,speed=tonumber(speed),anim=anim}
                if #runHistory > MAX_RUN_HISTORY then table.remove(runHistory, 1) end
            end
        end
        f:close()
    end
    function M.onPlayerSync(playerId, data)
        if not runEnabled[0] or not data or type(data) ~= 'table' then return end
        runDiag.received = runDiag.received + 1
        local pos = data.position
        if not pos then return end
        local x,y,z = tonumber(pos.x),tonumber(pos.y),tonumber(pos.z)
        if not x or not y or not z then return end
        local now = getGameTimer()
        local anim = runAnim(playerId, data.animationId)
        if not anim or (data.surfingVehicleId and tonumber(data.surfingVehicleId) ~= 65535) then
            runStates[playerId] = nil
            runDiag.rejected = runDiag.rejected + 1
            return
        end
        local name = 'ID ' .. tostring(playerId)
        if sampIsPlayerConnected(playerId) then
            name = sampGetPlayerNickname(playerId) or name
        end
        local state = runStates[playerId]
        if not state or state.name ~= name then
            runStates[playerId] = {name=name, anim=anim, points={{x=x,y=y,z=z,t=now}},
                lastAlert=-1000000, lastSeen=now}
            return
        end
        local last = state.points[#state.points]
        local dt = now-last.t
        if dt < 30 then return end
        local dx,dy,dz = x-last.x,y-last.y,z-last.z
        local speed = math.sqrt(dx*dx+dy*dy)*3600/dt
        if dt > RUN_MAX_GAP or dt < 0 or math.abs(dz) > RUN_MAX_Z_STEP or speed > RUN_MAX_STEP_KMH then
            runStates[playerId] = nil
            runDiag.rejected = runDiag.rejected + 1
            runDiag.last = 'Skipped jump/lag/teleport'
            return
        end
        state.lastSeen = now
        state.anim = anim
        state.points[#state.points+1] = {x=x,y=y,z=z,t=now}
        while #state.points > 2 and now - state.points[2].t > 2300 do
            table.remove(state.points,1)
        end
        local first=state.points[1]
        local span=now-first.t
        if span < RUN_MIN_DURATION or #state.points < RUN_MIN_SAMPLES then return end
        local distance = 0
        for i=2,#state.points do
            local a,b=state.points[i-1],state.points[i]
            distance=distance+math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)
        end
        local mean=distance*3600/span
        state.speed=mean
        runDiag.qualified=runDiag.qualified+1
        if mean >= runThreshold[0] and now - state.lastAlert >= RUN_COOLDOWN then
            state.lastAlert=now
            local event={stamp=os.date('%d.%m.%Y %H:%M:%S'),name=name,speed=mean,anim=anim}
            runHistory[#runHistory+1]=event
            if #runHistory>MAX_RUN_HISTORY then table.remove(runHistory,1) end
            saveRunHistory()
            sampAddChatMessage('{FFD22D}[Shishani] {FFFFFF}' .. clean(name)
                .. ' | RUN | ' .. string.format('%.1f km/h',mean) .. ' | '..tostring(anim)..' |', -1)
        end
    end

    function M.initialize()
        local folder = getWorkingDirectory() .. "\\config"
        if not doesDirectoryExist(folder) then createDirectory(folder) end
        loadHistory()
        loadRunHistory()
    end

    function M.maintenance(now)
        if now - staleLineCleanup < 30000 and now >= staleLineCleanup then return end
        staleLineCleanup = now
        for key, when in pairs(recentLines) do
            if now - when > 5000 or now < when then recentLines[key] = nil end
        end
        for key, when in pairs(recentEvents) do
            if now - when > 30000 or now < when then recentEvents[key] = nil end
        end
        for key, state in pairs(hitStates) do
            if now - state.updated > 60000 or now < state.updated then hitStates[key] = nil end
        end
        for key, state in pairs(runStates) do
            if now - state.lastSeen > 6000 or now < state.lastSeen then runStates[key] = nil end
        end
    end

    local function drawCheckerTab()
        imgui.TextColored(COL_YELLOW, u8"ПРОВЕРКА УСКОРЕНИЙ")
        imgui.SameLine()
        imgui.TextDisabled(u8" /mem | ШиШаНи v1.0")
        imgui.Separator()
        if imgui.Checkbox(u8"Проверять удары##prov_hits",enabled) then
            cfg.settings.prov_hits_enabled=enabled[0]
            saveSettings()
            hitStates={}
        end
        imgui.SameLine()
        if imgui.Checkbox(u8"Проверять бег 55+##prov_run",runEnabled) then
            cfg.settings.prov_run_enabled=runEnabled[0]
            saveSettings()
            runStates={}
        end
        imgui.TextDisabled(u8"Предупреждения не являются доказательством чита")
        imgui.Spacing()
        if imgui.BeginTabBar('prov_sub_tabs_fixed') then
            if imgui.BeginTabItem(u8"Все события##prov_all") then
                imgui.Text(u8"Удары: "..#history..u8" | Бег: "..#runHistory)
                imgui.Separator()
                imgui.BeginChild('prov_all_child', imgui.ImVec2(0,315),true)
                -- Do not draw hundreds of rows every frame. Max 35 newest from each.
                local events={}
                for i=math.max(1,#history-34),#history do
                    local e=history[i]
                    if e then events[#events+1]={kind='HIT',stamp=e.stamp,name=e.name,avg=e.avg,
                        detail=string.format('%s (ID %s) | %.1f ms | %s',weaponLabel(e.weapon),tostring(e.weapon),e.avg,e.level)} end
                end
                for i=math.max(1,#runHistory-34),#runHistory do
                    local e=runHistory[i]
                    if e then events[#events+1]={kind='RUN',stamp=e.stamp,name=e.name,
                        detail=string.format('%.1f km/h | %s',e.speed,e.anim)} end
                end
                table.sort(events,function(a,b) return a.stamp>b.stamp end)
                if #events==0 then imgui.TextDisabled(u8"Предупреждений пока нет") end
                for i=1,math.min(#events,50) do
                    local e=events[i]
                    imgui.TextColored(COL_YELLOW,(e.kind=='RUN' and 'RUN  ' or 'HIT  ')..tostring(e.name))
                    imgui.Text(tostring(e.detail))
                    imgui.TextDisabled(tostring(e.stamp))
                    imgui.Separator()
                end
                imgui.EndChild()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8"Ускорение ударов##prov_hits_view") then
                imgui.Text(u8"Диапазоны: 380-395 мс = x1.1 | 350-365 = x1.2")
                imgui.Text(u8"316-330 мс = x1.3 | до 315 = x1.3+")
                imgui.TextDisabled(u8"8 ударов, 7 интервалов. Скорость — ориентировочная.")
                imgui.BeginChild('prov_live_hits_child',imgui.ImVec2(0,240),true)
                local checks={}
                local now=getGameTimer()
                for _,st in pairs(hitStates) do
                    if st.updated and now>=st.updated and now-st.updated<20000 then checks[#checks+1]=st end
                end
                table.sort(checks,function(a,b) return a.updated>b.updated end)
                for i=1,math.min(#checks,25) do
                    local st=checks[i]
                    imgui.Text(tostring(st.name)..' | '..(st.median and string.format('%.1f ms | %s',st.median,st.level) or (#st.times..'/8 hits')))
                end
                if #checks==0 then imgui.TextDisabled(u8"Ожидание ударов...") end
                imgui.EndChild()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8"Ускоренный бег##prov_run_view") then
                if imgui.SliderInt(u8"Порог бега (км/ч)##prov_run_value",runThreshold,55,90) then
                    cfg.settings.prov_run_threshold=runThreshold[0]
                    saveSettings()
                end
                imgui.TextDisabled(u8"Проверяется только устойчивая анимация бега (1.6 с).")
                imgui.TextDisabled(u8"Прыжки, транспорт, телепорты и сбои синхронизации исключаются.")
                imgui.BeginChild('prov_live_run_child',imgui.ImVec2(0,215),true)
                local now=getGameTimer()
                local active={}
                for _,st in pairs(runStates) do
                    if st.lastSeen and now>=st.lastSeen and now-st.lastSeen<5000 then active[#active+1]=st end
                end
                table.sort(active,function(a,b) return a.lastSeen>b.lastSeen end)
                for i=1,math.min(#active,25) do
                    local st=active[i]
                    imgui.Text(tostring(st.name)..' | '..string.format('%.1f km/h',st.speed or 0)..' | '..tostring(st.anim))
                end
                if #active==0 then imgui.TextDisabled(u8"Нет подтверждённых серий бега") end
                imgui.EndChild()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8"Диагностика##prov_diag_fixed") then
                imgui.Text(string.format('RPC TAKE: %d | GIVE: %d | HUD: %d',diag.rpcTake,diag.rpcGive,diag.hud))
                imgui.Text(string.format('Accepted: %d | Filtered: %d',diag.accepted,diag.ignored))
                imgui.Text(string.format('RUN packets: %d | valid: %d | filtered: %d',runDiag.received,runDiag.qualified,runDiag.rejected))
                imgui.TextWrapped(u8"Последняя проверка: "..u8(tostring(diag.lastReason)))
                imgui.TextWrapped('Source: '..tostring(diag.lastSource))
                if uiError then imgui.TextColored(COL_RED,'UI ERROR: '..tostring(uiError):sub(1,250)) end
                imgui.TextDisabled(u8"Если нет событий, проверь передачу данных сервером.")
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
    end
    function M.drawTab()
        local ok, err = pcall(drawCheckerTab)
        if not ok then
            uiError = tostring(err)
            uiErrorCount=uiErrorCount+1
            local now=getGameTimer()
            if now - lastUiErrorAt>10000 then
                lastUiErrorAt=now
                sampAddChatMessage('{FF5555}[Shishani] Checker UI error; see moonloader.log', -1)
                if type(print)=='function' then print('[Shishani] Checker UI error: '..uiError) end
            end
            -- A UI fault must not bring down the remaining /mem features.
        end
    end
    return M
end)()

-- Configurable SA-MP command binder; one press or timed repeat while held.
local BINDER_FILE = getWorkingDirectory() .. "\\config\\MarCelloy_binds.tsv"
local BINDER_LIMIT = 30
local binds = {}
local bindEditing = 0  -- 0: new, 1..n: editing existing entry
local bindCommand = new.char[192]()  -- UTF-8 input for mimgui
local bindKey = new.int(0x72)       -- F3 default, user can change
local bindKeySecond = new.int(0)    -- 0 = no second key
local bindRepeat = new.bool(false)
local bindDelay = new.int(750)
local bindEnabled = new.bool(true)
local capturingBinderKey = false
local binderCaptureFirst = nil
local binderCaptureStarted = 0
local BINDER_COMBO_GRACE_MS = 450
local binderKeyWasDown = {}
local binderLastSend = {}

local function clampBinderDelay(ms)
    return math.max(150, math.min(5000, math.floor(tonumber(ms) or 750)))
end

local function resetBinderInputs()
    bindEditing = 0
    bindCommand[0] = 0
    bindKey[0] = 0x72
    bindKeySecond[0] = 0
    bindRepeat[0] = false
    bindDelay[0] = 750
    bindEnabled[0] = true
    capturingBinderKey = false
    binderCaptureFirst = nil
    binderCaptureStarted = 0
end

local function saveBinds()
    local folder = getWorkingDirectory() .. "\\config"
    if not doesDirectoryExist(folder) then createDirectory(folder) end
    local f = io.open(BINDER_FILE, "wb")
    if not f then return false end
    for _, b in ipairs(binds) do
        local cmd = tostring(b.command or ""):gsub('[\t\r\n]', ' ')
        -- v2: first key, second key (0 for single-key), hold, delay, active, command
        f:write(string.format('%d\t%d\t%d\t%d\t%d\t%s\n',
            b.key, b.key2 or 0, b.repeatHold and 1 or 0, b.delay,
            b.enabled and 1 or 0, cmd))
    end
    f:close()
    return true
end

local function loadBinds()
    binds = {}
    local f = io.open(BINDER_FILE, 'rb')
    if not f then return end
    for line in f:lines() do
        -- Accept both legacy 5-column and new 6-column formats.
        local key, key2, mode, delay, enabled, command =
            line:match('^(%d+)\t(%d+)\t([01])\t(%d+)\t([01])\t(.+)$')
        if not key then
            key, mode, delay, enabled, command =
                line:match('^(%d+)\t([01])\t(%d+)\t([01])\t(.+)$')
            key2 = '0'
        end
        key = tonumber(key)
        key2 = tonumber(key2) or 0
        if key and key >= 3 and key <= 254 and
            (key2 == 0 or (key2 >= 3 and key2 <= 254 and key2 ~= key)) and
            command and command ~= '' and #binds < BINDER_LIMIT then
            binds[#binds + 1] = {
                key = key, key2 = key2, repeatHold = mode == '1',
                delay = clampBinderDelay(delay), enabled = enabled == '1',
                command = command
            }
        end
    end
    f:close()
end

local function editBinder(i)
    local b = binds[i]
    if not b then return end
    bindEditing = i
    bindKey[0] = b.key
    bindKeySecond[0] = b.key2 or 0
    bindRepeat[0] = b.repeatHold
    bindDelay[0] = b.delay
    bindEnabled[0] = b.enabled
    bindCommand[0] = 0
    local count = math.min(#b.command, 190)
    ffi.copy(bindCommand, b.command, count)
    bindCommand[count] = 0
    capturingBinderKey = false
    binderCaptureFirst = nil
    binderCaptureStarted = 0
end

local function commitBinder()
    local cmd = ffi.string(bindCommand):gsub('[\r\n\t]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if cmd == '' then
        sampAddChatMessage('{FFCC44}[Shishani] {FFFFFF}Enter a command for the bind.', -1)
        return
    end
    local ok, ansi = pcall(function() return u8:decode(cmd) end)
    if not ok or not ansi or #ansi > 144 then
        sampAddChatMessage('{FFCC44}[Shishani] {FFFFFF}Command too long or encoding unsupported.', -1)
        return
    end
    local key, key2 = bindKey[0], bindKeySecond[0]
    if key < 3 or key > 254 or (key2 ~= 0 and (key2 < 3 or key2 > 254 or key2 == key)) then
        sampAddChatMessage('{FFCC44}[Shishani] {FFFFFF}Invalid combination (keys must differ).', -1)
        return
    end
    local b = {
        key = key, key2 = key2, command = cmd, repeatHold = bindRepeat[0],
        delay = clampBinderDelay(bindDelay[0]), enabled = bindEnabled[0]
    }
    if bindEditing >= 1 and binds[bindEditing] then
        binds[bindEditing] = b
    elseif #binds < BINDER_LIMIT then
        binds[#binds + 1] = b
    else
        sampAddChatMessage('{FFCC44}[Shishani] {FFFFFF}Binder limit reached (30).', -1)
        return
    end
    binderKeyWasDown, binderLastSend = {}, {}
    saveBinds()
    resetBinderInputs()
end

local function getBindKeyLabel(b)
    local one = getKeyName(b.key)
    if b.key2 and b.key2 ~= 0 then return one .. ' + ' .. getKeyName(b.key2) end
    return one
end

-- The binder uses one dedicated capture button for both single-key and two-key binds.
-- Holding the two desired keys during capture selects the combination automatically.
local function startBinderCapture()
    capturingBinderKey = true
    capturingFastShiftKey = false
    capturingLocationKey = false
    capturingOverlayKey = false
    binderCaptureFirst = nil
    binderCaptureStarted = 0
    keyCaptureArmed = false
end

local function stopBinderCapture(first, second)
    if first then
        bindKey[0] = first
        bindKeySecond[0] = second or 0
    end
    capturingBinderKey = false
    binderCaptureFirst = nil
    binderCaptureStarted = 0
    keyCaptureArmed = false
end

local function canCaptureBindKey(vk)
    -- Skip mouse buttons and generic Shift/Ctrl/Alt, using left/right codes instead.
    return vk ~= 1 and vk ~= 2 and vk ~= 4
        and vk ~= 16 and vk ~= 17 and vk ~= 18
        and vk ~= 229 and vk ~= 231
end

local function updateBinderKeyCapture(now)
    -- Wait for the mouse click used to open capture to be released.
    if not keyCaptureArmed then
        if not physicalKeyDown(1) and not physicalKeyDown(2) then
            keyCaptureArmed = true
        end
        return
    end

    if physicalKeyDown(27) then -- Escape cancels without changing the saved fields.
        stopBinderCapture(nil, nil)
        return
    end

    local held = {}
    for vk = 3, 254 do
        if canCaptureBindKey(vk) and physicalKeyDown(vk) then
            held[#held + 1] = vk
        end
    end

    if #held >= 2 then
        -- Pick a modifier first for readability (Ctrl + G rather than G + Ctrl).
        local function modifier(vk)
            return vk == 160 or vk == 161 or vk == 162 or vk == 163
                or vk == 164 or vk == 165
        end
        table.sort(held, function(a, b)
            if modifier(a) ~= modifier(b) then return modifier(a) end
            return a < b
        end)
        stopBinderCapture(held[1], held[2])
        return
    end
    if #held == 1 and not binderCaptureFirst then
        binderCaptureFirst = held[1]
        binderCaptureStarted = now
    end
    -- A single-key bind is accepted after a short grace period so the user can
    -- press the second key slightly later, without requiring the exact same frame.
    if binderCaptureFirst and now - binderCaptureStarted >= BINDER_COMBO_GRACE_MS then
        stopBinderCapture(binderCaptureFirst, nil)
    end
end

local function processBinds(now)
    local blocked = menuOpen[0] or fastMenuOpen[0] or scMenuOpen[0]
        or capturingBinderKey or capturingFastShiftKey or capturingLocationKey or capturingOverlayKey
        or sampIsChatInputActive() or sampIsDialogActive() or isPauseMenuActive()
        or isSampfuncsConsoleActive()
    -- A two-key bind takes precedence over a single-key bind using the same key.
    local combosActive = {}
    if not blocked then
        for _, b in ipairs(binds) do
            if b.enabled and b.key2 and b.key2 ~= 0