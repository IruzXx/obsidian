-- NotificationManager.lua
-- Addon untuk Obsidian Library
-- Memperluas sistem notifikasi dengan queue, kategori, tombol aksi, dan history log
-- Dibuat untuk digunakan bersama Library dari Obsidian

local NotificationManager = {
    Library = nil,

    -- Antrian notifikasi
    Queue = {},
    IsProcessing = false,

    -- History semua notifikasi
    History = {},
    MaxHistory = 50,

    -- Pengaturan
    QueueDelay = 0.3,       -- Jeda antar notifikasi dari queue (detik)
    DefaultTime = 3,        -- Durasi default notifikasi (detik)
    MaxQueue = 20,          -- Maksimal antrian

    -- Kategori warna
    Categories = {
        Info    = { Icon = "info",          Color = Color3.fromRGB(80,  150, 255) },
        Success = { Icon = "check-circle",  Color = Color3.fromRGB(80,  200, 100) },
        Warning = { Icon = "triangle-alert",Color = Color3.fromRGB(255, 200, 50)  },
        Error   = { Icon = "x-circle",      Color = Color3.fromRGB(255, 70,  70)  },
        Custom  = { Icon = "bell",          Color = Color3.fromRGB(180, 100, 255) },
    },
}

-- =========================================================
--                    SETUP
-- =========================================================

function NotificationManager:SetLibrary(Library)
    assert(Library, "Library tidak boleh nil")
    NotificationManager.Library = Library
end

-- =========================================================
--                    INTERNAL HELPERS
-- =========================================================

local function SafeNotify(Data)
    local Library = NotificationManager.Library
    if not Library or not Library.Notify then return end

    local ok, err = pcall(function()
        Library:Notify(Data)
    end)
    if not ok then
        warn("[NotificationManager] Gagal menampilkan notifikasi:", err)
    end
end

