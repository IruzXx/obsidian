-- ShortcutManager.lua
-- Addon untuk Obsidian Library
-- Quick actions / command palette untuk power users
-- Author: IruzXx

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local RunService = cloneref(game:GetService("RunService"))
local Players = cloneref(game:GetService("Players"))

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local ShortcutManager = {
    Library = nil,

    -- Shortcuts
    Shortcuts = {},
    ShortcutIdCounter = 0,

    -- Command palette
    PaletteOpen = false,
    PaletteGui = nil,

    -- Settings
    ToggleKey = Enum.KeyCode.F1,
    MaxRecentCommands = 10,
    ShowInPalette = true,

    -- History
    RecentCommands = {},

    -- Internal connections (for cleanup)
    _statsRefreshLoop = nil,
    _inputConnection = nil,
    _searchConnection = nil,
}

-- =========================================================
--                    TYPE DEFINITIONS
-- =========================================================

export type ShortcutCategory = "general" | "toggles" | "scripts" | "navigation" | "custom"

export type ShortcutAction = () -> ()

export type Shortcut = {
    id: number,
    name: string,
    description: string,
    category: ShortcutCategory,
    icon: string?,
    keybind: Enum.KeyCode?,
    action: ShortcutAction?,
    actionId: string?,
    metadata: { [string]: any },
    usageCount: number,
    lastUsed: number?,
}

export type ShortcutFilter = {
    category: ShortcutCategory?,
    search: string?,
}

-- =========================================================
--                    SETUP
-- =========================================================

function ShortcutManager:SetLibrary(Library)
    assert(Library, "[ShortcutManager] Library tidak boleh nil")
    ShortcutManager.Library = Library

    -- Setup command palette (deferred to allow GUI creation)
    task.defer(function()
        ShortcutManager:_CreatePaletteGui()
    end)

    -- Hook toggle key
    ShortcutManager:_HookInput()
end

function ShortcutManager:_HookInput()
    if ShortcutManager._inputConnection then return end

    ShortcutManager._inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == ShortcutManager.ToggleKey then
            ShortcutManager:TogglePalette()
        end

        if input.KeyCode == Enum.KeyCode.Escape and ShortcutManager.PaletteOpen then
            ShortcutManager:HidePalette()
        end
    end)
end

function ShortcutManager:_Cleanup()
    -- Disconnect stats refresh loop
    if ShortcutManager._statsRefreshLoop then
        ShortcutManager._statsRefreshLoop:Disconnect()
        ShortcutManager._statsRefreshLoop = nil
    end

    -- Disconnect input connection
    if ShortcutManager._inputConnection then
        ShortcutManager._inputConnection:Disconnect()
        ShortcutManager._inputConnection = nil
    end

    -- Disconnect search connection
    if ShortcutManager._searchConnection then
        ShortcutManager._searchConnection:Disconnect()
        ShortcutManager._searchConnection = nil
    end

    -- Destroy palette GUI
    if ShortcutManager.PaletteGui and ShortcutManager.PaletteGui.ScreenGui then
        ShortcutManager.PaletteGui.ScreenGui:Destroy()
        ShortcutManager.PaletteGui = nil
    end
end

-- =========================================================
--                    SHORTCUT MANAGEMENT
-- =========================================================

--- Register shortcut baru
--- @param name string
--- @param description string
--- @param category ShortcutCategory
--- @param config { action: ShortcutAction?, actionId: string?, keybind: Enum.KeyCode?, icon: string? }
--- @return number shortcutId
function ShortcutManager:Register(name: string, description: string, category: ShortcutCategory, config: {
    action: ShortcutAction?,
    actionId: string?,
    keybind: Enum.KeyCode?,
    icon: string?,
    metadata: { [string]: any }?,
}): number
    ShortcutManager.ShortcutIdCounter += 1
    local id = ShortcutManager.ShortcutIdCounter

    local shortcut: Shortcut = {
        id = id,
        name = name,
        description = description,
        category = category,
        icon = config.icon,
        keybind = config.keybind,
        action = config.action,
        actionId = config.actionId,
        metadata = config.metadata or {},
        usageCount = 0,
        lastUsed = nil,
    }

    ShortcutManager.Shortcuts[id] = shortcut

    -- Register keybind if provided
    if config.keybind then
        ShortcutManager:_RegisterKeybind(shortcut)
    end

    return id
end

