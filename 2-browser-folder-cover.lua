local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")

local _ = require("gettext")
local Screen = Device.screen

local logger = require("logger")

local FolderCover = {
    name = ".cover",
    exts = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
}

local function findCover(dir_path)
    local path = dir_path .. "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then
            return fname
        end
    end
end

local function getMenuItem(menu, ...) -- path
    local function findItem(sub_items, texts)
        local find = {}
        local texts = type(texts) == "table" and texts or {texts}
        -- stylua: ignore
        for _, text in ipairs(texts) do
            find[text] = true
        end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then
                return item
            end
        end
    end

    local sub_items, item
    for _, texts in ipairs {...} do -- walk path
        sub_items = (item or menu).sub_item_table
        if not sub_items then
            return
        end
        item = findItem(sub_items, texts)
        if not item then
            return
        end
    end
    return item
end

local function toKey(...)
    local keys = {}
    for _, key in pairs {...} do
        if type(key) == "table" then
            table.insert(keys, "table")
            for k, v in pairs(key) do
                table.insert(keys, tostring(k))
                table.insert(keys, tostring(v))
            end
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "")
end

local orig_FileChooser_getListItem = FileChooser.getListItem
local cached_list = {}

function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
    cached_list[key] = cached_list[key] or orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
    return cached_list[key]
end

-- local orig_FileChooser_genItemTableFromPath = FileChooser.genItemTableFromPath

