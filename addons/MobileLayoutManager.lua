-- MobileLayoutManager.lua
-- Addon untuk Obsidian Library
-- Kelola semua tombol mobile floating dari satu panel terpusat.
-- Fitur: daftarkan tombol, atur posisi/ukuran/warna, preset layout, simpan ke file.

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local isfolder, isfile, listfiles = isfolder, isfile, listfiles

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local MobileLayoutManager = {
    Library = nil,

    -- Semua tombol yang terdaftar
    -- Format entry: { id, label, gui, btn, stroke, visible, posX, posY, sizeW, sizeH, color, textColor }
    Buttons = {},

    -- Folder untuk menyimpan layout
    Folder  = "ObsidianLibSettings",

    -- Preset nama yang tersedia
    Presets = {},

    -- Apakah drag-to-reposition aktif
    DragEnabled = true,

    -- Tween info untuk animasi show/hide
    TweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- =========================================================
--                    SETUP
-- =========================================================

function MobileLayoutManager:SetLibrary(Library)
    assert(Library, "[MobileLayoutManager] Library tidak boleh nil")
    MobileLayoutManager.Library = Library
end

function MobileLayoutManager:SetFolder(Folder)
    assert(typeof(Folder) == "string" and Folder ~= "", "[MobileLayoutManager] Folder tidak valid")
    MobileLayoutManager.Folder = Folder
    MobileLayoutManager:_EnsureFolders()
end

-- =========================================================
--                    PATH HELPERS
-- =========================================================

function MobileLayoutManager:_GetLayoutsPath()
    return MobileLayoutManager.Folder .. "/mobile_layouts"
end

function MobileLayoutManager:_GetLayoutPath(Name)
    return MobileLayoutManager:_GetLayoutsPath() .. "/" .. Name .. ".json"
end

function MobileLayoutManager:_EnsureFolders()
    local Path = MobileLayoutManager:_GetLayoutsPath()
    local Segs = Path:split("/")
    local Trav = ""
    for _, S in ipairs(Segs) do
        Trav = Trav == "" and S or (Trav .. "/" .. S)
        if not isfolder(Trav) then pcall(makefolder, Trav) end
    end
end

-- =========================================================
--                    INTERNAL - DRAG SETUP
-- =========================================================

--- Pasang logika drag-to-reposition pada sebuah tombol
local function AttachDrag(Entry)
    local btn  = Entry.btn
    local drag, ds, sp = false, nil, nil

    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            drag = true
            ds   = i.Position
            sp   = btn.Position
        end
    end)

    btn.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            drag = false
            -- Simpan posisi terbaru ke Entry
            Entry.posX = btn.Position.X.Offset
            Entry.posY = btn.Position.Y.Offset
        end
    end)

    UserInputService.InputChanged:Connect(function(i)
        if not drag then return end
        if not MobileLayoutManager.DragEnabled then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
        and i.UserInputType ~= Enum.UserInputType.Touch then return end

        btn.Position = UDim2.new(
            sp.X.Scale,
            sp.X.Offset + (i.Position.X - ds.X),
            sp.Y.Scale,
            sp.Y.Offset + (i.Position.Y - ds.Y)
        )
    end)
end

-- =========================================================
--                    REGISTER TOMBOL
-- =========================================================

