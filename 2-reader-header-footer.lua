------------------------------------------------------------
-- Reader Header & Footer Patch (KOReader 2025.08+)
-- Author: Djeymisson Moraes (refined)
-- This patch is based on “2-reader-header-print-edition.lua” by Joshua Cant (https://github.com/joshuacant/KOReader.patches),
-- and incorporates modifications originally made by Isaac_729, adapted and enhanced for KOReader version 2025.08
-- with additional features (header/footer, margin handling, settings menu).
------------------------------------------------------------
------------------------------------------------------------
-- MODULES (REQUIRE)
------------------------------------------------------------
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Device = require("device")
local datetime = require("datetime")
local T = require("ffi/util").template
local _ = require("gettext")
local Geom = require("ui/geometry")
local ReaderView = require("apps/reader/modules/readerview")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local ReaderMenu = require("apps/reader/modules/readermenu")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local NetworkMgr = require("ui/network/manager")

------------------------------------------------------------
-- CONFIGURATION (SETTINGS)
------------------------------------------------------------
local SETTINGS_KEY = "reader_header_footer"
local defaults = {
    enabled = true,
    show_clock = true,
    show_battery = true,
    show_wifi = true,
    show_footer = true,
    color = "black",
    separator = "|",
    font_size = "normal",
    use_doc_margins = true,
    left_margin = 0,
    right_margin = 0,
    sync_margins = false
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
-- HELPER FUNCTIONS
------------------------------------------------------------

-- Resolves the color name to a Blitbuffer value
local function resolveColor(name)
    if name == "gray" then
        return Blitbuffer.COLOR_GRAY_6
    else
        return Blitbuffer.COLOR_BLACK
    end
end

-- Resolves the font size name to a numeric value
local function resolveFontSize(size_name)
    if size_name == "small" then
        return 12
    elseif size_name == "large" then
        return 16
    else
        return 14
    end
end

-- Creates a standardized TextWidget for the header/footer
local function createTextWidget(text, face_obj, is_bold, color)
    return TextWidget:new{
        text = BD.auto(text or ""),
        face = face_obj,
        bold = is_bold,
        fgcolor = color
    }
end

-- Creates a HorizontalGroup with margins and dynamic spacing
local function createPaddedRow(left_widget, right_widget, left_margin, right_margin, screen_w)
    local left_w = left_widget:getSize().w or 0
    local right_w = right_widget:getSize().w or 0

    local dynamic_space = screen_w - left_w - right_w - left_margin - right_margin
    if dynamic_space < 0 then
        -- Ensures the space is not negative, avoiding overlap
        dynamic_space = 0
    end

    return HorizontalGroup:new{HorizontalSpan:new{
        width = left_margin
    }, left_widget, HorizontalSpan:new{
        width = dynamic_space
    }, right_widget, HorizontalSpan:new{
        width = right_margin
    }}
end

-- Opens the margin configuration dialog
local function openMarginDialog(current_left, current_right, is_synced, onConfirm)
    if is_synced then
        local widget = SpinWidget:new{
            title_text = _("Custom margins (Synced)"),
            text = _("Margin"),
            value = tonumber(current_left) or 0,
            value_min = 0,
            value_max = 500,
            default_value = 0,
            keep_shown_on_apply = false,
            callback = function(spin)
                local margin_val = math.floor(spin.value)
                onConfirm(margin_val, margin_val)
            end,
            close_callback = function()
                -- called when the user manually closes the window
            end
        }
        UIManager:show(widget)
    else
        local widget = DoubleSpinWidget:new{
            title_text = _("Custom margins"),
            width_factor = 0.6,
            left_text = _("Left margin"),
            left_value = tonumber(current_left) or 0,
            left_min = 0,
            left_max = 500,
            left_default = 0,
            left_precision = "%01d",
            right_text = _("Right margin"),
            right_value = tonumber(current_right) or 0,
            right_min = 0,
            right_max = 500,
            right_default = 0,
            right_precision = "%01d",
            keep_shown_on_apply = false,
            callback = function(left_value, right_value)
                onConfirm(math.floor(left_value), math.floor(right_value))
            end,
            close_callback = function()
                -- called when the user manually closes the window
            end
        }
        UIManager:show(widget)
    end
end

------------------------------------------------------------
-- MENU INTEGRATION
------------------------------------------------------------

local function buildMenu(reader_ui)
    local s = getSettings()
    local submenu = {{
        text = _("Reader Header & Footer"),
        checked_func = function()
            return s.enabled
        end,
        callback = function()
            s.enabled = not s.enabled
            saveSettings(s)
        end,
        separator = true
    }, {
        text = _("Configure items"),
        enabled_func = function()
            return s.enabled
        end,
        sub_item_table = {{
            text = _("Show clock"),
            checked_func = function()
                return s.show_clock
            end,
            callback = function()
                s.show_clock = not s.show_clock
                saveSettings(s)
            end
        }, {
            text = _("Show battery"),
            checked_func = function()
                return s.show_battery
            end,
            callback = function()
                s.show_battery = not s.show_battery
                saveSettings(s)
            end
        }, {
            text = _("Show Wi-Fi"),
            checked_func = function()
                return s.show_wifi
            end,
            callback = function()
                s.show_wifi = not s.show_wifi
                saveSettings(s)
            end
        }, {
            text = _("Show footer"),
            checked_func = function()
                return s.show_footer
            end,
            callback = function()
                s.show_footer = not s.show_footer
                saveSettings(s)
            end
        }}
    }, {
        text = _("Custom margins"),
        enabled_func = function()
            return s.enabled
        end,
        sub_item_table = {{
            text = _("Use document margins"),
            checked_func = function()
                return s.use_doc_margins
            end,
            callback = function()
                s.use_doc_margins = not s.use_doc_margins
                saveSettings(s)
            end
        }, {
            text = _("Sync left and right margins"),
            checked_func = function()
                return s.sync_margins
            end,
            callback = function()
                s.sync_margins = not s.sync_margins

                if s.sync_margins then
                    if s.left_margin > s.right_margin then
                        s.right_margin = s.left_margin
                    else
                        s.left_margin = s.right_margin
                    end
                end

                saveSettings(s)
            end,
            enabled_func = function()
                return not s.use_doc_margins
            end
        }, {
            text_func = function()
                return T(_("Set custom margins (L: %1 px, R: %2 px)"), s.left_margin or 0, s.right_margin or 0)
            end,
            enabled_func = function()
                return not s.use_doc_margins
            end,
            callback = function()
                local confirm_callback = function(left, right)
                    s.left_margin = left
                    s.right_margin = right
                    saveSettings(s)

                    -- Forces a UI repaint to apply the margins
                    if UIManager and reader_ui and reader_ui.view then
                        UIManager:setDirty(reader_ui.view, "ui")
                        UIManager:forceRePaint()
                    elseif UIManager then
                        UIManager:forceRePaint()
                    else
                        print("Reader Header & Footer: CRITICAL ERROR - UIManager is 'nil'.")
                    end
                end
                openMarginDialog(s.left_margin, s.right_margin, s.sync_margins, confirm_callback)
            end
        }}
    }, {
        text = _("Font color"),
        enabled_func = function()
            return s.enabled
        end,
        sub_item_table = {{
            text = _("Black"),
            checked_func = function()
                return s.color == "black"
            end,
            callback = function()
                s.color = "black";
                saveSettings(s)
            end
        }, {
            text = _("Gray"),
            checked_func = function()
                return s.color == "gray"
            end,
            callback = function()
                s.color = "gray";
                saveSettings(s)
            end
        }}
    }, {
        text = _("Font size"),
        enabled_func = function()
            return s.enabled
        end,
        sub_item_table = {{
            text = _("Small"),
            checked_func = function()
                return s.font_size == "small"
            end,
            callback = function()
                s.font_size = "small";
                saveSettings(s)
            end
        }, {
            text = _("Normal"),
            checked_func = function()
                return s.font_size == "normal"
            end,
            callback = function()
                s.font_size = "normal";
                saveSettings(s)
            end
        }, {
            text = _("Large"),
            checked_func = function()
                return s.font_size == "large"
            end,
            callback = function()
                s.font_size = "large";
                saveSettings(s)
            end
        }}
    }, {
        text = _("Separator"),
        enabled_func = function()
            return s.enabled
        end,
        sub_item_table = {{
            text = "|",
            checked_func = function()
                return s.separator == "|"
            end,
            callback = function()
                s.separator = "|";
                saveSettings(s)
            end
        }, {
            text = "•",
            checked_func = function()
                return s.separator == "•"
            end,
            callback = function()
                s.separator = "•";
                saveSettings(s)
            end
        }, {
            text = "·",
            checked_func = function()
                return s.separator == "·"
            end,
            callback = function()
                s.separator = "·";
                saveSettings(s)
            end
        }, {
            text = "—",
            checked_func = function()
                return s.separator == "—"
            end,
            callback = function()
                s.separator = "—";
                saveSettings(s)
            end
        }}
    }}

    return {
        text_func = function()
            return _("Reader Header & Footer")
        end,
        sub_item_table = submenu
    }
end

-- Generic patch function
local function patch(menu, order)
    table.insert(order.setting, "----------------------------")
    table.insert(order.setting, "reader_header_footer")
    menu.menu_items.reader_header_footer = buildMenu(menu.ui)
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
-- DRAWING LOGIC (HEADER & FOOTER)
------------------------------------------------------------
local _orig_paint = ReaderView.paintTo
function ReaderView:paintTo(bb, x, y)
    -- 1. Draw the original page content
    _orig_paint(self, bb, x, y)

    -- 2. Guard clauses (to exit if not drawing)
    local s = getSettings()
    if not s.enabled then
        return
    end
    if self.render_mode ~= nil then
        -- Do not draw during scroll/pan/etc.
        return
    end

    -- 3. Variable initialization
    local fgcolor = resolveColor(s.color)
    local font_face_name = "ffont"
    local font_size = resolveFontSize(s.font_size)
    local bold = true
    local padding_top = Size.padding.large
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()

    -- Reusable font object
    local font_face_obj = Font:getFace(font_face_name, font_size)

    -- 4. Data collection
    local pageno = self.state.page or 1
    local book_title = self.ui.doc_props.display_title or ""
    local book_author = self.ui.doc_props.authors or ""
    if book_author:find("\n") then
        book_author = T(_("%1 et al."), require("util").splitToArray(book_author, "\n")[1] .. ",")
    end
    local book_chapter = self.ui.toc:getTocTitleByPage(pageno) or ""
    local pages_done = (self.ui.toc:getChapterPagesDone(pageno) or 0) + 1

    -- 5. Header Logic
    -- 5a. Header Left Side (Book Info)
    local left_text = ""
    if (pages_done > 1) and (pageno % 2 == 0) then
        -- Even page: Author and Title
        left_text = string.format("%s %s %s", book_author, s.separator, book_title)
    elseif (pages_done > 1) then
        -- Odd page: Chapter
        left_text = string.format("%s", book_chapter)
    end
    local left_widget = createTextWidget(left_text, font_face_obj, bold, fgcolor)

    -- 5b. Header Right Side (Status)
    local parts = {}
    if s.show_wifi then
        table.insert(parts, NetworkMgr:isWifiOn() and "" or "")
    end
    if s.show_clock then
        table.insert(parts, datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")))
    end
    if s.show_battery and Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local lvl = powerd:getCapacity() or 0
        local is_charging = powerd:isCharging() or false
        local symbol = powerd:getBatterySymbol(powerd:isCharged(), is_charging, lvl) or ""
        table.insert(parts, symbol .. lvl .. "%")
    end
    local right_text = table.concat(parts, " " .. s.separator .. " ")
    local right_widget = createTextWidget(right_text, font_face_obj, bold, fgcolor)

    -- 6. Margin Calculation
    local left_margin, right_margin = 0, 0
    if s.use_doc_margins and self.document and self.document.getPageMargins then
        local m = self.document:getPageMargins()
        left_margin = m.left or 0
        right_margin = m.right or 0
    else
        left_margin = s.left_margin or 0
        right_margin = s.right_margin or 0
    end

    -- 7. Header Drawing
    local header_h = math.max(left_widget:getSize().h, right_widget:getSize().h) + padding_top
    local header_row = createPaddedRow(left_widget, right_widget, left_margin, right_margin, screen_w)

    local header = CenterContainer:new{
        dimen = Geom:new{
            w = screen_w,
            h = header_h
        },
        VerticalGroup:new{VerticalSpan:new{
            height = padding_top
        }, header_row}
    }

    header:paintTo(bb, x, y)
    header:free() -- Frees the memory of the container and its children

    -- 8. Footer Drawing (if enabled)
    if s.show_footer then
        -- 8a. Footer Left Side (Pages remaining)
        local pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
        local pages_left_text = _("pages left in chapter")
        local footer_left_text = string.format("%d %s", pages_left, pages_left_text)
        local left_footer = createTextWidget(footer_left_text, font_face_obj, bold, fgcolor)

        -- 8b. Footer Right Side (Percentage)
        local pages = self.ui.doc_settings.data.doc_pages or 1
        local percentage = (pageno / pages) * 100
        local footer_right_text = string.format("%.f%%", percentage)
        local right_footer = createTextWidget(footer_right_text, font_face_obj, bold, fgcolor)

        -- 8c. Footer Layout and Drawing
        local footer_h = math.max(left_footer:getSize().h, right_footer:getSize().h)
        local footer_padding_bottom = 6 -- Bottom padding (original "magic number")
        local footer_y = screen_h - footer_h - footer_padding_bottom

        local footer_row = createPaddedRow(left_footer, right_footer, left_margin, right_margin, screen_w)

        local footer = CenterContainer:new{
            dimen = Geom:new{
                w = screen_w,
                h = footer_h
            },
            VerticalGroup:new{footer_row}
        }

        footer:paintTo(bb, x, footer_y)
        footer:free() -- Frees memory
    end
end
