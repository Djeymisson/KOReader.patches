-- Display the book cover while opening and closing documents.
-- Place this file in koreader/patches/.

local logger = require("logger")
local UIManager = require("ui/uimanager")
local ImageWidget = require("ui/widget/imagewidget")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")
local DocumentRegistry = require("document/documentregistry")
local _ = require("gettext")

local LOG_PREFIX = "BookLoadCover patch:"

local function info(...)
    logger.info(LOG_PREFIX, ...)
end

local function warn(...)
    logger.warn(LOG_PREFIX, ...)
end

local ReaderUI

local State = {
    cover_widget = nil,
    owned_cover_bb = nil,
    book_info_manager = nil,
    file_manager_book_info = nil,
    coverbrowser_path_added = false,
    suppress_closing_notice = false,
}

local Settings = {
    enabled = "bookloadcover_enabled",
    open_mode = "bookloadcover_open_mode",
    close_mode = "bookloadcover_close_mode",
    close_enabled_legacy = "bookloadcover_close_enabled",
    extract_enabled = "bookloadcover_extract_enabled",
    cover_source = "bookloadcover_cover_source",
    close_on_teardown = "bookloadcover_close_on_teardown",
    suppress_closing_notice = "bookloadcover_suppress_closing_notice",
    open_close_delay = "bookloadcover_close_delay",
    after_close_delay = "bookloadcover_after_close_delay",
    closing_notice_suppress_delay = "bookloadcover_closing_notice_suppress_delay",
}

local Mode = {
    off = "off",
    no_transition_widgets = "no_transition_widgets",
    cover_with_widgets = "cover_with_widgets",
    cover_only = "cover_only",
}

local SourceMode = {
    balanced = "balanced",
    best_quality = "best_quality",
}

local DEFAULT_OPEN_MODE = Mode.cover_only
local DEFAULT_CLOSE_MODE = Mode.cover_only
local DEFAULT_SOURCE_MODE = SourceMode.balanced

local MODE_ORDER = {
    Mode.off,
    Mode.no_transition_widgets,
    Mode.cover_with_widgets,
    Mode.cover_only,
}

local VALID_MODES = {
    [Mode.off] = true,
    [Mode.no_transition_widgets] = true,
    [Mode.cover_with_widgets] = true,
    [Mode.cover_only] = true,
}

local SOURCE_MODE_ORDER = {
    SourceMode.balanced,
    SourceMode.best_quality,
}

local VALID_SOURCE_MODES = {
    [SourceMode.balanced] = true,
    [SourceMode.best_quality] = true,
}

local function modeLabel(mode)
    local labels = {
        [Mode.off] = _("Default widgets only"),
        [Mode.no_transition_widgets] = _("No cover or default widgets"),
        [Mode.cover_with_widgets] = _("Cover + default widgets"),
        [Mode.cover_only] = _("Cover only"),
    }
    return labels[mode] or labels[Mode.cover_only]
end

local function sourceModeLabel(mode)
    local labels = {
        [SourceMode.balanced] = _("Balanced (faster)"),
        [SourceMode.best_quality] = _("Best quality"),
    }
    return labels[mode] or labels[SourceMode.balanced]
end

local function readMode(key, default_mode)
    local mode = G_reader_settings:readSetting(key, default_mode)
    return VALID_MODES[mode] and mode or default_mode
end

local function getCoverSourceMode()
    local mode = G_reader_settings:readSetting(Settings.cover_source, DEFAULT_SOURCE_MODE)
    return VALID_SOURCE_MODES[mode] and mode or DEFAULT_SOURCE_MODE
end

local function isEnabled()
    return G_reader_settings:nilOrTrue(Settings.enabled)
end

local function getOpenMode()
    return readMode(Settings.open_mode, DEFAULT_OPEN_MODE)
end