local function AddToHistory(Entry)
    table.insert(NotificationManager.History, 1, Entry)
    -- Batasi history
    if #NotificationManager.History > NotificationManager.MaxHistory then
        table.remove(NotificationManager.History, #NotificationManager.History)
    end
end

local function ProcessQueue()
    if NotificationManager.IsProcessing then return end
    NotificationManager.IsProcessing = true

    task.spawn(function()
        while #NotificationManager.Queue > 0 do
            local Entry = table.remove(NotificationManager.Queue, 1)
            SafeNotify(Entry.NotifyData)
            AddToHistory(Entry)
            task.wait(NotificationManager.QueueDelay + (Entry.NotifyData.Time or NotificationManager.DefaultTime))
        end
        NotificationManager.IsProcessing = false
    end)
end

local function BuildNotifyData(Category, Title, Description, Time, ExtraData)
    local CatData = NotificationManager.Categories[Category] or NotificationManager.Categories.Info
    ExtraData = ExtraData or {}

    local Data = {
        Title           = Title or Category,
        Description     = Description or "",
        Time            = Time or NotificationManager.DefaultTime,
        TitleColor      = ExtraData.TitleColor or CatData.Color,
        Icon            = ExtraData.Icon or CatData.Icon,
        IconColor       = ExtraData.IconColor or CatData.Color,
        BigIcon         = ExtraData.BigIcon,
        SoundId         = ExtraData.SoundId,
        Volume          = ExtraData.Volume,
        Persist         = ExtraData.Persist,
    }

    return Data
end

-- =========================================================
--                    API PUBLIK - NOTIFY
-- =========================================================

--- Tampilkan notifikasi Info (biru)
function NotificationManager:Info(Title, Description, Time, ExtraData)
    local Data = BuildNotifyData("Info", Title, Description, Time, ExtraData)
    local Entry = {
        Category = "Info",
        NotifyData = Data,
        Timestamp = os.time(),
    }
    if #NotificationManager.Queue < NotificationManager.MaxQueue then
        table.insert(NotificationManager.Queue, Entry)
        ProcessQueue()
    end
end

--- Tampilkan notifikasi Success (hijau)
function NotificationManager:Success(Title, Description, Time, ExtraData)
    local Data = BuildNotifyData("Success", Title, Description, Time, ExtraData)
    local Entry = {
        Category = "Success",
        NotifyData = Data,
        Timestamp = os.time(),
    }
    if #NotificationManager.Queue < NotificationManager.MaxQueue then
        table.insert(NotificationManager.Queue, Entry)
        ProcessQueue()
    end
end

--- Tampilkan notifikasi Warning (kuning)
function NotificationManager:Warning(Title, Description, Time, ExtraData)
    local Data = BuildNotifyData("Warning", Title, Description, Time, ExtraData)
    local Entry = {
        Category = "Warning",
        NotifyData = Data,
        Timestamp = os.time(),
    }
    if #NotificationManager.Queue < NotificationManager.MaxQueue then
        table.insert(NotificationManager.Queue, Entry)
        ProcessQueue()
    end
end

--- Tampilkan notifikasi Error (merah)
function NotificationManager:Error(Title, Description, Time, ExtraData)
    local Data = BuildNotifyData("Error", Title, Description, Time, ExtraData)
    local Entry = {
        Category = "Error",
        NotifyData = Data,
        Timestamp = os.time(),
    }
    if #NotificationManager.Queue < NotificationManager.MaxQueue then
        table.insert(NotificationManager.Queue, Entry)
        ProcessQueue()
    end
end

--- Tampilkan notifikasi Custom (ungu)
function NotificationManager:Custom(Title, Description, Time, ExtraData)
    local Data = BuildNotifyData("Custom", Title, Description, Time, ExtraData)
    local Entry = {
        Category = "Custom",
        NotifyData = Data,
        Timestamp = os.time(),
    }
    if #NotificationManager.Queue < NotificationManager.MaxQueue then
        table.insert(NotificationManager.Queue, Entry)
        ProcessQueue()
    end
end

--- Tampilkan notifikasi dengan tombol konfirmasi (Ya/Tidak)
--- @param Title string
--- @param Description string
--- @param OnConfirm function dipanggil saat user klik "Ya"
--- @param OnCancel function? dipanggil saat user klik "Tidak" (opsional)
--- @param Time number? durasi (default 8 detik)
function NotificationManager:Confirm(Title, Description, OnConfirm, OnCancel, Time)
    local Library = NotificationManager.Library
    if not Library then return end

    -- Tampilkan via Dialog Obsidian
    local ok, err = pcall(function()
        Library.Window:AddDialog("NM_Confirm_" .. tostring(os.clock()), {
            Title       = Title or "Konfirmasi",
            Description = Description or "",
            AutoDismiss = false,
            OutsideClickDismiss = false,

            FooterButtons = {
                Cancel = {
                    Title    = "Tidak",
                    Variant  = "Ghost",
                    Order    = 1,
                    Callback = function(Dialog)
                        Dialog:Dismiss()
                        if typeof(OnCancel) == "function" then
                            pcall(OnCancel)
                        end
                    end,
                },
                Confirm = {
                    Title    = "Ya",
                    Variant  = "Primary",
                    Order    = 2,
                    Callback = function(Dialog)
                        Dialog:Dismiss()
                        if typeof(OnConfirm) == "function" then
                            pcall(OnConfirm)
                        end
                    end,
                },
            },
        })
    end)

    if not ok then
        -- Fallback: tampilkan notifikasi biasa jika Dialog tidak tersedia
        warn("[NotificationManager] Confirm dialog gagal, fallback ke notifikasi biasa:", err)
        NotificationManager:Warning(Title, Description .. "\n(Gunakan dialog manual)", Time or 5)
    end

    -- Simpan ke history
    AddToHistory({
        Category   = "Confirm",
        NotifyData = { Title = Title, Description = Description },
        Timestamp  = os.time(),
    })
end

--- Tampilkan notifikasi dengan progress bar (step-based)
--- @return NotificationHandle object dengan method :SetStep(n), :SetDescription(s), :Finish(msg), :Destroy()
function NotificationManager:Progress(Title, Description, TotalSteps)
    local Library = NotificationManager.Library
    if not Library then return { Destroyed = true, SetStep = function() end, SetDescription = function() end, Finish = function() end, Destroy = function() end } end

    local Handle = { Destroyed = false }
    local NotifObj = nil
    local Steps = TotalSteps or 10

    -- Obsidian tidak mendukung "persistent" notif via Instance trick secara resmi.
    -- Kita simpan referensi dan gunakan waktu yang cukup panjang (999 detik),
    -- lalu destroy manual saat selesai.
    local ok, result = pcall(function()
        return Library:Notify({
            Title       = Title or "Progress",
            Description = Description or "",
            Time        = 999,
            Steps       = Steps,
            TitleColor  = NotificationManager.Categories.Info.Color,
        })
    end)

    if ok and result then
        NotifObj = result
    else
        -- Fallback: tidak ada NotifObj, Handle tetap valid tapi silent
        warn("[NotificationManager] Gagal membuat progress notification, berjalan tanpa UI")
    end

    function Handle:SetStep(Step)
        if Handle.Destroyed or not NotifObj then return end
        pcall(function() NotifObj:ChangeStep(Step) end)
    end

    function Handle:SetDescription(Text)
        if Handle.Destroyed or not NotifObj then return end
        pcall(function() NotifObj:ChangeDescription(Text) end)
    end

    function Handle:Finish(FinishMessage)
        if Handle.Destroyed then return end
        Handle:SetStep(Steps)
        Handle:SetDescription(FinishMessage or "Selesai!")
        task.delay(1.5, function()
            Handle:Destroy()
        end)
    end

    function Handle:Destroy()
        if Handle.Destroyed then return end
        Handle.Destroyed = true
        if NotifObj then
            pcall(function() NotifObj:Destroy() end)
            NotifObj = nil
        end
    end

    return Handle
end

-- =========================================================
--                    QUEUE MANAGEMENT
-- =========================================================

--- Bersihkan semua antrian notifikasi yang belum tampil
function NotificationManager:ClearQueue()
    NotificationManager.Queue = {}
    NotificationManager.IsProcessing = false
end

--- Dapatkan jumlah notifikasi di antrian
function NotificationManager:GetQueueCount()
    return #NotificationManager.Queue
end

-- =========================================================
--                    HISTORY
-- =========================================================

--- Dapatkan semua history notifikasi
--- @return table Array of { Category, NotifyData, Timestamp }
function NotificationManager:GetHistory()
    return NotificationManager.History
end

--- Bersihkan history
function NotificationManager:ClearHistory()
    NotificationManager.History = {}
end

--- Dapatkan history yang difilter berdasarkan kategori
function NotificationManager:GetHistoryByCategory(Category)
    local Result = {}
    for _, Entry in ipairs(NotificationManager.History) do
        if Entry.Category == Category then
            table.insert(Result, Entry)
        end
    end
    return Result
end

--- Format timestamp ke string yang mudah dibaca
function NotificationManager:FormatTimestamp(Timestamp)
    return os.date("%H:%M:%S", Timestamp)
end

-- =========================================================
--                    UI SECTION (opsional)
-- =========================================================

--- Tambahkan section History ke dalam Groupbox Obsidian
--- @param Groupbox any Groupbox dari Obsidian
function NotificationManager:BuildHistorySection(Groupbox)
    assert(Groupbox, "Groupbox tidak boleh nil")

    local HistoryLabel = Groupbox:AddLabel("History: (kosong)", true)
    local CategoryFilter = "Semua"

    local function RefreshHistoryLabel()
        local History = CategoryFilter == "Semua"
            and NotificationManager:GetHistory()
            or NotificationManager:GetHistoryByCategory(CategoryFilter)

        if #History == 0 then
            HistoryLabel:SetText("History: (kosong)")
            return
        end

        local Lines = {}
        for i, Entry in ipairs(History) do
            if i > 10 then break end -- Tampilkan max 10
            local Time = NotificationManager:FormatTimestamp(Entry.Timestamp)
            local Title = (Entry.NotifyData and Entry.NotifyData.Title) or "?"
            table.insert(Lines, string.format("[%s] %s: %s", Time, Entry.Category, Title))
        end

        HistoryLabel:SetText(table.concat(Lines, "\n"))
    end

    Groupbox:AddDropdown("NM_CategoryFilter", {
        Values   = { "Semua", "Info", "Success", "Warning", "Error", "Custom", "Confirm" },
        Default  = "Semua",
        Text     = "Filter Kategori",
        Callback = function(Value)
            CategoryFilter = Value
            RefreshHistoryLabel()
        end,
    })

    Groupbox:AddButton({
        Text = "Refresh History",
        Func = function()
            RefreshHistoryLabel()
        end,
    })

    Groupbox:AddButton({
        Text = "Hapus History",
        Func = function()
            NotificationManager:ClearHistory()
            RefreshHistoryLabel()
            NotificationManager:Info("History", "History notifikasi telah dihapus.", 2)
        end,
    })

    Groupbox:AddButton({
        Text = "Hapus Queue",
        Func = function()
            NotificationManager:ClearQueue()
            NotificationManager:Info("Queue", "Antrian notifikasi telah dihapus.", 2)
        end,
    })

    -- Auto-refresh setiap 5 detik
    task.spawn(function()
        while true do
            task.wait(5)
            pcall(RefreshHistoryLabel)
        end
    end)
end

return NotificationManager