--- Daftarkan tombol mobile yang sudah ada ke MobileLayoutManager
--- @param Id string        ID unik
--- @param Label string     Nama tampilan di panel
--- @param Gui ScreenGui    ScreenGui induk tombol
--- @param Btn TextButton   Instance tombol
--- @param Options table?   { stroke, posX, posY, sizeW, sizeH, visible, category }
--- @return Entry table
function MobileLayoutManager:Register(Id, Label, Gui, Btn, Options)
    assert(Id    and Id    ~= "", "[MobileLayoutManager] Id tidak boleh kosong")
    assert(Label and Label ~= "", "[MobileLayoutManager] Label tidak boleh kosong")
    assert(Gui,  "[MobileLayoutManager] Gui tidak boleh nil")
    assert(Btn,  "[MobileLayoutManager] Btn tidak boleh nil")

    Options = Options or {}

    -- Hapus entry lama jika sudah ada
    MobileLayoutManager:Unregister(Id)

    local Entry = {
        id        = Id,
        label     = Label,
        gui       = Gui,
        btn       = Btn,
        stroke    = Options.stroke,
        posX      = Options.posX    or Btn.Position.X.Offset,
        posY      = Options.posY    or Btn.Position.Y.Offset,
        sizeW     = Options.sizeW   or Btn.Size.X.Offset,
        sizeH     = Options.sizeH   or Btn.Size.Y.Offset,
        visible   = Options.visible ~= false,
        category  = Options.category or "Umum",
        color     = Options.color,
        textColor = Options.textColor,
    }

    -- Sinkronkan visibility
    Gui.Enabled = Entry.visible

    AttachDrag(Entry)
    table.insert(MobileLayoutManager.Buttons, Entry)
    return Entry
end

--- Hapus registrasi tombol
function MobileLayoutManager:Unregister(Id)
    for i = #MobileLayoutManager.Buttons, 1, -1 do
        if MobileLayoutManager.Buttons[i].id == Id then
            table.remove(MobileLayoutManager.Buttons, i)
            return true
        end
    end
    return false
end

--- Dapatkan entry berdasarkan Id
function MobileLayoutManager:GetEntry(Id)
    for _, E in ipairs(MobileLayoutManager.Buttons) do
        if E.id == Id then return E end
    end
    return nil
end

-- =========================================================
--                    KONTROL INDIVIDUAL
-- =========================================================

--- Tampilkan / sembunyikan tombol
function MobileLayoutManager:SetVisible(Id, Visible)
    local E = MobileLayoutManager:GetEntry(Id)
    if not E then return false end
    E.visible     = Visible
    E.gui.Enabled = Visible
    return true
end

--- Pindahkan tombol ke posisi baru
function MobileLayoutManager:SetPosition(Id, PosX, PosY, Animate)
    local E = MobileLayoutManager:GetEntry(Id)
    if not E then return false end
    E.posX = PosX
    E.posY = PosY
    if Animate then
        TweenService:Create(E.btn, MobileLayoutManager.TweenInfo,
            { Position = UDim2.fromOffset(PosX, PosY) }):Play()
    else
        E.btn.Position = UDim2.fromOffset(PosX, PosY)
    end
    return true
end

--- Ubah ukuran tombol
function MobileLayoutManager:SetSize(Id, W, H)
    local E = MobileLayoutManager:GetEntry(Id)
    if not E then return false end
    E.sizeW    = W
    E.sizeH    = H
    E.btn.Size = UDim2.fromOffset(W, H)
    return true
end

--- Ubah warna background tombol
function MobileLayoutManager:SetColor(Id, BgColor, TxtColor)
    local E = MobileLayoutManager:GetEntry(Id)
    if not E then return false end
    if BgColor  then E.color              = BgColor;  E.btn.BackgroundColor3 = BgColor  end
    if TxtColor then E.textColor          = TxtColor; E.btn.TextColor3       = TxtColor end
    return true
end

--- Tampilkan / sembunyikan semua tombol sekaligus
function MobileLayoutManager:SetAllVisible(Visible)
    for _, E in ipairs(MobileLayoutManager.Buttons) do
        E.visible     = Visible
        E.gui.Enabled = Visible
    end
end

-- =========================================================
--                    PRESET LAYOUTS
-- =========================================================

