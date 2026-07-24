-- ProfileManager.lua
-- Addon untuk Obsidian Library
-- Sistem manajemen profil/preset: simpan beberapa konfigurasi berbeda,
-- switch antar profil dengan satu klik, export/import via clipboard.
-- Pola penggunaan sama dengan SaveManager & ThemeManager.

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))
local isfolder, isfile, listfiles = isfolder, isfile, listfiles

-- Simple compatibility check for executor functions
if typeof(clonefunction or copyfunction or nil) == "function" then
    local cf = (clonefunction or copyfunction)
    local _if, _isf, _lf = cf(isfolder), cf(isfile), cf(listfiles)

    local ok = pcall(_if, "test_pm_" .. tostring(math.random(1e6, 9e6)))
    if not ok or type(ok) ~= "boolean" then
        isfolder = function(p)
            local s, r = pcall(_if, p)
            return s == true and r == true
        end
        isfile = function(p)
            local s, r = pcall(_isf, p)
            return s == true and r == true
        end
        listfiles = function(p)
            local s, r = pcall(_lf, p)
            return (s == true and type(r) == "table") and r or {}
        end
    end
end

-- Patch fungsi filesystem agar tidak error di executor tertentu
if typeof(clonefunction or copyfunction or nil) == "function" then
    local cf = (clonefunction or copyfunction)
    local _if = cf(isfolder)
    local _isf = cf(isfile)
    local _lf = cf(listfiles)

    local ok, res = pcall(_if, "test_pm_" .. tostring(math.random(1e6, 9e6)))
    if not ok or typeof(res) ~= "boolean" then
        isfolder  = function(p) local s,r = pcall(_if,  p) return s and r or false end
        isfile    = function(p) local s,r = pcall(_isf, p) return s and r or false end
        listfiles = function(p) local s,r = pcall(_lf,  p) return s and r or {}    end
    end
end

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local ProfileManager = {
    Library    = nil,
    SaveManager = nil,    -- opsional, untuk integrasi SaveManager

    Folder     = "ObsidianLibSettings",
    SubFolder  = "",

    -- Profil yang sedang aktif
    ActiveProfile = nil,

    -- Cache daftar profil
    _ProfileCache = {},
}

-- =========================================================
--                    SETUP
-- =========================================================

function ProfileManager:SetLibrary(Library)
    assert(Library, "[ProfileManager] Library tidak boleh nil")
    ProfileManager.Library = Library
end

--- Opsional: integrasikan dengan SaveManager agar profil pakai
--- sistem penyimpanan yang sama.
function ProfileManager:SetSaveManager(SaveManager)
    ProfileManager.SaveManager = SaveManager
    -- Sinkronkan folder
    if SaveManager.Folder then
        ProfileManager.Folder = SaveManager.Folder
    end
    if SaveManager.SubFolder and SaveManager.SubFolder ~= "" then
        ProfileManager.SubFolder = SaveManager.SubFolder
    end
end

function ProfileManager:SetFolder(Folder: string)
    assert(typeof(Folder) == "string" and Folder ~= "", "[ProfileManager] Folder tidak valid")
    ProfileManager.Folder = Folder
    ProfileManager:_EnsureFolders()
end

function ProfileManager:SetSubFolder(SubFolder: string)
    assert(typeof(SubFolder) == "string" and SubFolder ~= "", "[ProfileManager] SubFolder tidak valid")
    ProfileManager.SubFolder = SubFolder
    ProfileManager:_EnsureFolders()
end

-- =========================================================
--                    PATH HELPERS
-- =========================================================

function ProfileManager:_GetProfilesPath(): string
    local Base = ProfileManager.Folder
    if ProfileManager.SubFolder ~= "" then
        return string.format("%s/%s/profiles", Base, ProfileManager.SubFolder)
    end
    return string.format("%s/profiles", Base)
end

function ProfileManager:_GetProfilePath(Name: string): string
    return string.format("%s/%s.json", ProfileManager:_GetProfilesPath(), Name)
end

function ProfileManager:_GetActiveFilePath(): string
    return string.format("%s/_active.txt", ProfileManager:_GetProfilesPath())
end

function ProfileManager:_EnsureFolders()
    local Path = ProfileManager:_GetProfilesPath()
    local Segments = Path:split("/")
    local Traversed = ""
    for _, Seg in ipairs(Segments) do
        Traversed = Traversed == "" and Seg or (Traversed .. "/" .. Seg)
        if not isfolder(Traversed) then
            pcall(makefolder, Traversed)
        end
    end
