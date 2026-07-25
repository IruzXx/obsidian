-- CrashHandler.lua
-- Addon untuk Obsidian Library
-- Handle errors gracefully, auto-restart script, prevent infinite crash loops
-- Author: IruzXx

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))
local RunService = cloneref(game:GetService("RunService"))
local Players = cloneref(game:GetService("Players"))

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local CrashHandler = {
    Library = nil,

    -- Pengaturan
    EnableAutoRestart = true,
    MaxRetries = 3,
    RetryDelay = 2,           -- detik sebelum retry
    CooldownTime = 60,       -- cooldown antar crash (detik)

    -- State internal
    _crashCount = 0,
    _lastCrashTime = 0,
    _isRestarting = false,
    _crashLogs = {},
    _maxLogs = 50,
    _originalFunctions = {},
    _heartbeatConnection = nil,
    _statsRefreshLoop = nil,
    _logsRefreshLoop = nil,

    -- Callbacks
    OnCrash = nil,           -- function(error, stack) called saat crash
    OnRestart = nil,         -- function(attempt) called saat restart
    OnMaxRetriesExceeded = nil, -- function() called saat max retries reached

    -- Export
    ExportCallback = nil,     -- function(crashData) - untuk export ke webhook/file
}

-- =========================================================
--                    SETUP
-- =========================================================

function CrashHandler:SetLibrary(Library)
    assert(Library, "[CrashHandler] Library tidak boleh nil")
    CrashHandler.Library = Library
end

-- =========================================================
--                    INTERNAL HELPERS
-- =========================================================

local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function formatStack(traceback)
    if not traceback then return "No stack trace" end
    -- Extract relevant lines dari stack trace
    local lines = {}
    for line in traceback:gmatch("[^\r\n]+") do
        if line:find("%.lua") or line:find("stack traceback") then
            table.insert(lines, line)
        end
    end
    return table.concat(lines, "\n")
end

local function canRestart()
    local now = os.time()

    -- Cooldown check
    if now - CrashHandler._lastCrashTime < CrashHandler.CooldownTime then
        return false, "Cooldown active"
    end

    -- Max retries check
    if CrashHandler._crashCount >= CrashHandler.MaxRetries then
        return false, "Max retries exceeded"
    end

    -- Already restarting check
    if CrashHandler._isRestarting then
        return false, "Already restarting"
    end

    return true
end

-- =========================================================
--                    SAFE WRAPPER
-- =========================================================

