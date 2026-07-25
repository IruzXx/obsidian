-- SchedulerManager.lua
-- Addon untuk Obsidian Library
-- Schedule tasks untuk auto-execute pada waktu tertentu
-- Author: IruzXx

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local RunService = cloneref(game:GetService("RunService"))

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local SchedulerManager = {
    Library = nil,

    -- Scheduled tasks
    Tasks = {},  -- { [id] = Task }
    TaskIdCounter = 0,

    -- State
    IsRunning = true,
    CheckInterval = 1,  -- detik antar check

    -- Callbacks
    OnTaskExecute = nil,
    OnTaskSkip = nil,

    -- Internal connections (for cleanup)
    _taskListRefreshLoop = nil,
}

-- =========================================================
--                    TYPE DEFINITIONS
-- =========================================================

export type TaskType = "once" | "interval" | "daily" | "custom"

export type ScheduledTask = {
    id: number,
    name: string,
    type: TaskType,
    enabled: boolean,
    -- For once
    executeAt: number?,  -- timestamp
    -- For interval
    intervalSeconds: number?,
    nextExecute: number?,
    -- For daily
    timeOfDay: string?,  -- "HH:MM" format
    -- For custom (cron-like)
    cronExpression: string?,
    -- Execution
    callback: (() -> ())?,
    callbackId: string?,  -- untuk integration dengan Library
    metadata: { [string]: any },
    -- Stats
    lastExecute: number?,
    executeCount: number,
    skipCount: number,
}

-- =========================================================
--                    SETUP
-- =========================================================

function SchedulerManager:SetLibrary(Library)
    assert(Library, "[SchedulerManager] Library tidak boleh nil")
    SchedulerManager.Library = Library
end

-- =========================================================
--                    TASK MANAGEMENT
-- =========================================================

--- Buat task baru
--- @param taskType TaskType
--- @param name string
--- @param config Configuration
--- @return number taskId
function SchedulerManager:CreateTask(taskType: TaskType, name: string, config: {
    executeAt: number?,
    intervalSeconds: number?,
    timeOfDay: string?,
    callback: (() -> ())?,
    callbackId: string?,
    metadata: { [string]: any }?,
}): number
    SchedulerManager.TaskIdCounter += 1
    local taskId = SchedulerManager.TaskIdCounter

    local task: ScheduledTask = {
        id = taskId,
        name = name,
        type = taskType,
        enabled = true,
        callback = config.callback,
        callbackId = config.callbackId,
        metadata = config.metadata or {},
        lastExecute = 0,
        executeCount = 0,
        skipCount = 0,
    }

    -- Setup berdasarkan type
    if taskType == "once" then
        task.executeAt = config.executeAt or (os.time() + 60)

    elseif taskType == "interval" then
        task.intervalSeconds = config.intervalSeconds or 60
        task.nextExecute = os.time() + task.intervalSeconds

    elseif taskType == "daily" then
        task.timeOfDay = config.timeOfDay or "00:00"
        task.nextExecute = SchedulerManager:_GetNextDailyTime(task.timeOfDay)
    end

    SchedulerManager.Tasks[taskId] = task

    return taskId
end

--- Hapus task
--- @param taskId number
--- @return boolean success
function SchedulerManager:DeleteTask(taskId: number): boolean
    if not SchedulerManager.Tasks[taskId] then
        return false
    end

    SchedulerManager.Tasks[taskId] = nil
    return true
end

--- Enable/disable task
--- @param taskId number
--- @param enabled boolean
function SchedulerManager:SetTaskEnabled(taskId: number, enabled: boolean)
    local task = SchedulerManager.Tasks[taskId]
    if task then
        task.enabled = enabled
    end
end

--- Get task
--- @param taskId number
--- @return ScheduledTask?
function SchedulerManager:GetTask(taskId: number): ScheduledTask?
    return SchedulerManager.Tasks[taskId]
end

--- Get semua tasks
--- @return { [number]: ScheduledTask }
function SchedulerManager:GetAllTasks(): { [number]: ScheduledTask }
    return SchedulerManager.Tasks
end

--- Get tasks by type
--- @param taskType TaskType
--- @return { ScheduledTask }
function SchedulerManager:GetTasksByType(taskType: TaskType): { ScheduledTask }
    local result = {}
    for _, task in pairs(SchedulerManager.Tasks) do
        if task.type == taskType then
            table.insert(result, task)
        end
    end
    return result
end

-- =========================================================
--                    TASK EXECUTION
-- =========================================================