end

-- =========================================================
--                    SERIALISE / DESERIALISE
-- =========================================================

--- Kumpulkan semua nilai elemen UI saat ini ke dalam tabel
function ProfileManager:_CollectCurrentState(): { [string]: any }
    local Library = ProfileManager.Library
    assert(Library, "[ProfileManager] Library belum di-set")

    local State = {
        _version   = 1,
        _timestamp = os.time(),
        toggles    = {},
        options    = {},
    }

    -- Toggles
    for Idx, Toggle in Library.Toggles do
        if Toggle.Type then
            State.toggles[Idx] = Toggle.Value
        end
    end

    -- Options (Slider, Dropdown, ColorPicker, KeyPicker, Input)
    for Idx, Option in Library.Options do
        if not Option.Type then continue end

        if Option.Type == "Slider" then
            State.options[Idx] = { type = "Slider", value = Option.Value }

        elseif Option.Type == "Dropdown" then
            State.options[Idx] = { type = "Dropdown", value = Option.Value, multi = Option.Multi }

        elseif Option.Type == "ColorPicker" then
            State.options[Idx] = {
                type         = "ColorPicker",
                value        = Option.Value and Option.Value:ToHex() or "ffffff",
                transparency = Option.Transparency or 0,
            }

        elseif Option.Type == "KeyPicker" then
            State.options[Idx] = {
                type      = "KeyPicker",
                key       = Option.Value,
                mode      = Option.Mode,
                modifiers = Option.Modifiers,
                toggled   = Option.Toggled,
            }

        elseif Option.Type == "Input" then
            State.options[Idx] = { type = "Input", value = Option.Value }
        end
    end

    return State
end

--- Terapkan tabel state ke semua elemen UI
function ProfileManager:_ApplyState(State: { [string]: any })
    local Library = ProfileManager.Library
    assert(Library, "[ProfileManager] Library belum di-set")

    if not State or State._version ~= 1 then
        warn("[ProfileManager] Format state tidak valid")
        return false
    end

    -- Toggles
    if typeof(State.toggles) == "table" then
        for Idx, Value in State.toggles do
            local Toggle = Library.Toggles[Idx]
            if Toggle and Toggle.SetValue then
                task.defer(function()
                    pcall(Toggle.SetValue, Toggle, Value)
                end)
            end
        end
    end

    -- Options
    if typeof(State.options) == "table" then
        for Idx, Data in State.options do
            local Option = Library.Options[Idx]
            if not Option then continue end

            task.defer(function()
                local ok, err = pcall(function()
                    if Data.type == "Slider" then
                        Option:SetValue(Data.value)

                    elseif Data.type == "Dropdown" then
                        Option:SetValue(Data.value)

                    elseif Data.type == "ColorPicker" then
                        -- Obsidian ColorPicker: SetValue menerima Color3
                        -- Transparency disimpan terpisah jika ada
                        local color = Color3.fromHex(Data.value)
                        Option:SetValue(color)
                        if typeof(Data.transparency) == "number" and Option.SetTransparency then
                            pcall(function() Option:SetTransparency(Data.transparency) end)
                        end

                    elseif Data.type == "KeyPicker" then
                        Option:SetValue({ Data.key, Data.mode, Data.modifiers })
                        if Data.mode == "Toggle" and Data.toggled ~= nil then
                            Option.Toggled = Data.toggled
                            Option:Update()
                        end

                    elseif Data.type == "Input" then
                        Option:SetValue(Data.value)
                    end
                end)
                if not ok then
                    warn(string.format("[ProfileManager] Gagal apply opsi '%s': %s", Idx, err))
                end
            end)
        end
    end

    return true
end

-- =========================================================
--                    CRUD PROFIL
-- =========================================================

--- Simpan profil baru dengan nama tertentu
--- @return boolean, string? success, errorMessage
function ProfileManager:SaveProfile(Name: string): (boolean, string?)
    if not Name or Name:match("^%s*$") then
        return false, "Nama profil tidak boleh kosong"
    end
    if Name:find('[<>:"|%?%*%z/\\]') then
        return false, "Nama profil mengandung karakter yang tidak valid"
    end

    ProfileManager:_EnsureFolders()

    local State   = ProfileManager:_CollectCurrentState()
    local ok, Encoded = pcall(HttpService.JSONEncode, HttpService, State)
    if not ok then
        return false, "Gagal encode data: " .. tostring(Encoded)
    end

    local Path = ProfileManager:_GetProfilePath(Name)
    local writeOk, writeErr = pcall(writefile, Path, Encoded)
    if not writeOk then
        return false, "Gagal menulis file: " .. tostring(writeErr)
    end

    -- Update cache
    if not table.find(ProfileManager._ProfileCache, Name) then
        table.insert(ProfileManager._ProfileCache, Name)
    end

    return true