-- function FileChooser:genItemTableFromPath(path)
--     local start = os.clock()
--     local item_table = orig_FileChooser_genItemTableFromPath(self, path)
--     logger.info("!!!!!!! GEN", path, (os.clock() - start) * 1000)
--     return item_table
-- end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local Folder = {
    edge = {
        thick = Screen:scaleBySize(2.5),
        margin = Size.line.medium,
        color = Blitbuffer.COLOR_GRAY_4,
        width = 0.97
    },
    face = {
        border_size = Size.border.thick,
        alpha = 0.75,
        nb_items_font_size = 20,
        nb_items_margin = Screen:scaleBySize(5),
        dir_max_font_size = 25
    }
}

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        return
    end -- Protect against remnants of project title
    -- Some KOReader/patch combinations wrap MosaicMenuItem.update before this
    -- patch is applied. In that case BookInfoManager may no longer be an
    -- upvalue of MosaicMenuItem.update, so fall back to the module directly.
    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
        or require("bookinfomanager")
    local original_update = MosaicMenuItem.update

    -- setting
    local function BooleanSetting(text, name, default)
        local setting_obj = {
            text = text
        }
        setting_obj.get = function()
            local setting = BookInfoManager:getSetting(name)
            if default then
                return not setting
            end -- false is stored as nil, so we need or own logic for boolean default
            return setting
        end
        setting_obj.toggle = function()
            return BookInfoManager:toggleSetting(name)
        end
        return setting_obj
    end

    local settings = {
        crop_to_fit = BooleanSetting(_("Crop folder custom image"), "folder_crop_custom_image", true),
        name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", true),
        show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", true)
    }

    -- cover item
    function MosaicMenuItem:update(...)
        original_update(self, ...)
        if self._foldercover_processed or not self.menu or self.menu.no_refresh_covers or not self.do_cover_image then
            return
        end

        if not self.entry or self.entry.is_file or self.entry.file or not self.mandatory then
            return
        end -- it's a file
        local dir_path = self.entry and self.entry.path
        if not dir_path then
            return
        end

        self._foldercover_processed = true

        local cover_file = findCover(dir_path) -- custom
        if cover_file then
            local success, w, h = pcall(function()
                local tmp_img = ImageWidget:new{
                    file = cover_file,
                    scale_factor = 1
                }
                tmp_img:_render()
                local orig_w = tmp_img:getOriginalWidth()
                local orig_h = tmp_img:getOriginalHeight()
                tmp_img:free()
                return orig_w, orig_h
            end)
            if success then
                self:_setFolderCover{
                    file = cover_file,
                    w = w,
                    h = h,
                    scale_to_fit = settings.crop_to_fit.get()
                }
                return
            end
        end

        self.menu._dummy = true
        local entries = self.menu:genItemTableFromPath(dir_path) -- sorted
        self.menu._dummy = false
        if not entries then
            return
        end

        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched and
                    not bookinfo.ignore_cover and
                    not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                    self:_setFolderCover{
                        data = bookinfo.cover_bb,
                        w = bookinfo.cover_w,
                        h = bookinfo.cover_h
                    }
                    break
                end
            end
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        local top_h = 2 * (Folder.edge.thick + Folder.edge.margin)
        local target = {
            w = self.width - 2 * Folder.face.border_size,
            h = self.height - 2 * Folder.face.border_size - top_h
        }

        local img_options = {
            file = img.file,
            image = img.data
        }
        if img.scale_to_fit then
            img_options.scale_factor = math.max(target.w / img.w, target.h / img.h)
            img_options.width = target.w
            img_options.height = target.h
        else
            img_options.scale_factor = math.min(target.w / img.w, target.h / img.h)
        end

        local image = ImageWidget:new(img_options)
        local size = image:getSize()
        local dimen = {
            w = size.w + 2 * Folder.face.border_size,
            h = size.h + 2 * Folder.face.border_size
        }

        local image_widget = FrameContainer:new{
            padding = 0,
            bordersize = Folder.face.border_size,
            image,
            overlap_align = "center"
        }

        local directory, nbitems = self:_getTextBoxes{
            w = size.w,
            h = size.h
        }
        local size = nbitems:getSize()
        local nb_size = math.max(size.w, size.h)

        local folder_name_widget
        if settings.show_folder_name.get() then
            folder_name_widget = (settings.name_centered.get() and CenterContainer or TopContainer):new{
                dimen = dimen,
                FrameContainer:new{
                    padding = 0,
                    bordersize = Folder.face.border_size,
                    AlphaContainer:new{
                        alpha = Folder.face.alpha,
                        directory
                    }
                },
                overlap_align = "center"
            }
        else
            folder_name_widget = VerticalSpan:new{
                width = 0
            }
        end

        local nbitems_widget

        local widget = CenterContainer:new{
            dimen = {
                w = self.width,
                h = self.height
            },
            VerticalGroup:new{VerticalSpan:new{
                width = math.max(0, math.ceil((self.height - (top_h + dimen.h)) * 0.5))
            }, LineWidget:new{
                background = Folder.edge.color,
                dimen = {
                    w = math.floor(dimen.w * (Folder.edge.width ^ 2)),
                    h = Folder.edge.thick
                }
            }, VerticalSpan:new{
                width = Folder.edge.margin
            }, LineWidget:new{
                background = Folder.edge.color,
                dimen = {
                    w = math.floor(dimen.w * Folder.edge.width),
                    h = Folder.edge.thick
                }
            }, VerticalSpan:new{
                width = Folder.edge.margin
            }, OverlapGroup:new{
                dimen = {
                    w = self.width,
                    h = self.height - top_h
                },
                image_widget,
                folder_name_widget,
                nbitems_widget
            }}
        }
        if self._underline_container[1] then
            local previous_widget = self._underline_container[1]
            previous_widget:free()
        end

        self._underline_container[1] = widget
    end

    function MosaicMenuItem:_getTextBoxes(dimen)
        local nbitems = TextWidget:new{
            text = self.mandatory:match("(%d+) \u{F016}") or "", -- nb books
            face = Font:getFace("cfont", Folder.face.nb_items_font_size),
            bold = true,
            padding = 0
        }

        local text = self.text
        if text:match("/$") then
            text = text:sub(1, -2)
        end -- remove "/"
        text = BD.directory(capitalize(text))
        local available_height = dimen.h - 2 * nbitems:getSize().h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then
                directory:free(true)
            end
            directory = TextBoxWidget:new{
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true
            }
            if directory:getSize().h <= available_height then
                break
            end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then -- don't go too low
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end

        return directory, nbitems
    end

    -- menu
    local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu

    function plugin:addToMainMenu(menu_items)
        orig_CoverBrowser_addToMainMenu(self, menu_items)
        if menu_items.filebrowser_settings == nil then
            return
        end

        local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
        if item then
            item.sub_item_table[#item.sub_item_table].separator = true
            for i, setting in pairs(settings) do
                if not getMenuItem( -- already exists ?
                menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), setting.text) then
                    table.insert(item.sub_item_table, {
                        text = setting.text,
                        checked_func = function()
                            return setting.get()
                        end,
                        callback = function()
                            setting.toggle()
                            self.ui.file_chooser:updateItems()
                        end
                    })
                end
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
