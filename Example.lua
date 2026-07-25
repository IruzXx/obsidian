--[[
    Obsidian UI Library - Full Feature Demo
    Showcases all addons in a comprehensive example
    Author: IruzXx
--]]

-- =========================================================
--                    CONFIGURATION
-- =========================================================

local CONFIG = {
    ScriptName = "Obsidian Demo",
    ScriptVersion = "1.0.0",
    WebhookURL = "", -- Set your webhook URL for crash reports
    TelemetryEndpoint = "", -- Set your telemetry endpoint
}

-- =========================================================
--                    LIBRARY SETUP
-- =========================================================

-- Get the repo URL (change for your deployment)
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

-- Load core library
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

-- Load all official addons
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local CrashHandler = loadstring(game:HttpGet(repo .. "addons/CrashHandler.lua"))()
local AnalyticsManager = loadstring(game:HttpGet(repo .. "addons/AnalyticsManager.lua"))()
local TelemetryManager = loadstring(game:HttpGet(repo .. "addons/TelemetryManager.lua"))()
local TranslatorManager = loadstring(game:HttpGet(repo .. "addons/TranslatorManager.lua"))()
local SchedulerManager = loadstring(game:HttpGet(repo .. "addons/SchedulerManager.lua"))()
local ShortcutManager = loadstring(game:HttpGet(repo .. "addons/ShortcutManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

-- =========================================================
--                    ADDON INITIALIZATION
-- =========================================================

-- Configure Analytics
AnalyticsManager:Configure({
    scriptName = CONFIG.ScriptName,
    scriptVersion = CONFIG.ScriptVersion,
    enableTracking = true,
    batchInterval = 30,
    webhookURL = CONFIG.WebhookURL,
})

-- Configure Telemetry (disabled by default - opt-in)
TelemetryManager:Configure({
    enabled = false, -- User must opt-in
    endpoint = CONFIG.TelemetryEndpoint,
    privacyMode = true,
})

-- Configure Crash Handler
CrashHandler:Configure({
    EnableAutoRestart = true,
    MaxRetries = 3,
    RetryDelay = 2,
    CooldownTime = 60,
})

-- Set callbacks for CrashHandler
CrashHandler.OnCrash = function(errorMsg, stack)
    print("[CrashHandler] Application crashed:", errorMsg)
    AnalyticsManager:TrackError(errorMsg, { stack = stack })
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
        SchedulerManager:Stop()
        Library:Notify({
            Title = "Scheduler",
            Description = "All tasks stopped",
            Time = 2,
        })
    end,
})

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
    AnalyticsManager:TrackToggle("GodMode", enabled)
end)

Toggles.SpeedHack:OnChanged(function()
    local enabled = Toggles.SpeedHack.Value
    print("[SpeedHack]", enabled and "Enabled" or "Disabled")
    AnalyticsManager:TrackToggle("SpeedHack", enabled)
end)

Toggles.InfiniteJump:OnChanged(function()
    local enabled = Toggles.InfiniteJump.Value
    print("[InfiniteJump]", enabled and "Enabled" or "Disabled")
    AnalyticsManager:TrackToggle("InfiniteJump", enabled)
end)

Toggles.ESP:OnChanged(function()
    local enabled = Toggles.ESP.Value
    print("[ESP]", enabled and "Enabled" or "Disabled")
    AnalyticsManager:TrackToggle("ESP", enabled)
end)

Toggles.Aimbot:OnChanged(function()
    local enabled = Toggles.Aimbot.Value
    print("[Aimbot]", enabled and "Enabled" or "Disabled")
    AnalyticsManager:TrackToggle("Aimbot", enabled)
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
    AnalyticsManager:TrackSliderChange("WalkSpeed", value)
end)

Options.JumpPower:OnChanged(function()
    local value = Options.JumpPower.Value
    print("[JumpPower]", value)
    AnalyticsManager:TrackSliderChange("JumpPower", value)
end)

Options.FlySpeed:OnChanged(function()
    local value = Options.FlySpeed.Value
    print("[FlySpeed]", value)
    AnalyticsManager:TrackSliderChange("FlySpeed", value)
end)

Options.ESPAlpha:OnChanged(function()
    local value = Options.ESPAlpha.Value
    print("[ESPAlpha]", value)
    AnalyticsManager:TrackSliderChange("ESPAlpha", value)
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
        SchedulerManager:ScheduleOnce("Reminder", 30, function()
            Library:Notify({
                Title = "Scheduler",
                Description = "30 seconds have passed!",
                Time = 5,
            })
            AnalyticsManager:TrackEvent("scheduler", "reminder_triggered", 1, {})
        end)
        Library:Notify({
            Title = "Scheduler",
            Description = "Reminder scheduled for 30 seconds",
            Time = 2,
        })
        AnalyticsManager:TrackButtonClick("ScheduleReminder")
    end,
})