--- Preset bawaan posisi tombol
local BuiltInPresets = {
    ["Kiri"] = function(Buttons)
        local Y = 100
        for _, E in ipairs(Buttons) do
            MobileLayoutManager:SetPosition(E.id, 8, Y, true)
            Y = Y + (E.sizeH or 34) + 8
        end
    end,
    ["Kanan"] = function(Buttons)
        local ScreenW = workspace.CurrentCamera
            and workspace.CurrentCamera.ViewportSize.X or 1080
        local Y = 100
        for _, E in ipairs(Buttons) do
            local W = E.sizeW or 110
            MobileLayoutManager:SetPosition(E.id, ScreenW - W - 8, Y, true)
            Y = Y + (E.sizeH or 34) + 8
        end
    end,
    ["Tersebar"] = function(Buttons)
        local ScreenW = workspace.CurrentCamera
            and workspace.CurrentCamera.ViewportSize.X or 1080
        local ScreenH = workspace.CurrentCamera
            and workspace.CurrentCamera.ViewportSize.Y or 1920
        local Count   = #Buttons
        if Count == 0 then return end
        local ColMax  = 3
        local Col, Row = 0, 0
        for _, E in ipairs(Buttons) do
            local W   = E.sizeW or 110
            local H   = E.sizeH or 34
            local X   = 8 + Col * (W + 8)
            local Y   = ScreenH - 200 - Row * (H + 8)
            MobileLayoutManager:SetPosition(E.id, X, Y, true)
            Col = Col + 1
            if Col >= ColMax then Col = 0; Row = Row + 1 end
        end
    end,
}

--- Terapkan preset layout
--- @param PresetName string  "Kiri" | "Kanan" | "Tersebar" | nama custom
function MobileLayoutManager:ApplyPreset(PresetName)
    -- Cek built-in
    if BuiltInPresets[PresetName] then
        BuiltInPresets[PresetName](MobileLayoutManager.Buttons)
        return true
    end
    -- Cek preset custom yang tersimpan
    local ok, err = MobileLayoutManager:LoadLayout(PresetName)
    return ok, err
end

-- =========================================================
--                    SAVE / LOAD LAYOUT
-- =========================================================

--- Simpan posisi & visibility semua tombol ke file JSON
--- @param Name string  nama layout
--- @return boolean, string?
function MobileLayoutManager:SaveLayout(Name)
    if not Name or Name == "" then return false, "Nama layout kosong" end

    MobileLayoutManager:_EnsureFolders()

    local Data = { _version = 1, buttons = {} }
    for _, E in ipairs(MobileLayoutManager.Buttons) do
        -- Baca posisi terkini dari instance (mungkin sudah di-drag)
        local CurrX = E.btn.Position.X.Offset
        local CurrY = E.btn.Position.Y.Offset
        Data.buttons[E.id] = {
            posX    = CurrX,
            posY    = CurrY,
            sizeW   = E.sizeW,
            sizeH   = E.sizeH,
            visible = E.visible,
        }
    end

    local ok, Encoded = pcall(HttpService.JSONEncode, HttpService, Data)
    if not ok then return false, "Gagal encode: " .. tostring(Encoded) end

    local wOk, wErr = pcall(writefile, MobileLayoutManager:_GetLayoutPath(Name), Encoded)
    if not wOk then return false, "Gagal tulis file: " .. tostring(wErr) end

    -- Tambahkan ke cache preset
    if not table.find(MobileLayoutManager.Presets, Name) then
        table.insert(MobileLayoutManager.Presets, Name)
    end

    return true
end

