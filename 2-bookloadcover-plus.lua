-- Display the book cover while opening and closing documents.
-- Place this file in koreader/patches/.

local logger = require("logger")
local UIManager = require("ui/uimanager")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")
local DocumentRegistry = require("document/documentregistry")
local _ = require("gettext")

local PLUGIN_NAME = "BookLoadCover Plus"
local LOG_PREFIX = PLUGIN_NAME .. " patch:"
local PATCH_VERSION = "1.3.0"

local function pluginName()
	return _("BookLoadCover Plus")
end

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
	current_book_path = nil,
}

local Settings = {
	open_mode = "bookloadcover_open_mode",
	close_mode = "bookloadcover_close_mode",
	close_enabled_legacy = "bookloadcover_close_enabled",
	extract_enabled = "bookloadcover_extract_enabled",
	cover_source = "bookloadcover_cover_source",
	open_layout = "bookloadcover_open_layout",
	close_layout = "bookloadcover_close_layout",
	cover_layout_legacy = "bookloadcover_cover_layout",
	card_size_percent = "bookloadcover_card_size_percent",
	card_rounded_corners = "bookloadcover_card_rounded_corners",
	close_on_teardown = "bookloadcover_close_on_teardown",
	suppress_closing_notice = "bookloadcover_suppress_closing_notice",
	open_close_delay = "bookloadcover_close_delay",
	after_close_delay = "bookloadcover_after_close_delay",
	closing_notice_suppress_delay = "bookloadcover_closing_notice_suppress_delay",
}

-- Closing-only choice: reuse whatever is set for opening.
local SAME_AS_OPENING = "same_as_opening"

local Mode = {
	off = "off",
	no_transition_widgets = "no_transition_widgets",
	cover_with_widgets = "cover_with_widgets",
	cover_only = "cover_only",
	same_as_opening = SAME_AS_OPENING,
}

local SourceMode = {
	balanced = "balanced",
	best_quality = "best_quality",
}

local LayoutMode = {
	stretch = "stretch",
	fit_black = "fit_black",
	fit_white = "fit_white",
	fill_zoom = "fill_zoom",
	centered_card = "centered_card",
	same_as_opening = SAME_AS_OPENING,
}

local Action = {
	open = "open",
	close = "close",
}

local DEFAULT_OPEN_MODE = Mode.cover_only
local DEFAULT_CLOSE_MODE = Mode.cover_only
local DEFAULT_SOURCE_MODE = SourceMode.balanced
local DEFAULT_LAYOUT_MODE = LayoutMode.stretch
local DEFAULT_CLOSE_LAYOUT_MODE = LayoutMode.same_as_opening
local DEFAULT_CARD_SIZE_PERCENT = 70

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

local LAYOUT_MODE_ORDER = {
	LayoutMode.stretch,
	LayoutMode.fit_black,
	LayoutMode.fit_white,
	LayoutMode.fill_zoom,
	LayoutMode.centered_card,
}

local VALID_LAYOUT_MODES = {
	[LayoutMode.stretch] = true,
	[LayoutMode.fit_black] = true,
	[LayoutMode.fit_white] = true,
	[LayoutMode.fill_zoom] = true,
	[LayoutMode.centered_card] = true,
}

-- Labels are built once at load time instead of on every lookup.
local MODE_LABELS = {
	[Mode.off] = _("KOReader default (message, no cover)"),
	[Mode.no_transition_widgets] = _("Nothing (no cover, no message)"),
	[Mode.cover_with_widgets] = _("Cover + KOReader message"),
	[Mode.cover_only] = _("Cover only"),
	[Mode.same_as_opening] = _("Same as opening"),
}

local SOURCE_MODE_LABELS = {
	[SourceMode.balanced] = _("Balanced (faster)"),
	[SourceMode.best_quality] = _("Best quality"),
}

local LAYOUT_MODE_LABELS = {
	[LayoutMode.stretch] = _("Stretch to screen"),
	[LayoutMode.fit_black] = _("Fit to screen (black background)"),
	[LayoutMode.fit_white] = _("Fit to screen (white background)"),
	[LayoutMode.fill_zoom] = _("Fill screen (zoom/crop)"),
	[LayoutMode.centered_card] = _("Centered card"),
	[LayoutMode.same_as_opening] = _("Same as opening"),
}