--- Execute shortcut by ID
--- @param shortcutId number
--- @return boolean success
function ShortcutManager:Execute(shortcutId: number): boolean
    local shortcut = ShortcutManager.Shortcuts[shortcutId]
    if not shortcut then
        return false
    end

    -- Execute action
    if shortcut.action then
        local success, err = pcall(shortcut.action)
        if not success then
            warn(string.format("[ShortcutManager] Shortcut '%s' error: %s", shortcut.name, tostring(err)))
            return false
        end
    end

    -- Execute Library callback if actionId
    if shortcut.actionId and ShortcutManager.OnShortcutExecute then
        pcall(ShortcutManager.OnShortcutExecute, shortcut)
    end

    -- Update stats
    shortcut.usageCount += 1
    shortcut.lastUsed = os.time()

    -- Add to recent
    ShortcutManager:_AddToRecent(shortcut)

    return true
end

--- Delete shortcut
--- @param shortcutId number
function ShortcutManager:Delete(shortcutId: number)
    local shortcut = ShortcutManager.Shortcuts[shortcutId]
    if shortcut and shortcut.keybind then
        ShortcutManager:_UnregisterKeybind(shortcut)
    end
    ShortcutManager.Shortcuts[shortcutId] = nil
end

--- Get shortcut
--- @param shortcutId number
--- @return Shortcut?
function ShortcutManager:Get(shortcutId: number): Shortcut?
    return ShortcutManager.Shortcuts[shortcutId]
end

--- Get all shortcuts
--- @param filter ShortcutFilter?
--- @return { Shortcut }
function ShortcutManager:GetAll(filter: ShortcutFilter?): { Shortcut }
    local results = {}

    for _, shortcut in pairs(ShortcutManager.Shortcuts) do
        local include = true

        if filter then
            if filter.category and shortcut.category ~= filter.category then
                include = false
            end
            if filter.search then
                local search = filter.search:lower()
                local nameMatch = shortcut.name:lower():find(search, 1, true)
                local descMatch = shortcut.description:lower():find(search, 1, true)
                include = nameMatch or descMatch
            end
        end

        if include then
            table.insert(results, shortcut)
        end
    end

    return results
end

-- =========================================================
--                    KEYBINDS
-- =========================================================

function ShortcutManager:_RegisterKeybind(shortcut: Shortcut)
    -- Implementation depends on input service
end

function ShortcutManager:_UnregisterKeybind(shortcut: Shortcut)
    -- Implementation depends on input service
end

-- =========================================================
--                    COMMAND PALETTE
-- =========================================================

function ShortcutManager:_CreatePaletteGui()
    if ShortcutManager.PaletteGui then return end

    -- Check for LocalPlayer (required for PlayerGui)
    if not Players.LocalPlayer then
        warn("[ShortcutManager] LocalPlayer not available, deferring GUI creation")
        return false
    end

    local success, playerGui = pcall(function()
        return Players.LocalPlayer:WaitForChild("PlayerGui", 5)
    end)

    if not success or not playerGui then
        warn("[ShortcutManager] Could not access PlayerGui")
        return false
    end

    -- Create ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ShortcutManagerPalette"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true

    -- Main frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.Size = UDim2.new(0, 500, 0, 350)
    mainFrame.Position = UDim2.new(0.5, -250, 0.5, -175)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

    -- Shadow
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 47, 1, 47)
    shadow.Position = UDim2.new(0, -23, 0, -23)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.Parent = mainFrame

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    -- Fix bottom corners of titlebar
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Command Palette"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.new(0, 26, 0, 26)
    closeBtn.Position = UDim2.new(1, -36, 0.5, -13)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 12
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    closeBtn.MouseButton1Click:Connect(function()
        ShortcutManager:HidePalette()
    end)

    -- Search bar
    local searchBar = Instance.new("TextBox")
    searchBar.Name = "SearchBar"
    searchBar.Size = UDim2.new(1, -24, 0, 36)
    searchBar.Position = UDim2.new(0, 12, 0, 52)
    searchBar.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    searchBar.Text = ""
    searchBar.PlaceholderText = "Type to search..."
    searchBar.PlaceholderColor3 = Color3.fromRGB(150, 150, 170)
    searchBar.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBar.TextSize = 14
    searchBar.Font = Enum.Font.Gotham
    searchBar.BorderSizePixel = 0
    searchBar.ClearTextOnFocus = true
    searchBar.Parent = mainFrame
    Instance.new("UICorner", searchBar).CornerRadius = UDim.new(0, 8)

    -- Results container
    local resultsContainer = Instance.new("ScrollingFrame")
    resultsContainer.Name = "Results"
    resultsContainer.Size = UDim2.new(1, -24, 1, -100)
    resultsContainer.Position = UDim2.new(0, 12, 0, 96)
    resultsContainer.BackgroundTransparency = 1
    resultsContainer.ScrollBarThickness = 4
    resultsContainer.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
    resultsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    resultsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    resultsContainer.Parent = mainFrame

    local resultsLayout = Instance.new("UIListLayout")
    resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    resultsLayout.Padding = UDim.new(0, 4)
    resultsLayout.Parent = resultsContainer

    -- Padding
    local padding = Instance.new("UIPadding")
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = resultsContainer

    -- Store references
    ShortcutManager.PaletteGui = {
        ScreenGui = screenGui,
        Main = mainFrame,
        SearchBar = searchBar,
        Results = resultsContainer,
    }

    -- Search handler (store connection for cleanup)
    ShortcutManager._searchConnection = searchBar:GetPropertyChangedSignal("Text"):Connect(function()
        ShortcutManager:_UpdateResults(searchBar.Text)
    end)

    -- Click outside to close
    mainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ShortcutManager:HidePalette()
        end
    end)

    -- Initial hide
    screenGui.Enabled = false
    screenGui.Parent = playerGui

    return true