--- Muat layout dari file dan terapkan
--- @param Name string
--- @return boolean, string?
function MobileLayoutManager:LoadLayout(Name)
    if not Name or Name == "" then return false, "Nama layout kosong" end

    local Path = MobileLayoutManager:_GetLayoutPath(Name)
    if not isfile(Path) then
        return false, string.format("Layout '%s' tidak ditemukan", Name)
    end

    local rOk, Content = pcall(readfile, Path)
    if not rOk then return false, "Gagal baca file" end

    local dOk, Data = pcall(HttpService.JSONDecode, HttpService, Content)
    if not dOk or typeof(Data) ~= "table" or Data._version ~= 1 then
        return false, "Format layout tidak valid"
    end

    local Applied = 0
    for Id, BtnData in Data.buttons do
        local E = MobileLayoutManager:GetEntry(Id)
        if E then
            MobileLayoutManager:SetPosition(Id, BtnData.posX, BtnData.posY, true)
            if typeof(BtnData.sizeW) == "number" and typeof(BtnData.sizeH) == "number" then
                MobileLayoutManager:SetSize(Id, BtnData.sizeW, BtnData.sizeH)
            end
            if typeof(BtnData.visible) == "boolean" then
                MobileLayoutManager:SetVisible(Id, BtnData.visible)
            end
            Applied += 1
        end
    end

    return true, string.format("%d tombol berhasil dimuat", Applied)
end

--- Hapus layout
function MobileLayoutManager:DeleteLayout(Name)
    local Path = MobileLayoutManager:_GetLayoutPath(Name)
    if not isfile(Path) then return false, "Layout tidak ditemukan" end
    local ok, err = pcall(delfile, Path)
    if not ok then return false, tostring(err) end

    local idx = table.find(MobileLayoutManager.Presets, Name)
    if idx then table.remove(MobileLayoutManager.Presets, idx) end
    return true
end

--- Dapatkan semua layout tersimpan
function MobileLayoutManager:GetLayoutList()
    MobileLayoutManager:_EnsureFolders()
    local Path = MobileLayoutManager:_GetLayoutsPath()
    local ok, Files = pcall(listfiles, Path)
    if not ok or typeof(Files) ~= "table" then return {} end

    local Names = {}
    for _, F in ipairs(Files) do
        local Raw = F:match("(.+)%..+$")
        if not Raw then continue end
        local Pos  = Raw:gsub("\\", "/"):find("/[^/]*$")
        local Name = Pos and Raw:sub(Pos + 1) or Raw
        if Name then table.insert(Names, Name) end
    end
    table.sort(Names)
    MobileLayoutManager.Presets = Names
    return Names
end

-- =========================================================
--                    UI SECTION
-- =========================================================