local function modeLabel(mode)
	return MODE_LABELS[mode] or MODE_LABELS[Mode.cover_only]
end

local function sourceModeLabel(mode)
	return SOURCE_MODE_LABELS[mode] or SOURCE_MODE_LABELS[SourceMode.balanced]
end

local function layoutModeLabel(mode)
	return LAYOUT_MODE_LABELS[mode] or LAYOUT_MODE_LABELS[LayoutMode.stretch]
end

local function readMode(key, default_mode)
	local mode = G_reader_settings:readSetting(key, default_mode)
	return VALID_MODES[mode] and mode or default_mode
end

local function getCoverSourceMode()
	local mode = G_reader_settings:readSetting(Settings.cover_source, DEFAULT_SOURCE_MODE)
	return VALID_SOURCE_MODES[mode] and mode or DEFAULT_SOURCE_MODE
end

local function readLayoutSetting(key)
	local mode = G_reader_settings:readSetting(key)
	return VALID_LAYOUT_MODES[mode] and mode or nil
end

-- Older versions stored a single layout for both actions; it is used as the
-- opening layout until one is chosen explicitly.
local function getOpenLayoutMode()
	return readLayoutSetting(Settings.open_layout)
		or readLayoutSetting(Settings.cover_layout_legacy)
		or DEFAULT_LAYOUT_MODE
end

-- Raw closing choice, which may be "same as opening".
local function getCloseLayoutSetting()
	local mode = G_reader_settings:readSetting(Settings.close_layout, DEFAULT_CLOSE_LAYOUT_MODE)
	if mode == LayoutMode.same_as_opening or VALID_LAYOUT_MODES[mode] then
		return mode
	end
	return DEFAULT_CLOSE_LAYOUT_MODE
end

local function getCloseLayoutMode()
	local mode = getCloseLayoutSetting()
	if mode == LayoutMode.same_as_opening then
		return getOpenLayoutMode()
	end
	return mode
end

local function getLayoutModeForAction(action)
	if action == Action.close then
		return getCloseLayoutMode()
	end
	return getOpenLayoutMode()
end

local function getCardSizePercent()
	local percent = tonumber(G_reader_settings:readSetting(Settings.card_size_percent, DEFAULT_CARD_SIZE_PERCENT))
	if not percent then
		return DEFAULT_CARD_SIZE_PERCENT
	end
	return math.max(30, math.min(95, math.floor(percent)))
end

local function useRoundedCardCorners()
	return G_reader_settings:nilOrTrue(Settings.card_rounded_corners)
end

local function getOpenMode()
	return readMode(Settings.open_mode, DEFAULT_OPEN_MODE)
end

-- Raw closing choice, which may be "same as opening".
local function getCloseModeSetting()
	if
		G_reader_settings:hasNot(Settings.close_mode)
		and G_reader_settings:has(Settings.close_enabled_legacy)
		and not G_reader_settings:nilOrTrue(Settings.close_enabled_legacy)
	then
		return Mode.off
	end

	local mode = G_reader_settings:readSetting(Settings.close_mode, DEFAULT_CLOSE_MODE)
	if mode == Mode.same_as_opening or VALID_MODES[mode] then
		return mode
	end
	return DEFAULT_CLOSE_MODE
end

local function getCloseMode()
	local mode = getCloseModeSetting()
	if mode == Mode.same_as_opening then
		return getOpenMode()
	end
	return mode
end

local function modeShowsCover(mode)
	return mode == Mode.cover_with_widgets or mode == Mode.cover_only
end

local function modeSuppressesDefaultWidgets(mode)
	return mode == Mode.cover_only or mode == Mode.no_transition_widgets
end

local function shouldShowOnInternalTransition()
	return G_reader_settings:isTrue(Settings.close_on_teardown)
end

local function shouldShowOpeningCover()
	return modeShowsCover(getOpenMode())
end

local function getReaderFile(ui)
	return ui and ui.document and ui.document.file or nil
end

local function sameFile(left, right)
	return left and right and left == right
end

local function rememberCurrentBook(file)
	if file and file ~= "" then
		State.current_book_path = file
	end
end

local function resetCurrentBook()
	State.current_book_path = nil
end

local function looksLikeInternalOpening(ui, file, seamless)
	return seamless == true or sameFile(getReaderFile(ui), file) or sameFile(State.current_book_path, file)
