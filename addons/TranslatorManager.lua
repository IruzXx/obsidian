-- TranslatorManager.lua
-- Addon untuk Obsidian Library
-- Multi-language support (EN, ID, JP, BR, dll)
-- Author: IruzXx

local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)

local HttpService = cloneref(game:GetService("HttpService"))

-- =========================================================
--                    MODULE TABLE
-- =========================================================

local TranslatorManager = {
    Library = nil,

    -- Language settings
    CurrentLanguage = "en",
    FallbackLanguage = "en",

    -- Supported languages
    Languages = {
        en = { name = "English", nativeName = "English", flag = "🇺🇸" },
        id = { name = "Indonesian", nativeName = "Bahasa Indonesia", flag = "🇮🇩" },
        jp = { name = "Japanese", nativeName = "日本語", flag = "🇯🇵" },
        br = { name = "Portuguese (Brazil)", nativeName = "Português (BR)", flag = "🇧🇷" },
        es = { name = "Spanish", nativeName = "Español", flag = "🇪🇸" },
        fr = { name = "French", nativeName = "Français", flag = "🇫🇷" },
        de = { name = "German", nativeName = "Deutsch", flag = "🇩🇪" },
        zh = { name = "Chinese", nativeName = "中文", flag = "🇨🇳" },
        kr = { name = "Korean", nativeName = "한국어", flag = "🇰🇷" },
        th = { name = "Thai", nativeName = "ไทย", flag = "🇹🇭" },
        vi = { name = "Vietnamese", nativeName = "Tiếng Việt", flag = "🇻🇳" },
        ru = { name = "Russian", nativeName = "Русский", flag = "🇷🇺" },
        ar = { name = "Arabic", nativeName = "العربية", flag = "🇸🇦" },
        hi = { name = "Hindi", nativeName = "हिन्दी", flag = "🇮🇳" },
    },

    -- Translations storage
    Translations = {},

    -- Custom translations (developer-defined)
    CustomTranslations = {},

    -- Translation API (opsional untuk auto-translate)
    TranslateAPI = {
        enabled = false,
        apiKey = "",
        endpoint = "https://api.mymemory.translated.net/get",
    },
}

-- =========================================================
--                    TYPE DEFINITIONS
-- =========================================================

export type LanguageCode = keyof typeof TranslatorManager.Languages

export type TranslationTable = { [string]: string }

export type TranslatorConfig = {
    defaultLanguage: LanguageCode?,
    fallbackLanguage: LanguageCode?,
    apiKey: string?,
}

-- =========================================================
--                    SETUP
-- =========================================================

function TranslatorManager:SetLibrary(Library)
    assert(Library, "[TranslatorManager] Library tidak boleh nil")
    TranslatorManager.Library = Library
end

--- Konfigurasi translator
--- @param config TranslatorConfig
function TranslatorManager:Configure(config)
    if config.defaultLanguage then
        TranslatorManager.CurrentLanguage = config.defaultLanguage
    end
    if config.fallbackLanguage then
        TranslatorManager.FallbackLanguage = config.fallbackLanguage
    end
    if config.apiKey then
        TranslatorManager.TranslateAPI.apiKey = config.apiKey
        TranslatorManager.TranslateAPI.enabled = config.apiKey ~= ""
    end
end

-- =========================================================
--                    LANGUAGE MANAGEMENT
-- =========================================================

--- Set bahasa aktif
--- @param langCode string
function TranslatorManager:SetLanguage(langCode: LanguageCode)
    if not TranslatorManager.Languages[langCode] then
        warn(string.format("[TranslatorManager] Language '%s' not supported", langCode))
        return false
    end

    TranslatorManager.CurrentLanguage = langCode

    -- Callback
    if TranslatorManager.OnLanguageChanged then
        pcall(TranslatorManager.OnLanguageChanged, langCode)
    end

    return true
end

--- Get bahasa aktif
function TranslatorManager:GetLanguage(): LanguageCode
    return TranslatorManager.CurrentLanguage
end

--- Get semua bahasa yang tersedia
function TranslatorManager:GetAvailableLanguages()
    local result = {}
    for code, info in pairs(TranslatorManager.Languages) do
        table.insert(result, {
            code = code,
            name = info.name,
            nativeName = info.nativeName,
        })
    end
    return result
end

-- Callbacks
TranslatorManager.OnLanguageChanged = nil :: ((langCode: LanguageCode) -> ())?

-- =========================================================
--                    TRANSLATION REGISTRATION
-- =========================================================

