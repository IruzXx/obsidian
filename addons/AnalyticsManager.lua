-- AnalyticsManager.lua
-- Addon untuk Obsidian Library
-- Track feature usage, script performance, crash logs
-- Author: IruzXx

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local isfolder = (isfolder or function() return false end)
local isfile = (isfile or function() return false end)
local listfiles = (listfiles or function() return {} end)
local makefolder = (makefolder or function() end)
local readfile = (readfile or function() return nil end)
local writefile = (writefile or function() end)
local delfile = (delfile or function() end)

-- Inline ensureFolders (replaces Utils dependency)
local function ensureFolders(path: string): boolean
    local current = ""
    for part in string.gmatch(path, "[^/]+") do
        current = current == "" and part or (current .. "/" .. part)
        if not isfolder(current) then
            local ok = pcall(makefolder, current)
            if not ok then return false end
        end
    end
    return true
end

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local AnalyticsManager = {
    Library = nil,

    -- Identitas script
    ScriptName = "ObsidianScript",
    ScriptVersion = "1.0.0",

    -- Pengaturan
    EnableTracking = true,
    BatchInterval = 30,          -- detik antara batch send
    MaxEventsPerBatch = 100,
    PersistLocally = true,       -- Simpan ke file

    -- Storage
    Folder = "ObsidianAnalytics",
    Events = {},
    PerformanceMetrics = {},

    -- Webhook (opsional)
    WebhookURL = "",

    -- State
    _sessionId = nil,
    _sessionStart = 0,
    _eventsQueue = {},
    _startTime = 0,
    _lastBatchTime = 0,
    _summaryRefreshLoop = nil,
}

-- =========================================================
--                    EVENT TYPES
-- =========================================================

export type EventType =
    "feature_used"
    | "toggle_enabled"
    | "toggle_disabled"
    | "button_clicked"
    | "slider_changed"
    | "dropdown_changed"
    | "error_occurred"
    | "script_started"
    | "script_unloaded"
    | "config_loaded"
    | "theme_changed"

export type AnalyticsEvent = {
    type: EventType,
    name: string,
    value: any,
    timestamp: number,
    metadata: { [string]: any },
}

export type PerformanceMetric = {
    name: string,
    startTime: number,
    endTime: number,
    duration: number,
    metadata: { [string]: any },
}

-- =========================================================
--                    SETUP
-- =========================================================

function AnalyticsManager:SetLibrary(Library)
    assert(Library, "[AnalyticsManager] Library tidak boleh nil")
    AnalyticsManager.Library = Library
end

function AnalyticsManager:Configure(Config)
    if Config.scriptName then AnalyticsManager.ScriptName = Config.scriptName end
    if Config.scriptVersion then AnalyticsManager.ScriptVersion = Config.scriptVersion end
    if Config.enableTracking ~= nil then AnalyticsManager.EnableTracking = Config.enableTracking end
    if Config.batchInterval then AnalyticsManager.BatchInterval = Config.batchInterval end
    if Config.webhookURL then AnalyticsManager.WebhookURL = Config.webhookURL end
    if Config.folder then AnalyticsManager.Folder = Config.folder end
end

-- =========================================================
--                    SESSION MANAGEMENT
-- =========================================================

function AnalyticsManager:StartSession()
    if AnalyticsManager._sessionId then
        return AnalyticsManager._sessionId
    end

    AnalyticsManager._sessionId = HttpService:GenerateGUID(false)
    AnalyticsManager._sessionStart = os.time()
    AnalyticsManager._startTime = tick()
    AnalyticsManager._lastBatchTime = tick()

    -- Track session start
    AnalyticsManager:TrackEvent("script_started", "session_start", {
        scriptName = AnalyticsManager.ScriptName,
        version = AnalyticsManager.ScriptVersion,
    })

    -- Start batch sender
    AnalyticsManager:_StartBatchSender()

    return AnalyticsManager._sessionId
end

function AnalyticsManager:EndSession()
    if not AnalyticsManager._sessionId then return end

    local sessionDuration = tick() - AnalyticsManager._startTime

    -- Track session end
    AnalyticsManager:TrackEvent("script_unloaded", "session_end", {
        duration = sessionDuration,
    })

    -- Flush remaining events
    AnalyticsManager:FlushEvents()

    AnalyticsManager._sessionId = nil
end

function AnalyticsManager:GetSessionId()
    return AnalyticsManager._sessionId