end

local function shouldShowOpeningCoverForRequest(ui, file, seamless)
	if not shouldShowOpeningCover() then
		return false
	end

	if shouldShowOnInternalTransition() then
		return true
	end

	return not looksLikeInternalOpening(ui, file, seamless)
end

local function shouldShowClosingCoverMode()
	return modeShowsCover(getCloseMode())
end

local function shouldUseSeamlessOpening()
	return modeSuppressesDefaultWidgets(getOpenMode())
end

local function shouldSuppressClosingNotice()
	local close_mode = getCloseMode()
	if close_mode == Mode.no_transition_widgets then
		return true
	end

	return close_mode == Mode.cover_only and G_reader_settings:nilOrTrue(Settings.suppress_closing_notice)
end

local function shouldPreSuppressClosingNotice()
	return shouldSuppressClosingNotice()
end

local function shouldPreferBestQualityCover()
	return getCoverSourceMode() == SourceMode.best_quality
end

local function shouldExtractFromDocument()
	return G_reader_settings:nilOrTrue(Settings.extract_enabled)
end

local function getOpenCloseDelay()
	return G_reader_settings:readSetting(Settings.open_close_delay, 0.1)
end

local function getAfterCloseDelay()
	return G_reader_settings:readSetting(Settings.after_close_delay, 0.5)
end

local function getClosingNoticeSuppressDelay()
	return G_reader_settings:readSetting(Settings.closing_notice_suppress_delay, getAfterCloseDelay() + 0.3)
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

-- A pending close from a previous transition must not close a newer cover,
-- and repeated schedules must not pile up.
local function cancelScheduledCloseCover()
	UIManager:unschedule(closeCover)
end

local function scheduleCloseCover(delay)
	cancelScheduledCloseCover()
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
		UIManager:unschedule(stopSuppressingClosingNotice)
		UIManager:scheduleIn(delay, stopSuppressingClosingNotice)
	end
end

local function setMode(key, mode)
	if VALID_MODES[mode] or (key == Settings.close_mode and mode == Mode.same_as_opening) then
		saveSetting(key, mode)
	end
end

local function setCoverSourceMode(mode)
	if VALID_SOURCE_MODES[mode] then
		saveSetting(Settings.cover_source, mode)
	end
end

local function setLayoutModeForAction(action, mode)
	if action == Action.close then
		if mode == LayoutMode.same_as_opening or VALID_LAYOUT_MODES[mode] then
			saveSetting(Settings.close_layout, mode)
		end
	elseif VALID_LAYOUT_MODES[mode] then
		saveSetting(Settings.open_layout, mode)
	end
end

local function anyLayoutUsesCenteredCard()
	return getOpenLayoutMode() == LayoutMode.centered_card or getCloseLayoutMode() == LayoutMode.centered_card
end

local function setCardSizePercent(percent)
	percent = tonumber(percent)
	if percent then
		saveSetting(Settings.card_size_percent, math.max(30, math.min(95, math.floor(percent))))
	end
end

local WIDGET_TEXT_FIELDS = { "text", "message", "title", "info_text", "content", "label" }

-- The "Closing book…" notice is a short message; longer texts are skipped
-- without lowercasing or scanning them.
local MAX_NOTICE_TEXT_LENGTH = 120

local function getWidgetText(widget)
	if type(widget) ~= "table" then
		return nil
	end

	for i = 1, #WIDGET_TEXT_FIELDS do
		local value = widget[WIDGET_TEXT_FIELDS[i]]
		if type(value) == "string" and value ~= "" then
			return value
		end
	end

	return nil
end

local function textHasAllWords(text, words)
	for i = 1, #words do
		if not text:find(words[i], 1, true) then
			return false
		end
	end
	return true
end

local CLOSING_NOTICE_WORD_SETS = {
	{ "closing", "book" }, -- English
	{ "fechando", "livro" }, -- Portuguese
	{ "chiusura", "libro" }, -- Italian
	{ "chiudendo", "libro" }, -- Italian alternative
	{ "fermeture", "livre" }, -- French
	{ "cerrando", "libro" }, -- Spanish
	{ "schließen", "buch" }, -- German
	{ "schlies", "buch" }, -- German fallback without ß
	{ "закры", "кни" }, -- Russian stem fallback
}

local closing_notice_localized