local function getCloseMode()
    if G_reader_settings:hasNot(Settings.close_mode)
        and G_reader_settings:has(Settings.close_enabled_legacy)
        and not G_reader_settings:nilOrTrue(Settings.close_enabled_legacy) then
        return Mode.off
    end

    return readMode(Settings.close_mode, DEFAULT_CLOSE_MODE)
end

local function modeShowsCover(mode)
    return mode == Mode.cover_with_widgets or mode == Mode.cover_only
end

local function modeSuppressesDefaultWidgets(mode)
    return mode == Mode.cover_only or mode == Mode.no_transition_widgets
end

local function shouldShowOpeningCover()
    return isEnabled() and modeShowsCover(getOpenMode())
end

local function shouldShowClosingCoverMode()
    return isEnabled() and modeShowsCover(getCloseMode())
end

local function shouldUseSeamlessOpening()
    return isEnabled() and modeSuppressesDefaultWidgets(getOpenMode())
end

local function shouldSuppressClosingNotice()
    local close_mode = getCloseMode()
    if close_mode == Mode.no_transition_widgets then
        return true
    end

    return close_mode == Mode.cover_only
        and G_reader_settings:nilOrTrue(Settings.suppress_closing_notice)
end

local function shouldPreSuppressClosingNotice()
    return isEnabled() and shouldSuppressClosingNotice()
end

local function shouldPreferBestQualityCover()
    return getCoverSourceMode() == SourceMode.best_quality
end

local function shouldExtractFromDocument()
    return G_reader_settings:nilOrTrue(Settings.extract_enabled)
end

local function shouldShowOnTeardown()
    return G_reader_settings:isTrue(Settings.close_on_teardown)
end

local function getOpenCloseDelay()
    return G_reader_settings:readSetting(Settings.open_close_delay, 0.1)
end

local function getAfterCloseDelay()
    return G_reader_settings:readSetting(Settings.after_close_delay, 0.5)
end

local function getClosingNoticeSuppressDelay()
    return G_reader_settings:readSetting(
        Settings.closing_notice_suppress_delay,
        getAfterCloseDelay() + 0.3
    )
end

local function flushSettings()
    if UIManager.flushSettings then
        pcall(function()
            UIManager:flushSettings()
        end)
    end
end

local function saveSetting(key, value)
    G_reader_settings:saveSetting(key, value)
    flushSettings()
end

local function joinPath(base, name)
    if not base or base == "" then
        return name
    end
    return base:sub(-1) == "/" and base .. name or base .. "/" .. name
end

local function safeRequire(module_name)
    local ok, module = pcall(require, module_name)
    if ok then
        return module
    end

    warn("failed to load module", module_name, module)
    return nil
end

local function addCoverBrowserToPackagePath(plugin_path)
    if State.coverbrowser_path_added then
        return
    end

    package.path = plugin_path .. "/?.lua;" .. package.path
    State.coverbrowser_path_added = true
end

local function getBookInfoManager()
    if State.book_info_manager then
        return State.book_info_manager
    end

    local plugin_path = "plugins/coverbrowser.koplugin"
    if lfs.attributes(plugin_path, "mode") ~= "directory" then
        warn("CoverBrowser plugin directory not found")
        return nil
    end

    addCoverBrowserToPackagePath(plugin_path)
    State.book_info_manager = safeRequire("bookinfomanager")
    return State.book_info_manager
end

local function getFileManagerBookInfo()
    if State.file_manager_book_info then
        return State.file_manager_book_info
    end

    State.file_manager_book_info = safeRequire("apps/filemanager/filemanagerbookinfo")
    return State.file_manager_book_info
end

local function freeOwnedCover()
    if not State.owned_cover_bb then
        return
    end

    local ok, err = pcall(function()
        State.owned_cover_bb:free()
    end)

    if not ok then
        warn("failed to free owned cover blitbuffer", err)
    end

    State.owned_cover_bb = nil
end