--- Bungkus fungsi dengan error handler
--- @param name string Nama fungsi (untuk logging)
--- @param func function Fungsi yang akan dibungkus
--- @param ... any Argumen untuk fungsi
--- @return boolean success, any... hasil
function CrashHandler:SafeCall(name, func, ...)
    local args = {...}

    local success, result = pcall(function()
        return func(table.unpack(args, 1, #args))
    end)

    if not success then
        CrashHandler:LogError(name, result)
        return false, result
    end

    return true, result
end

--- Wrap semua metode dari tabel dengan error handler
--- @param obj table Object yang metodenya akan di-wrap
--- @param name string Nama object (untuk logging)
--- @return table wrapped object
function CrashHandler:WrapObject(obj, name)
    local wrapped = {}
    name = name or "Object"

    for key, value in pairs(obj) do
        if type(value) == "function" then
            wrapped[key] = function(...)
                return CrashHandler:SafeCall(name .. ":" .. tostring(key), value, ...)
            end
        else
            wrapped[key] = value
        end
    end

    return wrapped
end

-- =========================================================
--                    ERROR LOGGING
-- =========================================================

function CrashHandler:LogError(context, errorMsg, traceback)
    local timestamp = getTimestamp()
    local stack = formatStack(traceback or debug.traceback())

    local logEntry = {
        timestamp = timestamp,
        context = context or "Unknown",
        error = tostring(errorMsg),
        stack = stack,
        player = Players.LocalPlayer and Players.LocalPlayer.Name or "Unknown",
    }

    -- Simpan ke memory
    table.insert(CrashHandler._crashLogs, 1, logEntry)

    -- Batasi jumlah logs
    while #CrashHandler._crashLogs > CrashHandler._maxLogs do
        table.remove(CrashHandler._crashLogs)
    end

    -- Update crash count & time
    CrashHandler._crashCount += 1
    CrashHandler._lastCrashTime = os.time()

    -- Print ke console
    warn(string.format(
        "[CrashHandler] %s | Context: %s | Error: %s",
        timestamp, context, tostring(errorMsg)
    ))

    -- Callback user
    if CrashHandler.OnCrash then
        pcall(CrashHandler.OnCrash, errorMsg, stack)
    end

    -- Export callback
    if CrashHandler.ExportCallback then
        pcall(CrashHandler.ExportCallback, logEntry)
    end

    return logEntry
end

function CrashHandler:GetLogs(count)
    count = count or CrashHandler._maxLogs
    local logs = {}
    for i = 1, math.min(count, #CrashHandler._crashLogs) do
        table.insert(logs, CrashHandler._crashLogs[i])
    end
    return logs
end

function CrashHandler:ClearLogs()
    CrashHandler._crashLogs = {}
end

-- =========================================================
--                    AUTO RESTART
-- =========================================================

function CrashHandler:AttemptRestart(attempt)
    attempt = attempt or 1

    local canDo, reason = canRestart()

    if not canDo then
        warn(string.format("[CrashHandler] Cannot restart: %s", reason))

        if reason == "Max retries exceeded" and CrashHandler.OnMaxRetriesExceeded then
            pcall(CrashHandler.OnMaxRetriesExceeded)
        end
        return false
    end

    CrashHandler._isRestarting = true

    task.spawn(function()
        -- Tunggu delay
        task.wait(CrashHandler.RetryDelay)

        warn(string.format("[CrashHandler] Restarting script... (Attempt %d/%d)",
            attempt, CrashHandler.MaxRetries))

        -- Callback
        if CrashHandler.OnRestart then
            pcall(CrashHandler.OnRestart, attempt)
        end

        CrashHandler._isRestarting = false
    end)

    return true
end

function CrashHandler:ResetCrashCount()
    CrashHandler._crashCount = 0
end

function CrashHandler:GetStats()
    return {
        crashCount = CrashHandler._crashCount,
        lastCrashTime = CrashHandler._lastCrashTime,
        canRestart = canRestart(),
        logsCount = #CrashHandler._crashLogs,
        isRestarting = CrashHandler._isRestarting,
    }
end

-- =========================================================
--                    GLOBAL ERROR HANDLER
-- =========================================================

-- Simpan original settings
local originalSettings = {
    identity = nil,
}

function CrashHandler:EnableGlobalHandler()
    -- Hook to RunService heartbeat for detect crashes
    CrashHandler._heartbeatConnection = RunService.Heartbeat:Connect(function()
        -- Periodic health check can be added here
    end)
end

function CrashHandler:DisableGlobalHandler()
    -- Disconnect heartbeat
    if CrashHandler._heartbeatConnection then
        CrashHandler._heartbeatConnection:Disconnect()
        CrashHandler._heartbeatConnection = nil
    end

    -- Disconnect UI refresh loops
    if CrashHandler._statsRefreshLoop then
        CrashHandler._statsRefreshLoop:Disconnect()
        CrashHandler._statsRefreshLoop = nil
    end
    if CrashHandler._logsRefreshLoop then
        CrashHandler._logsRefreshLoop:Disconnect()
        CrashHandler._logsRefreshLoop = nil
    end
end

-- =========================================================
--                    WEBHOOK EXPORT
-- =========================================================

function CrashHandler:ExportToWebhook(webhookUrl, crashData)
    if not webhookUrl or webhookUrl == "" then
        return false, "Webhook URL empty"
    end

    local data = {
        ["embeds"] = {{
            ["title"] = "Crash Report",
            ["color"] = 15158332, -- merah
            ["fields"] = {
                {
                    ["name"] = "Player",
                    ["value"] = crashData.player or "Unknown",
                    ["inline"] = true
                },
                {
                    ["name"] = "Context",
                    ["value"] = crashData.context or "Unknown",
                    ["inline"] = true
                },
                {
                    ["name"] = "Error",
                    ["value"] = string.format("```\n%s\n```", crashData.error or "N/A"),
                    ["inline"] = false
                },
            },
            ["footer"] = {
                ["text"] = string.format("Timestamp: %s | Crash #%d",
                    crashData.timestamp or "N/A",
                    CrashHandler._crashCount)
            }
        }}
    }

    local success, err = pcall(function()
        local response = HttpService:PostAsync(webhookUrl, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
        return response
    end)

    if not success then
        return false, tostring(err)
    end

    return true
end

-- =========================================================
--                    UI SECTION
-- =========================================================

function CrashHandler:BuildCrashSection(Tab, GroupboxName)
    assert(Tab, "[CrashHandler] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Crash Handler", "shield-alert")

    local StatusLabel
    local LogsLabel

    -- Stats display
    local function RefreshStats()
        local stats = CrashHandler:GetStats()

        local status = string.format(
            "Crashes: %d/%d | Last: %s | Status: %s",
            stats.crashCount,
            CrashHandler.MaxRetries,
            stats.lastCrashTime > 0
                and os.date("%H:%M:%S", stats.lastCrashTime)
                or "Never",
            stats.canRestart and "Ready" or "Cooldown"
        )

        if StatusLabel then
            StatusLabel:SetText(status)
        end
    end

    -- Logs display
    local function RefreshLogs()
        if not LogsLabel then return end

        local logs = CrashHandler:GetLogs(5)
        if #logs == 0 then
            LogsLabel:SetText("(no crash logs)")
            return
        end

        local lines = {}
        for i, log in ipairs(logs) do
            table.insert(lines, string.format(
                "[%s] %s: %s",
                log.timestamp:sub(12, 19), -- hanya HH:MM:SS
                log.context,
                log.error:sub(1, 40) .. (log.error:len() > 40 and "..." or "")
            ))
        end

        LogsLabel:SetText(table.concat(lines, "\n"))
    end

    -- Toggle auto restart
    Box:AddToggle("CH_AutoRestart", {
        Text = "Auto Restart on Crash",
        Default = CrashHandler.EnableAutoRestart,
        Tooltip = "Otomatis restart script setelah crash",
        Callback = function(Value)
            CrashHandler.EnableAutoRestart = Value
        end,
    })

    -- Max retries slider
    Box:AddSlider("CH_MaxRetries", {
        Text = "Max Retries",
        Default = CrashHandler.MaxRetries,
        Min = 1,
        Max = 10,
        Rounding = 0,
        Suffix = "",
        Callback = function(Value)
            CrashHandler.MaxRetries = math.max(1, math.floor(Value))
        end,
    })

    -- Retry delay slider
    Box:AddSlider("CH_RetryDelay", {
        Text = "Retry Delay",
        Default = CrashHandler.RetryDelay,
        Min = 1,
        Max = 30,
        Rounding = 0,
        Suffix = "s",
        Callback = function(Value)
            CrashHandler.RetryDelay = math.max(1, Value)
        end,
    })

    -- Cooldown slider
    Box:AddSlider("CH_Cooldown", {
        Text = "Cooldown",
        Default = CrashHandler.CooldownTime,
        Min = 10,
        Max = 300,
        Rounding = 0,
        Suffix = "s",
        Callback = function(Value)
            CrashHandler.CooldownTime = math.max(10, Value)
        end,
    })

    Box:AddDivider()

    -- Status label
    StatusLabel = Box:AddLabel("Stats: Loading...", false)

    -- Logs label
    LogsLabel = Box:AddLabel("(no crash logs)", true)

    Box:AddDivider()

    -- Buttons
    Box:AddButton({
        Text = "Refresh Stats",
        Func = function()
            RefreshStats()
            RefreshLogs()
        end,
    })

    Box:AddButton({
        Text = "Clear Logs",
        Func = function()
            CrashHandler:ClearLogs()
            CrashHandler:ResetCrashCount()
            RefreshStats()
            RefreshLogs()
            if CrashHandler.Library then
                CrashHandler.Library:Notify({
                    Title = "CrashHandler",
                    Description = "Logs cleared",
                    Time = 2,
                })
            end
        end,
    })

    Box:AddButton({
        Text = "Export Logs",
        Func = function()
            local logs = CrashHandler:GetLogs(CrashHandler._maxLogs)
            local content = HttpService:JSONEncode(logs)
            pcall(setclipboard, content)
            if CrashHandler.Library then
                CrashHandler.Library:Notify({
                    Title = "CrashHandler",
                    Description = "Logs copied to clipboard",
                    Time = 2,
                })
            end
        end,
    })

    -- Auto refresh using heartbeat connections (cleaned up properly)
    CrashHandler._statsRefreshLoop = RunService.Heartbeat:Connect(function()
        task.wait(5)
        RefreshStats()
    end)

    CrashHandler._logsRefreshLoop = RunService.Heartbeat:Connect(function()
        task.wait(2)
        RefreshLogs()
    end)

    return Box
end

-- =========================================================
--                    INIT
-- =========================================================

-- Auto-enable global handler
CrashHandler:EnableGlobalHandler()

-- Cleanup saat script unload
task.defer(function()
    if CrashHandler.Library then
        CrashHandler.Library:OnUnload(function()
            CrashHandler:DisableGlobalHandler()
        end)
    end
end)

return CrashHandler