local function getLocalizedClosingNotices()
	if not closing_notice_localized then
		closing_notice_localized = {}
		for _, candidate in ipairs({ _("Closing book…"), _("Closing book..."), _("Closing book") }) do
			if type(candidate) == "string" and candidate ~= "" then
				table.insert(closing_notice_localized, candidate:lower())
			end
		end
	end
	return closing_notice_localized
end

local function textLooksLikeClosingBookNotice(text)
	if type(text) ~= "string" or #text > MAX_NOTICE_TEXT_LENGTH then
		return false
	end

	local normalized = text:lower()
	local localized = getLocalizedClosingNotices()
	for i = 1, #localized do
		if normalized:find(localized[i], 1, true) then
			return true
		end
	end

	for i = 1, #CLOSING_NOTICE_WORD_SETS do
		if textHasAllWords(normalized, CLOSING_NOTICE_WORD_SETS[i]) then
			return true
		end
	end

	return false
end

local function widgetLooksLikeClosingBookNotice(widget)
	if type(widget) == "string" then
		return textLooksLikeClosingBookNotice(widget)
	end

	return textLooksLikeClosingBookNotice(getWidgetText(widget))
end

local Lazy = {}

-- Resolves a module once and remembers the result (including failure).
local function lazyRequire(module_name)
	local cached = Lazy[module_name]
	if cached == nil then
		cached = safeRequire(module_name) or false
		Lazy[module_name] = cached
	end
	return cached or nil
end

local function getCoverFromCoverImageCache(filepath)
	local cache_path = G_reader_settings:readSetting("cover_image_cache_path")
	if not cache_path or lfs.attributes(cache_path, "mode") ~= "directory" then
		return nil
	end

	local util = lazyRequire("util")
	local sha2 = lazyRequire("ffi/sha2")
	local RenderImage = lazyRequire("ui/renderimage")
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

local function tryCoverSource(source, ...)
	local ok, cover_bb, needs_free = pcall(source, ...)
	if ok and cover_bb then
		return cover_bb, needs_free
	end
	if not ok then
		warn("cover source failed", cover_bb)
	end
	return nil
end

local function findCover(filepath, options)
	options = options or {}

	local open_document = options.open_document
	local allow_extract = options.allow_direct_extract ~= false
	local cover_bb, needs_free

	if shouldPreferBestQualityCover() then
		if open_document then
			cover_bb, needs_free = tryCoverSource(getCoverFromOpenDocument, open_document)
			if cover_bb then
				return cover_bb, needs_free
			end
		end

		if allow_extract then
			cover_bb, needs_free = tryCoverSource(extractCoverFromDocument, filepath, true)
			if cover_bb then
				return cover_bb, needs_free
			end
		end

		cover_bb, needs_free = tryCoverSource(getCoverFromDB, filepath)
		if cover_bb then
			return cover_bb, needs_free
		end

		return tryCoverSource(getCoverFromCoverImageCache, filepath)
	end

	cover_bb, needs_free = tryCoverSource(getCoverFromCoverImageCache, filepath)
	if cover_bb then
		return cover_bb, needs_free
	end

	cover_bb, needs_free = tryCoverSource(getCoverFromDB, filepath)
	if cover_bb then
		return cover_bb, needs_free
	end

	if open_document then
		cover_bb, needs_free = tryCoverSource(getCoverFromOpenDocument, open_document)
		if cover_bb then
			return cover_bb, needs_free
		end
	end

	if allow_extract then
		return tryCoverSource(extractCoverFromDocument, filepath)
	end

	return nil
end

local function getCoverSize(cover_bb)
	if not cover_bb or not cover_bb.getWidth or not cover_bb.getHeight then
		return nil, nil
	end

	local ok, w, h = pcall(function()
		return cover_bb:getWidth(), cover_bb:getHeight()
	end)

	if ok and w and h and w > 0 and h > 0 then
		return w, h
	end

	return nil, nil
end

local function makeStretchCoverWidget(cover_bb, screen_w, screen_h)
	return ImageWidget:new({
		image = cover_bb,
		width = screen_w,
		height = screen_h,
		alpha = true,
		image_disposable = false,
	})
end

