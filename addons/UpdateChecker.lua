-- UpdateChecker.lua
-- Addon untuk Obsidian Library
-- Cek versi terbaru script dari URL (GitHub/pastebin/dll),
-- tampilkan changelog, notifikasi update, dan opsi auto-update.

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local UpdateChecker = {
    Library = nil,

    -- Info script saat ini (diisi oleh developer)
    CurrentVersion = "1.0.0",
    ScriptName     = "Script",
    Author         = "",

    -- URL ke file version.json di GitHub/CDN
    -- Format file yang diharapkan: lihat FORMAT VERSION FILE di bawah
    VersionURL     = "",

    -- URL ke file script terbaru (untuk auto-update)
    ScriptURL      = "",

    -- Pengaturan
    CheckOnStartup     = true,   -- cek otomatis saat SetLibrary dipanggil
    StartupDelay       = 3,      -- detik tunggu sebelum cek startup
    NotifyIfUpToDate   = false,  -- tampilkan notif jika sudah terbaru
    AutoCheckInterval  = 0,      -- 0 = tidak auto-cek berkala; >0 = interval detik

    -- State internal
    _LastCheckTime    = 0,
    _LastResult       = nil,   -- hasil cek terakhir
    _CheckInProgress  = false,
    _IntervalTask     = nil,
}

--[[
    FORMAT VERSION FILE (version.json di server):
    {
        "version":   "3.2",
        "changelog": "- Fixed ESP bug\n- Added new map data\n- Performance improvements",
        "critical":  false,
        "min_version": "3.0",
        "script_url": "https://raw.githubusercontent.com/.../script.lua"
    }

    Field wajib : version
    Field opsional: changelog, critical, min_version, script_url
]]

-- =========================================================
--                    SETUP
-- =========================================================

function UpdateChecker:SetLibrary(Library)
    assert(Library, "[UpdateChecker] Library tidak boleh nil")
    UpdateChecker.Library = Library

    if UpdateChecker.CheckOnStartup and UpdateChecker.VersionURL ~= "" then
        task.delay(UpdateChecker.StartupDelay, function()
            UpdateChecker:Check(true)
        end)
    end

    if UpdateChecker.AutoCheckInterval > 0 then
        UpdateChecker:_StartIntervalCheck()
    end
end

--- Konfigurasi singkat — panggil sebelum SetLibrary
--- @param Config table  { name, author, currentVersion, versionURL, scriptURL, ... }
function UpdateChecker:Configure(Config)
    assert(typeof(Config) == "table", "[UpdateChecker] Config harus tabel")

    UpdateChecker.ScriptName          = Config.name             or UpdateChecker.ScriptName
    UpdateChecker.Author              = Config.author           or UpdateChecker.Author
    UpdateChecker.CurrentVersion      = Config.currentVersion   or UpdateChecker.CurrentVersion
    UpdateChecker.VersionURL          = Config.versionURL       or UpdateChecker.VersionURL
    UpdateChecker.ScriptURL           = Config.scriptURL        or UpdateChecker.ScriptURL
    UpdateChecker.CheckOnStartup      = Config.checkOnStartup   ~= nil and Config.checkOnStartup or UpdateChecker.CheckOnStartup
    UpdateChecker.StartupDelay        = Config.startupDelay     or UpdateChecker.StartupDelay
    UpdateChecker.NotifyIfUpToDate    = Config.notifyIfUpToDate ~= nil and Config.notifyIfUpToDate or UpdateChecker.NotifyIfUpToDate
    UpdateChecker.AutoCheckInterval   = Config.autoCheckInterval or UpdateChecker.AutoCheckInterval
end

-- =========================================================
--                    VERSI HELPER
-- =========================================================

--- Parse versi "X.Y.Z" ke tabel angka { X, Y, Z }
local function ParseVersion(VerStr)
    if not VerStr or VerStr == "" then return { 0 } end
    local Parts = {}
    for Part in tostring(VerStr):gmatch("[^%.]+") do
        table.insert(Parts, tonumber(Part) or 0)
    end
    return Parts
end

