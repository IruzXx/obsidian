-- TelemetryManager.lua
-- Addon untuk Obsidian Library
-- Anonymous usage statistics (privacy-focused)
-- Author: IruzXx

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local isfolder = isfolder

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local TelemetryManager = {
    Library = nil,

    -- Settings
    Enabled = false,  -- Default off - user harus opt-in
    AnonymousId = "",  -- Generated unique ID
    Endpoint = "",  -- Telemetry server URL

    -- Data
    Data = {
        sessionId = "",
        sessionStart = 0,
        events = {},
        counters = {},
        gauges = {},
    },

    -- Privacy
    PrivacyMode = true,  -- Don't send identifiable data

    -- Storage
    Folder = "ObsidianTelemetry",

    -- Internal connections (for cleanup)
    _statusRefreshLoop = nil,
}

-- =========================================================
--                    TYPE DEFINITIONS
-- =========================================================

export type TelemetryEvent = {
    name: string,
    value: number,
    timestamp: number,
    sessionId: string,
}

export type TelemetryCounter = {
    name: string,
    value: number,
    delta: number,
}

-- =========================================================
--                    SETUP
-- =========================================================

function TelemetryManager:SetLibrary(Library)
    assert(Library, "[TelemetryManager] Library tidak boleh nil")
    TelemetryManager.Library = Library
end

function TelemetryManager:Configure(config)
    if config.enabled ~= nil then TelemetryManager.Enabled = config.enabled end
    if config.endpoint then TelemetryManager.Endpoint = config.endpoint end
    if config.privacyMode ~= nil then TelemetryManager.PrivacyMode = config.privacyMode end
end

-- =========================================================
--                    ANONYMOUS ID
-- =========================================================