end

function ShortcutManager:_UpdateResults(searchText: string)
    if not ShortcutManager.PaletteGui then return end

    local container = ShortcutManager.PaletteGui.Results

    -- Clear old results
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    -- Get filtered shortcuts
    local filter: ShortcutFilter = {}
    if searchText and searchText ~= "" then
        filter.search = searchText
    end

    local shortcuts = ShortcutManager:GetAll(filter)

    -- Create result buttons
    local y = 0
    for i, shortcut in ipairs(shortcuts) do
        local btn = Instance.new("TextButton")
        btn.Name = "Result_" .. shortcut.id
        btn.Size = UDim2.new(1, 0, 0, 44)
        btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        btn.Text = ""
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Parent = container
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        -- Icon
        if shortcut.icon then
            local icon = Instance.new("TextLabel")
            icon.Size = UDim2.new(0, 24, 0, 24)
            icon.Position = UDim2.new(0, 12, 0.5, -12)
            icon.BackgroundTransparency = 1
            icon.Text = shortcut.icon
            icon.TextColor3 = Color3.fromRGB(255, 255, 255)
            icon.TextSize = 16
            icon.Parent = btn
        end

        -- Name
        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, -60, 0, 18)
        name.Position = UDim2.new(0, shortcut.icon and 44 or 12, 0, 6)
        name.BackgroundTransparency = 1
        name.Text = shortcut.name
        name.TextColor3 = Color3.fromRGB(255, 255, 255)
        name.TextSize = 13
        name.Font = Enum.Font.GothamBold
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.Parent = btn

        -- Description
        local desc = Instance.new("TextLabel")
        desc.Size = UDim2.new(1, -60, 0, 14)
        desc.Position = UDim2.new(0, shortcut.icon and 44 or 12, 0, 24)
        desc.BackgroundTransparency = 1
        desc.Text = shortcut.description
        desc.TextColor3 = Color3.fromRGB(150, 150, 170)
        desc.TextSize = 11
        desc.Font = Enum.Font.Gotham
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.TextTruncate = Enum.TextTruncate.AtEnd
        desc.Parent = btn

        -- Click handler
        btn.MouseButton1Click:Connect(function()
            ShortcutManager:Execute(shortcut.id)
            ShortcutManager:HidePalette()
        end)

        -- Hover effects
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(55, 55, 75)
            }):Play()
        end)

        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(40, 40, 55)
            }):Play()
        end)
    end
end

function ShortcutManager:ShowPalette()
    if not ShortcutManager.PaletteGui then return end

    ShortcutManager.PaletteOpen = true
    ShortcutManager.PaletteGui.ScreenGui.Enabled = true
    ShortcutManager.PaletteGui.SearchBar:CaptureFocus()
    ShortcutManager.PaletteGui.SearchBar.Text = ""
    ShortcutManager:_UpdateResults("")
end

function ShortcutManager:HidePalette()
    if not ShortcutManager.PaletteGui then return end

    ShortcutManager.PaletteOpen = false
    ShortcutManager.PaletteGui.ScreenGui.Enabled = false
    ShortcutManager.PaletteGui.SearchBar:ReleaseFocus()
end

function ShortcutManager:TogglePalette()
    if ShortcutManager.PaletteOpen then
        ShortcutManager:HidePalette()
    else
        ShortcutManager:ShowPalette()
    end
