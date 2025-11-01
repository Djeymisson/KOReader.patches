------------------------------------------------------------
-- Sleep Overlay Patch (KOReader 2025.08+)
-- Author: Djeymisson Moraes (refined)
-- This patch blends a random overlay image onto the current sleep cover.
-- Place transparent PNG overlays in the KOReader "sleepoverlays" folder.
------------------------------------------------------------
------------------------------------------------------------
-- MODULES (REQUIRE)
------------------------------------------------------------
local Blitbuffer = require("ffi/blitbuffer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local RenderImage = require("ui/renderimage")
local Screensaver = require("ui/screensaver")
local util = require("util")

-- Requires for settings menu
local _ = require("gettext")
local ReaderMenu = require("apps/reader/modules/readermenu")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")

------------------------------------------------------------
-- MODULE CONSTANTS & STATE
------------------------------------------------------------
-- Filesystem path
local joinPath = ffiUtil.joinPath
local overlay_dir = ffiUtil.realpath("sleepoverlays") or "sleepoverlays"

-- When the resulting image carries an alpha channel, flatten it onto a solid background
-- so that ImageWidget can display it without turning transparent regions black.
local FLATTEN_ALPHA_BACKGROUND = true
local FLATTEN_ALPHA_COLOR = Blitbuffer.COLOR_WHITE

-- Module state
local overlay_candidates
local random_seeded

-- Math optimizations
local math_floor = math.floor
local math_abs = math.abs

------------------------------------------------------------
-- CONFIGURATION (SETTINGS)
------------------------------------------------------------
local SETTINGS_KEY = "sleep_overlay_settings"
local defaults = {
    enable_overlay = true,
    overlay_resize_mode = "stretch" -- "fit", "fill", "center", "stretch"
}

local function getSettings()
    local s = G_reader_settings:readSetting(SETTINGS_KEY) or {}
    for k, v in pairs(defaults) do
        if s[k] == nil then
            s[k] = v
        end
    end
    return s
end

local function saveSettings(s)
    G_reader_settings:saveSetting(SETTINGS_KEY, s)
end

------------------------------------------------------------
-- MENU INTEGRATION
------------------------------------------------------------

local function buildMenu(reader_ui)
    local s = getSettings()

    -- "fit", "fill", "center", "stretch"
    local resize_options = {"fit", "fill", "center", "stretch"}
    local resize_options_text = {
        fit = _("Fit to screen"),
        fill = _("Fill screen (keep aspect ratio)"),
        center = _("Center (original size)"),
        stretch = _("Stretch to fill screen")
    }

    local sub_item_table = {}
    for _, mode in ipairs(resize_options) do
        table.insert(sub_item_table, {
            text = resize_options_text[mode] or mode,
            checked_func = function()
                return (s.overlay_resize_mode or defaults.overlay_resize_mode) == mode
            end,
            callback = function()
                s.overlay_resize_mode = mode
                saveSettings(s)
            end
        })
    end

    local submenu = {{
        text = _("Sleep Overlay"),
        checked_func = function()
            return s.enable_overlay
        end,
        callback = function()
            s.enable_overlay = not s.enable_overlay
            saveSettings(s)
        end
    }, {
        text = _("Overlay resize mode"),
        sub_item_table = sub_item_table,
        enabled_func = function()
            return s.enable_overlay
        end
    }}

    return {
        text_func = function()
            return _("Sleep Overlay")
        end,
        sub_item_table = submenu
    }
end

-- Generic patch function
local function patch(menu, order)
    table.insert(order.screen, "----------------------------")
    table.insert(order.screen, "sleep_overlay")
    menu.menu_items.sleep_overlay = buildMenu(menu.ui)
end

-- Apply the patch to the File Manager menu
local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
function FileManagerMenu:setUpdateItemTable()
    patch(self, require("ui/elements/filemanager_menu_order"))
    orig_FileManagerMenu_setUpdateItemTable(self)
end

-- Apply the patch to the Reader menu
local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable
function ReaderMenu:setUpdateItemTable()
    patch(self, require("ui/elements/reader_menu_order"))
    orig_ReaderMenu_setUpdateItemTable(self)
end

------------------------------------------------------------
-- OVERLAY LOGIC (HELPERS)
------------------------------------------------------------

local function seedRandom()
    if not random_seeded then
        random_seeded = true
        math.randomseed(os.time())
    end
end

local function refreshOverlayList()
    overlay_candidates = {}
    local attr = lfs.attributes(overlay_dir, "mode")
    if attr ~= "directory" then
        logger.dbg("SleepOverlay: overlay directory not found", overlay_dir)
        return
    end

    for entry in lfs.dir(overlay_dir) do
        if entry ~= "." and entry ~= ".." then
            local full = joinPath(overlay_dir, entry)
            local mode = lfs.attributes(full, "mode")
            if mode == "file" then
                local suffix = util.getFileNameSuffix(entry)
                if suffix and suffix:lower() == "png" then
                    table.insert(overlay_candidates, full)
                end
            end
        end
    end

    if #overlay_candidates == 0 then
        overlay_candidates = nil
        logger.dbg("SleepOverlay: no PNG overlays in", overlay_dir)
    end
end

local function pickOverlayPath()
    if not overlay_candidates then
        refreshOverlayList()
    end
    if not overlay_candidates then
        return nil
    end
    seedRandom()
    local idx = math.random(#overlay_candidates)
    return overlay_candidates[idx]
end

local function ensureBaseImage(self)
    if self.image then
        return self.image
    end
    if not self.image_file then
        return nil
    end

    local base_bb = RenderImage:renderImageFile(self.image_file, false, nil, nil)
    if base_bb then
        self.image = base_bb
        self.image_file = nil
    end
    return base_bb
end

-- Helper function to handle overlay resizing logic
local function _resizeOverlay(overlay_bb, base_w, base_h, resize_mode)
    local overlay_w, overlay_h = overlay_bb:getWidth(), overlay_bb:getHeight()

    if resize_mode == "center" then
        return overlay_bb -- No resize needed
    end

    local target_w, target_h
    if resize_mode == "stretch" then
        if overlay_w == base_w and overlay_h == base_h then
            return overlay_bb -- Already correct size
        end
        target_w, target_h = base_w, base_h
    else
        -- 'fit' or 'fill'
        local scale
        if resize_mode == "fill" then
            scale = math.max(base_w / overlay_w, base_h / overlay_h)
        else -- default to 'fit'
            scale = math.min(base_w / overlay_w, base_h / overlay_h)
        end

        -- Check if scaling is needed (avoids scaling if scale is ~1.0)
        if not scale or scale <= 0 or math.abs(scale - 1) < 0.0001 then
            return overlay_bb -- No scaling needed
        end
        target_w = math.max(1, math_floor(overlay_w * scale + 0.5))
        target_h = math.max(1, math_floor(overlay_h * scale + 0.5))
    end

    -- Perform scaling
    local scaled = RenderImage:scaleBlitBuffer(overlay_bb, target_w, target_h)
    if scaled then
        if overlay_bb.free then
            overlay_bb:free()
        end
        return scaled
    end
    return overlay_bb -- Scaling failed, return original
end

-- Helper function to calculate blitting coordinates (centering/cropping)
local function _getBlitCoords(base_w, base_h, overlay_w, overlay_h)
    local width = math.min(base_w, overlay_w)
    local height = math.min(base_h, overlay_h)

    local dest_x, dest_y = 0, 0
    local src_x, src_y = 0, 0

    if overlay_w < base_w then
        dest_x = math_floor((base_w - overlay_w) / 2) -- Center horizontally
    elseif overlay_w > base_w then
        src_x = math_floor((overlay_w - base_w) / 2) -- Crop horizontally
    end

    if overlay_h < base_h then
        dest_y = math_floor((base_h - overlay_h) / 2) -- Center vertically
    elseif overlay_h > base_h then
        src_y = math_floor((overlay_h - base_h) / 2) -- Crop vertically
    end

    return dest_x, dest_y, src_x, src_y, width, height
end

------------------------------------------------------------
-- OVERLAY LOGIC (CORE)
------------------------------------------------------------
local function composeOverlay(self)
    local s = getSettings() -- Get current settings

    -- 1. Guard Clauses and Setup
    if not s.enable_overlay then
        return
    end
    if not self:modeIsImage() then
        return
    end
    if self._sleep_overlay_applied then
        return
    end

    local base_bb = ensureBaseImage(self)
    if not base_bb then
        return
    end

    local overlay_path = pickOverlayPath()
    if not overlay_path then
        return
    end

    local overlay_bb = RenderImage:renderImageFile(overlay_path, false, nil, nil)
    if not overlay_bb then
        logger.dbg("SleepOverlay: failed to render overlay", overlay_path)
        return
    end

    -- 2. Get Dimensions
    local base_w, base_h = base_bb:getWidth(), base_bb:getHeight()
    local resize_mode = s.overlay_resize_mode or defaults.overlay_resize_mode
    resize_mode = type(resize_mode) == "string" and resize_mode:lower() or "fit"

    -- 3. (REFACTORED) Resize Overlay
    overlay_bb = _resizeOverlay(overlay_bb, base_w, base_h, resize_mode)
    local overlay_w, overlay_h = overlay_bb:getWidth(), overlay_bb:getHeight()

    -- 4. (REFACTORED) Get Blit Coordinates
    local dest_x, dest_y, src_x, src_y, width, height = _getBlitCoords(base_w, base_h, overlay_w, overlay_h)

    if width <= 0 or height <= 0 then
        if overlay_bb.free then
            overlay_bb:free()
        end
        return
    end

    -- 5. Buffer Type Conversion
    -- This block ensures that the base and overlay buffers are compatible
    -- for blitting, converting one if necessary.
    local overlay_type = overlay_bb.getType and overlay_bb:getType()
    local base_type = base_bb.getType and base_bb:getType()
    local original_base_type = base_type

    if overlay_type == Blitbuffer.TYPE_BBRGB32 or overlay_type == Blitbuffer.TYPE_BB8A then
        if base_type ~= overlay_type then
            local old_base = base_bb
            local converted_base = Blitbuffer.new(base_w, base_h, overlay_type)
            converted_base:blitFrom(old_base, 0, 0, 0, 0, base_w, base_h)
            base_bb = converted_base
            self.image = base_bb
            self.image_file = nil
            base_type = overlay_type
            if old_base ~= base_bb and old_base.free then
                old_base:free()
            end
        end
    elseif base_type and overlay_type and overlay_type ~= base_type then
        local converted_overlay = Blitbuffer.new(overlay_w, overlay_h, base_type)
        converted_overlay:blitFrom(overlay_bb, 0, 0, 0, 0, overlay_w, overlay_h)
        if overlay_bb.free then
            overlay_bb:free()
        end
        overlay_bb = converted_overlay
        overlay_type = base_type
    end

    -- 6. Re-check dimensions after potential conversion
    base_w, base_h = base_bb:getWidth(), base_bb:getHeight()
    overlay_w, overlay_h = overlay_bb:getWidth(), overlay_bb:getHeight()
    width = math.min(width, base_w, overlay_w - src_x, base_w - dest_x)
    height = math.min(height, base_h, overlay_h - src_y, base_h - dest_y)

    if width <= 0 or height <= 0 then
        if overlay_bb.free then
            overlay_bb:free()
        end
        return
    end

    -- 7. Blit Overlay (Protected Call)
    local ok, err = pcall(function()
        if overlay_type == Blitbuffer.TYPE_BBRGB32 or overlay_type == Blitbuffer.TYPE_BB8A then
            base_bb:alphablitFrom(overlay_bb, dest_x, dest_y, src_x, src_y, width, height)
        else
            base_bb:blitFrom(overlay_bb, dest_x, dest_y, src_x, src_y, width, height)
        end
    end)
    if not ok then
        logger.err("SleepOverlay: blit failed", err)
    end

    -- 8. Flatten Alpha Channel (if needed)
    -- This prevents transparent areas from turning black on some devices.
    if FLATTEN_ALPHA_BACKGROUND then
        local final_type = base_bb.getType and base_bb:getType()
        if final_type == Blitbuffer.TYPE_BBRGB32 or final_type == Blitbuffer.TYPE_BB8A then
            local base_before_flatten = base_bb
            local flattened = Blitbuffer.new(base_w, base_h, final_type)
            flattened:fill(FLATTEN_ALPHA_COLOR)
            flattened:alphablitFrom(base_before_flatten, 0, 0, 0, 0, base_w, base_h)
            if base_before_flatten.free then
                base_before_flatten:free()
            end
            base_bb = flattened
            self.image = base_bb

            -- Convert back to original type if necessary
            if original_base_type and original_base_type ~= final_type then
                local converted_back = Blitbuffer.new(base_w, base_h, original_base_type)
                converted_back:blitFrom(base_bb, 0, 0, 0, 0, base_w, base_h)
                if base_bb.free then
                    base_bb:free()
                end
                base_bb = converted_back
                self.image = base_bb
            end
        end
    end

    -- 9. Cleanup
    if overlay_bb.free then
        overlay_bb:free()
    end
    self._sleep_overlay_applied = true
    logger.dbg("SleepOverlay: applied overlay", overlay_path)
end

------------------------------------------------------------
-- SCREENSAVER HOOKS
------------------------------------------------------------
local orig_show = Screensaver.show
function Screensaver:show(...)
    local ok, err = pcall(composeOverlay, self)
    if not ok then
        logger.err("SleepOverlay: compose failed", err)
    end
    return orig_show(self, ...)
end

local orig_cleanup = Screensaver.cleanup
function Screensaver:cleanup()
    self._sleep_overlay_applied = nil
    return orig_cleanup(self)
end