local function makeCenteredCardCoverWidget(cover_bb, cover_w, cover_h, screen_w, screen_h)
	local percent = getCardSizePercent() / 100
	local card_w = math.max(1, math.floor(screen_w * percent))
	local card_h = math.max(1, math.floor(screen_h * percent))
	local border_size = Screen:scaleBySize(2)
	local padding = Screen:scaleBySize(10)
	local inner_w = math.max(1, card_w - (padding + border_size) * 2)
	local inner_h = math.max(1, card_h - (padding + border_size) * 2)
	local scale_factor = math.min(inner_w / cover_w, inner_h / cover_h)

	local image = ImageWidget:new({
		image = cover_bb,
		scale_factor = scale_factor,
		alpha = true,
		image_disposable = false,
	})

	local card = FrameContainer:new({
		dimen = { w = card_w, h = card_h },
		padding = padding,
		bordersize = border_size,
		radius = useRoundedCardCorners() and Screen:scaleBySize(18) or 0,
		background = Blitbuffer.COLOR_WHITE,
		color = Blitbuffer.COLOR_BLACK,
		CenterContainer:new({
			dimen = { w = inner_w, h = inner_h },
			image,
		}),
	})

	return CenterContainer:new({
		dimen = { w = screen_w, h = screen_h },
		card,
	})
end

local function makeCoverImageWidget(cover_bb, layout_mode)
	local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()

	if layout_mode == LayoutMode.stretch then
		return makeStretchCoverWidget(cover_bb, screen_w, screen_h)
	end

	local cover_w, cover_h = getCoverSize(cover_bb)
	if not cover_w or not cover_h then
		warn("failed to read cover size, falling back to stretch layout")
		return makeStretchCoverWidget(cover_bb, screen_w, screen_h)
	end

	if layout_mode == LayoutMode.centered_card then
		return makeCenteredCardCoverWidget(cover_bb, cover_w, cover_h, screen_w, screen_h)
	end

	local scale_factor
	if layout_mode == LayoutMode.fill_zoom then
		scale_factor = math.max(screen_w / cover_w, screen_h / cover_h)
		return ImageWidget:new({
			image = cover_bb,
			width = screen_w,
			height = screen_h,
			scale_factor = scale_factor,
			alpha = true,
			image_disposable = false,
		})
	end

	scale_factor = math.min(screen_w / cover_w, screen_h / cover_h)
	local image = ImageWidget:new({
		image = cover_bb,
		scale_factor = scale_factor,
		alpha = true,
		image_disposable = false,
	})

	local background = layout_mode == LayoutMode.fit_white and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

	return FrameContainer:new({
		dimen = { w = screen_w, h = screen_h },
		padding = 0,
		bordersize = 0,
		background = background,
		CenterContainer:new({
			dimen = { w = screen_w, h = screen_h },
			image,
		}),
	})
end

local function showCover(filepath, options)
	if not filepath or filepath == "" then
		return false
	end

	cancelScheduledCloseCover()
	closeCover()

	local cover_bb, needs_free = findCover(filepath, options)
	if not cover_bb then
		return false
	end

	if needs_free then
		State.owned_cover_bb = cover_bb
	end

	local action = options and options.reason or Action.open
	local ok, err = pcall(function()
		local cover_widget = makeCoverImageWidget(cover_bb, getLayoutModeForAction(action))
		UIManager:show(cover_widget, "full")
		State.cover_widget = cover_widget
		UIManager:forceRePaint()
	end)

	if not ok then
		warn("failed to display cover", err)
		closeCover()
		return false
	end

	return true
end

local function shouldShowClosingCover(ui, full_refresh)
	if not shouldShowClosingCoverMode() then
		return false
	end

	if not ui or not ui.document or not ui.document.file then
		return false
	end

	if full_refresh == false and ui.tearing_down and not shouldShowOnInternalTransition() then
		return false
	end

	return true
end

local function refreshMenu(touchmenu_instance)
	if touchmenu_instance then
		touchmenu_instance:updateItems()
	end
end

local function makeRadioMenu(values, label_func, get_current, set_value, on_change)
	local items = {}

	for _, value in ipairs(values) do
		table.insert(items, {
			text = label_func(value),
			radio = true,
			keep_menu_open = true,
			checked_func = function()
				return get_current() == value
			end,
			callback = function(touchmenu_instance)
				set_value(value)
				if on_change then
					on_change(value)
				end
				refreshMenu(touchmenu_instance)
			end,
		})
	end

	return items
