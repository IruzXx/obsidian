--[[
    Obsidian UI Library - Full Feature Demo
    Showcases all addons in a comprehensive example
    Author: IruzXx

    IMPORTANT: For production, deploy files to your repo and update LOAD_MODE.
    For local testing, set LOAD_MODE = "local"
--]]

-- =========================================================
--                    CONFIGURATION
-- =========================================================

local CONFIG = {
    ScriptName = "Obsidian Demo",
    ScriptVersion = "1.0.0",
    WebhookURL = "", -- Set your webhook URL for crash reports
    TelemetryEndpoint = "", -- Set your telemetry endpoint

    -- LOAD_MODE: "remote" (from repo) or "local" (from same directory)
    -- For testing: use "local"
    -- For production: use "remote" after deploying
    LOAD_MODE = "remote",

    -- Your repo URL (update this after pushing to GitHub)
    REPO_OWNER = "IruzXx",
    REPO_NAME = "obsidian",
    REPO_BRANCH = "main",
}

-- Get repo base URL
local function getRepoUrl()
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/",
        CONFIG.REPO_OWNER,
        CONFIG.REPO_NAME,
        CONFIG.REPO_BRANCH
    )
end

-- =========================================================
--                    LIBRARY LOADER
-- =========================================================

local function loadScript(path)
    local mode = CONFIG.LOAD_MODE

    if mode == "local" then
        -- Load from local files
        local success, result = pcall(loadfile, path)
        if success and result then
            return result()
        else
            return nil, "Failed to load local: " .. path .. " - " .. tostring(result)
        end
    else
        -- Load from remote repo
        local repoUrl = getRepoUrl()
        local url = repoUrl .. path
        local success, result = pcall(loadstring, game:HttpGet(url))
        if success and result then
            return result()
        else
            return nil, "Failed to load remote: " .. url
        end
    end
end

-- =========================================================
--                    LIBRARY SETUP
-- =========================================================

-- Load core library
local Library = loadScript("Library.lua")

-- Fallback to remote if local fails
if not Library then
    warn("Local Library.lua not found, trying remote...")
    local repoUrl = getRepoUrl()
    Library = loadstring(game:HttpGet(repoUrl .. "Library.lua"))()
end

if not Library then
    error("Failed to load Library! Please check your deployment.")
end

-- =========================================================
--                    LOAD ADDONS
-- =========================================================

local function loadAddon(name, path)
    local addon = loadScript(path)
    if not addon then
        warn(string.format("[%s] Not available (using fallback)", name))
        return nil
    end
    print(string.format("[%s] Loaded successfully", name))
    return addon
end

-- Load all official addons
local ThemeManager = loadAddon("ThemeManager", "addons/ThemeManager.lua")
local SaveManager = loadAddon("SaveManager", "addons/SaveManager.lua")
local CrashHandler = loadAddon("CrashHandler", "addons/CrashHandler.lua")
local AnalyticsManager = loadAddon("AnalyticsManager", "addons/AnalyticsManager.lua")
local TelemetryManager = loadAddon("TelemetryManager", "addons/TelemetryManager.lua")
local TranslatorManager = loadAddon("TranslatorManager", "addons/TranslatorManager.lua")
local SchedulerManager = loadAddon("SchedulerManager", "addons/SchedulerManager.lua")
local ShortcutManager = loadAddon("ShortcutManager", "addons/ShortcutManager.lua")

local Options = Library.Options
local Toggles = Library.Toggles

-- =========================================================
--                    ADDON INITIALIZATION
-- =========================================================

-- Configure Analytics
if AnalyticsManager then
    AnalyticsManager:Configure({
        scriptName = CONFIG.ScriptName,
        scriptVersion = CONFIG.ScriptVersion,
        enableTracking = true,
        batchInterval = 30,
        webhookURL = CONFIG.WebhookURL,
    })
end