end

--- Muat dan terapkan profil berdasarkan nama
--- @return boolean, string? success, errorMessage
function ProfileManager:LoadProfile(Name: string): (boolean, string?)
    if not Name or Name:match("^%s*$") then
        return false, "Nama profil tidak boleh kosong"
    end

    local Path = ProfileManager:_GetProfilePath(Name)
    if not isfile(Path) then
        return false, string.format("Profil '%s' tidak ditemukan", Name)
    end

    local readOk, Content = pcall(readfile, Path)
    if not readOk then
        return false, "Gagal membaca file: " .. tostring(Content)
    end

    local decodeOk, State = pcall(HttpService.JSONDecode, HttpService, Content)
    if not decodeOk or typeof(State) ~= "table" then
        return false, "Data profil rusak atau format tidak valid"
    end

    local applied = ProfileManager:_ApplyState(State)
    if not applied then
        return false, "Gagal menerapkan state profil"
    end

    ProfileManager.ActiveProfile = Name
    pcall(function()
        writefile(ProfileManager:_GetActiveFilePath(), Name)
    end)

    return true
end

--- Hapus profil berdasarkan nama
--- @return boolean, string?
function ProfileManager:DeleteProfile(Name: string): (boolean, string?)
    if not Name or Name:match("^%s*$") then
        return false, "Nama profil tidak boleh kosong"
    end

    local Path = ProfileManager:_GetProfilePath(Name)
    if not isfile(Path) then
        return false, string.format("Profil '%s' tidak ditemukan", Name)
    end

    local ok, err = pcall(delfile, Path)
    if not ok then
        return false, "Gagal menghapus file: " .. tostring(err)
    end

    -- Hapus dari cache
    local idx = table.find(ProfileManager._ProfileCache, Name)
    if idx then table.remove(ProfileManager._ProfileCache, idx) end

    -- Reset active jika profil yang dihapus adalah yang aktif
    if ProfileManager.ActiveProfile == Name then
        ProfileManager.ActiveProfile = nil
        pcall(function()
            if isfile(ProfileManager:_GetActiveFilePath()) then
                delfile(ProfileManager:_GetActiveFilePath())
            end
        end)
    end

    return true
end

--- Rename profil
--- @return boolean, string?
function ProfileManager:RenameProfile(OldName: string, NewName: string): (boolean, string?)
    if not OldName or not NewName then
        return false, "Nama tidak boleh kosong"
    end
    if NewName:find('[<>:"|%?%*%z/\\]') then
        return false, "Nama baru mengandung karakter yang tidak valid"
    end

    local OldPath = ProfileManager:_GetProfilePath(OldName)
    if not isfile(OldPath) then
        return false, string.format("Profil '%s' tidak ditemukan", OldName)
    end

    local NewPath = ProfileManager:_GetProfilePath(NewName)
    if isfile(NewPath) then
        return false, string.format("Profil '%s' sudah ada", NewName)
    end

    -- Baca → tulis ulang dengan nama baru → hapus lama
    local readOk, Content = pcall(readfile, OldPath)
    if not readOk then return false, "Gagal membaca profil lama" end

    local writeOk, writeErr = pcall(writefile, NewPath, Content)
    if not writeOk then return false, "Gagal menulis profil baru: " .. tostring(writeErr) end

    pcall(delfile, OldPath)

    -- Update cache
    local idx = table.find(ProfileManager._ProfileCache, OldName)
    if idx then ProfileManager._ProfileCache[idx] = NewName end

    if ProfileManager.ActiveProfile == OldName then
        ProfileManager.ActiveProfile = NewName
        pcall(writefile, ProfileManager:_GetActiveFilePath(), NewName)
    end

    return true
end

-- =========================================================
--                    DAFTAR PROFIL
-- =========================================================

