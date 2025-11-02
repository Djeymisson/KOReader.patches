--[[
    Screensaver Patch
    Adds 5 new options to the "Sleep screen" menu:
    1. Close widgets before showing the screensaver
    2. Refresh before showing the screensaver
    3. Message do not overlap image
    4. Center image
    5. Invert message color when no fill

    This patch overrides the Screensaver.show() function and adds
    items to the Reader and File Manager menus.
]] -- Core/Device
local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local Font = require("ui/font")

-- UI/Widgets
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local InfoMessage = require("ui/widget/infomessage")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
local UIManager = require("ui/uimanager")

-- Libs/Utils
local ffiUtil = require("ffi/util")
local util = require("util")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

-- App Specific
local ReaderUI = require("apps/reader/readerui")
local RenderImage = require("ui/renderimage")
local DocumentRegistry = require("document/documentregistry")
local Screensaver = require("ui/screensaver")

-- Default values for the new patch menu entries
if G_reader_settings:hasNot("screensaver_close_widgets_when_no_fill") then
    G_reader_settings:saveSetting("screensaver_close_widgets_when_no_fill", false)
end
if G_reader_settings:hasNot("screensaver_center_image") then
    G_reader_settings:saveSetting("screensaver_center_image", false)
end
if G_reader_settings:hasNot("screensaver_overlap_message") then
    G_reader_settings:saveSetting("screensaver_overlap_message", true)
end
if G_reader_settings:hasNot("screensaver_refresh") then
    G_reader_settings:saveSetting("screensaver_refresh", true)
end
if G_reader_settings:hasNot("screensaver_invert_message_color") then
    G_reader_settings:saveSetting("screensaver_invert_message_color", false)
end

local userpatch = require("userpatch")
-- Get a reference to the local function 'addOverlayMessage' from the original Screensaver.show
local addOverlayMessage = userpatch.getUpValue(Screensaver.show, "addOverlayMessage")

