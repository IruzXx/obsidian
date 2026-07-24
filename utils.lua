-- utils.lua
-- Shared utilities untuk Obsidian Library
-- Compatibility helpers: cloneref, filesystem functions, dll

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local clonefunction = (clonefunction or copyfunction or function(func: any)
    return func
end)

local HttpService = cloneref(game:GetService("HttpService"))

-- =========================================================
--                    CLONEREF
-- =========================================================

export type Cloneref = typeof(cloneref)

-- =========================================================
--                    FILESYSTEM HELPERS
-- =========================================================

local isfolder_raw = isfolder
local isfile_raw = isfile
local listfiles_raw = listfiles

-- Patch filesystem functions untuk executor yang error-prone
if typeof(clonefunction) == "function" then
    local isfolder_copy = clonefunction(isfolder_raw)
    local isfile_copy = clonefunction(isfile_raw)
    local listfiles_copy = clonefunction(listfiles_raw)

    local test_path = "test_" .. tostring(math.random(1000000, 9999999))
    local isfolder_success = pcall(function()
        return isfolder_copy(test_path)
    end)

    if isfolder_success == false or type(isfolder_success) ~= "boolean" then
        isfolder_raw = function(folder: string): boolean
            local success, data = pcall(isfolder_copy, folder)
            return success == true and data == true
        end

        isfile_raw = function(file: string): boolean
            local success, data = pcall(isfile_copy, file)
            return success == true and data == true
        end

        listfiles_raw = function(folder: string): { string }
            local success, data = pcall(listfiles_copy, folder)
            if success == true and type(data) == "table" then
                return data
            end
            return {}
        end
    end
end

-- =========================================================
--                    PUBLIC API
-- =========================================================

local Utils = {
    cloneref = cloneref,
    clonefunction = clonefunction,
    HttpService = HttpService,

    --- Check jika folder ada
    isfolder = isfolder_raw,

    --- Check jika file ada
    isfile = isfile_raw,

    --- List semua file dalam folder
    listfiles = listfiles_raw,

    --- Check jika path valid dan tidak kosong
    --- @param path string?
    --- @return boolean
    isValidPath = function(path: string?): boolean
        if type(path) ~= "string" then return false end
        local trimmed = path:match("^%s*(.-)%s*$")
        return trimmed ~= "" and not trimmed:find('[<>:"|%?%*%z/\\]')
    end,

    --- Trim whitespace dari string
    --- @param text string
    --- @return string
    trim = function(text: string): string
        return text:match("^%s*(.-)%s*$")
    end,

    --- Check jika string kosong
    --- @param str string?
    --- @return boolean
    isEmpty = function(str: string?): boolean
        return type(str) ~= "string" or Utils.trim(str) == ""
    end,

    --- Split path ke segments
    --- @param path string
    --- @return { string }
    splitPath = function(path: string): { string }
        local result = {}
        local current = ""
        for part in string.gmatch(path, "[^/]+") do
            current = current == "" and part or (current .. "/" .. part)
            table.insert(result, current)
        end
        return result
    end,

    --- Ensure semua folder dalam path ada
    --- @param path string
    --- @return boolean success
    ensureFolders = function(path: string): boolean
        local segments = Utils.splitPath(path)
        for _, segment in ipairs(segments) do
            if not isfolder_raw(segment) then
                local success = pcall(makefolder, segment)
                if not success then return false end
            end
        end
        return true
    end,
}

return Utils