local function closeBookInfoDbIfLoaded()
    local BIM = State.book_info_manager
    if not BIM or not BIM.closeDbConnection then
        return
    end

    local ok, err = pcall(function()
        BIM:closeDbConnection()
    end)

    if not ok then
        warn("failed to close BookInfoManager DB connection", err)
    end
end

local function closeCover()
    if State.cover_widget then
        local ok, err = pcall(function()
            UIManager:close(State.cover_widget)
        end)
        if not ok then
            warn("failed to close cover widget", err)
        end
        State.cover_widget = nil
    end

    freeOwnedCover()
    closeBookInfoDbIfLoaded()
end

local function scheduleCloseCover(delay)
    UIManager:scheduleIn(delay, closeCover)
end

local function stopSuppressingClosingNotice()
    State.suppress_closing_notice = false
end

local function startSuppressingClosingNotice()
    if shouldSuppressClosingNotice() then
        State.suppress_closing_notice = true
    end
end

local function scheduleStopSuppressingClosingNotice(delay)
    if State.suppress_closing_notice then
        UIManager:scheduleIn(delay, stopSuppressingClosingNotice)
    end
end

local function setPatchEnabled(enabled)
    saveSetting(Settings.enabled, enabled and true or false)
    if not enabled then
        stopSuppressingClosingNotice()
        closeCover()
    end
end

local function setMode(key, mode)
    if VALID_MODES[mode] then
        saveSetting(key, mode)
    end
end

local function setCoverSourceMode(mode)
    if VALID_SOURCE_MODES[mode] then
        saveSetting(Settings.cover_source, mode)
    end
end

local function getWidgetText(widget)
    if type(widget) ~= "table" then
        return nil
    end

    local candidates = {
        widget.text,
        widget.message,
        widget.title,
        widget.info_text,
        widget.content,
        widget.label,
    }

    for _, value in ipairs(candidates) do
        if type(value) == "string" and value ~= "" then
            return value
        end
    end

    return nil
end

local function textLooksLikeClosingBookNotice(text)
    if type(text) ~= "string" then
        return false
    end

    local normalized = text:lower()

    return normalized:find("closing book", 1, true)
        or (normalized:find("closing", 1, true) and normalized:find("book", 1, true))
        or normalized:find("fechando livro", 1, true)
        or (normalized:find("fechando", 1, true) and normalized:find("livro", 1, true))
end

local function widgetLooksLikeClosingBookNotice(widget)
    if type(widget) == "string" then
        return textLooksLikeClosingBookNotice(widget)
    end

    return textLooksLikeClosingBookNotice(getWidgetText(widget))
end

local function getCoverFromCoverImageCache(filepath)
    local cache_path = G_reader_settings:readSetting("cover_image_cache_path")
    if not cache_path or lfs.attributes(cache_path, "mode") ~= "directory" then
        return nil
    end

    local util = safeRequire("util")
    local sha2 = safeRequire("ffi/sha2")
    local RenderImage = safeRequire("ui/renderimage")
    if not util or not sha2 or not sha2.md5 or not RenderImage then
        return nil
    end

    local _, document_name = util.splitFilePathName(filepath)
    if not document_name then
        return nil
    end

    local quality = G_reader_settings:readSetting("cover_image_quality", 75)
    local stretch_limit = G_reader_settings:readSetting("cover_image_stretch_limit", 8)
    local background = G_reader_settings:readSetting("cover_image_background", "black")
    local format = G_reader_settings:readSetting("cover_image_format", "auto")
    local grayscale = G_reader_settings:isTrue("cover_image_grayscale")
    local rotate = G_reader_settings:readSetting("cover_image_rotate", true)
    local rotated = rotate and "_rotated_" or ""

    local key = document_name
        .. quality
        .. stretch_limit
        .. background
        .. format
        .. tostring(grayscale)
        .. Screen:getRotationMode()
        .. rotated

    local ext = "jpg"
    local cover_path = G_reader_settings:readSetting("cover_image_path")
    if cover_path then
        local suffix = util.getFileNameSuffix(cover_path)
        if suffix and suffix ~= "" then
            ext = suffix:lower()
        end
    end

    local cache_file = joinPath(cache_path, "cover_" .. sha2.md5(key) .. "." .. ext)
    if lfs.attributes(cache_file, "mode") ~= "file" then
        return nil
    end

    local ok, cover_bb = pcall(function()
        return RenderImage:renderImageFile(cache_file)
    end)

    if ok and cover_bb then
        return cover_bb, true
    end

    warn("failed to load CoverImage cache file", cover_bb)
    return nil