--- Bandingkan dua versi. Return: 1 jika A > B, -1 jika A < B, 0 jika sama
local function CompareVersions(A, B)
    local PA = ParseVersion(A)
    local PB = ParseVersion(B)
    local MaxLen = math.max(#PA, #PB)
    for i = 1, MaxLen do
        local a = PA[i] or 0
        local b = PB[i] or 0
        if a > b then return  1 end
        if a < b then return -1 end
    end
    return 0
end

--- Apakah versi A lebih baru dari B?
local function IsNewer(A, B)
    return CompareVersions(A, B) > 0
end

-- =========================================================
--                    FETCH VERSION DATA
-- =========================================================

--- Fetch dan parse version.json dari URL
--- @return boolean ok, table|string data_or_error
local function FetchVersionData(URL)
    if not URL or URL == "" then
        return false, "VersionURL belum diset"
    end

    local fetchOk, Raw = pcall(function()
        return game:HttpGet(URL .. "?t=" .. tostring(os.time()))
    end)

    if not fetchOk or not Raw or Raw == "" then
        return false, "Gagal mengambil data dari URL: " .. tostring(Raw)
    end

    local decOk, Data = pcall(HttpService.JSONDecode, HttpService, Raw)
    if not decOk or typeof(Data) ~= "table" then
        -- Coba baca sebagai plain text (hanya berisi versi)
        local Plain = Raw:match("^%s*([%d%.]+)%s*$")
        if Plain then
            return true, { version = Plain, changelog = "", critical = false }
        end
        return false, "Format data versi tidak valid"
    end

    if not Data.version then
        return false, "Field 'version' tidak ditemukan di data"
    end

    return true, Data
end

-- =========================================================
--                    CEK UPDATE
-- =========================================================

--- Hasil cek: { hasUpdate, latestVersion, currentVersion, changelog, critical, scriptURL }
--- @param Silent boolean  jika true, tidak tampilkan notif "sudah terbaru"
--- @param Callback function? dipanggil dengan (Result) setelah selesai
--- @return table|nil Result (juga dikembalikan sync jika tidak pakai callback)
function UpdateChecker:Check(Silent, Callback)
    if UpdateChecker._CheckInProgress then
        warn("[UpdateChecker] Cek sedang berjalan, tunggu sebentar")
        return nil
    end

    UpdateChecker._CheckInProgress = true
    UpdateChecker._LastCheckTime   = os.time()

    local function Finish(Result)
        UpdateChecker._LastResult       = Result
        UpdateChecker._CheckInProgress  = false

        if typeof(Callback) == "function" then
            pcall(Callback, Result)
        end

        -- Notifikasi otomatis
        if UpdateChecker.Library and UpdateChecker.Library.Notify then
            if Result.hasUpdate then
                local Desc = string.format(
                    "Versi terbaru: %s (kamu: %s)%s%s",
                    Result.latestVersion,
                    Result.currentVersion,
                    Result.critical and "\n⚠ Update WAJIB!" or "",
                    (Result.changelog and Result.changelog ~= "")
                        and ("\n\nChangelog:\n" .. Result.changelog) or ""
                )
                UpdateChecker.Library:Notify({
                    Title       = (Result.critical and "⚠ " or "") .. UpdateChecker.ScriptName .. " - Ada Update!",
                    Description = Desc,
                    Time        = Result.critical and 15 or 8,
                    TitleColor  = Result.critical
                        and Color3.fromRGB(255, 80, 80)
                        or  Color3.fromRGB(115, 215, 85),
                })
            elseif not Silent and UpdateChecker.NotifyIfUpToDate then
                UpdateChecker.Library:Notify({
                    Title       = UpdateChecker.ScriptName .. " - Sudah Terbaru",
                    Description = string.format("Kamu menggunakan versi terbaru (%s)", Result.currentVersion),
                    Time        = 3,
                })
            end
        end
    end

    -- Jalankan di background agar tidak memblokir UI
    task.spawn(function()
        local fetchOk, Data = FetchVersionData(UpdateChecker.VersionURL)

        if not fetchOk then
            local Result = {
                hasUpdate      = false,
                error          = tostring(Data),
                currentVersion = UpdateChecker.CurrentVersion,
                latestVersion  = nil,
                changelog      = "",
                critical       = false,
                scriptURL      = "",
            }

            if UpdateChecker.Library and not Silent then
                UpdateChecker.Library:Notify({
                    Title       = UpdateChecker.ScriptName .. " - Gagal Cek Update",
                    Description = "Error: " .. tostring(Data),
                    Time        = 4,
                    TitleColor  = Color3.fromRGB(255, 80, 80),
                })
            end

            Finish(Result)
            return
        end

        local LatestVersion = tostring(Data.version)
        local HasUpdate     = IsNewer(LatestVersion, UpdateChecker.CurrentVersion)

        -- Cek min_version: jika versi sekarang di bawah min, paksa update
        local Critical = Data.critical == true
        if Data.min_version and IsNewer(Data.min_version, UpdateChecker.CurrentVersion) then
            Critical = true
        end

        local ScriptURL = Data.script_url or UpdateChecker.ScriptURL

        local Result = {
            hasUpdate      = HasUpdate,
            currentVersion = UpdateChecker.CurrentVersion,
            latestVersion  = LatestVersion,
            changelog      = Data.changelog or "",
            critical       = Critical,
            scriptURL      = ScriptURL,
            rawData        = Data,
            checkedAt      = os.time(),
            error          = nil,
        }

        Finish(Result)
    end)

    return nil
end

--- Dapatkan hasil cek terakhir tanpa fetch ulang
function UpdateChecker:GetLastResult()
    return UpdateChecker._LastResult
end

--- Berapa detik sejak cek terakhir
function UpdateChecker:GetTimeSinceLastCheck()
    if UpdateChecker._LastCheckTime == 0 then return nil end
    return os.time() - UpdateChecker._LastCheckTime
end

-- =========================================================
--                    AUTO-UPDATE
-- =========================================================

--- Download dan jalankan versi terbaru dari scriptURL
--- PERHATIAN: Ini akan loadstring() script dari internet.
---            Pastikan URL adalah milik kamu sendiri dan terpercaya.
--- @param ConfirmCallback function? dipanggil dulu untuk konfirmasi (opsional)
function UpdateChecker:PerformUpdate(ConfirmCallback)
    local Result = UpdateChecker._LastResult
    local URL    = (Result and Result.scriptURL and Result.scriptURL ~= "" and Result.scriptURL)
                   or UpdateChecker.ScriptURL

    if not URL or URL == "" then
        warn("[UpdateChecker] ScriptURL belum diset, tidak bisa auto-update")
        if UpdateChecker.Library then
            UpdateChecker.Library:Notify({
                Title       = "Auto-Update Gagal",
                Description = "ScriptURL belum diset di konfigurasi UpdateChecker.",
                Time        = 4,
                TitleColor  = Color3.fromRGB(255, 80, 80),
            })
        end
        return false
    end

    local function DoUpdate()
        task.spawn(function()
            if UpdateChecker.Library then
                UpdateChecker.Library:Notify({
                    Title       = "Mengunduh Update...",
                    Description = "Mohon tunggu, script sedang diunduh.",
                    Time        = 3,
                })
            end

            task.wait(0.5)

            local fetchOk, ScriptContent = pcall(function()
                return game:HttpGet(URL)
            end)

            if not fetchOk or not ScriptContent or ScriptContent == "" then
                if UpdateChecker.Library then
                    UpdateChecker.Library:Notify({
                        Title       = "Update Gagal",
                        Description = "Gagal mengunduh script: " .. tostring(ScriptContent),
                        Time        = 5,
                        TitleColor  = Color3.fromRGB(255, 80, 80),
                    })
                end
                return
            end

            local loadOk, loadErr = pcall(function()
                -- Unload library lama dulu jika ada
                if UpdateChecker.Library and UpdateChecker.Library.Unload then
                    UpdateChecker.Library:Unload()
                end
                task.wait(0.3)
                loadstring(ScriptContent)()
            end)

            if not loadOk then
                warn("[UpdateChecker] Gagal menjalankan script baru:", loadErr)
            end
        end)
    end

    if typeof(ConfirmCallback) == "function" then
        ConfirmCallback(DoUpdate)
    else
        DoUpdate()
    end

    return true
end

--- Tampilkan dialog konfirmasi update lalu jalankan jika disetujui
function UpdateChecker:PromptUpdate()
    local Library = UpdateChecker.Library
    if not Library or not Library.Window then
        warn("[UpdateChecker] Library/Window belum tersedia")
        return
    end

    local Result = UpdateChecker._LastResult
    if not Result or not Result.hasUpdate then
        Library:Notify({
            Title       = "Tidak Ada Update",
            Description = "Kamu sudah menggunakan versi terbaru.",
            Time        = 3,
        })
        return
    end

    Library.Window:AddDialog("UC_UpdatePrompt", {
        Title       = "Update Tersedia!",
        Description = string.format(
            "Versi baru %s tersedia (kamu: %s).\n\nChangelog:\n%s\n\nUpdate sekarang?",
            Result.latestVersion,
            Result.currentVersion,
            (Result.changelog ~= "" and Result.changelog) or "(tidak ada changelog)"
        ),
        AutoDismiss  = false,
        OutsideClickDismiss = true,
        FooterButtons = {
            Skip = {
                Title    = "Nanti",
                Variant  = "Ghost",
                Order    = 1,
                Callback = function(Dialog) Dialog:Dismiss() end,
            },
            Update = {
                Title    = "Update Sekarang",
                Variant  = "Primary",
                Order    = 2,
                Callback = function(Dialog)
                    Dialog:Dismiss()
                    UpdateChecker:PerformUpdate()
                end,
            },
        },
    })
end

-- =========================================================
--                    INTERVAL CHECK
-- =========================================================

function UpdateChecker:_StartIntervalCheck()
    if UpdateChecker._IntervalTask then return end
    UpdateChecker._IntervalTask = task.spawn(function()
        while UpdateChecker.AutoCheckInterval > 0 do
            task.wait(UpdateChecker.AutoCheckInterval)
            if not UpdateChecker._CheckInProgress then
                UpdateChecker:Check(true)
            end
        end
    end)
end

function UpdateChecker:_StopIntervalCheck()
    if UpdateChecker._IntervalTask then
        pcall(task.cancel, UpdateChecker._IntervalTask)
        UpdateChecker._IntervalTask = nil
    end
end

--- Ubah interval cek otomatis (0 = nonaktif)
function UpdateChecker:SetAutoCheckInterval(Seconds)
    UpdateChecker.AutoCheckInterval = Seconds or 0
    UpdateChecker:_StopIntervalCheck()
    if Seconds and Seconds > 0 then
        UpdateChecker:_StartIntervalCheck()
    end
end

-- =========================================================
--                    UI SECTION
-- =========================================================

--- Bangun section UpdateChecker di dalam Tab/Groupbox Obsidian
--- @param Tab any           Tab Obsidian
--- @param GroupboxName string?
function UpdateChecker:BuildUpdateSection(Tab, GroupboxName)
    assert(Tab, "[UpdateChecker] Tab tidak boleh nil")

    local BoxLeft  = Tab:AddLeftGroupbox(GroupboxName or "Update Checker", "refresh-cw")
    local BoxRight = Tab:AddRightGroupbox("Changelog & Info", "file-text")

    local StatusLabel
    local ChangelogLabel
    local LastCheckLabel

    -- Helper update label status
    local function SetStatus(Msg, IsError)
        if StatusLabel then
            StatusLabel:SetText("Status: " .. Msg)
        end
    end

    local function UpdateLastCheckLabel()
        if not LastCheckLabel then return end
        local t = UpdateChecker:GetTimeSinceLastCheck()
        if not t then
            LastCheckLabel:SetText("Terakhir dicek: Belum pernah")
        else
            local mins = math.floor(t / 60)
            local secs = t % 60
            if mins > 0 then
                LastCheckLabel:SetText(string.format("Terakhir dicek: %d menit %d detik lalu", mins, secs))
            else
                LastCheckLabel:SetText(string.format("Terakhir dicek: %d detik lalu", secs))
            end
        end
    end

    local function UpdateChangelogLabel()
        if not ChangelogLabel then return end
        local Result = UpdateChecker._LastResult
        if not Result then
            ChangelogLabel:SetText("(belum dicek)")
            return
        end
        if Result.error then
            ChangelogLabel:SetText("Error: " .. Result.error)
            return
        end

        local Lines = {}
        table.insert(Lines, string.format("Versi saat ini : %s", Result.currentVersion))
        table.insert(Lines, string.format("Versi terbaru  : %s", Result.latestVersion or "?"))
        table.insert(Lines, string.format("Ada update     : %s", Result.hasUpdate and "YA" or "Tidak"))

        if Result.critical then
            table.insert(Lines, "⚠ Update WAJIB (critical)")
        end

        if Result.changelog and Result.changelog ~= "" then
            table.insert(Lines, "")
            table.insert(Lines, "Changelog:")
            -- Pecah per baris agar rapi
            for Line in (Result.changelog .. "\n"):gmatch("([^\n]*)\n") do
                if Line ~= "" then
                    table.insert(Lines, "  " .. Line)
                end
            end
        else
            table.insert(Lines, "(tidak ada changelog)")
        end

        ChangelogLabel:SetText(table.concat(Lines, "\n"))
    end

    -- ── KIRI: Kontrol ─────────────────────────────────────

    -- Info versi saat ini
    BoxLeft:AddLabel(string.format(
        "%s v%s%s",
        UpdateChecker.ScriptName,
        UpdateChecker.CurrentVersion,
        UpdateChecker.Author ~= "" and (" by " .. UpdateChecker.Author) or ""
    ), false)

    BoxLeft:AddDivider()

    -- Tombol cek manual
    BoxLeft:AddButton({
        Text    = "Cek Update Sekarang",
        Tooltip = "Periksa apakah ada versi terbaru dari server",
        Func    = function()
            if UpdateChecker.VersionURL == "" then
                SetStatus("VersionURL belum diset!", true)
                return
            end
            SetStatus("Sedang memeriksa...")
            UpdateChecker:Check(false, function(Result)
                if Result.error then
                    SetStatus("Gagal: " .. Result.error, true)
                elseif Result.hasUpdate then
                    SetStatus("Update tersedia: v" .. Result.latestVersion)
                else
                    SetStatus("Sudah versi terbaru (" .. Result.currentVersion .. ")")
                end
                UpdateChangelogLabel()
                UpdateLastCheckLabel()
            end)
        end,
    })

    -- Tombol update sekarang
    BoxLeft:AddButton({
        Text    = "Update Sekarang",
        Tooltip = "Download dan jalankan versi terbaru (butuh ScriptURL)",
        Func    = function()
            local Result = UpdateChecker._LastResult
            if not Result then
                SetStatus("Cek update dulu sebelum update!")
                return
            end
            if not Result.hasUpdate then
                SetStatus("Tidak ada update untuk dijalankan")
                return
            end
            UpdateChecker:PromptUpdate()
        end,
    })

    BoxLeft:AddDivider()

    -- Input VersionURL (untuk konfigurasi dari UI)
    BoxLeft:AddInput("UC_VersionURL", {
        Text        = "Version URL",
        Default     = UpdateChecker.VersionURL,
        Finished    = true,
        Placeholder = "https://raw.githubusercontent.com/.../version.json",
        ClearTextOnFocus = false,
        Callback    = function(Value)
            UpdateChecker.VersionURL = Value
        end,
    })

    BoxLeft:AddInput("UC_ScriptURL", {
        Text        = "Script URL (auto-update)",
        Default     = UpdateChecker.ScriptURL,
        Finished    = true,
        Placeholder = "https://raw.githubusercontent.com/.../script.lua",
        ClearTextOnFocus = false,
        Callback    = function(Value)
            UpdateChecker.ScriptURL = Value
        end,
    })

    BoxLeft:AddDivider()

    -- Toggle notif jika sudah terbaru
    BoxLeft:AddToggle("UC_NotifyUpToDate", {
        Text    = "Notif Jika Sudah Terbaru",
        Default = UpdateChecker.NotifyIfUpToDate,
        Callback = function(Value)
            UpdateChecker.NotifyIfUpToDate = Value
        end,
    })

    -- Auto-check interval
    BoxLeft:AddDropdown("UC_AutoInterval", {
        Values   = { "Nonaktif", "5 menit", "15 menit", "30 menit", "1 jam" },
        Default  = "Nonaktif",
        Text     = "Auto-Cek Berkala",
        Tooltip  = "Cek update otomatis setiap interval yang ditentukan",
        Callback = function(Value)
            local Map = {
                ["Nonaktif"]  = 0,
                ["5 menit"]   = 300,
                ["15 menit"]  = 900,
                ["30 menit"]  = 1800,
                ["1 jam"]     = 3600,
            }
            UpdateChecker:SetAutoCheckInterval(Map[Value] or 0)
        end,
    })

    BoxLeft:AddDivider()

    StatusLabel   = BoxLeft:AddLabel("Status: Siap", false)
    LastCheckLabel = BoxLeft:AddLabel("Terakhir dicek: Belum pernah", false)

    -- ── KANAN: Changelog & Info ────────────────────────────
    ChangelogLabel = BoxRight:AddLabel("(belum dicek)", true)

    BoxRight:AddDivider()

    BoxRight:AddLabel(
        "Cara pakai:\n"
        .. "1. Isi Version URL di kiri\n"
        .. "2. Klik 'Cek Update Sekarang'\n"
        .. "3. Jika ada update, klik 'Update Sekarang'\n\n"
        .. "Format version.json:\n"
        .. '{ "version":"1.1",\n'
        .. '  "changelog":"- fix bug",\n'
        .. '  "critical":false }',
        true
    )

    -- Update label terakhir cek setiap 30 detik
    task.spawn(function()
        while true do
            task.wait(30)
            pcall(UpdateLastCheckLabel)
        end
    end)

    return BoxLeft, BoxRight
end

-- =========================================================
--                    INIT
-- =========================================================

return UpdateChecker
