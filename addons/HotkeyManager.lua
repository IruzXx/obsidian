-- HotkeyManager.lua
-- Addon untuk Obsidian Library
-- Manajemen keybind terpusat: lihat semua keybind aktif, deteksi konflik,
-- reset massal, cari berdasarkan nama fitur, export/import keybind.

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local UserInputService = cloneref(game:GetService("UserInputService"))
local HttpService = cloneref(game:GetService("HttpService"))

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local HotkeyManager = {
    Library = nil,

    -- Semua keybind yang terdaftar manual (di luar KeyPicker Obsidian)
    -- Format: { id = string, name = string, category = string, key = string, callback = function, enabled = boolean }
    CustomHotkeys = {},

    -- Kategori untuk pengelompokan di UI
    Categories = {},

    -- Koneksi InputBegan global
    _InputConnection = nil,
    _IsListening     = false,
}

-- =========================================================
--                    SETUP
-- =========================================================

function HotkeyManager:SetLibrary(Library)
    assert(Library, "[HotkeyManager] Library tidak boleh nil")
    HotkeyManager.Library = Library
end

-- =========================================================
--                    INTERNAL HELPERS
-- =========================================================

--- Ambil semua KeyPicker yang terdaftar di Library.Options
local function GetLibraryKeypickers()
    local Library = HotkeyManager.Library
    if not Library then return {} end

    local Result = {}
    for Idx, Option in Library.Options do
        if Option.Type == "KeyPicker" then
            table.insert(Result, {
                id       = Idx,
                name     = Option.Text or Idx,
                key      = Option.Value or "None",
                mode     = Option.Mode or "Toggle",
                modifiers = Option.Modifiers or {},
                source   = "Library",
                option   = Option,
            })
        end
    end

    -- Urutkan berdasarkan nama
    table.sort(Result, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    return Result
end

--- Format tampilan key + modifiers
local function FormatKeyDisplay(Key, Modifiers)
    if not Key or Key == "None" or Key == "" then
        return "(tidak diset)"
    end

    local Parts = {}
    if typeof(Modifiers) == "table" then
        for _, Mod in ipairs(Modifiers) do
            table.insert(Parts, tostring(Mod))
        end
    end
    table.insert(Parts, tostring(Key))

    return table.concat(Parts, " + ")
end

--- Cek apakah dua entry keybind pakai key yang sama (konflik)
local function IsConflict(A, B)
    if A.id == B.id then return false end
    if A.key == "None" or A.key == "" or B.key == "None" or B.key == "" then return false end
    if A.key ~= B.key then return false end

    -- Cek modifiers: keduanya harus punya set modifier yang identik
    local ModA = A.modifiers or {}
    local ModB = B.modifiers or {}
    if #ModA ~= #ModB then return false end

    -- Cek A ⊆ B
    for _, m in ipairs(ModA) do
        if not table.find(ModB, m) then return false end
    end
    -- Cek B ⊆ A (pastikan simetris, cegah duplikat di salah satu sisi)
    for _, m in ipairs(ModB) do
        if not table.find(ModA, m) then return false end
    end

    return true
end

--- Kumpulkan semua keybind (Library KeyPicker + Custom)
function HotkeyManager:_GetAllHotkeys()
    local All = {}

    -- Dari Library.Options (KeyPicker)
    for _, Entry in ipairs(GetLibraryKeypickers()) do
        table.insert(All, Entry)
    end

    -- Dari custom hotkey yang didaftarkan manual
    for _, Entry in ipairs(HotkeyManager.CustomHotkeys) do
        table.insert(All, {
            id        = Entry.id,
            name      = Entry.name,
            key       = Entry.key or "None",
            mode      = "Custom",
            modifiers = Entry.modifiers or {},
            category  = Entry.category,
            source    = "Custom",
            enabled   = Entry.enabled,
            entry     = Entry,
        })
    end

    return All
end

--- Temukan semua pasangan konflik
function HotkeyManager:_FindConflicts()
    local All      = HotkeyManager:_GetAllHotkeys()
    local Conflicts = {}  -- { ids = {id1, id2}, key = string }

    for i = 1, #All do
        for j = i + 1, #All do
            if IsConflict(All[i], All[j]) then
                table.insert(Conflicts, {
                    A   = All[i],
                    B   = All[j],
                    key = All[i].key,
                })
            end
        end
    end

    return Conflicts
end

--- Mulai listen input untuk custom hotkeys
function HotkeyManager:_StartListening()
    if HotkeyManager._IsListening then return end
    HotkeyManager._IsListening = true

    HotkeyManager._InputConnection = UserInputService.InputBegan:Connect(function(Input, GameProcessed)
        if GameProcessed then return end
        if UserInputService:GetFocusedTextBox() then return end

        local KeyName = nil
        if Input.UserInputType == Enum.UserInputType.Keyboard then
            KeyName = Input.KeyCode.Name
        elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
            KeyName = "MB1"
        elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
            KeyName = "MB2"
        elseif Input.UserInputType == Enum.UserInputType.MouseButton3 then
            KeyName = "MB3"
        end

        if not KeyName then return end

        -- Cek active modifiers
        local ActiveMods = {}
        local ModMap = {
            LeftControl  = "LCtrl",  RightControl = "RCtrl",
            LeftAlt      = "LAlt",   RightAlt     = "RAlt",
            LeftShift    = "LShift", RightShift   = "RShift",
        }
        for EnumName, ShortName in pairs(ModMap) do
            if UserInputService:IsKeyDown(Enum.KeyCode[EnumName]) then
                table.insert(ActiveMods, ShortName)
            end
        end

        -- Cocokkan dengan custom hotkeys
        for _, Entry in ipairs(HotkeyManager.CustomHotkeys) do
            if not Entry.enabled then continue end
            if Entry.key ~= KeyName then continue end

            -- Cek modifiers
            local EntryMods = Entry.modifiers or {}
            local ModsMatch = (#EntryMods == #ActiveMods)
            if ModsMatch and #EntryMods > 0 then
                for _, m in ipairs(EntryMods) do
                    if not table.find(ActiveMods, m) then
                        ModsMatch = false
                        break
                    end
                end
            end

            if ModsMatch then
                task.spawn(function()
                    pcall(Entry.callback)
                end)
            end
        end
    end)
end

function HotkeyManager:_StopListening()
    HotkeyManager._IsListening = false
    if HotkeyManager._InputConnection then
        pcall(HotkeyManager._InputConnection.Disconnect, HotkeyManager._InputConnection)
        HotkeyManager._InputConnection = nil
    end
end

-- =========================================================
--                    API PUBLIK - CUSTOM HOTKEYS
-- =========================================================

--- Daftarkan hotkey custom (di luar sistem KeyPicker Obsidian)
--- @param Id string         ID unik
--- @param Name string       Nama tampilan
--- @param Key string        Nama key (misal "F", "MB1", "Z")
--- @param Callback function Fungsi yang dipanggil saat key ditekan
--- @param Options table?    { category = string, modifiers = {string}, enabled = boolean }
--- @return boolean
function HotkeyManager:Register(Id: string, Name: string, Key: string, Callback: () -> (), Options: {}?): boolean
    assert(Id and Id ~= "",       "[HotkeyManager] Id tidak boleh kosong")
    assert(Name and Name ~= "",   "[HotkeyManager] Name tidak boleh kosong")
    assert(typeof(Callback) == "function", "[HotkeyManager] Callback harus fungsi")

    Options = Options or {}

    -- Hapus jika Id sudah ada (re-register)
    HotkeyManager:Unregister(Id)

    local Entry = {
        id        = Id,
        name      = Name,
        key       = Key or "None",
        modifiers = Options.modifiers or {},
        category  = Options.category or "Umum",
        callback  = Callback,
        enabled   = Options.enabled ~= false,  -- default: true
    }

    table.insert(HotkeyManager.CustomHotkeys, Entry)

    -- Tambahkan kategori jika belum ada
    if not table.find(HotkeyManager.Categories, Entry.category) then
        table.insert(HotkeyManager.Categories, Entry.category)
    end

    -- Pastikan listener aktif
    HotkeyManager:_StartListening()

    return true
end

--- Hapus registrasi hotkey berdasarkan Id
function HotkeyManager:Unregister(Id: string)
    for i = #HotkeyManager.CustomHotkeys, 1, -1 do
        if HotkeyManager.CustomHotkeys[i].id == Id then
            table.remove(HotkeyManager.CustomHotkeys, i)
            return true
        end
    end
    return false
end

--- Aktifkan / nonaktifkan hotkey custom berdasarkan Id
function HotkeyManager:SetEnabled(Id: string, Enabled: boolean)
    for _, Entry in ipairs(HotkeyManager.CustomHotkeys) do
        if Entry.id == Id then
            Entry.enabled = Enabled
            return true
        end
    end
    return false
end

--- Ubah key dari hotkey custom
function HotkeyManager:SetKey(Id: string, Key: string, Modifiers: {}?)
    for _, Entry in ipairs(HotkeyManager.CustomHotkeys) do
        if Entry.id == Id then
            Entry.key       = Key or "None"
            Entry.modifiers = Modifiers or {}
            return true
        end
    end
    return false
end

-- =========================================================
--                    API PUBLIK - LIBRARY KEYPICKERS
-- =========================================================

--- Reset semua KeyPicker di Library ke nilai default
function HotkeyManager:ResetAllKeypickers()
    local Library = HotkeyManager.Library
    if not Library then return 0 end

    local Count = 0
    for _, Option in Library.Options do
        if Option.Type ~= "KeyPicker" then continue end

        -- Cari nilai default: cek beberapa field yang mungkin dipakai Obsidian
        local DefaultKey = Option.Default or Option.DefaultKey or "None"
        local DefaultMode = Option.Mode or Option.DefaultMode or "Toggle"
        local DefaultMods = Option.DefaultModifiers or {}

        pcall(function()
            Option:SetValue({ DefaultKey, DefaultMode, DefaultMods })
        end)
        Count += 1
    end

    return Count
end

--- Dapatkan semua KeyPicker di Library (untuk inspeksi)
function HotkeyManager:GetLibraryKeypickers()
    return GetLibraryKeypickers()
end

--- Cari keybind berdasarkan kata kunci nama
--- @param Query string
--- @return table Array of hotkey entries yang cocok
function HotkeyManager:Search(Query: string)
    if not Query or Query == "" then
        return HotkeyManager:_GetAllHotkeys()
    end

    local Lower  = Query:lower()
    local Result = {}

    for _, Entry in ipairs(HotkeyManager:_GetAllHotkeys()) do
        local NameMatch = (Entry.name or ""):lower():find(Lower, 1, true)
        local KeyMatch  = (Entry.key  or ""):lower():find(Lower, 1, true)
        local CatMatch  = (Entry.category or ""):lower():find(Lower, 1, true)
        if NameMatch or KeyMatch or CatMatch then
            table.insert(Result, Entry)
        end
    end

    return Result
end

-- =========================================================
--                    EXPORT / IMPORT
-- =========================================================

--- Export semua keybind Library KeyPicker ke JSON string
function HotkeyManager:ExportKeybinds(): string?
    local Library = HotkeyManager.Library
    if not Library then return nil end

    local Data = { _version = 1, keybinds = {} }

    for _, Entry in ipairs(GetLibraryKeypickers()) do
        Data.keybinds[Entry.id] = {
            key       = Entry.key,
            mode      = Entry.mode,
            modifiers = Entry.modifiers,
        }
    end

    local ok, Encoded = pcall(HttpService.JSONEncode, HttpService, Data)
    return ok and Encoded or nil
end

--- Export ke clipboard
function HotkeyManager:ExportToClipboard(): boolean
    local Encoded = HotkeyManager:ExportKeybinds()
    if not Encoded then return false end
    local ok = pcall(setclipboard, Encoded)
    return ok
end

--- Import keybind dari JSON string dan terapkan ke KeyPicker Library
function HotkeyManager:ImportKeybinds(JsonString: string): (boolean, string?)
    if not JsonString or JsonString == "" then
        return false, "Data kosong"
    end

    local decOk, Data = pcall(HttpService.JSONDecode, HttpService, JsonString)
    if not decOk or typeof(Data) ~= "table" or Data._version ~= 1 then
        return false, "Format tidak valid"
    end

    local Library = HotkeyManager.Library
    if not Library then return false, "Library belum di-set" end

    local Applied = 0
    for Idx, KeyData in Data.keybinds do
        local Option = Library.Options[Idx]
        if Option and Option.Type == "KeyPicker" then
            pcall(function()
                Option:SetValue({ KeyData.key, KeyData.mode, KeyData.modifiers })
            end)
            Applied += 1
        end
    end

    return true, string.format("%d keybind berhasil diterapkan", Applied)
end

--- Import dari clipboard
function HotkeyManager:ImportFromClipboard(): (boolean, string?)
    local Clip = ""
    local ok   = pcall(function() Clip = getclipboard() end)
    if not ok or Clip == "" then
        return false, "Clipboard kosong atau tidak didukung"
    end
    return HotkeyManager:ImportKeybinds(Clip)
end

-- =========================================================
--                    UI SECTION
-- =========================================================

--- Bangun section HotkeyManager di dalam Tab Obsidian
--- @param Tab any           Tab Obsidian
--- @param GroupboxName string?
function HotkeyManager:BuildHotkeySection(Tab: any, GroupboxName: string?)
    assert(Tab, "[HotkeyManager] Tab tidak boleh nil")

    local BoxLeft  = Tab:AddLeftGroupbox(GroupboxName  or "Keybind Manager", "keyboard")
    local BoxRight = Tab:AddRightGroupbox("Konflik & Export", "alert-triangle")

    local SearchQuery  = ""
    local FilterCategory = "Semua"
    local AllKeybindLabel
    local ConflictLabel

    -- ── Bangun teks daftar keybind ──────────────────────────
    local function BuildKeybindText()
        local Entries = SearchQuery ~= ""
            and HotkeyManager:Search(SearchQuery)
            or  HotkeyManager:_GetAllHotkeys()

        if #Entries == 0 then
            return "(tidak ada keybind ditemukan)"
        end

        -- Filter kategori
        if FilterCategory ~= "Semua" then
            local Filtered = {}
            for _, E in ipairs(Entries) do
                local Cat = E.category or (E.source == "Library" and "Library" or "Custom")
                if Cat == FilterCategory then
                    table.insert(Filtered, E)
                end
            end
            Entries = Filtered
        end

        if #Entries == 0 then
            return "(tidak ada keybind di kategori ini)"
        end

        local Lines = {}
        for _, E in ipairs(Entries) do
            local KeyDisplay = FormatKeyDisplay(E.key, E.modifiers)
            local Cat = E.category or (E.source == "Library" and "Library" or "Custom")
            local Enabled = E.enabled
            local Status = (E.source == "Custom" and not Enabled) and " [OFF]" or ""
            table.insert(Lines, string.format("%-28s → %s  [%s]%s", E.name, KeyDisplay, Cat, Status))
        end

        return table.concat(Lines, "\n")
    end

    -- ── Bangun teks konflik ─────────────────────────────────
    local function BuildConflictText()
        local Conflicts = HotkeyManager:_FindConflicts()
        if #Conflicts == 0 then
            return "✓ Tidak ada konflik keybind"
        end

        local Lines = { string.format("⚠ Ditemukan %d konflik:", #Conflicts) }
        for _, C in ipairs(Conflicts) do
            table.insert(Lines, string.format(
                "  [%s] & [%s] → key '%s' sama",
                C.A.name, C.B.name, C.key
            ))
        end
        return table.concat(Lines, "\n")
    end

    local function RefreshAll()
        if AllKeybindLabel then AllKeybindLabel:SetText(BuildKeybindText())  end
        if ConflictLabel   then ConflictLabel:SetText(BuildConflictText())   end
    end

    -- ── Kiri: Daftar Keybind ────────────────────────────────
    BoxLeft:AddInput("HM_Search", {
        Text        = "Cari Keybind",
        Placeholder = "Nama fitur atau key...",
        Default     = "",
        Finished    = false,
        Callback    = function(Value)
            SearchQuery = Value
            RefreshAll()
        end,
    })

    -- Ambil semua kategori yang ada
    local function GetCategoryList()
        local Cats = { "Semua", "Library" }
        for _, Cat in ipairs(HotkeyManager.Categories) do
            if not table.find(Cats, Cat) then
                table.insert(Cats, Cat)
            end
        end
        return Cats
    end

    BoxLeft:AddDropdown("HM_CategoryFilter", {
        Values    = GetCategoryList(),
        Default   = "Semua",
        Text      = "Filter Kategori",
        AllowNull = false,
        Callback  = function(Value)
            FilterCategory = Value
            RefreshAll()
        end,
    })

    BoxLeft:AddButton({
        Text    = "Refresh Daftar",
        Tooltip = "Perbarui tampilan daftar keybind",
        Func    = function()
            -- Update filter dropdown jika ada kategori baru
            local CatDropdown = HotkeyManager.Library.Options.HM_CategoryFilter
            if CatDropdown then
                CatDropdown:SetValues(GetCategoryList())
            end
            RefreshAll()
        end,
    })

    BoxLeft:AddDivider()

    AllKeybindLabel = BoxLeft:AddLabel(BuildKeybindText(), true)

    BoxLeft:AddDivider()

    BoxLeft:AddButton({
        Text    = "Reset Semua ke Default",
        Tooltip = "Reset semua KeyPicker Library ke nilai default mereka",
        Risky   = true,
        Func    = function()
            HotkeyManager.Library.Window:AddDialog("HM_ResetConfirm", {
                Title       = "Reset Semua Keybind?",
                Description = "Semua KeyPicker akan dikembalikan ke nilai default. Tindakan ini tidak bisa dibatalkan.",
                AutoDismiss = false,
                FooterButtons = {
                    Cancel = { Title = "Batal", Variant = "Ghost",       Order = 1, Callback = function(d) d:Dismiss() end },
                    Reset  = { Title = "Reset", Variant = "Destructive", Order = 2, Callback = function(d)
                        d:Dismiss()
                        local Count = HotkeyManager:ResetAllKeypickers()
                        HotkeyManager.Library:Notify({
                            Title       = "Reset Selesai",
                            Description = string.format("%d keybind berhasil direset ke default.", Count),
                            Time        = 3,
                        })
                        RefreshAll()
                    end},
                },
            })
        end,
    })

    -- ── Kanan: Konflik & Export ─────────────────────────────
    ConflictLabel = BoxRight:AddLabel(BuildConflictText(), true)

    BoxRight:AddButton({
        Text    = "Cek Konflik",
        Tooltip = "Periksa apakah ada keybind yang bentrok",
        Func    = function()
            if ConflictLabel then
                ConflictLabel:SetText(BuildConflictText())
            end
            local Conflicts = HotkeyManager:_FindConflicts()
            HotkeyManager.Library:Notify({
                Title       = "Cek Konflik",
                Description = #Conflicts == 0
                    and "Tidak ada konflik keybind ditemukan."
                    or  string.format("Ditemukan %d konflik! Lihat panel kanan.", #Conflicts),
                Time = 3,
            })
        end,
    })

    BoxRight:AddDivider()

    BoxRight:AddButton({
        Text    = "Export Keybind ke Clipboard",
        Tooltip = "Salin semua keybind Library ke clipboard",
        Func    = function()
            local ok = HotkeyManager:ExportToClipboard()
            HotkeyManager.Library:Notify({
                Title       = ok and "Export Berhasil" or "Export Gagal",
                Description = ok
                    and "Semua keybind berhasil disalin ke clipboard."
                    or  "setclipboard tidak tersedia di executor ini.",
                Time = 3,
            })
        end,
    })

    BoxRight:AddButton({
        Text    = "Import Keybind dari Clipboard",
        Tooltip = "Tempel dan terapkan keybind dari clipboard",
        Func    = function()
            local ok, msg = HotkeyManager:ImportFromClipboard()
            HotkeyManager.Library:Notify({
                Title       = ok and "Import Berhasil" or "Import Gagal",
                Description = msg or "",
                Time        = 3,
            })
            if ok then RefreshAll() end
        end,
    })

    BoxRight:AddDivider()

    -- Info ringkas
    BoxRight:AddLabel(
        "Tips:\n"
        .. "• Keybind yang sama pada 2 fitur = Konflik\n"
        .. "• 'None' = keybind belum diset\n"
        .. "• Export untuk backup, Import untuk restore",
        true
    )

    -- Auto-refresh saat pertama kali
    task.defer(RefreshAll)

    return BoxLeft, BoxRight
end

-- =========================================================
--                    INIT
-- =========================================================

-- Mulai listener untuk custom hotkeys segera
-- (tidak ada efek jika belum ada yang didaftarkan)
task.defer(function()
    if #HotkeyManager.CustomHotkeys > 0 then
        HotkeyManager:_StartListening()
    end
end)

return HotkeyManager