end

-- =========================================================
--                    EVENT TRACKING
-- =========================================================

--- Track sebuah event
--- @param eventType EventType
--- @param name string
--- @param value any
--- @param metadata table?
function AnalyticsManager:TrackEvent(eventType: EventType, name: string, value: any, metadata: {}?)
    if not AnalyticsManager.EnableTracking then return end

    local event: AnalyticsEvent = {
        type = eventType,
        name = name,
        value = value,
        timestamp = os.time(),
        metadata = metadata or {},
    }

    -- Add session & player info
    event.metadata.sessionId = AnalyticsManager._sessionId
    event.metadata.playerId = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
    event.metadata.playerName = Players.LocalPlayer and Players.LocalPlayer.Name or "Unknown"

    -- Add to queue
    table.insert(AnalyticsManager._eventsQueue, event)

    -- Persist locally
    if AnalyticsManager.PersistLocally then
        AnalyticsManager:_PersistEvent(event)
    end

    -- Check if should send batch
    if #AnalyticsManager._eventsQueue >= AnalyticsManager.MaxEventsPerBatch then
        AnalyticsManager:FlushEvents()
    end
end

-- Shortcut methods untuk event types
function AnalyticsManager:TrackFeatureUsed(featureName: string, metadata: {}?)
    AnalyticsManager:TrackEvent("feature_used", featureName, 1, metadata)
end

function AnalyticsManager:TrackToggle(name: string, enabled: boolean, metadata: {}?)
    AnalyticsManager:TrackEvent(
        enabled and "toggle_enabled" or "toggle_disabled",
        name,
        enabled and 1 or 0,
        metadata
    )
end

function AnalyticsManager:TrackButtonClick(name: string, metadata: {}?)
    AnalyticsManager:TrackEvent("button_clicked", name, 1, metadata)
end

function AnalyticsManager:TrackSliderChange(name: string, value: number, metadata: {}?)
    AnalyticsManager:TrackEvent("slider_changed", name, value, metadata)
end

function AnalyticsManager:TrackDropdownChange(name: string, value: any, metadata: {}?)
    AnalyticsManager:TrackEvent("dropdown_changed", name, value, metadata)
end

function AnalyticsManager:TrackError(errorMsg: string, metadata: {}?)
    AnalyticsManager:TrackEvent("error_occurred", "error", errorMsg, metadata)
end

function AnalyticsManager:TrackConfigLoaded(configName: string, metadata: {}?)
    AnalyticsManager:TrackEvent("config_loaded", configName, 1, metadata)
end

function AnalyticsManager:TrackThemeChange(themeName: string, metadata: {}?)
    AnalyticsManager:TrackEvent("theme_changed", themeName, 1, metadata)
end

-- =========================================================
--                    PERFORMANCE TRACKING
-- =========================================================

--- Start timing untuk sebuah operation
--- @param name string
--- @param metadata table?
--- @return function endFunction - call ini untuk stop timing
function AnalyticsManager:StartTimer(name: string, metadata: {}?)
    local startTime = tick()

    return function(endMetadata: {}?)
        local endTime = tick()
        local duration = endTime - startTime

        local metric: PerformanceMetric = {
            name = name,
            startTime = startTime,
            endTime = endTime,
            duration = duration,
            metadata = metadata or endMetadata or {},
        }

        table.insert(AnalyticsManager.PerformanceMetrics, metric)

        -- Track as event
        if AnalyticsManager.EnableTracking then
            AnalyticsManager:TrackEvent("feature_used", "perf_" .. name, duration, metadata)
        end

        return duration
    end
end

--- Track FPS
function AnalyticsManager:TrackFPS()
    local fps = math.floor(1 / RunService.RenderStepped:Wait())

    AnalyticsManager:TrackEvent("feature_used", "fps_sample", fps, {
        fps = fps,
        quality = fps >= 55 and "high" or (fps >= 30 and "medium" or "low"),
    })

    return fps
end

-- =========================================================
--                    BATCH & EXPORT
-- =========================================================