--- Daftarkan translations untuk satu bahasa
--- @param langCode string
--- @param translations TranslationTable
function TranslatorManager:AddTranslations(langCode: LanguageCode, translations: TranslationTable)
    if not TranslatorManager.Translations[langCode] then
        TranslatorManager.Translations[langCode] = {}
    end

    for key, value in pairs(translations) do
        TranslatorManager.Translations[langCode][key] = value
    end
end

--- Daftarkan single translation key
--- @param langCode string
--- @param key string
--- @param value string
function TranslatorManager:SetTranslation(langCode: LanguageCode, key: string, value: string)
    if not TranslatorManager.Translations[langCode] then
        TranslatorManager.Translations[langCode] = {}
    end
    TranslatorManager.Translations[langCode][key] = value
end

--- Batch register translations dari table
--- @param translations { [langCode]: TranslationTable }
function TranslatorManager:AddAllTranslations(translations: { [LanguageCode]: TranslationTable })
    for langCode, langTranslations in pairs(translations) do
        TranslatorManager:AddTranslations(langCode, langTranslations)
    end
end

-- =========================================================
--                    TRANSLATION GETTER
-- =========================================================

--- Get translation untuk key
--- @param key string Translation key
--- @param langCode string? Bahasa (default: current language)
--- @param substitutions { [string]: string }? Variable substitutions
--- @return string
function TranslatorManager:Get(key: string, langCode: LanguageCode?, substitutions: { [string]: string }?): string
    langCode = langCode or TranslatorManager.CurrentLanguage

    -- Try primary language
    local translation = TranslatorManager.Translations[langCode]
        and TranslatorManager.Translations[langCode][key]

    -- Fallback to fallback language
    if not translation and langCode ~= TranslatorManager.FallbackLanguage then
        translation = TranslatorManager.Translations[TranslatorManager.FallbackLanguage]
            and TranslatorManager.Translations[TranslatorManager.FallbackLanguage][key]
    end

    -- Fallback to English
    if not translation and langCode ~= "en" then
        translation = TranslatorManager.Translations["en"]
            and TranslatorManager.Translations["en"][key]
    end

    -- Ultimate fallback to key
    if not translation then
        translation = key
    end

    -- Apply substitutions
    if substitutions then
        for placeholder, value in pairs(substitutions) do
            translation = translation:gsub("{" .. placeholder .. "}", tostring(value))
        end
    end

    return translation
end

--- Shorthand untuk Get
--- @param key string
--- @param subs { [string]: string }?
--- @return string
function TranslatorManager:T(key: string, subs: { [string]: string }?): string
    return TranslatorManager:Get(key, nil, subs)
end

-- =========================================================
--                    AUTO TRANSLATE (Optional)
-- =========================================================

--- Translate satu text via API
--- @param text string
--- @param fromLang string
--- @param toLang string
--- @param callback function(result: string, error: string?)
function TranslatorManager:TranslateText(text: string, fromLang: string, toLang: string, callback: (string, string?) -> ())
    if not TranslatorManager.TranslateAPI.enabled then
        callback(text, "Translate API not enabled")
        return
    end

    task.spawn(function()
        local url = string.format(
            "%s?q=%s&langpair=%s|%s",
            TranslatorManager.TranslateAPI.endpoint,
            HttpService:UrlEncode(text),
            fromLang,
            toLang
        )

        if TranslatorManager.TranslateAPI.apiKey ~= "" then
            url = url .. "&key=" .. TranslatorManager.TranslateAPI.apiKey
        end

        local success, response = pcall(function()
            return HttpService:GetAsync(url)
        end)

        if not success or not response then
            callback(text, "Failed to fetch translation")
            return
        end

        local decodeSuccess, data = pcall(HttpService.JSONDecode, HttpService, response)
        if not decodeSuccess or not data.responseData then
            callback(text, "Failed to parse response")
            return
        end

        local translatedText = data.responseData.translatedText or text
        callback(translatedText)
    end)
end

--- Batch translate keys
--- @param keys { string }
--- @param fromLang string
--- @param toLang string
--- @param callback function(results: { [string]: string })
function TranslatorManager:BatchTranslate(keys: { string }, fromLang: string, toLang: string, callback: ({ [string]: string }) -> ())
    local results = {}
    local pending = #keys

    if pending == 0 then
        callback(results)
        return
    end

    for _, key in ipairs(keys) do
        TranslatorManager:TranslateText(key, fromLang, toLang, function(translated, err)
            results[key] = translated
            pending -= 1

            if pending <= 0 then
                callback(results)
            end
        end)
    end
