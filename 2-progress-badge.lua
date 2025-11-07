--[[
User patch for Cover Browser plugin to add progress percentage badges in top right corner
]] --
-- ========================== [[ User Preferences ]] ==================================
-- Adjust font size (0 to 1) relative to corner mark
local text_size = 0.6
-- Adjust how far left the badge should sit (from the right edge)
local move_on_x = 6
-- Adjust how far down the badge should sit (from the top edge)
local move_on_y = 8
-- Adjust badge width
local badge_w = 55
-- Adjust badge height
local badge_h = 30
-- Fine-tune text position (horizontal offset)
local text_offset_x = 21
-- Fine-tune text position (vertical offset)
local text_offset_y = 12
-- ==========================================================================================

local userpatch = require("userpatch")
local logger = require("logger")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Screen = require("device").screen
local Size = require("ui/size")
local Blitbuffer = require("ffi/blitbuffer")
local BD = require("ui/bidi")
local IconWidget = require("ui/widget/iconwidget")

-- Pre-calculate scaled dimensions (improves performance by calculating once)
local BADGE_W = Screen:scaleBySize(badge_w)
local BADGE_H = Screen:scaleBySize(badge_h)
local INSET_X = Screen:scaleBySize(move_on_x)
local INSET_Y = Screen:scaleBySize(move_on_y)
local TEXT_PAD = Screen:scaleBySize(6) -- Internal padding for text

-- Instantiate SHARED widgets once (improves performance)
-- 1. The SVG badge icon (for progress)
local percent_badge = IconWidget:new{
    icon = "percent.badge",
    alpha = true,
    width = BADGE_W + 15, -- Set width once
    height = BADGE_H + 25 -- Set height once
}

-- 2. The "completed" icon
local completed_icon = IconWidget:new{
    icon = "percent.badge.done", -- KOReader's built-in checkmark icon
    alpha = true,
    width = BADGE_W + 15, -- Use same dimensions for consistency
    height = BADGE_H + 25 -- Use same dimensions for consistency
}

-- The TextWidget CANNOT be shared. It will be created and cached
-- on the item itself (self) inside the paintTo function.

local function patchCoverBrowserProgressPercent(plugin)
    -- Grab Cover Grid mode and the individual Cover Grid items
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")

    -- Store original MosaicMenuItem paintTo method
    local origMosaicMenuItemPaintTo = MosaicMenuItem.paintTo

    -- Override paintTo method to add progress percentage badges
    function MosaicMenuItem:paintTo(bb, x, y)
        -- Call the original paintTo method to draw the cover normally
        origMosaicMenuItemPaintTo(self, bb, x, y)

        -- Get the cover image widget
        local target = self[1][1][1]
        if not target or not target.dimen then
            return -- Not a valid item to patch
        end

        -- Check if item is a book and has been opened (main check)
        if self.do_hint_opened and self.been_opened and not self.is_directory then

            -- Calculate common positions first
            local fx = x + math.floor((self.width - target.dimen.w) / 2)
            local fy = y + math.floor((self.height - target.dimen.h) / 2)
            local fw = target.dimen.w

            -- Badge position (relative to the frame)
            local bx = fx + fw - BADGE_W - INSET_X
            local by = fy + INSET_Y
            bx, by = math.floor(bx), math.floor(by)

            -- Now, decide WHAT to draw based on status
            if self.status == "complete" then
                -- CASE 1: Book is COMPLETE
                -- Paint the "completed" icon
                completed_icon:paintTo(bb, bx, by)

            elseif self.percent_finished and self.status ~= "complete" then
                -- CASE 2: Book is IN PROGRESS
                -- Use the same corner_mark_size as the original code
                local corner_mark_size = Screen:scaleBySize(20)

                -- 1. Update or Create the TextWidget
                local percent_text = string.format("%d%%", math.floor(self.percent_finished * 100))
                local font_size = math.floor(corner_mark_size * text_size)

                if not self.percent_widget then
                    self.percent_widget = TextWidget:new{
                        text = percent_text,
                        font_size = font_size,
                        face = Font:getFace("cfont", font_size),
                        alignment = "center",
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        bold = true,
                        truncate_with_ellipsis = false,
                        max_width = BADGE_W - 2 * TEXT_PAD
                    }
                else
                    self.percent_widget.text = percent_text
                    self.percent_widget.font_size = font_size
                    self.percent_widget.face = Font:getFace("cfont", font_size)
                end

                -- 2. Paint the SHARED SVG badge
                percent_badge:paintTo(bb, bx, by)

                -- 3. Calculate text position
                local ts = self.percent_widget:getSize()
                local tx = bx + math.floor((BADGE_W - ts.w) / 2) + text_offset_x
                local ty = by + math.floor((BADGE_H - ts.h) / 2) + text_offset_y

                -- 4. Paint the item's specific text
                self.percent_widget:paintTo(bb, math.floor(tx), math.floor(ty))
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowserProgressPercent)