function TelemetryManager:_GenerateAnonymousId()
    -- Seed math.random for better entropy
    math.randomseed(os.time() + (math.random(1, 10000)))

    -- Generate random ID that cannot be traced to player
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local id = {}

    for i = 1, 16 do
        local idx = math.random(1, #chars)
        table.insert(id, chars:sub(idx, idx))
    end

    return table.concat(id)
end

function TelemetryManager:_GetOrCreateAnonymousId()
    if TelemetryManager.AnonymousId == "" then
        TelemetryManager.AnonymousId = TelemetryManager:_GenerateAnonymousId()
    end
    return TelemetryManager.AnonymousId
end

-- =========================================================
--                    SESSION
-- =========================================================

function TelemetryManager:StartSession()
    TelemetryManager.Data.sessionId = HttpService:GenerateGUID(false)
    TelemetryManager.Data.sessionStart = os.time()
    TelemetryManager:_GenerateAnonymousId()

    -- Record session start
    TelemetryManager:TrackEvent("session_start", 1)
end

function TelemetryManager:EndSession()
    TelemetryManager:TrackEvent("session_duration", os.time() - TelemetryManager.Data.sessionStart)
    TelemetryManager:Flush()

    TelemetryManager.Data.sessionId = ""
    TelemetryManager.Data.events = {}
    TelemetryManager.Data.counters = {}
end

-- =========================================================
--                    TRACKING
-- =========================================================

--- Track event
--- @param name string Event name
--- @param value number Event value
function TelemetryManager:TrackEvent(name: string, value: number)
    if not TelemetryManager.Enabled then return end

    local event: TelemetryEvent = {
        name = name,
        value = value,
        timestamp = os.time(),
        sessionId = TelemetryManager.Data.sessionId,
    }

    table.insert(TelemetryManager.Data.events, event)
end

--- Increment counter
--- @param name string Counter name
--- @param delta number Amount to increment (default 1)
function TelemetryManager:IncrementCounter(name: string, delta: number?)
    if not TelemetryManager.Enabled then return end

    delta = delta or 1

    if not TelemetryManager.Data.counters[name] then
        TelemetryManager.Data.counters[name] = 0
    end

    TelemetryManager.Data.counters[name] += delta
    TelemetryManager:TrackEvent("counter_" .. name, TelemetryManager.Data.counters[name])
end

--- Set gauge value
--- @param name string Gauge name
--- @param value number Current value
function TelemetryManager:SetGauge(name: string, value: number)
    if not TelemetryManager.Enabled then return end

    TelemetryManager.Data.gauges[name] = value
    TelemetryManager:TrackEvent("gauge_" .. name, value)
end

-- =========================================================
--                    AGGREGATIONS
-- =========================================================

--- Get summary statistics
function TelemetryManager:GetSummary()
    local summary = {
        totalEvents = #TelemetryManager.Data.events,
        sessionDuration = os.time() - TelemetryManager.Data.sessionStart,
        eventTypes = {},
        totalCounters = 0,
    }

    -- Count event types
    for _, event in ipairs(TelemetryManager.Data.events) do
        summary.eventTypes[event.name] = (summary.eventTypes[event.name] or 0) + 1
    end

    -- Sum counters
    for _, value in pairs(TelemetryManager.Data.counters) do
        summary.totalCounters += value
    end

    return summary
end

-- =========================================================
--                    FLUSH & EXPORT
-- =========================================================

function TelemetryManager:Flush()
    if not TelemetryManager.Enabled or #TelemetryManager.Data.events == 0 then
        return 0
    end

    local payload = TelemetryManager:_BuildPayload()
    TelemetryManager.Data.events = {}  -- Clear after build

    -- Send to endpoint
    if TelemetryManager.Endpoint ~= "" then
        task.spawn(function()
            local success, err = pcall(function()
                local data = HttpService:JSONEncode(payload)
                HttpService:PostAsync(
                    TelemetryManager.Endpoint,
                    data,
                    Enum.HttpContentType.ApplicationJson
                )
            end)

            if not success then
                warn("[TelemetryManager] Failed to send telemetry:", err)
            end
        end)
    end

    return #payload.events
end

function TelemetryManager:_BuildPayload()
    local data = {
        anonymousId = TelemetryManager:_GetOrCreateAnonymousId(),
        sessionId = TelemetryManager.Data.sessionId,
        timestamp = os.time(),
        sessionStart = TelemetryManager.Data.sessionStart,
        events = TelemetryManager.Data.events,
        counters = TelemetryManager.Data.counters,
        gauges = TelemetryManager.Data.gauges,
    }

    -- Privacy: remove atau hash identifiable data
    if TelemetryManager.PrivacyMode then
        -- Don't include player-specific data
    end

    return data
end

-- =========================================================
--                    UI SECTION
-- =========================================================

function TelemetryManager:BuildTelemetrySection(Tab, GroupboxName)
    assert(Tab, "[TelemetryManager] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Telemetry", "activity")

    local StatusLabel

    -- Enable toggle
    Box:AddToggle("TM_Enable", {
        Text = "Enable Telemetry",
        Default = TelemetryManager.Enabled,
        Tooltip = "Help improve the script by sending anonymous usage statistics",
        Callback = function(Value)
            TelemetryManager.Enabled = Value

            if Value then
                TelemetryManager:StartSession()
            else
                TelemetryManager:EndSession()
            end
        end,
    })

    Box:AddDivider()

    -- Privacy info
    Box:AddLabel("Privacy Information:", false)
    Box:AddLabel(function()
        return "Anonymous ID: " .. TelemetryManager:_GetOrCreateAnonymousId():sub(1, 8) .. "..."
    end, true)
    Box:AddLabel("- No personal data collected", true)
    Box:AddLabel("- No Roblox username/ID", true)
    Box:AddLabel("- Cannot be used to identify you", true)

    Box:AddDivider()

    -- Status
    StatusLabel = Box:AddLabel("Status: Not tracking", false)

    Box:AddButton({
        Text = "View Summary",
        Func = function()
            local summary = TelemetryManager:GetSummary()

            if TelemetryManager.Library then
                TelemetryManager.Library:Notify({
                    Title = "Telemetry Summary",
                    Description = string.format(
                        "Events: %d\nSession: %ds\nCounters: %d",
                        summary.totalEvents,
                        summary.sessionDuration,
                        summary.totalCounters
                    ),
                    Time = 4,
                })
            end
        end,
    })

    Box:AddButton({
        Text = "Flush Now",
        Func = function()
            local flushed = TelemetryManager:Flush()
            if TelemetryManager.Library then
                TelemetryManager.Library:Notify({
                    Title = "Telemetry",
                    Description = string.format("Flushed %d events", flushed),
                    Time = 2,
                })
            end
        end,
    })

    -- Auto update status using heartbeat (properly cleaned up)
    TelemetryManager._statusRefreshLoop = RunService.Heartbeat:Connect(function()
        task.wait(3)

        local summary = TelemetryManager:GetSummary()
        StatusLabel:SetText(string.format(
            "Status: %s | Events: %d | Duration: %ds",
            TelemetryManager.Enabled and "Tracking" or "Off",
            summary.totalEvents,
            summary.sessionDuration
        ))
    end)

    return Box
end

-- =========================================================
--                    INIT
-- =========================================================

-- Auto start session if enabled
if TelemetryManager.Enabled then
    TelemetryManager:StartSession()
end

-- Cleanup
task.defer(function()
    if TelemetryManager.Library then
        TelemetryManager.Library:OnUnload(function()
            TelemetryManager:EndSession()

            -- Disconnect UI refresh loop
            if TelemetryManager._statusRefreshLoop then
                TelemetryManager._statusRefreshLoop:Disconnect()
                TelemetryManager._statusRefreshLoop = nil
            end
        end)
    end
end)

return TelemetryManager