end

-- =========================================================
--                    PRESET TRANSLATIONS
-- =========================================================

--- Default translations untuk UI elements
function TranslatorManager:AddDefaultUITranslations()
    -- English (default)
    TranslatorManager:AddTranslations("en", {
        -- General
        ["app.name"] = "Obsidian UI",
        ["app.version"] = "Version {version}",

        -- Settings
        ["settings.title"] = "Settings",
        ["settings.general"] = "General",
        ["settings.ui"] = "UI Settings",
        ["settings.appearance"] = "Appearance",
        ["settings.language"] = "Language",

        -- Actions
        ["action.save"] = "Save",
        ["action.cancel"] = "Cancel",
        ["action.reset"] = "Reset",
        ["action.apply"] = "Apply",
        ["action.delete"] = "Delete",
        ["action.export"] = "Export",
        ["action.import"] = "Import",
        ["action.refresh"] = "Refresh",

        -- Status
        ["status.enabled"] = "Enabled",
        ["status.disabled"] = "Disabled",
        ["status.loading"] = "Loading...",
        ["status.error"] = "Error",
        ["status.success"] = "Success",

        -- Errors
        ["error.generic"] = "An error occurred",
        ["error.network"] = "Network error",
        ["error.notfound"] = "Not found",
    })

    -- Indonesian
    TranslatorManager:AddTranslations("id", {
        ["app.name"] = "Obsidian UI",
        ["app.version"] = "Versi {version}",

        ["settings.title"] = "Pengaturan",
        ["settings.general"] = "Umum",
        ["settings.ui"] = "Pengaturan UI",
        ["settings.appearance"] = "Tampilan",
        ["settings.language"] = "Bahasa",

        ["action.save"] = "Simpan",
        ["action.cancel"] = "Batal",
        ["action.reset"] = "Reset",
        ["action.apply"] = "Terapkan",
        ["action.delete"] = "Hapus",
        ["action.export"] = "Export",
        ["action.import"] = "Import",
        ["action.refresh"] = "Segarkan",

        ["status.enabled"] = "Aktif",
        ["status.disabled"] = "Nonaktif",
        ["status.loading"] = "Memuat...",
        ["status.error"] = "Error",
        ["status.success"] = "Berhasil",

        ["error.generic"] = "Terjadi kesalahan",
        ["error.network"] = "Kesalahan jaringan",
        ["error.notfound"] = "Tidak ditemukan",
    })

    -- Japanese
    TranslatorManager:AddTranslations("jp", {
        ["app.name"] = "Obsidian UI",
        ["app.version"] = "バージョン {version}",

        ["settings.title"] = "設定",
        ["settings.general"] = "一般",
        ["settings.ui"] = "UI設定",
        ["settings.appearance"] = "外観",
        ["settings.language"] = "言語",

        ["action.save"] = "保存",
        ["action.cancel"] = "キャンセル",
        ["action.reset"] = "リセット",
        ["action.apply"] = "適用",
        ["action.delete"] = "削除",
        ["action.export"] = "エクスポート",
        ["action.import"] = "インポート",
        ["action.refresh"] = "更新",

        ["status.enabled"] = "有効",
        ["status.disabled"] = "無効",
        ["status.loading"] = "読み込み中...",
        ["status.error"] = "エラー",
        ["status.success"] = "成功",

        ["error.generic"] = "エラーが発生しました",
        ["error.network"] = "ネットワークエラー",
        ["error.notfound"] = "見つかりません",
    })

    -- Portuguese (Brazil)
    TranslatorManager:AddTranslations("br", {
        ["app.name"] = "Obsidian UI",
        ["app.version"] = "Versão {version}",

        ["settings.title"] = "Configurações",
        ["settings.general"] = "Geral",
        ["settings.ui"] = "Configurações de UI",
        ["settings.appearance"] = "Aparência",
        ["settings.language"] = "Idioma",

        ["action.save"] = "Salvar",
        ["action.cancel"] = "Cancelar",
        ["action.reset"] = "Redefinir",
        ["action.apply"] = "Aplicar",
        ["action.delete"] = "Excluir",
        ["action.export"] = "Exportar",
        ["action.import"] = "Importar",
        ["action.refresh"] = "Atualizar",

        ["status.enabled"] = "Ativado",
        ["status.disabled"] = "Desativado",
        ["status.loading"] = "Carregando...",
        ["status.error"] = "Erro",
        ["status.success"] = "Sucesso",

        ["error.generic"] = "Ocorreu um erro",
        ["error.network"] = "Erro de rede",
        ["error.notfound"] = "Não encontrado",
    })