-- Configure Telemetry (disabled by default - opt-in)
if TelemetryManager then
    TelemetryManager:Configure({
        enabled = false, -- User must opt-in
        endpoint = CONFIG.TelemetryEndpoint,
        privacyMode = true,
    })
end

-- Configure Crash Handler (set properties directly)
if CrashHandler then
    CrashHandler.EnableAutoRestart = true
    CrashHandler.MaxRetries = 3
    CrashHandler.RetryDelay = 2
    CrashHandler.CooldownTime = 60

    -- Set callbacks for CrashHandler
    CrashHandler.OnCrash = function(errorMsg, stack)
        print("[CrashHandler] Application crashed:", errorMsg)
        if AnalyticsManager then AnalyticsManager:TrackError(errorMsg, { stack = stack }) end
    end

    CrashHandler.OnRestart = function(attempt)
        print("[CrashHandler] Restarting... Attempt", attempt)
        Library:Notify({
            Title = "CrashHandler",
            Description = string.format("Restarting... Attempt %d", attempt),
            Time = 3,
        })
    end

    CrashHandler.OnMaxRetriesExceeded = function()
        print("[CrashHandler] Max retries exceeded!")
        Library:Notify({
            Title = "CrashHandler",
            Description = "Max retries exceeded. Please restart manually.",
            Time = 5,
        })
    end
end

-- =========================================================
--                    WINDOW SETUP
-- =========================================================

