script_name('Shishani AutoUpdater')
script_author('ШиШаНи')
script_version('1.0')

require 'lib.moonloader'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local downloadStatus = require('moonloader').download_status

-- Public GitHub repository. Update ONLY files from this path.
local BASE = 'https://raw.githubusercontent.com/Selvatore5747/Khavaji/master/shishani-center/'
local CHECK_EVERY_MS = 30 * 60 * 1000
local MIN_SIZE = 15000
local directory = thisScript().path:match('^(.*)[/\\]') or getWorkingDirectory()
local target = directory .. '\\Shishani_Center.lua'
local backup = directory .. '\\Shishani_Center.lua.bak'
local latestFile = directory .. '\\shishani_latest.tmp'
local candidateFile = directory .. '\\shishani_candidate.tmp'
local busy = false
local lastCheck = 0

local function inform(text)
    local msg = '{FFD22D}[Shishani Update] {FFFFFF}' .. u8:decode(text)
    if isSampAvailable() then sampAddChatMessage(msg, -1) else print(msg) end
end

local function readAll(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function writeAll(path, contents)
    local f = io.open(path, 'wb')
    if not f then return false end
    local ok = f:write(contents)
    f:close()
    return ok ~= nil
end

local function versionParts(value)
    local parts = {}
    for n in tostring(value):gmatch('%d+') do parts[#parts+1] = tonumber(n) end
    return parts
end

local function newer(a,b)
    local aa, bb = versionParts(a), versionParts(b)
    if #aa == 0 or #bb == 0 then return false end
    for i=1, math.max(#aa,#bb) do
        local x,y = aa[i] or 0, bb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

local function installedVersion()
    local source = readAll(target)
    if not source then return '0.0' end
    return source:match([[script_version%s*%(%s*["']([%d%.]+)["']%s*%)]]) or '0.0'
end

local function download(url, path, callback)
    os.remove(path)
    local finished = false
    local succeeded = false
    local ok, err = pcall(function()
        downloadUrlToFile(url .. '?_=' .. tostring(os.time()), path,
            function(_, status)
                if status == downloadStatus.STATUS_ENDDOWNLOADDATA then
                    succeeded = true
                    finished = true
                elseif status == downloadStatus.STATUSEX_ENDDOWNLOAD then
                    finished = true
                end
            end)
    end)
    if not ok then callback(false, tostring(err)); return end
    -- MoonLoader calls progress handlers asynchronously.
    lua_thread.create(function()
        local started = getGameTimer()
        while not finished and getGameTimer() - started < 20000 do wait(100) end
        callback(succeeded and doesFileExist(path), succeeded and nil or 'download failed or timed out')
    end)
end

local function performCheck(manual)
    if busy then
        if manual then inform('Проверка уже выполняется.') end
        return
    end
    busy = true
    lastCheck = getGameTimer()
    download(BASE .. 'version.txt', latestFile, function(ok, err)
        if not ok then
            if manual then inform('Не удалось проверить GitHub: ' .. tostring(err)) end
            busy = false
            return
        end
        local remote = (readAll(latestFile) or ''):match('^%s*([%d%.]+)%s*$')
        os.remove(latestFile)
        if not remote then
            if manual then inform('Некорректный файл версии на GitHub.') end
            busy = false
            return
        end
        local current = installedVersion()
        if not newer(remote, current) then
            if manual then inform('Установлена актуальная версия ' .. current .. '.') end
            busy = false
            return
        end
        inform('Найдена версия ' .. remote .. ' (установлена ' .. current .. '). Загружаю...')
        download(BASE .. 'Shishani_Center.lua', candidateFile, function(success, reason)
            if not success then
                inform('Ошибка загрузки: ' .. tostring(reason))
                busy = false
                return
            end
            local utf8source = readAll(candidateFile)
            os.remove(candidateFile)
            if not utf8source or #utf8source < MIN_SIZE then
                inform('Файл обновления пустой или слишком короткий.')
                busy = false
                return
            end
            -- UTF-8 source is kept readable on GitHub; game script needs CP1251.
            local ansiOK, ansi = pcall(function() return u8:decode(utf8source) end)
            if not ansiOK or not ansi then
                inform('Ошибка кодировки обновления.')
                busy = false
                return
            end
            local actual = ansi:match([[script_version%s*%(%s*["']([%d%.]+)["']%s*%)]])
            if actual ~= remote or not ansi:find('script_name', 1, true) then
                inform('Версия файла не совпадает с version.txt.')
                busy = false
                return
            end
            local chunk, syntaxErr = loadstring(ansi, '@Shishani_Center.lua')
            if not chunk then
                inform('Обновление содержит ошибку Lua. Старый файл сохранён.')
                print('Shishani update parse error: ' .. tostring(syntaxErr))
                busy = false
                return
            end
            local staged = target .. '.new'
            if not writeAll(staged, ansi) then
                inform('Не удалось записать обновление на диск.')
                busy = false
                return
            end
            os.remove(backup)
            if doesFileExist(target) and not os.rename(target, backup) then
                os.remove(staged)
                inform('Не удалось создать резервную копию.')
                busy = false
                return
            end
            if not os.rename(staged, target) then
                os.rename(backup, target)
                inform('Не удалось установить обновление. Старый файл восстановлен.')
                busy = false
                return
            end
            inform('Версия ' .. remote .. ' установлена. Перезапусти игру для применения.')
            busy = false
        end)
    end)
end

function main()
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand('shupdate', function() performCheck(true) end)
    wait(3000)
    performCheck(false)
    while true do
        wait(3000)
        if not busy and (getGameTimer() < lastCheck or getGameTimer() - lastCheck >= CHECK_EVERY_MS) then
            performCheck(false)
        end
    end
end