--- Ambil semua nama profil yang tersimpan
--- @return { string }
function ProfileManager:GetProfileList(): { string }
    ProfileManager:_EnsureFolders()
    local Path = ProfileManager:_GetProfilesPath()

    local ok, Files = pcall(listfiles, Path)
    if not ok or typeof(Files) ~= "table" then
        return {}
    end

    local Names = {}
    for _, FilePath in Files do
        local Raw = FilePath:match("(.+)%..+$")
        if not Raw then continue end
        local Pos  = Raw:gsub("\\", "/"):find("/[^/]*$")
        local Name = Pos and Raw:sub(Pos + 1) or Raw
        if Name and Name ~= "_active" then
            table.insert(Names, Name)
        end
    end

    table.sort(Names)
    ProfileManager._ProfileCache = Names
    return Names
end

--- Cek apakah profil dengan nama tertentu ada
function ProfileManager:ProfileExists(Name: string): boolean
    return isfile(ProfileManager:_GetProfilePath(Name))
end

--- Dapatkan nama profil yang sedang aktif (dari file atau memory)
function ProfileManager:GetActiveProfile(): string?
    if ProfileManager.ActiveProfile then
        return ProfileManager.ActiveProfile
    end

    local ActivePath = ProfileManager:_GetActiveFilePath()
    if isfile(ActivePath) then
        local ok, Name = pcall(readfile, ActivePath)
        if ok and Name and Name ~= "" then
            ProfileManager.ActiveProfile = Name
            return Name
        end
    end

    return nil
end

-- =========================================================
--                    EXPORT / IMPORT
-- =========================================================

--- Export profil ke string JSON (untuk di-copy ke clipboard)
--- @return string? jsonString atau nil jika gagal
function ProfileManager:ExportProfile(Name: string): string?
    local Path = ProfileManager:_GetProfilePath(Name)
    if not isfile(Path) then
        warn(string.format("[ProfileManager] Profil '%s' tidak ditemukan untuk di-export", Name))
        return nil
    end

    local ok, Content = pcall(readfile, Path)
    if not ok then return nil end

    -- Wrap dengan metadata export
    local ExportData = {
        _export_version = 1,
        _profile_name   = Name,
        _export_time    = os.time(),
        data            = Content,
    }

    local encOk, Encoded = pcall(HttpService.JSONEncode, HttpService, ExportData)
    if not encOk then return nil end

    return Encoded
end

--- Export profil aktif ke clipboard
function ProfileManager:ExportToClipboard(Name: string)
    local Exported = ProfileManager:ExportProfile(Name)
    if not Exported then
        warn("[ProfileManager] Export gagal")
        return false
    end

    local ok = pcall(function()
        setclipboard(Exported)
    end)

    return ok
end

--- Import profil dari string JSON (hasil export)
--- @param JsonString string
--- @param OverrideName string? nama override (opsional, default pakai nama dari export)
--- @return boolean, string?
function ProfileManager:ImportProfile(JsonString: string, OverrideName: string?): (boolean, string?)
    if not JsonString or JsonString == "" then
        return false, "Data import kosong"
    end

    local decOk, ImportData = pcall(HttpService.JSONDecode, HttpService, JsonString)
    if not decOk or typeof(ImportData) ~= "table" then
        return false, "Format data import tidak valid"
    end

    if ImportData._export_version ~= 1 then
        return false, "Versi export tidak didukung"
    end

    local ProfileName = OverrideName or ImportData._profile_name
    if not ProfileName or ProfileName == "" then
        return false, "Nama profil tidak valid"
    end

    local InnerData = ImportData.data
    if not InnerData then
        return false, "Data profil di dalam export kosong"
    end

    -- Validasi inner data
    local innerOk, Decoded = pcall(HttpService.JSONDecode, HttpService, InnerData)
    if not innerOk or typeof(Decoded) ~= "table" then
        return false, "Data profil di dalam export rusak"
    end

    ProfileManager:_EnsureFolders()
    local Path = ProfileManager:_GetProfilePath(ProfileName)
    local writeOk, writeErr = pcall(writefile, Path, InnerData)
    if not writeOk then
        return false, "Gagal menyimpan profil hasil import: " .. tostring(writeErr)
    end

    if not table.find(ProfileManager._ProfileCache, ProfileName) then
        table.insert(ProfileManager._ProfileCache, ProfileName)
    end

    return true
end