function AnalyticsManager:FlushEvents()
    if #AnalyticsManager._eventsQueue == 0 then return end

    local eventsToSend = AnalyticsManager._eventsQueue
    AnalyticsManager._eventsQueue = {}

    -- Create batch payload
    local payload = {
        scriptName = AnalyticsManager.ScriptName,
        scriptVersion = AnalyticsManager.ScriptVersion,
        sessionId = AnalyticsManager._sessionId,
        batchTime = os.time(),
        events = eventsToSend,
        performanceMetrics = AnalyticsManager.PerformanceMetrics,
    }

    -- Send to webhook if configured
    if AnalyticsManager.WebhookURL ~= "" then
        task.spawn(function()
            AnalyticsManager:_SendToWebhook(payload)
        end)
    end

    -- Save locally
    if AnalyticsManager.PersistLocally then
        AnalyticsManager:_SaveBatchLocally(payload)
    end

    AnalyticsManager._lastBatchTime = tick()

    return #eventsToSend
end

function AnalyticsManager:_SendToWebhook(payload)
    local success, err = pcall(function()
        local data = HttpService:JSONEncode(payload)
        local response = HttpService:PostAsync(
            AnalyticsManager.WebhookURL,
            data,
            Enum.HttpContentType.ApplicationJson
        )
        return response
    end)

    if not success then
        warn("[AnalyticsManager] Failed to send to webhook:", err)
    end
end

function AnalyticsManager:_StartBatchSender()
    task.spawn(function()
        while AnalyticsManager._sessionId do
            task.wait(AnalyticsManager.BatchInterval)

            local elapsed = tick() - AnalyticsManager._lastBatchTime
            if elapsed >= AnalyticsManager.BatchInterval and #AnalyticsManager._eventsQueue > 0 then
                AnalyticsManager:FlushEvents()
            end
        end
    end)
end

-- =========================================================
--                    LOCAL PERSISTENCE
-- =========================================================

function AnalyticsManager:_GetAnalyticsPath()
    return AnalyticsManager.Folder .. "/analytics"
end

function AnalyticsManager:_EnsureFolders()
    local path = AnalyticsManager:_GetAnalyticsPath()
    ensureFolders(path)
end

function AnalyticsManager:_PersistEvent(event)
    -- Simple persistence - add to daily file
    local date = os.date("%Y-%m-%d")
    local filepath = string.format("%s/%s.json", AnalyticsManager:_GetAnalyticsPath(), date)

    AnalyticsManager:_EnsureFolders()

    local existing = {}
    if isfile(filepath) then
        local ok, content = pcall(readfile, filepath)
        if ok and content then
            local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, content)
            if ok2 then
                existing = decoded
            end
        end
    end

    table.insert(existing, event)

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, existing)
    if ok then
        pcall(writefile, filepath, encoded)
    end
end

function AnalyticsManager:_SaveBatchLocally(payload)
    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local filepath = string.format("%s/batch_%s.json", AnalyticsManager:_GetAnalyticsPath(), timestamp)

    AnalyticsManager:_EnsureFolders()

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if ok then
        pcall(writefile, filepath, encoded)
    end
end

function AnalyticsManager:GetLocalEvents(count: number?)
    AnalyticsManager:_EnsureFolders()

    local events = {}
    local ok, files = pcall(listfiles, AnalyticsManager:_GetAnalyticsPath())

    if not ok or type(files) ~= "table" then
        return events
    end

    -- Sort by date (descending - newest first, longest strings first)
    table.sort(files, function(a, b)
        return #a > #b or (#a == #b and a < b)
    end)

    local collected = 0
    local maxCollect = count or 100

    for _, filepath in ipairs(files) do
        if collected >= maxCollect then break end

        local ok, content = pcall(readfile, filepath)
        if ok then
            local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, content)
            if ok2 then
                if decoded.events then
                    for _, event in ipairs(decoded.events) do
                        table.insert(events, event)
                        collected += 1
                        if collected >= maxCollect then break end
                    end
                end
            end
        end
    end

    return events
end

-- =========================================================
--                    ANALYTICS
-- =========================================================

function AnalyticsManager:GetSummary()
    local events = AnalyticsManager:GetLocalEvents(1000)

    local summary = {
        totalEvents = #events,
        eventTypes = {},
        topFeatures = {},
        errorCount = 0,
        sessionDuration = os.time() - AnalyticsManager._sessionStart,
    }

    -- Count event types
    local featureCounts = {}

    for _, event in ipairs(events) do
        -- Count by type
        summary.eventTypes[event.type] = (summary.eventTypes[event.type] or 0) + 1

        -- Count errors
        if event.type == "error_occurred" then
            summary.errorCount += 1
        end

        -- Count features
        if event.type == "feature_used" then
            featureCounts[event.name] = (featureCounts[event.name] or 0) + 1
        end
    end

    -- Sort top features
    local sorted = {}
    for name, count in pairs(featureCounts) do
        table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    summary.topFeatures = sorted

    return summary