end

local function getCoverFromDB(filepath)
    local BIM = getBookInfoManager()
    if not BIM then
        return nil
    end

    local ok, bookinfo = pcall(function()
        return BIM:getBookInfo(filepath, true)
    end)

    if not ok then
        warn("failed to read book info from DB", bookinfo)
        return nil
    end

    if not bookinfo or not bookinfo.has_cover or bookinfo.ignore_cover or not bookinfo.cover_bb then
        return nil
    end

    return bookinfo.cover_bb, false
end

local function closeDocument(document)
    if not document then
        return
    end

    local ok, err = pcall(function()
        document:close()
    end)

    if not ok then
        warn("failed to close temporary document", err)
    end
end

local function getCoverFromOpenDocument(document)
    if not document then
        return nil
    end

    local FMBI = getFileManagerBookInfo()
    if not FMBI then
        return nil
    end

    local ok, cover_bb = pcall(function()
        return FMBI:getCoverImage(document)
    end)

    if ok and cover_bb then
        return cover_bb, true
    end

    if not ok then
        warn("failed to get cover from open document", cover_bb)
    end

    return nil
end

local function extractCoverFromDocument(filepath, force_extract)
    if not force_extract and not shouldExtractFromDocument() then
        return nil
    end

    if not DocumentRegistry:hasProvider(filepath) then
        return nil
    end

    local FMBI = getFileManagerBookInfo()
    if not FMBI then
        return nil
    end

    local document
    local ok, cover_bb = pcall(function()
        local provider = ReaderUI:extendProvider(filepath, DocumentRegistry:getProvider(filepath))
        document = DocumentRegistry:openDocument(filepath, provider)
        if not document then
            return nil
        end

        if document.loadDocument and not document:loadDocument(false) then
            return nil
        end

        return FMBI:getCoverImage(document)
    end)

    closeDocument(document)

    if ok and cover_bb then
        return cover_bb, true
    end

    if not ok then
        warn("failed to extract cover from document", cover_bb)
    end

    return nil
end

local function findCover(filepath, options)
    options = options or {}

    local sources = {}

    if shouldPreferBestQualityCover() then
        if options.open_document then
            table.insert(sources, function()
                return getCoverFromOpenDocument(options.open_document)
            end)
        end

        if options.allow_direct_extract ~= false then
            table.insert(sources, function()
                return extractCoverFromDocument(filepath, true)
            end)
        end

        table.insert(sources, getCoverFromDB)
        table.insert(sources, getCoverFromCoverImageCache)
    else
        table.insert(sources, getCoverFromCoverImageCache)
        table.insert(sources, getCoverFromDB)

        if options.open_document then
            table.insert(sources, function()
                return getCoverFromOpenDocument(options.open_document)
            end)
        end

        if options.allow_direct_extract ~= false then
            table.insert(sources, extractCoverFromDocument)
        end
    end

    for _, source in ipairs(sources) do
        local ok, cover_bb, needs_free = pcall(source, filepath)
        if ok and cover_bb then
            return cover_bb, needs_free
        end
        if not ok then
            warn("cover source failed", cover_bb)
        end
    end

    return nil
end