end

-- Builds the radio list for one action. Closing gets an extra
-- "Same as opening" entry on top, which shows the value it resolves to.
local function makeActionChoiceMenu(action, order, label_func, get_open, get_close_setting, set_value, on_change)
	local get_current = action == Action.close and get_close_setting or get_open
	local items = makeRadioMenu(order, label_func, get_current, set_value, on_change)

	if action == Action.close then
		local same = makeRadioMenu({ SAME_AS_OPENING }, label_func, get_current, set_value, on_change)[1]
		same.text = nil
		same.text_func = function()
			return label_func(SAME_AS_OPENING) .. " (" .. label_func(get_open()) .. ")"
		end
		same.separator = true
		table.insert(items, 1, same)
	end

	return items
end

local function makeModeMenu(action)
	local setting_key = action == Action.close and Settings.close_mode or Settings.open_mode
	return makeActionChoiceMenu(action, MODE_ORDER, modeLabel, getOpenMode, getCloseModeSetting, function(mode)
		setMode(setting_key, mode)
	end, function()
		if not modeShowsCover(getOpenMode()) and not modeShowsCover(getCloseMode()) then
			stopSuppressingClosingNotice()
			cancelScheduledCloseCover()
			closeCover()
		end
	end)
end

local function makeLayoutModeMenu(action)
	return makeActionChoiceMenu(action, LAYOUT_MODE_ORDER, layoutModeLabel, getOpenLayoutMode, getCloseLayoutSetting, function(mode)
		setLayoutModeForAction(action, mode)
	end)
end

local CARD_SIZE_OPTIONS = { 40, 50, 60, 70, 80, 90 }

local function makeCardSizeMenu()
	return makeRadioMenu(CARD_SIZE_OPTIONS, function(percent)
		return percent .. "%"
	end, getCardSizePercent, setCardSizePercent)
end

local function makeActionMenu(action)
	local is_close = action == Action.close
	local get_mode = is_close and getCloseMode or getOpenMode

	return {
		{
			text_func = function()
				if is_close and getCloseModeSetting() == Mode.same_as_opening then
					return _("Show") .. ": " .. modeLabel(Mode.same_as_opening)
				end
				return _("Show") .. ": " .. modeLabel(get_mode())
			end,
			help_text = is_close
					and _("What appears on screen while the book is closing and KOReader returns to the file browser. Choose 'Same as opening' to reuse the opening choice.")
				or _("What appears on screen while the book is loading."),
			keep_menu_open = true,
			sub_item_table = makeModeMenu(action),
		},
		{
			text_func = function()
				if is_close and getCloseLayoutSetting() == LayoutMode.same_as_opening then
					return _("Cover style") .. ": " .. layoutModeLabel(LayoutMode.same_as_opening)
				end
				return _("Cover style") .. ": " .. layoutModeLabel(getLayoutModeForAction(action))
			end,
			help_text = is_close
					and _("How the cover looks on screen when closing a book: stretched, fitted, zoomed or as a centered card. Choose 'Same as opening' to reuse the opening style.")
				or _("How the cover looks on screen when opening a book: stretched, fitted, zoomed or as a centered card."),
			enabled_func = function()
				return modeShowsCover(get_mode())
			end,
			keep_menu_open = true,
			sub_item_table = makeLayoutModeMenu(action),
		},
	}
end

local function showVersionInfo()
	UIManager:show(InfoMessage:new({
		text = pluginName() .. "\n" .. _("Version") .. ": v" .. PATCH_VERSION,
		timeout = 3,
	}))
end

local BookLoadCoverMenu = {
	name = "bookloadcover",
}