local Window = Library:CreateWindow({
    Title = CONFIG.ScriptName,
    Footer = string.format("v%s", CONFIG.ScriptVersion),
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- Create tabs
local Tabs = {
    Main = Window:AddTab("Main", "user"),
    Features = Window:AddTab("Features", "sparkles"),
    Analytics = Window:AddTab("Analytics", "bar-chart-2"),
    Scheduler = Window:AddTab("Scheduler", "clock"),
    Settings = Window:AddTab("Settings", "settings"),
}

-- =========================================================
--                    REGISTER SHORTCUTS
-- =========================================================

if ShortcutManager then
    ShortcutManager:Register("Toggle UI", "Toggle menu visibility", "general", {
        keybind = Enum.KeyCode.RightShift,
        action = function()
            Window:Toggle()
        end,
    })

    ShortcutManager:Register("Show Analytics", "Open analytics tab", "navigation", {
        action = function()
            Window:SelectTab(Tabs.Analytics)
        end,
    })

    ShortcutManager:Register("Emergency Stop", "Stop all scheduled tasks", "general", {
        action = function()
            if SchedulerManager then SchedulerManager:Stop() end
            Library:Notify({
                Title = "Scheduler",
                Description = "All tasks stopped",
                Time = 2,
            })
        end,
    })
end

-- =========================================================
--                    MAIN TAB - TOGGLES
-- =========================================================

local MainGroupbox = Tabs.Main:AddLeftGroupbox("Toggles", "toggle-left")

-- Feature toggles
MainGroupbox:AddToggle("GodMode", {
    Text = "God Mode",
    Default = false,
    Tooltip = "Become invincible",
})

MainGroupbox:AddToggle("SpeedHack", {
    Text = "Speed Hack",
    Default = false,
    Tooltip = "Increase walk speed",
})

MainGroupbox:AddToggle("InfiniteJump", {
    Text = "Infinite Jump",
    Default = false,
    Tooltip = "Jump without cooldown",
})

MainGroupbox:AddToggle("ESP", {
    Text = "ESP Players",
    Default = false,
    Tooltip = "Show player names through walls",
})

MainGroupbox:AddToggle("Aimbot", {
    Text = "Aimbot",
    Default = false,
    Tooltip = "Auto-aim at nearest player",
})

-- Toggle callbacks with analytics
Toggles.GodMode:OnChanged(function()
    local enabled = Toggles.GodMode.Value
    print("[GodMode]", enabled and "Enabled" or "Disabled")
    if AnalyticsManager then AnalyticsManager:TrackToggle("GodMode", enabled) end
end)

Toggles.SpeedHack:OnChanged(function()
    local enabled = Toggles.SpeedHack.Value
    print("[SpeedHack]", enabled and "Enabled" or "Disabled")
    if AnalyticsManager then AnalyticsManager:TrackToggle("SpeedHack", enabled) end
end)

Toggles.InfiniteJump:OnChanged(function()
    local enabled = Toggles.InfiniteJump.Value
    print("[InfiniteJump]", enabled and "Enabled" or "Disabled")
    if AnalyticsManager then AnalyticsManager:TrackToggle("InfiniteJump", enabled) end
end)

Toggles.ESP:OnChanged(function()
    local enabled = Toggles.ESP.Value
    print("[ESP]", enabled and "Enabled" or "Disabled")
    if AnalyticsManager then AnalyticsManager:TrackToggle("ESP", enabled) end
end)

Toggles.Aimbot:OnChanged(function()
    local enabled = Toggles.Aimbot.Value
    print("[Aimbot]", enabled and "Enabled" or "Disabled")
    if AnalyticsManager then AnalyticsManager:TrackToggle("Aimbot", enabled) end
end)

-- =========================================================
--                    MAIN TAB - SLIDERS
-- =========================================================

local SlidersGroupbox = Tabs.Main:AddRightGroupbox("Adjustments", "sliders-horizontal")

SlidersGroupbox:AddSlider("WalkSpeed", {
    Text = "Walk Speed",
    Default = 16,
    Min = 1,
    Max = 200,
    Rounding = 0,
    Suffix = "",
    Compact = true,
})

SlidersGroupbox:AddSlider("JumpPower", {
    Text = "Jump Power",
    Default = 50,
    Min = 1,
    Max = 200,
    Rounding = 0,
    Suffix = "",
    Compact = true,
})

SlidersGroupbox:AddSlider("FlySpeed", {
    Text = "Fly Speed",
    Default = 50,
    Min = 1,
    Max = 200,
    Rounding = 0,
    Suffix = "",
    Compact = true,
})

SlidersGroupbox:AddSlider("ESPAlpha", {
    Text = "ESP Transparency",
    Default = 0.5,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Compact = true,
})

-- Slider callbacks with analytics
Options.WalkSpeed:OnChanged(function()
    local value = Options.WalkSpeed.Value
    print("[WalkSpeed]", value)
    if AnalyticsManager then AnalyticsManager:TrackSliderChange("WalkSpeed", value) end
end)

Options.JumpPower:OnChanged(function()
    local value = Options.JumpPower.Value
    print("[JumpPower]", value)
    if AnalyticsManager then AnalyticsManager:TrackSliderChange("JumpPower", value) end
end)

Options.FlySpeed:OnChanged(function()
    local value = Options.FlySpeed.Value
    print("[FlySpeed]", value)
    if AnalyticsManager then AnalyticsManager:TrackSliderChange("FlySpeed", value) end
end)

Options.ESPAlpha:OnChanged(function()
    local value = Options.ESPAlpha.Value
    print("[ESPAlpha]", value)
    if AnalyticsManager then AnalyticsManager:TrackSliderChange("ESPAlpha", value) end
end)

-- =========================================================
--                    FEATURES TAB
-- =========================================================

-- --- Scheduler Demo ---
local SchedulerGroupbox = Tabs.Features:AddLeftGroupbox("Scheduler Demo", "clock")

SchedulerGroupbox:AddButton({
    Text = "Schedule Reminder (30s)",
    Tooltip = "Schedule a reminder in 30 seconds",
    Func = function()
        if SchedulerManager then
            SchedulerManager:ScheduleOnce("Reminder", 30, function()
                Library:Notify({
                    Title = "Scheduler",
                    Description = "30 seconds have passed!",
                    Time = 5,
                })
                if AnalyticsManager then AnalyticsManager:TrackEvent("scheduler", "reminder_triggered", 1, {}) end
            end)
        end
        Library:Notify({
            Title = "Scheduler",
            Description = "Reminder scheduled for 30 seconds",
            Time = 2,
        })
        if AnalyticsManager then AnalyticsManager:TrackButtonClick("ScheduleReminder") end
    end,
})

SchedulerGroupbox:AddButton({
    Text = "Schedule Auto-Save (1min)",
    Tooltip = "Schedule auto-save every minute",
    Func = function()
        if SchedulerManager then
            local taskId = SchedulerManager:ScheduleInterval("AutoSave", 60, function()
                print("[AutoSave] Saving configuration...")
                if AnalyticsManager then AnalyticsManager:TrackEvent("scheduler", "autosave", 1, {}) end
            end)
            Library:Notify({
                Title = "Scheduler",
                Description = string.format("Auto-save scheduled (Task #%d)", taskId),
                Time = 2,
            })
        end
        if AnalyticsManager then AnalyticsManager:TrackButtonClick("ScheduleAutoSave") end
    end,
})

SchedulerGroupbox:AddButton({
    Text = "List Active Tasks",
    Func = function()
        local count = 0
        if SchedulerManager then
            local tasks = SchedulerManager:GetAllTasks()
            for _ in pairs(tasks) do count = count + 1 end
        end
        Library:Notify({
            Title = "Scheduler",
            Description = string.format("Active tasks: %d", count),
            Time = 3,
        })
    end,
})

-- Build scheduler UI section
if SchedulerManager then
    SchedulerManager:BuildSchedulerSection(Tabs.Scheduler)
end

-- --- Translator Demo ---
if TranslatorManager then
    local TranslatorGroupbox = Tabs.Features:AddRightGroupbox("Language", "globe")

    -- Add custom translations
    TranslatorManager:AddTranslations("en", {
        ["feature.godmode"] = "God Mode",
        ["feature.speedhack"] = "Speed Hack",
        ["feature.esp"] = "ESP Players",
        ["notification.saved"] = "Configuration saved!",
        ["notification.loaded"] = "Configuration loaded!",
    })

    TranslatorManager:AddTranslations("id", {
        ["feature.godmode"] = "Mode Dewa",
        ["feature.speedhack"] = "Hack Kecepatan",
        ["feature.esp"] = "ESP Pemain",
        ["notification.saved"] = "Konfigurasi disimpan!",
        ["notification.loaded"] = "Konfigurasi dimuat!",
    })

    TranslatorManager:AddTranslations("jp", {
        ["feature.godmode"] = "ゴッドモード",
        ["feature.speedhack"] = "スピードハック",
        ["feature.esp"] = "ESPプレイヤー",
        ["notification.saved"] = "設定が保存されました！",
        ["notification.loaded"] = "設定が読み込まれました！",
    })

    TranslatorGroupbox:AddLabel("Current Language:")
    TranslatorGroupbox:AddLabel(function()
        return TranslatorManager:GetLanguage():upper() .. " - " .. (TranslatorManager.Languages[TranslatorManager.CurrentLanguage] or {}).nativeName or ""
    end, false)

    TranslatorGroupbox:AddButton({
        Text = "Test Translation Key",
        Func = function()
            local key = Options.TranslatorTestKey and Options.TranslatorTestKey.Value or "feature.godmode"
            local translated = TranslatorManager:Get(key)
            Library:Notify({
                Title = "Translation",
                Description = string.format("%s = %s", key, translated),
                Time = 3,
            })
        end,
    })

    TranslatorGroupbox:AddInput("TranslatorTestKey", {
        Text = "Translation Key",
        Placeholder = "e.g., feature.godmode",
        Default = "feature.godmode",
    })

    -- Build translator UI section
    TranslatorManager:BuildLanguageSection(Tabs.Features)
end

-- --- Shortcuts Demo ---
if ShortcutManager then
    local ShortcutsGroupbox = Tabs.Settings:AddLeftGroupbox("Shortcuts", "command")

    ShortcutsGroupbox:AddLabel("Press F1 to open Command Palette", false)

    ShortcutsGroupbox:AddButton({
        Text = "Open Command Palette",
        Func = function()
            ShortcutManager:ShowPalette()
            if AnalyticsManager then AnalyticsManager:TrackButtonClick("OpenPalette") end
        end,
    })

    -- Build shortcuts UI section
    ShortcutManager:BuildShortcutSection(Tabs.Settings)
end

-- --- Analytics Demo ---
if AnalyticsManager then
    local AnalyticsGroupbox = Tabs.Analytics:AddLeftGroupbox("Usage Tracking", "bar-chart-2")

    AnalyticsGroupbox:AddToggle("EnableAnalytics", {
        Text = "Enable Analytics",
        Default = true,
        Tooltip = "Track feature usage",
        Callback = function(Value)
            AnalyticsManager.EnableTracking = Value
            if Value then
                AnalyticsManager:StartSession()
            else
                AnalyticsManager:EndSession()
            end
        end,
    })

    AnalyticsGroupbox:AddButton({
        Text = "Track Custom Event",
        Func = function()
            AnalyticsManager:TrackEvent("custom", "button_click", 1, {
                source = "demo_button",
                timestamp = os.time(),
            })
            Library:Notify({
                Title = "Analytics",
                Description = "Custom event tracked!",
                Time = 2,
            })
        end,
    })

    AnalyticsGroupbox:AddButton({
        Text = "Track Feature Usage",
        Func = function()
            AnalyticsManager:TrackFeatureUsed("demo_feature", {
                source = "demo_tab",
            })
            Library:Notify({
                Title = "Analytics",
                Description = "Feature usage tracked!",
                Time = 2,
            })
        end,
    })

    AnalyticsGroupbox:AddButton({
        Text = "Get Summary",
        Func = function()
            local summary = AnalyticsManager:GetSummary()
            Library:Notify({
                Title = "Analytics Summary",
                Description = string.format(
                    "Events: %d\nErrors: %d\nSession: %ds",
                    summary.totalEvents,
                    summary.errorCount,
                    summary.sessionDuration
                ),
                Time = 4,
            })
        end,
    })

    -- Build analytics UI section
    AnalyticsManager:BuildAnalyticsSection(Tabs.Analytics)
end

-- --- Telemetry Demo ---
if TelemetryManager then
    local TelemetryGroupbox = Tabs.Analytics:AddRightGroupbox("Anonymous Telemetry", "activity")

    TelemetryGroupbox:AddLabel("Privacy-First Analytics", false)
    TelemetryGroupbox:AddLabel("- No personal data collected", true)
    TelemetryGroupbox:AddLabel("- Anonymous ID only", true)
    TelemetryGroupbox:AddLabel("- Opt-in only", true)

    -- Build telemetry UI section
    TelemetryManager:BuildTelemetrySection(Tabs.Analytics)
end

-- --- Crash Handler Demo ---
if CrashHandler then
    local CrashGroupbox = Tabs.Analytics:AddRightGroupbox("Crash Handler", "shield-alert")

    CrashGroupbox:AddButton({
        Text = "Simulate Error",
        Tooltip = "Test crash handler (safe)",
        Risky = true,
        Func = function()
            CrashHandler:LogError("Demo Error", "This is a simulated error for testing", debug.traceback())
            Library:Notify({
                Title = "CrashHandler",
                Description = "Error logged successfully!",
                Time = 2,
            })
        end,
    })

    CrashGroupbox:AddButton({
        Text = "Test SafeCall",
        Func = function()
            local success, err = CrashHandler:SafeCall("TestFunction", function()
                return "Success!"
            end)
            print("[SafeCall] Success:", success, "Result:", err)
        end,
    })

    CrashGroupbox:AddButton({
        Text = "View Crash Logs",
        Func = function()
            local logs = CrashHandler:GetLogs(5)
            local Http = game:GetService("HttpService")
            local content = Http:JSONEncode(logs)
            setclipboard(content)
            Library:Notify({
                Title = "CrashHandler",
                Description = "Logs copied to clipboard!",
                Time = 2,
            })
        end,
    })

    -- Build crash handler UI section
    CrashHandler:BuildCrashSection(Tabs.Analytics)
end

-- =========================================================
--                    SETTINGS TAB
-- =========================================================

-- UI Settings
local MenuGroup = Tabs.Settings:AddRightGroupbox("Menu Settings", "wrench")

MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = Library.ShowCustomCursor,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})