--- Bangun panel MobileLayoutManager di dalam Tab Obsidian
--- @param Tab any            Tab Obsidian
--- @param GroupboxName string?
function MobileLayoutManager:BuildLayoutSection(Tab, GroupboxName)
    assert(Tab, "[MobileLayoutManager] Tab tidak boleh nil")

    local BoxLeft  = Tab:AddLeftGroupbox(GroupboxName or "Mobile Layout", "smartphone")
    local BoxRight = Tab:AddRightGroupbox("Tombol Individual", "toggle-right")

    local LayoutListDropdown
    local BtnListDropdown
    local StatusLabel

    -- Helper: buat daftar id→label untuk dropdown tombol
    local function GetBtnValues()
        local Values = {}
        for _, E in ipairs(MobileLayoutManager.Buttons) do
            table.insert(Values, E.id .. " | " .. E.label)
        end
        return #Values > 0 and Values or { "(belum ada tombol)" }
    end

    local function GetSelectedId()
        local Dropdown = MobileLayoutManager.Library and MobileLayoutManager.Library.Options.MLM_BtnList
        if not Dropdown or not Dropdown.Value then return nil end
        local Id = Dropdown.Value:match("^([^|]+)") -- ambil sebelum " | "
        return Id and Id:match("^%s*(.-)%s*$") or nil  -- trim
    end

    local function RefreshLayouts()
        local List = MobileLayoutManager:GetLayoutList()
        if LayoutListDropdown then
            LayoutListDropdown:SetValues(#List > 0 and List or { "(kosong)" })
            LayoutListDropdown:SetValue(nil)
        end
    end

    local function RefreshBtnList()
        if BtnListDropdown then
            BtnListDropdown:SetValues(GetBtnValues())
            BtnListDropdown:SetValue(nil)
        end
    end

    local function SetStatus(Msg)
        if StatusLabel then StatusLabel:SetText("Status: " .. Msg) end
    end

    -- ── KIRI: Preset & Layout ──────────────────────────────
    -- Preset bawaan
    BoxLeft:AddDropdown("MLM_Preset", {
        Values    = { "Kiri", "Kanan", "Tersebar" },
        Default   = "Kiri",
        Text      = "Preset Layout",
        AllowNull = false,
    })

    BoxLeft:AddButton({
        Text    = "Terapkan Preset",
        Tooltip = "Susun semua tombol sesuai preset yang dipilih",
        Func    = function()
            local PresetDD = MobileLayoutManager.Library.Options.MLM_Preset
            local Name = PresetDD and PresetDD.Value or "Kiri"
            local ok, err = MobileLayoutManager:ApplyPreset(Name)
            SetStatus(ok and ("Preset '" .. Name .. "' diterapkan") or (err or "Gagal"))
        end,
    })

    BoxLeft:AddDivider()

    -- Simpan / Muat layout custom
    BoxLeft:AddInput("MLM_LayoutName", {
        Text        = "Nama Layout",
        Placeholder = "Ketik nama layout...",
        Default     = "",
    })

    BoxLeft:AddButton({
        Text    = "Simpan Layout",
        Tooltip = "Simpan posisi semua tombol saat ini ke file",
        Func    = function()
            local Input = MobileLayoutManager.Library.Options.MLM_LayoutName
            local Name  = Input and Input.Value or ""
            if Name == "" then
                SetStatus("Nama layout tidak boleh kosong")
                return
            end
            local ok, err = MobileLayoutManager:SaveLayout(Name)
            SetStatus(ok and ("Layout '" .. Name .. "' disimpan") or (err or "Gagal"))
            RefreshLayouts()
        end,
    })

    BoxLeft:AddDropdown("MLM_LayoutList", {
        Values    = MobileLayoutManager:GetLayoutList(),
        AllowNull = true,
        Text      = "Layout Tersimpan",
    })

    BoxLeft:AddButton({
        Text    = "Muat Layout",
        Tooltip = "Terapkan layout yang dipilih",
        Func    = function()
            local DD   = MobileLayoutManager.Library.Options.MLM_LayoutList
            local Name = DD and DD.Value
            if not Name or Name == "(kosong)" then
                SetStatus("Pilih layout dulu")
                return
            end
            local ok, msg = MobileLayoutManager:LoadLayout(Name)
            SetStatus(ok and msg or (msg or "Gagal"))
        end,
    })

    BoxLeft:AddButton({
        Text    = "Hapus Layout",
        Tooltip = "Hapus layout yang dipilih dari disk",
        Risky   = true,
        Func    = function()
            local DD   = MobileLayoutManager.Library.Options.MLM_LayoutList
            local Name = DD and DD.Value
            if not Name or Name == "(kosong)" then
                SetStatus("Pilih layout dulu")
                return
            end
            local ok, err = MobileLayoutManager:DeleteLayout(Name)
            SetStatus(ok and ("Layout '" .. Name .. "' dihapus") or (err or "Gagal"))
            RefreshLayouts()
        end,
    })

    BoxLeft:AddButton({ Text = "Refresh Daftar", Func = RefreshLayouts })

    BoxLeft:AddDivider()

    -- Sembunyikan / tampilkan semua
    BoxLeft:AddButton({
        Text    = "Tampilkan Semua",
        Tooltip = "Tampilkan semua tombol mobile",
        Func    = function()
            MobileLayoutManager:SetAllVisible(true)
            SetStatus("Semua tombol ditampilkan")
        end,
    })

    BoxLeft:AddButton({
        Text    = "Sembunyikan Semua",
        Tooltip = "Sembunyikan semua tombol mobile",
        Func    = function()
            MobileLayoutManager:SetAllVisible(false)
            SetStatus("Semua tombol disembunyikan")
        end,
    })

    -- Toggle drag
    BoxLeft:AddToggle("MLM_DragEnabled", {
        Text    = "Drag to Reposition",
        Default = true,
        Tooltip = "Aktifkan/nonaktifkan drag tombol langsung di layar",
        Callback = function(Value)
            MobileLayoutManager.DragEnabled = Value
        end,
    })

    StatusLabel = BoxLeft:AddLabel("Status: Siap", false)

    -- ── KANAN: Kontrol Per-Tombol ──────────────────────────
    BoxRight:AddDropdown("MLM_BtnList", {
        Values    = GetBtnValues(),
        AllowNull = true,
        Text      = "Pilih Tombol",
        Tooltip   = "Pilih tombol yang ingin diatur",
    })

    BoxRight:AddToggle("MLM_BtnVisible", {
        Text    = "Tampilkan Tombol",
        Default = true,
        Tooltip = "Toggle visibility tombol yang dipilih",
        Callback = function(Value)
            local Id = GetSelectedId()
            if Id then MobileLayoutManager:SetVisible(Id, Value) end
        end,
    })

    BoxRight:AddInput("MLM_PosX", {
        Text = "Posisi X", Default = "8", Numeric = true, Finished = true,
        Placeholder = "Pixel dari kiri",
    })
    BoxRight:AddInput("MLM_PosY", {
        Text = "Posisi Y", Default = "100", Numeric = true, Finished = true,
        Placeholder = "Pixel dari atas",
    })

    BoxRight:AddButton({
        Text    = "Terapkan Posisi",
        Tooltip = "Pindahkan tombol ke koordinat X,Y yang diisi",
        Func    = function()
            local Id  = GetSelectedId()
            if not Id then SetStatus("Pilih tombol dulu"); return end
            local Lib = MobileLayoutManager.Library
            local X   = tonumber(Lib.Options.MLM_PosX and Lib.Options.MLM_PosX.Value) or 8
            local Y   = tonumber(Lib.Options.MLM_PosY and Lib.Options.MLM_PosY.Value) or 100
            MobileLayoutManager:SetPosition(Id, X, Y, true)
            SetStatus(string.format("Tombol '%s' dipindah ke (%d, %d)", Id, X, Y))
        end,
    })

    BoxRight:AddInput("MLM_SizeW", {
        Text = "Lebar (px)", Default = "110", Numeric = true, Finished = true,
    })
    BoxRight:AddInput("MLM_SizeH", {
        Text = "Tinggi (px)", Default = "30", Numeric = true, Finished = true,
    })

    BoxRight:AddButton({
        Text    = "Terapkan Ukuran",
        Tooltip = "Ubah ukuran tombol yang dipilih",
        Func    = function()
            local Id  = GetSelectedId()
            if not Id then SetStatus("Pilih tombol dulu"); return end
            local Lib = MobileLayoutManager.Library
            local W   = tonumber(Lib.Options.MLM_SizeW and Lib.Options.MLM_SizeW.Value) or 110
            local H   = tonumber(Lib.Options.MLM_SizeH and Lib.Options.MLM_SizeH.Value) or 30
            MobileLayoutManager:SetSize(Id, W, H)
            SetStatus(string.format("Ukuran tombol '%s' diubah ke %dx%d", Id, W, H))
        end,
    })

    BoxRight:AddButton({
        Text    = "Refresh Daftar Tombol",
        Tooltip = "Perbarui daftar tombol yang terdaftar",
        Func    = RefreshBtnList,
    })

    -- Simpan referensi dropdown untuk refresh
    LayoutListDropdown = MobileLayoutManager.Library and MobileLayoutManager.Library.Options.MLM_LayoutList
    BtnListDropdown    = MobileLayoutManager.Library and MobileLayoutManager.Library.Options.MLM_BtnList

    return BoxLeft, BoxRight
end

-- =========================================================
--                    INIT
-- =========================================================

MobileLayoutManager:_EnsureFolders()
return MobileLayoutManager