--- Import profil dari clipboard
--- @param OverrideName string? nama override opsional
--- @return boolean, string?
function ProfileManager:ImportFromClipboard(OverrideName: string?): (boolean, string?)
    local ClipContent = ""
    local ok = pcall(function()
        ClipContent = getclipboard()
    end)
    if not ok or ClipContent == "" then
        return false, "Clipboard kosong atau tidak didukung"
    end

    return ProfileManager:ImportProfile(ClipContent, OverrideName)
end

-- =========================================================
--                    UI SECTION
-- =========================================================

--- Bangun section ProfileManager di dalam Tab Obsidian
--- @param Tab any Tab dari Obsidian (AddLeftGroupbox akan dipanggil di dalamnya)
--- @param GroupboxName string? nama groupbox (default "Profil")
function ProfileManager:BuildProfileSection(Tab: any, GroupboxName: string?)
    assert(Tab, "[ProfileManager] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Profil", "layers")

    local ProfileListDropdown
    local ProfileNameInput
    local ActiveLabel

    local function Refresh()
        local List = ProfileManager:GetProfileList()
        if ProfileListDropdown then
            ProfileListDropdown:SetValues(#List > 0 and List or { "(kosong)" })
            ProfileListDropdown:SetValue(nil)
        end
        local Active = ProfileManager:GetActiveProfile()
        if ActiveLabel then
            ActiveLabel:SetText("Aktif: " .. (Active or "Belum ada"))
        end
    end

    -- Input nama profil baru
    Box:AddInput("PM_ProfileName", {
        Text        = "Nama Profil",
        Placeholder = "Masukkan nama profil...",
        Default     = "",
    })

    -- Tombol simpan
    Box:AddButton({
        Text    = "Simpan Profil Baru",
        Tooltip = "Simpan semua setting saat ini sebagai profil baru",
        Func    = function()
            local Input = ProfileManager.Library.Options.PM_ProfileName
            local Name  = Input and Input.Value or ""

            if Name == "" then
                ProfileManager.Library:Notify({ Title = "Profil", Description = "Nama profil tidak boleh kosong!", Time = 3 })
                return
            end

            if ProfileManager:ProfileExists(Name) then
                -- Tanya konfirmasi overwrite
                ProfileManager.Library.Window:AddDialog("PM_OverwriteConfirm", {
                    Title       = "Timpa Profil?",
                    Description = string.format("Profil '%s' sudah ada. Timpa dengan setting saat ini?", Name),
                    AutoDismiss = false,
                    FooterButtons = {
                        Cancel  = { Title = "Batal",  Variant = "Ghost",       Order = 1, Callback = function(d) d:Dismiss() end },
                        Confirm = { Title = "Timpa",  Variant = "Destructive", Order = 2, Callback = function(d)
                            d:Dismiss()
                            local ok, err = ProfileManager:SaveProfile(Name)
                            ProfileManager.Library:Notify({
                                Title       = ok and "Berhasil" or "Gagal",
                                Description = ok and string.format("Profil '%s' berhasil ditimpa.", Name) or err,
                                Time        = 3,
                            })
                            Refresh()
                        end},
                    },
                })
                return
            end

            local ok, err = ProfileManager:SaveProfile(Name)
            ProfileManager.Library:Notify({
                Title       = ok and "Berhasil" or "Gagal",
                Description = ok and string.format("Profil '%s' berhasil disimpan.", Name) or (err or ""),
                Time        = 3,
            })
            Refresh()
        end,
    })

    Box:AddDivider()

    -- Dropdown daftar profil
    Box:AddDropdown("PM_ProfileList", {
        Values   = ProfileManager:GetProfileList(),
        AllowNull = true,
        Text     = "Daftar Profil",
        Tooltip  = "Pilih profil untuk dimuat, dihapus, atau di-export",

        FormatDisplayValue = function(Value)
            if Value == ProfileManager.ActiveProfile then
                return Value .. " (aktif)"
            end
            return Value
        end,
        FormatListValue = function(Value)
            if Value == ProfileManager.ActiveProfile then
                return Value .. " (aktif)"
            end
            return Value
        end,
    })

    -- Muat profil
    Box:AddButton({
        Text    = "Muat Profil",
        Tooltip = "Terapkan profil yang dipilih ke semua setting",
        Func    = function()
            local Dropdown = ProfileManager.Library.Options.PM_ProfileList
            local Name     = Dropdown and Dropdown.Value
            if not Name or Name == "(kosong)" then
                ProfileManager.Library:Notify({ Title = "Profil", Description = "Pilih profil dulu!", Time = 2 })
                return
            end
            local ok, err = ProfileManager:LoadProfile(Name)
            ProfileManager.Library:Notify({
                Title       = ok and "Berhasil" or "Gagal",
                Description = ok and string.format("Profil '%s' berhasil dimuat.", Name) or (err or ""),
                Time        = 3,
            })
            Refresh()
        end,
    })

    -- Hapus profil
    Box:AddButton({
        Text    = "Hapus Profil",
        Tooltip = "Hapus profil yang dipilih secara permanen",
        Func    = function()
            local Dropdown = ProfileManager.Library.Options.PM_ProfileList
            local Name     = Dropdown and Dropdown.Value
            if not Name or Name == "(kosong)" then
                ProfileManager.Library:Notify({ Title = "Profil", Description = "Pilih profil dulu!", Time = 2 })
                return
            end

            ProfileManager.Library.Window:AddDialog("PM_DeleteConfirm", {
                Title       = "Hapus Profil?",
                Description = string.format("Apakah kamu yakin ingin menghapus profil '%s'? Tindakan ini tidak bisa dibatalkan.", Name),
                AutoDismiss = false,
                FooterButtons = {
                    Cancel = { Title = "Batal", Variant = "Ghost",       Order = 1, Callback = function(d) d:Dismiss() end },
                    Delete = { Title = "Hapus", Variant = "Destructive", Order = 2, Callback = function(d)
                        d:Dismiss()
                        local ok, err = ProfileManager:DeleteProfile(Name)
                        ProfileManager.Library:Notify({
                            Title       = ok and "Dihapus" or "Gagal",
                            Description = ok and string.format("Profil '%s' berhasil dihapus.", Name) or (err or ""),
                            Time        = 3,
                        })
                        Refresh()
                    end},
                },
            })
        end,
    })

    Box:AddDivider()

    -- Export / Import
    Box:AddButton({
        Text    = "Export ke Clipboard",
        Tooltip = "Salin profil yang dipilih ke clipboard untuk dibagikan",
        Func    = function()
            local Dropdown = ProfileManager.Library.Options.PM_ProfileList
            local Name     = Dropdown and Dropdown.Value
            if not Name or Name == "(kosong)" then
                ProfileManager.Library:Notify({ Title = "Export", Description = "Pilih profil dulu!", Time = 2 })
                return
            end
            local ok = ProfileManager:ExportToClipboard(Name)
            ProfileManager.Library:Notify({
                Title       = ok and "Export Berhasil" or "Export Gagal",
                Description = ok
                    and string.format("Profil '%s' berhasil disalin ke clipboard.", Name)
                    or  "setclipboard tidak tersedia di executor ini.",
                Time = 3,
            })
        end,
    })

    Box:AddButton({
        Text    = "Import dari Clipboard",
        Tooltip = "Tempel profil dari clipboard dan simpan",
        Func    = function()
            local Input = ProfileManager.Library.Options.PM_ProfileName
            local Name  = Input and Input.Value ~= "" and Input.Value or nil

            local ok, err = ProfileManager:ImportFromClipboard(Name)
            ProfileManager.Library:Notify({
                Title       = ok and "Import Berhasil" or "Import Gagal",
                Description = ok and "Profil berhasil diimpor." or (err or ""),
                Time        = 3,
            })
            if ok then Refresh() end
        end,
    })

    Box:AddDivider()

    -- Refresh & Status
    Box:AddButton({
        Text    = "Refresh Daftar",
        Tooltip = "Perbarui daftar profil dari disk",
        Func    = Refresh,
    })

    ActiveLabel = Box:AddLabel("Aktif: " .. (ProfileManager:GetActiveProfile() or "Belum ada"), false)

    -- Simpan referensi untuk Refresh
    ProfileListDropdown = ProfileManager.Library.Options.PM_ProfileList
    ProfileNameInput    = ProfileManager.Library.Options.PM_ProfileName

    -- Load profil terakhir aktif saat startup
    task.defer(function()
        local Active = ProfileManager:GetActiveProfile()
        if Active and ProfileManager:ProfileExists(Active) then
            pcall(function()
                ProfileManager:LoadProfile(Active)
            end)
        end
        Refresh()
    end)

    return Box
end

-- =========================================================
--                    INIT
-- =========================================================

pcall(function() ProfileManager:_EnsureFolders() end)
return ProfileManager