end

-- =========================================================
--                    HELPER FUNCTIONS
-- =========================================================

--- Format plural sesuai bahasa
--- @param count number
--- @param singular string
--- @param plural string
--- @param langCode string?
--- @return string
function TranslatorManager:Plural(count: number, singular: string, plural: string, langCode: LanguageCode?): string
    langCode = langCode or TranslatorManager.CurrentLanguage

    -- Simple rule untuk kebanyakan bahasa
    local isPlural = count ~= 1

    -- Exception untuk bahasa tertentu
    if langCode == "jp" or langCode == "zh" or langCode == "kr" then
        -- Bahasa Asia tidak membedakan singular/plural
        return singular
    end

    return isPlural and plural or singular
end

--- Format number sesuai locale
--- @param num number
--- @param langCode string?
--- @return string
function TranslatorManager:FormatNumber(num: number, langCode: LanguageCode?): string
    langCode = langCode or TranslatorManager.CurrentLanguage

    if langCode == "br" or langCode == "de" or langCode == "fr" then
        -- Gunakan koma sebagai decimal separator
        return string.format("%.2f", num):gsub("%.", ",")
    end

    return string.format("%.2f", num)
end

-- =========================================================
--                    UI SECTION
-- =========================================================

function TranslatorManager:BuildLanguageSection(Tab, GroupboxName)
    assert(Tab, "[TranslatorManager] Tab tidak boleh nil")

    local Box = Tab:AddLeftGroupbox(GroupboxName or "Language", "globe")

    -- Language dropdown
    local languages = {}
    local defaultIndex = 1

    for i, lang in ipairs(TranslatorManager:GetAvailableLanguages()) do
        table.insert(languages, string.format("%s %s", lang.flag or "", lang.nativeName))
        if lang.code == TranslatorManager.CurrentLanguage then
            defaultIndex = i
        end
    end

    local languageDropdown = Box:AddDropdown("TM_Language", {
        Values = languages,
        Default = defaultIndex,
        Text = "Language",
        Tooltip = "Select your preferred language",
        AllowNull = false,
    })

    -- Translation API toggle
    Box:AddToggle("TM_EnableAPI", {
        Text = "Enable Auto-Translate",
        Default = false,
        Tooltip = "Use API for missing translations",
        Callback = function(Value)
            TranslatorManager.TranslateAPI.enabled = Value
        end,
    })

    -- Current language display
    local currentLangLabel = Box:AddLabel("Current: English (en)", false)

    local function RefreshLangLabel()
        local lang = TranslatorManager.Languages[TranslatorManager.CurrentLanguage]
        if lang and currentLangLabel then
            currentLangLabel:SetText(string.format("Current: %s (%s)", lang.nativeName, TranslatorManager.CurrentLanguage))
        end
    end

    Box:AddDivider()

    -- Translation test area
    Box:AddInput("TM_TestKey", {
        Text = "Translation Key",
        Placeholder = "e.g., settings.title",
        Default = "",
    })

    local TestResultLabel = Box:AddLabel("Result: (enter key above)", true)

    Box:AddButton({
        Text = "Test Translation",
        Func = function()
            local key = TranslatorManager.Library
                and TranslatorManager.Library.Options
                and TranslatorManager.Library.Options.TM_TestKey
                and TranslatorManager.Library.Options.TM_TestKey.Value
                or ""

            if key == "" then
                TestResultLabel:SetText("Result: (enter key above)")
                return
            end

            local translation = TranslatorManager:Get(key)
            TestResultLabel:SetText("Result: " .. translation)
        end,
    })

    -- Events
    languageDropdown:OnChanged(function(Value)
        local index = table.find(languages, Value)
        if not index then return end

        local available = TranslatorManager:GetAvailableLanguages()
        local selected = available[index]

        if selected then
            TranslatorManager:SetLanguage(selected.code)
            RefreshLangLabel()

            if TranslatorManager.Library then
                TranslatorManager.Library:Notify({
                    Title = "Language",
                    Description = string.format("Language changed to %s", selected.nativeName),
                    Time = 2,
                })
            end
        end
    end)

    return Box
end

-- =========================================================
--                    INIT
-- =========================================================

-- Add default UI translations
TranslatorManager:AddDefaultUITranslations()

return TranslatorManager