SchedulerGroupbox:AddButton({
    Text = "Schedule Auto-Save (1min)",
    Tooltip = "Schedule auto-save every minute",
    Func = function()
        local taskId = SchedulerManager:ScheduleInterval("AutoSave", 60, function()
            print("[AutoSave] Saving configuration...")
            -- Your save logic here
            AnalyticsManager:TrackEvent("scheduler", "autosave", 1, {})
        end)
        Library:Notify({
            Title = "Scheduler",
            Description = string.format("Auto-save scheduled (Task #%d)", taskId),
            Time = 2,
        })
        AnalyticsManager:TrackButtonClick("ScheduleAutoSave")
    end,
})

SchedulerGroupbox:AddButton({
    Text = "List Active Tasks",
    Func = function()
        local tasks = SchedulerManager:GetAllTasks()
        local count = 0
        for _ in pairs(tasks) do count = count + 1 end
        Library:Notify({
            Title = "Scheduler",
            Description = string.format("Active tasks: %d", count),
            Time = 3,
        })
    end,
})

-- Build scheduler UI section
SchedulerManager:BuildSchedulerSection(Tabs.Scheduler)

-- --- Translator Demo ---
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

-- --- Shortcuts Demo ---
local ShortcutsGroupbox = Tabs.Settings:AddLeftGroupbox("Shortcuts", "command")

ShortcutsGroupbox:AddLabel("Press F1 to open Command Palette", false)

ShortcutsGroupbox:AddButton({
    Text = "Open Command Palette",
    Func = function()
        ShortcutManager:ShowPalette()
        AnalyticsManager:TrackButtonClick("OpenPalette")
    end,
})

-- Build shortcuts UI section
ShortcutManager:BuildShortcutSection(Tabs.Settings)

-- --- Analytics Demo ---
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

-- --- Telemetry Demo ---
local TelemetryGroupbox = Tabs.Analytics:AddRightGroupbox("Anonymous Telemetry", "activity")

TelemetryGroupbox:AddLabel("Privacy-First Analytics", false)
TelemetryGroupbox:AddLabel("- No personal data collected", true)
TelemetryGroupbox:AddLabel("- Anonymous ID only", true)
TelemetryGroupbox:AddLabel("- Opt-in only", true)

-- Build telemetry UI section
TelemetryManager:BuildTelemetrySection(Tabs.Analytics)

-- --- Crash Handler Demo ---
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
        local content = HttpService:JSONEncode(logs)
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
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
CrashHandler:SetLibrary(Library)
AnalyticsManager:SetLibrary(Library)
TelemetryManager:SetLibrary(Library)
TranslatorManager:SetLibrary(Library)
SchedulerManager:SetLibrary(Library)
ShortcutManager:SetLibrary(Library)

-- Ignore theme settings in save
SaveManager:IgnoreThemeSettings()

-- Ignore menu keybind in save
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "TranslatorTestKey" })

-- Set folders for save/theme
ThemeManager:SetFolder("ObsidianDemo")
SaveManager:SetFolder("ObsidianDemo")

-- Build config sections
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

-- Load auto-save config
SaveManager:LoadAutoloadConfig()

-- =========================================================
--                    INITIALIZATION COMPLETE
-- =========================================================

print("=================================")
print(string.format("%s v%s initialized!", CONFIG.ScriptName, CONFIG.ScriptVersion))
print("=================================")
print("Addons loaded:")
print("  - ThemeManager: OK")
print("  - SaveManager: OK")
print("  - CrashHandler: OK")
print("  - AnalyticsManager: OK")
print("  - TelemetryManager: OK")
print("  - TranslatorManager: OK")
print("  - SchedulerManager: OK")
print("  - ShortcutManager: OK")
print("=================================")

Library:Notify({
    Title = CONFIG.ScriptName,
    Description = string.format("v%s loaded successfully!", CONFIG.ScriptVersion),
    Time = 3,
})

-- Track script start
AnalyticsManager:TrackEvent("script", "started", 1, {
    version = CONFIG.ScriptVersion,
    game = game.GameId,
})

-- Cleanup on unload
Library:OnUnload(function()
    AnalyticsManager:TrackEvent("script", "unloaded", 1, {})
    AnalyticsManager:EndSession()
    TelemetryManager:EndSession()
    SchedulerManager:Stop()
end)