-- Override the original Screensaver.show function
Screensaver.show = function(self)
    -- Original code: Notify Device methods that we're in screensaver mode
    Device.screen_saver_mode = true

    -- Original code: Check for gesture lock
    local with_gesture_lock = Device:isTouchDevice() and G_reader_settings:readSetting("screensaver_delay") == "gesture"

    -- Original code: If there's nothing to show, return
    if self.screensaver_type == "disable" and not self.show_message and not self.overlay_message and
        not with_gesture_lock then
        return
    end

    local rotation_mode = Screen:getRotationMode()

    -- Original code: Screen rotation logic for portrait mode
    if self:modeExpectsPortrait() then
        Device.orig_rotation_mode = rotation_mode
        if bit.band(Device.orig_rotation_mode, 1) == 1 then
            Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
        else
            Device.orig_rotation_mode = nil
        end

        -- Patch modification: Allow disabling the refresh
        if G_reader_settings:readSetting("screensaver_refresh") then
            if Device:hasEinkScreen() and self:modeIsImage() then
                if self:withBackground() then
                    Screen:clear()
                end
                Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

                if Device:isKobo() and Device:isSunxi() then
                    ffiUtil.usleep(150 * 1000)
                end
            end
        end
    else
        Device.orig_rotation_mode = nil
    end

    local covers_fullscreen = true
    local background
    -- Patch modification: Define text/background colors
    local fgcolor, bgcolor = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    if self.screensaver_background == "black" then
        background = Blitbuffer.COLOR_BLACK
        bgcolor = background -- text follows the color scheme
        fgcolor = Blitbuffer.COLOR_WHITE
    elseif self.screensaver_background == "white" then
        background = Blitbuffer.COLOR_WHITE
    elseif self.screensaver_background == "none" then
        background = nil
        -- Patch modification: Allow inverting message color
        if G_reader_settings:isTrue("screensaver_invert_message_color") then
            fgcolor, bgcolor = bgcolor, fgcolor
        end
    end

    -- Original code: Adjust for night mode
    if G_reader_settings:isTrue("night_mode") then
        fgcolor, bgcolor = bgcolor, fgcolor
    end

    local is_cover_or_image = self.screensaver_type == "cover" or self.screensaver_type == "random_image"
    local message_height
    local message_widget
    -- Patch modification: Define 'overlap_message' based on new settings
    local overlap_message = true
    local is_message_top = false
    if self.show_message then
        -- Original code: Logic to get the message text
        local screensaver_message = self.default_screensaver_message
        if G_reader_settings:has(self.prefix .. "screensaver_message") then
            screensaver_message = G_reader_settings:readSetting(self.prefix .. "screensaver_message")
        elseif G_reader_settings:has("screensaver_message") then
            screensaver_message = G_reader_settings:readSetting("screensaver_message")
        end
        if screensaver_message == self.default_screensaver_message then
            if self.event_message then
                screensaver_message = self.event_message
                self.overlay_message = nil
            end
        end

        -- Original code: Expand variables in the message string (e.g., %percentage)
        if screensaver_message:find("%%") then
            screensaver_message = self.ui.bookinfo:expandString(screensaver_message) or self.event_message or
                                      self.default_screensaver_message
        end

        -- Original code: Get message position
        if G_reader_settings:has(self.prefix .. "screensaver_message_vertical_position") then
            message_pos = G_reader_settings:readSetting(self.prefix .. "screensaver_message_vertical_position")
        else
            message_pos = G_reader_settings:readSetting("screensaver_message_vertical_position")
        end

        -- Patch modification: Message layout logic
        local face = Font:getFace("infofont")
        local screen_w = Screen:getWidth()
        local container
        local is_message_middle = message_pos == 50
        local is_message_top = message_pos == 100

        local textbox = TextBoxWidget:new{
            text = screensaver_message,
            face = face,
            width = is_message_middle and math.floor(screen_w * 2 / 3) or screen_w,
            alignment = "center",
            fgcolor = fgcolor,
            bgcolor = bgcolor
        }
        container = is_message_middle and CenterContainer or (is_message_top and TopContainer or BottomContainer)
        overlap_message = not is_cover_or_image or G_reader_settings:readSetting("screensaver_overlap_message")
        if is_message_middle then
            overlap_message = true -- Middle always overlaps
        end
        local height = overlap_message and Screen:getHeight() or textbox:getSize().h
        message_widget = container:new{
            dimen = Geom:new{
                w = screen_w,
                h = height
            },
            FrameContainer:new{
                dimen = Geom:new{
                    w = screen_w,
                    h = height
                },
                padding = is_message_middle and Size.padding.small or 0,
                color = is_message_middle and fgcolor or bgcolor,
                background = bgcolor,
                radius = is_message_middle and Size.radius.button or 0,
                bordersize = is_message_middle and Size.border.window or 0,
                textbox
            }
        }

        if is_message_top then
            message_height = message_widget[1]:getSize().h
        end
    end

    -- Build the main widget
    local widget = nil
    local center_image = false
    if is_cover_or_image then
        -- Patch modification: Logic to adjust image height if message does not overlap
        local image_height = Screen:getHeight()
        if not overlap_message then
            center_image = G_reader_settings:readSetting("screensaver_center_image")
            image_height = image_height - message_widget[1]:getSize().h * (center_image and 2 or 1)
        end

        -- Simplified scale factor logic (uses original 'stretch_images' only)
        local scale_factor_value = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil

        local widget_settings = {
            width = Screen:getWidth(),
            height = image_height,
            scale_factor = scale_factor_value,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage")
        }

        -- Simplified image loading logic
        if self.image_file then
            -- MODE A: Random Image or image-based book (CBZ)
            widget_settings.file = self.image_file
            widget_settings.file_do_cache = false
            widget_settings.alpha = true
        elseif self.image then
            -- MODE B: EPUB/PDF Cover (pre-rendered thumbnail)
            widget_settings.image = self.image
            widget_settings.image_disposable = true
        end

        -- Original code: Auto-Rotation Logic
        if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
            if widget_settings.file then
                -- Rotation for MODE A (file-based)
                local file_to_check = widget_settings.file
                local temp_image

                if self.screensaver_type == "cover" and self.ui.bookinfo and
                    not DocumentRegistry:isImageFile(file_to_check) then
                    temp_image = self.ui.bookinfo:getCoverImage(self.ui.document, file_to_check)
                elseif util.getFileNameSuffix(file_to_check) == "svg" then
                    temp_image = RenderImage:renderSVGImageFile(file_to_check, nil, nil, 1)
                elseif DocumentRegistry:isImageFile(file_to_check) then
                    temp_image = RenderImage:renderImageFile(file_to_check, false, nil, nil)
                end

                if temp_image then
                    local angle = rotation_mode == 3 and 180 or 0
                    if (temp_image:getWidth() < temp_image:getHeight()) ~=
                        (widget_settings.width < widget_settings.height) then
                        angle = angle +
                                    (G_reader_settings:isTrue("imageviewer_rotation_landscape_invert") and -90 or 90)
                    end
                    widget_settings.rotation_angle = angle
                    temp_image:free()
                end

            elseif widget_settings.image then
                -- Rotation for MODE B (image buffer/thumbnail-based)
                local temp_image = widget_settings.image
                local angle = rotation_mode == 3 and 180 or 0
                if (temp_image:getWidth() < temp_image.getHeight()) ~= (widget_settings.width < widget_settings.height) then
                    angle = angle + (G_reader_settings:isTrue("imageviewer_rotation_landscape_invert") and -90 or 90)
                end
                widget_settings.rotation_angle = angle
            end
        end

        widget = ImageWidget:new(widget_settings)
    elseif self.screensaver_type == "bookstatus" then
        widget = BookStatusWidget:new{
            ui = self.ui,
            readonly = true
        }
    elseif self.screensaver_type == "readingprogress" then
        widget = self.ui.statistics:onShowReaderProgress(true)
    end

    if self.show_message then
        if widget == nil and self.screensaver_background == "none" then
            covers_fullscreen = false
        end

        if message_widget then
            if widget then -- There is a screensaver widget (image/status)
                -- Assemble the layout (Vertical or Overlap)
                local group_settings
                local group_type

                if overlap_message then
                    group_type = OverlapGroup
                    group_settings = {widget, message_widget}
                else
                    group_type = VerticalGroup
                    if center_image then
                        local verticalspan = VerticalSpan:new{
                            width = message_widget[1]:getSize().h
                        }
                        if is_message_top then
                            group_settings = {message_widget, widget, verticalspan}
                        else
                            group_settings = {verticalspan, widget, message_widget}
                        end
                    else
                        if is_message_top then
                            group_settings = {message_widget, widget}
                        else
                            group_settings = {widget, message_widget}
                        end
                    end
                end
                group_settings.dimen = {
                    w = Screen:getWidth(),
                    h = Screen:getHeight()
                }
                widget = group_type:new(group_settings)
            else
                -- No previous widget, just show the message
                widget = message_widget
            end
        end
    end

    -- NOTE: Make sure InputContainer gestures are not disabled, to prevent stupid interactions with UIManager on close.
    UIManager:setIgnoreTouchInput(false)

    -- Logic to close widgets
    if self.screensaver_background == "none" and is_cover_or_image then
        if G_reader_settings:readSetting("screensaver_close_widgets_when_no_fill") then
            -- Clear highlights
            local readerui = ReaderUI.instance
            if readerui and readerui.highlight then
                readerui.highlight:clear(readerui.highlight:getClearId())
            end

            local added = {}
            local widgets = {}
            -- Iterate over widgets to close popups, etc.
            for widget in UIManager:topdown_widgets_iter() do
                if not added[widget] then
                    table.insert(widgets, widget)
                    added[widget] = true
                end
            end
            table.remove(widgets) -- Remove the main widget (FileManager or ReaderUI)
            if #widgets >= 1 then
                for _, widget in ipairs(widgets) do
                    UIManager:close(widget, "fast")
                end
                UIManager:forceRePaint()
            end
        end
    end

    -- Add overlay message (e.g., "shutting down")
    if self.overlay_message then
        widget = addOverlayMessage(widget, message_height, self.overlay_message)
    end

    -- Show the final screensaver widget
    if widget then
        self.screensaver_widget = ScreenSaverWidget:new{
            widget = widget,
            background = background,
            covers_fullscreen = covers_fullscreen
        }
        self.screensaver_widget.modal = true
        self.screensaver_widget.dithered = true

        UIManager:show(self.screensaver_widget, "full")
    end

    -- Show the gesture lock widget
    if with_gesture_lock then
        self.screensaver_lock_widget = ScreenSaverLockWidget:new{}
        UIManager:show(self.screensaver_lock_widget)
    end