function BookLoadCoverMenu:addToMainMenu(menu_items)
	menu_items.bookloadcover = {
		text = pluginName(),
		sorting_hint = "setting",
		keep_menu_open = true,
		sub_item_table = {
			{
				text = _("When opening a book"),
				help_text = _("What to show, and the cover style, while a book is opening."),
				keep_menu_open = true,
				sub_item_table = makeActionMenu(Action.open),
			},
			{
				text = _("When closing a book"),
				help_text = _("What to show, and the cover style, while a book is closing."),
				keep_menu_open = true,
				sub_item_table = makeActionMenu(Action.close),
				separator = true,
			},
			{
				text = _("Centered card options"),
				help_text = _("Size and corners of the card. Applies to opening and closing whenever their cover style is 'Centered card'."),
				enabled_func = anyLayoutUsesCenteredCard,
				keep_menu_open = true,
				sub_item_table = {
					{
						text_func = function()
							return _("Size") .. ": " .. getCardSizePercent() .. "%"
						end,
						keep_menu_open = true,
						sub_item_table = makeCardSizeMenu(),
					},
					{
						text = _("Rounded corners"),
						checked_func = useRoundedCardCorners,
						keep_menu_open = true,
						callback = function(touchmenu_instance)
							saveSetting(Settings.card_rounded_corners, not useRoundedCardCorners())
							refreshMenu(touchmenu_instance)
						end,
					},
				},
			},
			{
				text_func = function()
					return _("Cover source") .. ": " .. sourceModeLabel(getCoverSourceMode())
				end,
				help_text = _("Balanced uses cached covers first (fast). Best quality extracts the cover from the document, which looks sharper but can slow down opening."),
				keep_menu_open = true,
				sub_item_table = makeRadioMenu(SOURCE_MODE_ORDER, sourceModeLabel, getCoverSourceMode, setCoverSourceMode),
			},
			{
				text = _("Advanced"),
				keep_menu_open = true,
				separator = true,
				sub_item_table = {
					{
						text = _("Extract cover directly from document when needed"),
						help_text = _("If no cached cover is found, open the document to read its cover. Slower for large books."),
						checked_func = shouldExtractFromDocument,
						keep_menu_open = true,
						callback = function(touchmenu_instance)
							saveSetting(Settings.extract_enabled, not shouldExtractFromDocument())
							refreshMenu(touchmenu_instance)
						end,
					},
					{
						text = _("Show cover on internal reload/document switch"),
						help_text = _("Also show the cover when KOReader reloads the current book (e.g. after changing some document settings)."),
						checked_func = shouldShowOnInternalTransition,
						keep_menu_open = true,
						callback = function(touchmenu_instance)
							saveSetting(Settings.close_on_teardown, not shouldShowOnInternalTransition())
							refreshMenu(touchmenu_instance)
						end,
					},
				},
			},
			{
				text_func = function()
					return _("Patch version") .. ": v" .. PATCH_VERSION
				end,
				keep_menu_open = false,
				callback = showVersionInfo,
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

local function patchFileManagerInit()
	local FileManager = safeRequire("apps/filemanager/filemanager")
	if not FileManager or FileManager._original_init_bookloadcover_plus then
		return
	end

	FileManager._original_init_bookloadcover_plus = FileManager.init
	FileManager.init = function(self, ...)
		resetCurrentBook()
		return FileManager._original_init_bookloadcover_plus(self, ...)
	end
end

local function patchUIManagerShow()
	if UIManager._original_show_bookloadcover then
		return
	end

	UIManager._original_show_bookloadcover = UIManager.show

	UIManager.show = function(self, widget, ...)
		-- Called for every widget: check the cheap suppression state before
		-- inspecting the widget text.
		if
			(State.suppress_closing_notice or shouldPreSuppressClosingNotice())
			and widgetLooksLikeClosingBookNotice(widget)
		then
			startSuppressingClosingNotice()
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
		if shouldShowOpeningCoverForRequest(self, file, seamless) then
			local ok, result = pcall(showCover, file, {
				reason = Action.open,
				allow_direct_extract = true,
			})
			if not ok then
				warn("showCover failed", result)
			end
		end

		local final_seamless = seamless
		if shouldUseSeamlessOpening() then
			final_seamless = true
		end

		local ret = ReaderUI._original_showReaderCoroutine_bookloadcover(self, file, provider, final_seamless)
		rememberCurrentBook(file)
		return ret
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
		rememberCurrentBook(getReaderFile(self))
		if State.cover_widget then
			scheduleCloseCover(getOpenCloseDelay())
		end
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

		if shouldSuppressClosingNotice() then
			startSuppressingClosingNotice()
			suppress_started = State.suppress_closing_notice
		end

		if shouldShowClosingCover(self, full_refresh) then
			local ok, result = pcall(showCover, self.document.file, {
				reason = Action.close,
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
patchFileManagerInit()
patchShowReaderCoroutine()
patchReaderInit()
patchReaderOnClose()

info("initialized successfully")