end

-- =========================================================
--                    RECENT COMMANDS
-- =========================================================

function ShortcutManager:_AddToRecent(shortcut: Shortcut)
    -- Remove if already exists
    for i = #ShortcutManager.RecentCommands, 1, -1 do
        if ShortcutManager.RecentCommands[i].id == shortcut.id then
            table.remove(ShortcutManager.RecentCommands, i)
        end
    end

    -- Add to front
    table.insert(ShortcutManager.RecentCommands, 1, {
        id = shortcut.id,
        name = shortcut.name,
        timestamp = os.time(),
    })

    -- Trim to max
    while #ShortcutManager.RecentCommands > ShortcutManager.MaxRecentCommands do
        table.remove(ShortcutManager.RecentCommands)
    end
end

function ShortcutManager:GetRecentCommands(): { { id: number, name: string, timestamp: number } }
    return ShortcutManager.RecentCommands
end

-- =========================================================
--                    CONVENIENCE METHODS
-- =========================================================

--- Register toggle shortcut
--- @param toggleName string
--- @param actionId string Library toggle actionId
function ShortcutManager:RegisterToggle(toggleName: string, actionId: string)
    return ShortcutManager:Register(
        toggleName,
        "Toggle " .. toggleName,
        "toggles",
        {
            actionId = actionId,
            action = function()
                local toggle = ShortcutManager.Library
                    and ShortcutManager.Library.Toggles
                    and ShortcutManager.Library.Toggles[actionId]

                if toggle then
                    toggle:SetValue(not toggle.Value)
                end
            end,
        }
    )
end

--- Register navigation shortcut
--- @param name string
--- @param tabName string
function ShortcutManager:RegisterNavigation(name: string, tabName: string)
    return ShortcutManager:Register(
        name,
        "Navigate to " .. tabName,
        "navigation",
        {
            action = function()
                -- Navigate to tab
                if ShortcutManager.Library
                    and ShortcutManager.Library.Tabs
                    and ShortcutManager.Library.Tabs[tabName]
                then
                    -- Trigger tab click
                end
            end,
        }
    )
end

-- =========================================================
--                    STATS
-- =========================================================

function ShortcutManager:GetStats()
    local stats = {
        totalShortcuts = 0,
        byCategory = {},
        topUsed = {},
    }

    local usageList = {}

    for _, shortcut in pairs(ShortcutManager.Shortcuts) do
        stats.totalShortcuts += 1
        stats.byCategory[shortcut.category] = (stats.byCategory[shortcut.category] or 0) + 1
        table.insert(usageList, shortcut)
    end

    -- Sort by usage
    table.sort(usageList, function(a, b)
        return a.usageCount > b.usageCount
    end)

    stats.topUsed = usageList

    return stats
end

-- =========================================================
--                    UI SECTION
-- =========================================================

function ShortcutManager:BuildShortcutSection(Tab, GroupboxName)
    assert(Tab, "[ShortcutManager] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Shortcuts", "command")

    local StatsLabel

    -- Stats
    StatsLabel = Box:AddLabel("Loading...", false)

    Box:AddDivider()

    -- Palette toggle
    Box:AddButton({
        Text = "Open Command Palette",
        Func = function()
            ShortcutManager:ShowPalette()
        end,
    })

    Box:AddDivider()

    -- Refresh stats
    Box:AddButton({
        Text = "Refresh Stats",
        Func = function()
            local stats = ShortcutManager:GetStats()
            local lines = {
                string.format("Total: %d shortcuts", stats.totalShortcuts),
                "By category:",
            }

            for cat, count in pairs(stats.byCategory) do
                table.insert(lines, string.format("  %s: %d", cat, count))
            end

            StatsLabel:SetText(table.concat(lines, "\n"))
        end,
    })

    -- Auto refresh using heartbeat (properly cleaned up)
    ShortcutManager._statsRefreshLoop = RunService.Heartbeat:Connect(function()
        task.wait(5)
        local stats = ShortcutManager:GetStats()
        StatsLabel:SetText(string.format(
            "Shortcuts: %d | Categories: %d",
            stats.totalShortcuts,
            #stats.topUsed
        ))
    end)

    return Box
end

-- =========================================================
--                    INIT
-- =========================================================

-- Cleanup on unload
task.defer(function()
    if ShortcutManager.Library then
        ShortcutManager.Library:OnUnload(function()
            ShortcutManager:_Cleanup()
        end)
    end
end)

return ShortcutManager