MenuGroup:AddSlider("UICornerSlider", {
    Text = "Corner Radius",
    Default = Library.CornerRadius,
    Min = 0,
    Max = 20,
    Rounding = 0,
    Callback = function(value)
        Window:SetCornerRadius(value)
    end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu keybind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })

MenuGroup:AddButton("Unload", function()
    Library:Notify({
        Title = CONFIG.ScriptName,
        Description = "Goodbye!",
        Time = 2,
    })
    task.wait(1)
    Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

-- =========================================================
--                    ADDON SETUP (Save/Theme)
-- =========================================================

-- Initialize addons with library
if ThemeManager then ThemeManager:SetLibrary(Library) end
if SaveManager then SaveManager:SetLibrary(Library) end
if CrashHandler then CrashHandler:SetLibrary(Library) end
if AnalyticsManager then AnalyticsManager:SetLibrary(Library) end
if TelemetryManager then TelemetryManager:SetLibrary(Library) end
if TranslatorManager then TranslatorManager:SetLibrary(Library) end
if SchedulerManager then SchedulerManager:SetLibrary(Library) end
if ShortcutManager then ShortcutManager:SetLibrary(Library) end

-- Ignore theme settings in save
if SaveManager then
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind", "TranslatorTestKey" })
    SaveManager:SetFolder("ObsidianDemo")
end

-- Set folders for save/theme
if ThemeManager then ThemeManager:SetFolder("ObsidianDemo") end

-- Build config sections
if SaveManager then SaveManager:BuildConfigSection(Tabs.Settings) end
if ThemeManager then ThemeManager:ApplyToTab(Tabs.Settings) end

-- Load auto-save config
if SaveManager then SaveManager:LoadAutoloadConfig() end

-- =========================================================
--                    INITIALIZATION COMPLETE
-- =========================================================

-- Count loaded addons
local loadedCount = 0
if ThemeManager then loadedCount = loadedCount + 1 end
if SaveManager then loadedCount = loadedCount + 1 end
if CrashHandler then loadedCount = loadedCount + 1 end
if AnalyticsManager then loadedCount = loadedCount + 1 end
if TelemetryManager then loadedCount = loadedCount + 1 end
if TranslatorManager then loadedCount = loadedCount + 1 end
if SchedulerManager then loadedCount = loadedCount + 1 end
if ShortcutManager then loadedCount = loadedCount + 1 end

print("=================================")
print(string.format("%s v%s initialized!", CONFIG.ScriptName, CONFIG.ScriptVersion))
print(string.format("Addons loaded: %d/8", loadedCount))
print("=================================")

Library:Notify({
    Title = CONFIG.ScriptName,
    Description = string.format("v%s loaded! (%d addons)", CONFIG.ScriptVersion, loadedCount),
    Time = 3,
})

-- Track script start
if AnalyticsManager then
    AnalyticsManager:TrackEvent("script", "started", 1, {
        version = CONFIG.ScriptVersion,
        game = game.GameId,
    })
end

-- Cleanup on unload
Library:OnUnload(function()
    if AnalyticsManager then
        AnalyticsManager:TrackEvent("script", "unloaded", 1, {})
        AnalyticsManager:EndSession()
    end
    if TelemetryManager then TelemetryManager:EndSession() end
    if SchedulerManager then SchedulerManager:Stop() end
end)