local function showCover(filepath, options)
    if not isEnabled() or not filepath or filepath == "" then
        return false
    end

    closeCover()

    local cover_bb, needs_free = findCover(filepath, options)
    if not cover_bb then
        return false
    end

    if needs_free then
        State.owned_cover_bb = cover_bb
    end

    local cover_widget = ImageWidget:new{
        image = cover_bb,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        alpha = true,
        image_disposable = false,
    }

    local ok, err = pcall(function()
        UIManager:show(cover_widget, "full")
        UIManager:forceRePaint()
    end)

    if not ok then
        warn("failed to display cover", err)
        freeOwnedCover()
        return false
    end

    State.cover_widget = cover_widget
    return true
end

local function shouldShowClosingCover(ui, full_refresh)
    if not shouldShowClosingCoverMode() then
        return false
    end

    if not ui or not ui.document or not ui.document.file then
        return false
    end

    if full_refresh == false and ui.tearing_down and not shouldShowOnTeardown() then
        return false
    end

    return true
end

local function makeModeMenu(setting_key, default_mode, get_current_mode)
    local items = {}

    for _, mode in ipairs(MODE_ORDER) do
        table.insert(items, {
            text = modeLabel(mode),
            radio = true,
            keep_menu_open = true,
            checked_func = function()
                local current_mode = get_current_mode and get_current_mode()
                    or readMode(setting_key, default_mode)
                return current_mode == mode
            end,
            callback = function(touchmenu_instance)
                setMode(setting_key, mode)
                if mode == Mode.off or mode == Mode.no_transition_widgets then
                    stopSuppressingClosingNotice()
                    closeCover()
                end
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return items
end

local function makeSourceModeMenu()
    local items = {}

    for _, mode in ipairs(SOURCE_MODE_ORDER) do
        table.insert(items, {
            text = sourceModeLabel(mode),
            radio = true,
            keep_menu_open = true,
            checked_func = function()
                return getCoverSourceMode() == mode
            end,
            callback = function(touchmenu_instance)
                setCoverSourceMode(mode)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return items
end

local BookLoadCoverMenu = {
    name = "bookloadcover",
}

function BookLoadCoverMenu:addToMainMenu(menu_items)
    menu_items.bookloadcover = {
        text_func = function()
            local title = _("Book cover while opening/closing")
            if isEnabled() then
                return title
            end
            return title .. " (" .. _("disabled") .. ")"
        end,
        sorting_hint = "setting",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = _("Enable patch"),
                checked_func = isEnabled,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    setPatchEnabled(not isEnabled())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
                separator = true,
            },
            {
                text_func = function()
                    return _("Opening") .. ": " .. modeLabel(getOpenMode())
                end,
                keep_menu_open = true,
                sub_item_table = makeModeMenu(Settings.open_mode, DEFAULT_OPEN_MODE, getOpenMode),
            },
            {
                text_func = function()
                    return _("Closing") .. ": " .. modeLabel(getCloseMode())
                end,
                keep_menu_open = true,
                sub_item_table = makeModeMenu(Settings.close_mode, DEFAULT_CLOSE_MODE, getCloseMode),
            },
            {
                text_func = function()
                    return _("Cover source") .. ": " .. sourceModeLabel(getCoverSourceMode())
                end,
                keep_menu_open = true,
                sub_item_table = makeSourceModeMenu(),
            },
            {
                text = _("Extract cover directly from document when needed"),
                checked_func = shouldExtractFromDocument,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    saveSetting(Settings.extract_enabled, not shouldExtractFromDocument())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
                separator = true,
            },
            {
                text = _("Show cover on internal reload/document switch"),
                checked_func = shouldShowOnTeardown,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    saveSetting(Settings.close_on_teardown, not shouldShowOnTeardown())
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
        },
    }
end

local function registerMenuToMainMenu(menu)
    if not menu or not menu.registerToMainMenu or menu._bookloadcover_menu_registered then
        return
    end

    menu:registerToMainMenu(BookLoadCoverMenu)
    menu._bookloadcover_menu_registered = true
    menu.tab_item_table = nil
end

local function patchFileManagerMenu()
    local FileManagerMenu = safeRequire("apps/filemanager/filemanagermenu")
    if not FileManagerMenu or FileManagerMenu._original_init_bookloadcover then
        return
    end

    FileManagerMenu._original_init_bookloadcover = FileManagerMenu.init
    FileManagerMenu.init = function(self, ...)
        local ret = FileManagerMenu._original_init_bookloadcover(self, ...)
        registerMenuToMainMenu(self)
        return ret
    end
end

local function patchUIManagerShow()
    if UIManager._original_show_bookloadcover then
        return
    end

    UIManager._original_show_bookloadcover = UIManager.show

    UIManager.show = function(self, widget, ...)
        if widgetLooksLikeClosingBookNotice(widget)
            and (State.suppress_closing_notice or shouldPreSuppressClosingNotice()) then
            return widget
        end

        return UIManager._original_show_bookloadcover(self, widget, ...)
    end
end

local function patchShowReaderCoroutine()
    if ReaderUI._original_showReaderCoroutine_bookloadcover then
        return
    end

    ReaderUI._original_showReaderCoroutine_bookloadcover = ReaderUI.showReaderCoroutine

    ReaderUI.showReaderCoroutine = function(self, file, provider, seamless)
        local cover_shown = false

        if shouldShowOpeningCover() then
            local ok, result = pcall(showCover, file, {
                reason = "open",
                allow_direct_extract = true,
            })
            if ok then
                cover_shown = result
            else
                warn("showCover failed", result)
            end
        end

        local final_seamless = seamless
        if shouldUseSeamlessOpening() then
            final_seamless = true
        end

        return ReaderUI._original_showReaderCoroutine_bookloadcover(
            self,
            file,
            provider,
            final_seamless
        )
    end
end

local function patchReaderInit()
    if ReaderUI._original_init_bookloadcover then
        return
    end

    ReaderUI._original_init_bookloadcover = ReaderUI.init

    ReaderUI.init = function(self, ...)
        local ret = ReaderUI._original_init_bookloadcover(self, ...)
        registerMenuToMainMenu(self.menu)
        scheduleCloseCover(getOpenCloseDelay())
        return ret
    end
end

local function patchReaderOnClose()
    if ReaderUI._original_onClose_bookloadcover then
        return
    end

    ReaderUI._original_onClose_bookloadcover = ReaderUI.onClose

    ReaderUI.onClose = function(self, full_refresh)
        local cover_shown = false
        local suppress_started = false

        if isEnabled() and shouldSuppressClosingNotice() then
            startSuppressingClosingNotice()
            suppress_started = State.suppress_closing_notice
        end

        if shouldShowClosingCover(self, full_refresh) then
            local ok, result = pcall(showCover, self.document.file, {
                reason = "close",
                open_document = self.document,
                allow_direct_extract = false,
            })

            if ok then
                cover_shown = result
                if not cover_shown and not suppress_started then
                    stopSuppressingClosingNotice()
                end
            else
                warn("showCover on close failed", result)
                if not suppress_started then
                    stopSuppressingClosingNotice()
                end
            end
        end

        local ok, ret = pcall(function()
            return ReaderUI._original_onClose_bookloadcover(self, full_refresh)
        end)

        if cover_shown then
            scheduleCloseCover(getAfterCloseDelay())
        end

        if suppress_started or State.suppress_closing_notice then
            scheduleStopSuppressingClosingNotice(getClosingNoticeSuppressDelay())
        end

        if not ok then
            error(ret)
        end

        return ret
    end
end

ReaderUI = require("apps/reader/readerui")
patchUIManagerShow()
patchFileManagerMenu()
patchShowReaderCoroutine()
patchReaderInit()
patchReaderOnClose()

info("initialized successfully")