end

-- Helper function to find menu items
local function find_item_from_path(menu, ...)
    local function find_sub_item(sub_items, text)
        for _, item in ipairs(sub_items) do
            local item_text = item.text or (item.text_func and item.text_func())
            if item_text and item_text == text then
                return item
            end
        end
    end

    local sub_items, item
    for _, text in ipairs {...} do
        sub_items = item and item.sub_item_table or menu
        if not sub_items then
            return
        end
        item = find_sub_item(sub_items, text)
        if not item then
            return
        end
    end
    return item
end

-- Add the new options to the "Sleep screen" submenu
local function add_options_in(menu)
    local items = menu.sub_item_table
    items[#items].separator = true
    table.insert(items, {
        text = _("Close widgets before showing the screensaver"),
        help_text = _("This option will only become available, if you have selected 'No fill'."),
        enabled_func = function()
            return G_reader_settings:readSetting("screensaver_img_background") == "none"
        end,
        checked_func = function()
            return G_reader_settings:isTrue("screensaver_close_widgets_when_no_fill")
        end,
        callback = function(touchmenu_instance)
            G_reader_settings:flipNilOrFalse("screensaver_close_widgets_when_no_fill")
            touchmenu_instance:updateItems()
        end
    })
    table.insert(items, {
        text = _("Refresh before showing the screensaver"),
        help_text = _("This option will only become available, if you have selected a cover or a random image."),
        enabled_func = function()
            local screensaver_type = G_reader_settings:readSetting("screensaver_type")
            return Device:hasEinkScreen() and (screensaver_type == "cover" or screensaver_type == "random_image")
        end,
        checked_func = function()
            return G_reader_settings:isTrue("screensaver_refresh")
        end,
        callback = function(touchmenu_instance)
            G_reader_settings:toggle("screensaver_refresh")
            touchmenu_instance:updateItems()
        end
    })
    items[#items].separator = true
    table.insert(items, {
        text = _("Message do not overlap image"),
        help_text = _(
            "This option will only become available, if you have selected a cover or a random image and you have a message and the message position is 'top' or 'bottom'."),
        enabled_func = function()
            local screensaver_type = G_reader_settings:readSetting("screensaver_type")
            local message_pos = G_reader_settings:readSetting("screensaver_message_vertical_position")
            return G_reader_settings:readSetting("screensaver_show_message") and
                       (screensaver_type == "cover" or screensaver_type == "random_image") and
                       (message_pos == 100 or message_pos == 0) -- 100=top, 0=bottom
        end,
        checked_func = function()
            return G_reader_settings:nilOrFalse("screensaver_overlap_message")
        end,
        callback = function(touchmenu_instance)
            G_reader_settings:toggle("screensaver_overlap_message")
            touchmenu_instance:updateItems()
        end
    })
    table.insert(items, {
        text = _("Center image"),
        help_text = _("This option will only become available, if you have selected 'Message do not overlap image'."),
        enabled_func = function()
            return G_reader_settings:nilOrFalse("screensaver_overlap_message")
        end,
        checked_func = function()
            return G_reader_settings:isTrue("screensaver_center_image")
        end,
        callback = function(touchmenu_instance)
            G_reader_settings:flipNilOrFalse("screensaver_center_image")
            touchmenu_instance:updateItems()
        end
    })
    table.insert(items, {
        text = _("Invert message color when no fill"),
        checked_func = function()
            return G_reader_settings:isTrue("screensaver_invert_message_color")
        end,
        callback = function(touchmenu_instance)
            G_reader_settings:flipNilOrFalse("screensaver_invert_message_color")
            touchmenu_instance:updateItems()
        end
    })
end

-- Hook function to inject the options into the menu
local function add_options_in_screensaver(order, menu, menu_name)
    local buttons = order["KOMenu:menu_buttons"]
    for i, button in ipairs(buttons) do
        if button == "setting" then
            local setting_menu = menu.tab_item_table[i]
            if setting_menu then
                local sub_menu = find_item_from_path(setting_menu, _("Screen"), _("Sleep screen"))
                if sub_menu then
                    add_options_in(sub_menu)
                    logger.info("Add screensaver options in", menu_name, "menu")
                end
            end
        end
    end
end

-- Hook for the File Manager Menu
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

FileManagerMenu.setUpdateItemTable = function(self)
    orig_FileManagerMenu_setUpdateItemTable(self)
    add_options_in_screensaver(FileManagerMenuOrder, self, "file manager")
end

-- Hook for the Reader Menu
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderMenuOrder = require("ui/elements/reader_menu_order")
local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable

ReaderMenu.setUpdateItemTable = function(self)
    orig_ReaderMenu_setUpdateItemTable(self)
    add_options_in_screensaver(ReaderMenuOrder, self, "reader")
end
