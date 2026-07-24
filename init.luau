--!strict
-- init.luau - Entry point untuk Obsidian Library
-- Exposes typed exports dari library dan addons

local ObsidianTypes = require("./Library.d")

-- =========================================================
--                    TYPE DEFINITIONS
-- =========================================================

export type ObsidianLibrary = ObsidianTypes.Library
export type ObsidianWindow = ObsidianTypes.Window
export type ObsidianTab = ObsidianTypes.Tab
export type ObsidianGroupbox = ObsidianTypes.Groupbox
export type ObsidianToggle = ObsidianTypes.Toggle
export type ObsidianSlider = ObsidianTypes.Slider
export type ObsidianDropdown = ObsidianTypes.Dropdown
export type ObsidianInput = ObsidianTypes.Input
export type ObsidianButton = ObsidianTypes.Button
export type ObsidianLabel = ObsidianTypes.Label
export type ObsidianColorPicker = ObsidianTypes.ColorPicker
export type ObsidianKeyPicker = ObsidianTypes.KeyPicker
export type ObsidianNotification = ObsidianTypes.Notification

-- =========================================================
--                    CORE MODULES
-- =========================================================

local LibraryModule = require("./Library")
local TypesModule = require("./Library.d")

-- =========================================================
--                    ADDON MODULES
-- =========================================================

local SaveManagerModule = require("./addons/SaveManager")
local ThemeManagerModule = require("./addons/ThemeManager")

-- New addons
local CrashHandlerModule = require("./addons/CrashHandler")
local AnalyticsManagerModule = require("./addons/AnalyticsManager")
local TranslatorManagerModule = require("./addons/TranslatorManager")
local SchedulerManagerModule = require("./addons/SchedulerManager")
local TelemetryManagerModule = require("./addons/TelemetryManager")
local ShortcutManagerModule = require("./addons/ShortcutManager")

-- =========================================================
--                    MODULE EXPORTS
-- =========================================================

local Obsidian = {
    --- Core library instance
    Library = (LibraryModule :: any) :: ObsidianLibrary,

    --- Type definitions module
    Types = TypesModule,

    --- Official Addons
    SaveManager = SaveManagerModule,
    ThemeManager = ThemeManagerModule,
    CrashHandler = CrashHandlerModule,
    AnalyticsManager = AnalyticsManagerModule,
    TranslatorManager = TranslatorManagerModule,
    SchedulerManager = SchedulerManagerModule,
    TelemetryManager = TelemetryManagerModule,
    ShortcutManager = ShortcutManagerModule,

    --- Addon modules (organized by category)
    Addons = {
        -- Config & Storage
        SaveManager = SaveManagerModule,
        ThemeManager = ThemeManagerModule,

        -- Utility
        CrashHandler = CrashHandlerModule,
        AnalyticsManager = AnalyticsManagerModule,
        TelemetryManager = TelemetryManagerModule,

        -- Automation
        SchedulerManager = SchedulerManagerModule,
        TranslatorManager = TranslatorManagerModule,

        -- UI Enhancement
        ShortcutManager = ShortcutManagerModule,
    } :: {
        SaveManager: typeof(SaveManagerModule),
        ThemeManager: typeof(ThemeManagerModule),
        CrashHandler: typeof(CrashHandlerModule),
        AnalyticsManager: typeof(AnalyticsManagerModule),
        TranslatorManager: typeof(TranslatorManagerModule),
        SchedulerManager: typeof(SchedulerManagerModule),
        TelemetryManager: typeof(TelemetryManagerModule),
        ShortcutManager: typeof(ShortcutManagerModule),
    },

    --- Addon list untuk iterasi
    AddonList = {
        "SaveManager",
        "ThemeManager",
        "CrashHandler",
        "AnalyticsManager",
        "TranslatorManager",
        "SchedulerManager",
        "TelemetryManager",
        "ShortcutManager",
    },
}

-- =========================================================
--                    TYPE ANNOTATION
-- =========================================================

export type Obsidian = typeof(Obsidian)

return Obsidian