end

-- =========================================================
--                    UI SECTION
-- =========================================================

function AnalyticsManager:BuildAnalyticsSection(Tab, GroupboxName)
    assert(Tab, "[AnalyticsManager] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Analytics", "bar-chart-2")

    local SummaryLabel
    local TopFeaturesLabel

    -- Toggle tracking
    Box:AddToggle("AM_EnableTracking", {
        Text = "Enable Analytics",
        Default = AnalyticsManager.EnableTracking,
        Tooltip = "Aktifkan/nonaktifkan tracking",
        Callback = function(Value)
            AnalyticsManager.EnableTracking = Value
        end,
    })

    Box:AddDivider()

    -- Summary label
    SummaryLabel = Box:AddLabel("Loading summary...", false)

    -- Top features label
    TopFeaturesLabel = Box:AddLabel("", true)

    Box:AddDivider()

    -- Buttons
    Box:AddButton({
        Text = "Refresh Summary",
        Func = function()
            local summary = AnalyticsManager:GetSummary()

            local lines = {
                string.format("Total Events: %d", summary.totalEvents),
                string.format("Errors: %d", summary.errorCount),
                string.format("Session: %ds", summary.sessionDuration),
            }

            SummaryLabel:SetText(table.concat(lines, "\n"))

            -- Top 5 features
            local topLines = { "Top Features:" }
            for i = 1, math.min(5, #summary.topFeatures) do
                local f = summary.topFeatures[i]
                table.insert(topLines, string.format("  %d. %s (%d)", i, f.name, f.count))
            end

            if #summary.topFeatures == 0 then
                table.insert(topLines, "  (no data)")
            end

            TopFeaturesLabel:SetText(table.concat(topLines, "\n"))
        end,
    })

    Box:AddButton({
        Text = "Export Analytics",
        Func = function()
            local events = AnalyticsManager:GetLocalEvents(500)
            local data = HttpService:JSONEncode({
                scriptName = AnalyticsManager.ScriptName,
                version = AnalyticsManager.ScriptVersion,
                exportTime = os.time(),
                events = events,
                summary = AnalyticsManager:GetSummary(),
            })

            pcall(setclipboard, data)

            if AnalyticsManager.Library then
                AnalyticsManager.Library:Notify({
                    Title = "Analytics",
                    Description = "Analytics data copied to clipboard",
                    Time = 3,
                })
            end
        end,
    })

    Box:AddButton({
        Text = "Clear Local Data",
        Risky = true,
        Func = function()
            local path = AnalyticsManager:_GetAnalyticsPath()
            local ok, files = pcall(listfiles, path)

            if ok and type(files) == "table" then
                for _, filepath in ipairs(files) do
                    pcall(delfile, filepath)
                end
            end

            if AnalyticsManager.Library then
                AnalyticsManager.Library:Notify({
                    Title = "Analytics",
                    Description = "Local analytics data cleared",
                    Time = 3,
                })
            end
        end,
    })

    -- Auto refresh using heartbeat (properly cleanup)
    AnalyticsManager._summaryRefreshLoop = RunService.Heartbeat:Connect(function()
        task.wait(10)
        local summary = AnalyticsManager:GetSummary()
        SummaryLabel:SetText(string.format(
            "Events: %d | Errors: %d | Session: %ds",
            summary.totalEvents, summary.errorCount, summary.sessionDuration
        ))
    end)

    return Box
end

function AnalyticsManager:Cleanup()
    -- Disconnect summary refresh loop
    if AnalyticsManager._summaryRefreshLoop then
        AnalyticsManager._summaryRefreshLoop:Disconnect()
        AnalyticsManager._summaryRefreshLoop = nil
    end
end

-- =========================================================
--                    INIT
-- =========================================================

-- Start session otomatis
AnalyticsManager:StartSession()

-- Cleanup saat unload
task.defer(function()
    if AnalyticsManager.Library then
        AnalyticsManager.Library:OnUnload(function()
            AnalyticsManager:EndSession()
            AnalyticsManager:Cleanup()
        end)
    end
end)

return AnalyticsManager