function SchedulerManager:_ExecuteTask(task: ScheduledTask)
    if not task.enabled then
        return
    end

    -- Execute callback
    if task.callback then
        local success, err = pcall(task.callback)
        if not success then
            warn(string.format("[SchedulerManager] Task '%s' error: %s", task.name, tostring(err)))
            return
        end
    end

    -- Execute Library callback if callbackId provided
    if task.callbackId and SchedulerManager.OnTaskExecute then
        pcall(SchedulerManager.OnTaskExecute, task)
    end

    -- Update stats
    task.lastExecute = os.time()
    task.executeCount += 1

    -- Reschedule based on type
    if task.type == "once" then
        -- Once tasks delete themselves
        SchedulerManager:DeleteTask(task.id)

    elseif task.type == "interval" then
        task.nextExecute = os.time() + (task.intervalSeconds or 60)

    elseif task.type == "daily" then
        task.nextExecute = SchedulerManager:_GetNextDailyTime(task.timeOfDay)
    end
end

function SchedulerManager:_ShouldSkipTask(task: ScheduledTask): boolean
    if task.type == "once" then
        return os.time() < (task.executeAt or 0)

    elseif task.type == "interval" then
        return os.time() < (task.nextExecute or 0)

    elseif task.type == "daily" then
        return os.time() < (task.nextExecute or 0)
    end

    return true
end

-- =========================================================
--                    SCHEDULER LOOP
-- =========================================================

function SchedulerManager:_StartSchedulerLoop()
    task.spawn(function()
        while SchedulerManager.IsRunning do
            task.wait(SchedulerManager.CheckInterval)

            local now = os.time()

            for _, task in pairs(SchedulerManager.Tasks) do
                if not task.enabled then continue end

                -- Check if should execute
                local shouldExecute = false

                if task.type == "once" then
                    shouldExecute = now >= (task.executeAt or 0)

                elseif task.type == "interval" then
                    shouldExecute = now >= (task.nextExecute or 0)

                elseif task.type == "daily" then
                    shouldExecute = now >= (task.nextExecute or 0)
                end

                if shouldExecute then
                    SchedulerManager:_ExecuteTask(task)
                end
            end
        end
    end)
end

function SchedulerManager:Start()
    if not SchedulerManager.IsRunning then
        SchedulerManager.IsRunning = true
        SchedulerManager:_StartSchedulerLoop()
    end
end

function SchedulerManager:Stop()
    SchedulerManager.IsRunning = false
end

-- =========================================================
--                    HELPER FUNCTIONS
-- =========================================================

function SchedulerManager:_GetNextDailyTime(timeStr: string): number
    -- Validate time string format (HH:MM)
    local hour, min = timeStr:match("^(%d+):(%d+)$")

    -- If pattern doesn't match, default to midnight
    if not hour or not min then
        warn(string.format("[SchedulerManager] Invalid time format '%s', defaulting to 00:00", tostring(timeStr)))
        hour, min = 0, 0
    else
        hour = tonumber(hour) or 0
        min = tonumber(min) or 0
        -- Validate hour and minute ranges
        hour = math.max(0, math.min(23, hour))
        min = math.max(0, math.min(59, min))
    end

    local now = os.time()
    local target = {
        year = now.year,
        month = now.month,
        day = now.day,
        hour = hour,
        min = min,
        sec = 0,
    }

    -- If time has passed today, use tomorrow
    local targetTime = os.time(target)
    if targetTime <= now then
        targetTime = targetTime + 86400  -- Add 1 day
    end

    return targetTime
end

-- =========================================================
--                    CONVENIENCE METHODS
-- =========================================================

--- Schedule sekali di masa depan
--- @param name string
--- @param seconds number Detik dari sekarang
--- @param callback function
--- @param metadata table?
--- @return number taskId
function SchedulerManager:ScheduleOnce(name: string, seconds: number, callback: () -> (), metadata: {}?)
    return SchedulerManager:CreateTask("once", name, {
        executeAt = os.time() + seconds,
        callback = callback,
        metadata = metadata,
    })
end

--- Schedule interval
--- @param name string
--- @param intervalSeconds number
--- @param callback function
--- @param metadata table?
--- @return number taskId
function SchedulerManager:ScheduleInterval(name: string, intervalSeconds: number, callback: () -> (), metadata: {}?)
    return SchedulerManager:CreateTask("interval", name, {
        intervalSeconds = intervalSeconds,
        callback = callback,
        metadata = metadata,
    })
end

--- Schedule daily
--- @param name string
--- @param timeOfDay string "HH:MM" format
--- @param callback function
--- @param metadata table?
--- @return number taskId
function SchedulerManager:ScheduleDaily(name: string, timeOfDay: string, callback: () -> (), metadata: {}?)
    return SchedulerManager:CreateTask("daily", name, {
        timeOfDay = timeOfDay,
        callback = callback,
        metadata = metadata,
    })
