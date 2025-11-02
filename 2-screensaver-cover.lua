-- Add 4 new options @ the end of the "Sleep screen" menu :
-- Close widgets before showing the screensaver
-- Refresh before showing the screensaver
-- Message do not overlap image
-- Center image
-- By default it doesn't change the sleep screen behavior
local Blitbuffer = require("ffi/blitbuffer")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderUI = require("apps/reader/readerui")
local RenderImage = require("ui/renderimage")
local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local Screensaver = require("ui/screensaver")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffiUtil = require("ffi/util")
local util = require("util")
local Screen = Device.screen
local _ = require("gettext")

local logger = require("logger")

-- default value, for new menu entries
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
local addOverlayMessage = userpatch.getUpValue(Screensaver.show, "addOverlayMessage")

Screensaver.show = function(self)
    -- Notify Device methods that we're in screen saver mode, so they know whether to suspend or resume on Power events.
    Device.screen_saver_mode = true

    -- Check if we requested a lock gesture
    local with_gesture_lock = Device:isTouchDevice() and G_reader_settings:readSetting("screensaver_delay") == "gesture"

    -- in as-is mode with no message, no overlay and no lock, we've got nothing to show :)
    if self.screensaver_type == "disable" and not self.show_message and not self.overlay_message and
        not with_gesture_lock then
        return
    end

    local rotation_mode = Screen:getRotationMode()

    -- We mostly always suspend in Portrait/Inverted Portrait mode...
    -- ... except when we just show an InfoMessage or when the screensaver
    -- is disabled, as it plays badly with Landscape mode (c.f., #4098 and #5920).
    -- We also exclude full-screen widgets that work fine in Landscape mode,
    -- like ReadingProgress and BookStatus (c.f., #5724)
    if self:modeExpectsPortrait() then
        Device.orig_rotation_mode = rotation_mode
        -- Leave Portrait & Inverted Portrait alone, that works just fine.
        if bit.band(Device.orig_rotation_mode, 1) == 1 then
            -- i.e., only switch to Portrait if we're currently in *any* Landscape orientation (odd number)
            Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
        else
            Device.orig_rotation_mode = nil
        end

        -- On eInk, if we're using a screensaver mode that shows an image,
        -- flash the screen to white first, to eliminate ghosting.
        if G_reader_settings:readSetting("screensaver_refresh") then
            if Device:hasEinkScreen() and self:modeIsImage() then
                if self:withBackground() then
                    Screen:clear()
                end
                Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

                -- On Kobo, on sunxi SoCs with a recent kernel, wait a tiny bit more to avoid weird refresh glitches...
                if Device:isKobo() and Device:isSunxi() then
                    ffiUtil.usleep(150 * 1000)
                end
            end
        end
    else
        -- nil it, in case user switched ScreenSaver modes during our lifetime.
        Device.orig_rotation_mode = nil
    end

    -- Assume that we'll be covering the full-screen by default (either because of a widget, or a background fill).
    local covers_fullscreen = true
    -- Speaking of, set that background fill up...
    local background
    local fgcolor, bgcolor = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    if self.screensaver_background == "black" then
        background = Blitbuffer.COLOR_BLACK
        bgcolor = background -- text follow the same color scheme
        fgcolor = Blitbuffer.COLOR_WHITE
    elseif self.screensaver_background == "white" then
        background = Blitbuffer.COLOR_WHITE
    elseif self.screensaver_background == "none" then
        background = nil
        if G_reader_settings:isTrue("screensaver_invert_message_color") then
            fgcolor, bgcolor = bgcolor, fgcolor
        end
    end

    if G_reader_settings:isTrue("night_mode") then
        fgcolor, bgcolor = bgcolor, fgcolor
    end

    local is_cover_or_image = self.screensaver_type == "cover" or self.screensaver_type == "random_image"
    local message_height
    local message_widget
    local overlap_message = true
    local is_message_top = false
    if self.show_message then
        -- Handle user settings & fallbacks, with that prefix mess on top...
        local screensaver_message = self.default_screensaver_message
        if G_reader_settings:has(self.prefix .. "screensaver_message") then
            screensaver_message = G_reader_settings:readSetting(self.prefix .. "screensaver_message")
        elseif G_reader_settings:has("screensaver_message") then
            screensaver_message = G_reader_settings:readSetting("screensaver_message")
        end
        -- If the message is set to the defaults (which is also the case when it's unset), prefer the event message if there is one.
        if screensaver_message == self.default_screensaver_message then
            if self.event_message then
                screensaver_message = self.event_message
                -- The overlay is only ever populated with the event message, and we only want to show it once ;).
                self.overlay_message = nil
            end
        end

        -- NOTE: Only attempt to expand if there are special characters in the message.
        if screensaver_message:find("%%") then
            screensaver_message = self.ui.bookinfo:expandString(screensaver_message) or self.event_message or
                                      self.default_screensaver_message
        end

        if G_reader_settings:has(self.prefix .. "screensaver_message_position") then
            message_pos = G_reader_settings:readSetting(self.prefix .. "screensaver_message_position")
        else
            message_pos = G_reader_settings:readSetting("screensaver_message_position")
        end

        local face = Font:getFace("infofont")
        local screen_w = Screen:getWidth()
        local container
        local is_message_middle = message_pos == "middle"
        local textbox = TextBoxWidget:new{ -- might need its height
            text = screensaver_message,
            face = face,
            width = is_message_middle and math.floor(screen_w * 2 / 3) or screen_w,
            alignment = "center",
            fgcolor = fgcolor,
            bgcolor = bgcolor
        }
        is_message_top = message_pos == "top"
        container = is_message_middle and CenterContainer or (is_message_top and TopContainer or BottomContainer)
        overlap_message = not is_cover_or_image or G_reader_settings:readSetting("screensaver_overlap_message")
        if is_message_middle then
            overlap_message = true
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

        -- Forward the height of the top message to the overlay widget
        if is_message_top then
            message_height = message_widget[1]:getSize().h
        end
        -- end
    end

    -- Build the main widget for the effective mode, all the sanity checks were handled in setup
    local widget = nil
    local center_image = false
    if is_cover_or_image then
        local image_height = Screen:getHeight()
        if not overlap_message then
            center_image = G_reader_settings:readSetting("screensaver_center_image")
            image_height = image_height - message_widget[1]:getSize().h * (center_image and 2 or 1)
        end

        local widget_settings = {
            width = Screen:getWidth(),
            height = image_height,
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage")
        }
        if self.image then
            widget_settings.image = self.image
            widget_settings.image_disposable = true
        elseif self.image_file then
            if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
                -- We need to load the image here to determine whether to rotate
                if util.getFileNameSuffix(self.image_file) == "svg" then
                    widget_settings.image = RenderImage:renderSVGImageFile(self.image_file, nil, nil, 1)
                else
                    widget_settings.image = RenderImage:renderImageFile(self.image_file, false, nil, nil)
                end
                if not widget_settings.image then
                    widget_settings.image = RenderImage:renderCheckerboard(Screen:getWidth(), Screen:getHeight(),
                        Screen.bb:getType())
                end
                widget_settings.image_disposable = true
            else
                widget_settings.file = self.image_file
                widget_settings.file_do_cache = false
            end
            widget_settings.alpha = true
        end -- set cover or file
        if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
            local angle = rotation_mode == 3 and 180 or 0 -- match mode if possible
            if (widget_settings.image:getWidth() < widget_settings.image:getHeight()) ~=
                (widget_settings.width < widget_settings.height) then
                angle = angle + (G_reader_settings:isTrue("imageviewer_rotation_landscape_invert") and -90 or 90)
            end
            widget_settings.rotation_angle = angle
        end
        widget = ImageWidget:new(widget_settings)
    elseif self.screensaver_type == "bookstatus" then
        local ReaderUI = require("apps/reader/readerui")
        widget = BookStatusWidget:new{
            ui = ReaderUI.instance,
            readonly = true
        }
    elseif self.screensaver_type == "readingprogress" then
        widget = Screensaver.getReaderProgress()
    end

    if self.show_message then
        -- The only case where we *won't* cover the full-screen is when we only display a message and no background.
        if widget == nil and self.screensaver_background == "none" then
            covers_fullscreen = false
        end
        -- Check if message_widget should be overlaid on another widget
        if message_widget then
            if widget then -- We have a Screensaver widget
                -- Show message_widget depending on overlap_message and center_image
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
                -- No previously created widget, so just show message widget
                widget = message_widget
            end
        end
    end

    -- NOTE: Make sure InputContainer gestures are not disabled, to prevent stupid interactions with UIManager on close.
    UIManager:setIgnoreTouchInput(false)

    if self.screensaver_background == "none" and is_cover_or_image then -- is the background kept ?
        if G_reader_settings:readSetting("screensaver_close_widgets_when_no_fill") then -- !!!!!!!!!
            -- clear highlight
            local readerui = ReaderUI.instance
            if readerui and readerui.highlight then
                readerui.highlight:clear(readerui.highlight:getClearId())
            end

            local added = {}
            local widgets = {}
            for widget in UIManager:topdown_widgets_iter() do -- populate bottom up with unique widgets (eg. keyboard appears several times)
                if not added[widget] then -- already added ?
                    table.insert(widgets, widget)
                    added[widget] = true
                end
            end
            table.remove(widgets) -- remove the main widget @ the end of the stack, we don't want to close it
            if #widgets >= 1 then -- close all the remaining ones and repaint
                for _, widget in ipairs(widgets) do
                    UIManager:close(widget, "fast")
                end
                UIManager:forceRePaint()
            end
        end
    end

    if self.overlay_message then
        widget = addOverlayMessage(widget, message_height, self.overlay_message)
    end

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

    -- Setup the gesture lock through an additional invisible widget, so that it works regardless of the configuration.
    if with_gesture_lock then
        self.screensaver_lock_widget = ScreenSaverLockWidget:new{}

        -- It's flagged as modal, so it'll stay on top
        UIManager:show(self.screensaver_lock_widget)
    end
end

local function find_item_from_path(menu, ...)
    local function find_sub_item(sub_items, text)
        -- logger.info("search item", text)
        for _, item in ipairs(sub_items) do
            local item_text = item.text or (item.text_func and item.text_func())
            if item_text and item_text == text then
                -- logger.info("Found item", item_text)
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
            local message_pos = G_reader_settings:readSetting("screensaver_message_position")
            return G_reader_settings:readSetting("screensaver_show_message") and
                       (screensaver_type == "cover" or screensaver_type == "random_image") and
                       (message_pos == "top" or message_pos == "bottom")
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
        -- help_text = _("When the This option will only become available, if you have selected 'Message do not overlap image'."),
        checked_func = function()
            return G_reader_settings:isTrue("screensaver_invert_message_color")
        end,
        callback = function(touchmenu_instance)
            G_reader_settings:flipNilOrFalse("screensaver_invert_message_color")
            touchmenu_instance:updateItems()
        end
    })
end

local function add_options_in_screensaver(order, menu, menu_name)
    local buttons = order["KOMenu:menu_buttons"]
    for i, button in ipairs(buttons) do
        if button == "setting" then
            local setting_menu = menu.tab_item_table[i]
            -- logger.info(i, setting_menu)
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

local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

FileManagerMenu.setUpdateItemTable = function(self)
    orig_FileManagerMenu_setUpdateItemTable(self)
    add_options_in_screensaver(FileManagerMenuOrder, self, "file manager")
end

local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderMenuOrder = require("ui/elements/reader_menu_order")
local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable

ReaderMenu.setUpdateItemTable = function(self)
    orig_ReaderMenu_setUpdateItemTable(self)
    add_options_in_screensaver(ReaderMenuOrder, self, "reader")
end