end

--- Cancel scheduled task
--- @param taskId number
function SchedulerManager:Cancel(taskId: number)
    SchedulerManager:DeleteTask(taskId)
end

--- Pause semua tasks
function SchedulerManager:PauseAll()
    for _, task in pairs(SchedulerManager.Tasks) do
        task.enabled = false
    end
end

--- Resume semua tasks
function SchedulerManager:ResumeAll()
    for _, task in pairs(SchedulerManager.Tasks) do
        task.enabled = true
    end
end

-- =========================================================
--                    STATS
-- =========================================================

function SchedulerManager:GetStats()
    local stats = {
        totalTasks = 0,
        enabledTasks = 0,
        disabledTasks = 0,
        byType = {},
        totalExecutions = 0,
    }

    for _, task in pairs(SchedulerManager.Tasks) do
        stats.totalTasks += 1
        stats.byType[task.type] = (stats.byType[task.type] or 0) + 1

        if task.enabled then
            stats.enabledTasks += 1
        else
            stats.disabledTasks += 1
        end

        stats.totalExecutions += task.executeCount
    end

    return stats
end

-- =========================================================
--                    UI SECTION
-- =========================================================

function SchedulerManager:BuildSchedulerSection(Tab, GroupboxName)
    assert(Tab, "[SchedulerManager] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Scheduler", "clock")

    local TaskListLabel

    -- Helper format time
    local function formatTime(timestamp: number): string
        if not timestamp or timestamp == 0 then return "Never" end
        return os.date("%H:%M:%S", timestamp)
    end

    local function formatInterval(seconds: number): string
        if seconds < 60 then
            return string.format("%ds", seconds)
        elseif seconds < 3600 then
            return string.format("%dm", math.floor(seconds / 60))
        else
            return string.format("%dh", math.floor(seconds / 3600))
        end
    end

    -- Refresh task list
    local function RefreshTaskList()
        if not TaskListLabel then return end

        local tasks = SchedulerManager:GetAllTasks()
        local lines = {}

        for _, task in pairs(tasks) do
            local status = task.enabled and "ON" or "OFF"
            local nextTime = ""

            if task.type == "once" then
                nextTime = formatTime(task.executeAt)
            elseif task.type == "interval" then
                local remaining = task.nextExecute - os.time()
                if remaining > 0 then
                    nextTime = formatInterval(remaining) .. " remaining"
                else
                    nextTime = "overdue"
                end
            elseif task.type == "daily" then
                nextTime = "Daily at " .. task.timeOfDay
            end

            table.insert(lines, string.format(
                "[%s] %s (%s) - %s",
                status, task.name, task.type, nextTime
            ))
        end

        if #lines == 0 then
            TaskListLabel:SetText("(no scheduled tasks)")
        else
            TaskListLabel:SetText(table.concat(lines, "\n"))
        end
    end

    -- Stats
    local stats = SchedulerManager:GetStats()
    Box:AddLabel(function()
        local s = SchedulerManager:GetStats()
        return string.format("Tasks: %d | Active: %d | Executions: %d",
            s.totalTasks, s.enabledTasks, s.totalExecutions)
    end, false)

    Box:AddDivider()

    -- Task list
    TaskListLabel = Box:AddLabel("(no scheduled tasks)", true)

    Box:AddDivider()

    -- Controls
    Box:AddButton({
        Text = "Pause All",
        Func = function()
            SchedulerManager:PauseAll()
            RefreshTaskList()
        end,
    })

    Box:AddButton({
        Text = "Resume All",
        Func = function()
            SchedulerManager:ResumeAll()
            RefreshTaskList()
        end,
    })

    Box:AddButton({
        Text = "Refresh",
        Func = RefreshTaskList,
    })

    -- Auto refresh using heartbeat (properly cleaned up)
    SchedulerManager._taskListRefreshLoop = RunService.Heartbeat:Connect(function()
        task.wait(2)
        RefreshTaskList()
    end)

    return Box
end

-- =========================================================
--                    INIT
-- =========================================================

-- Start scheduler loop
SchedulerManager:_StartSchedulerLoop()

-- Cleanup on unload
task.defer(function()
    if SchedulerManager.Library then
        SchedulerManager.Library:OnUnload(function()
            SchedulerManager:Stop()

            -- Disconnect UI refresh loop
            if SchedulerManager._taskListRefreshLoop then
                SchedulerManager._taskListRefreshLoop:Disconnect()
                SchedulerManager._taskListRefreshLoop = nil
            end
        end)
    end
end)

return SchedulerManager
