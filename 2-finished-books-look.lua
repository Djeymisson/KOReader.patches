--[[
User patch for Cover Browser patch to customize the look of finished books.

This patch combines two effects for books in mosaic view with a "complete" status:
1. Fades the book cover to make it look less prominent.
2. Removes all default corner status icons (e.g., dog-ear, star).
3. Adds a single, centered "complete" icon on top of the faded cover.
]] --
-- ========================== Edit your preferences here ================================
-- Set your desired fading amount from 0.0 (no fade) to 1.0 (full white).
local FADING_AMOUNT = 0.5
-- ======================================================================================

-- ========================== Do not modify below this line =============================
local userpatch = require("userpatch")
local IconWidget = require("ui/widget/iconwidget")
local BD = require("ui/bidi")

local function patchMosaicStatus(plugin)
    local MosaicMenu = require("mosaicmenu")
    if not MosaicMenu then
        return
    end

    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        return
    end

    -- Attached flag to the table 'MosaicMenuItem', not the function 'paintTo'
    if MosaicMenuItem._is_patched_paintTo_by_finished_books_look then
        return -- Already patched, do nothing.
    end
    -- ==========================================

    -- We must also guard the IconWidget patching
    if IconWidget._is_patched_new_by_finished_books_look then
        return
    end
    -- =======================================

    -- This flag controls when this patch is creating an icon,
    -- to differentiate it from KOReader's original icon creation.
    local is_drawing_new_icon = false

    -- Store original IconWidget.new
    local originalIconWidgetNew = IconWidget.new

    --[[
    Override IconWidget:new
    This is the logic to remove the original corner icons.
    ]] --
    function IconWidget:new(o)
        -- 1. If our flag is true, it's our patch creating the
        --    centered icon. Allow it to proceed.
        if is_drawing_new_icon then
            return originalIconWidgetNew(self, o)
        end

        -- 2. This is a list of original corner icons we want to block.
        local corner_icons = {
            ["dogear.reading"] = true,
            ["dogear.abandoned"] = true,
            ["dogear.abandoned.rtl"] = true,
            ["dogear.complete"] = true,
            ["dogear.complete.rtl"] = true,
            ["star.white"] = true
        }

        -- 3. If it's an icon from the block list, return a "dummy"
        --    widget with an empty paintTo function. This prevents
        --    the icon from being drawn and avoids a crash.
        if o.icon and corner_icons[o.icon] then
            local dummy_icon = originalIconWidgetNew(self, o)
            dummy_icon.paintTo = function()
            end
            return dummy_icon
        end

        -- 4. For any other icon (like the cover itself), proceed normally.
        return originalIconWidgetNew(self, o)
    end
    -- Mark IconWidget table as patched
    IconWidget._is_patched_new_by_finished_books_look = true

    -- Store original MosaicMenuItem.paintTo
    local originalMosaicMenuItemPaintTo = MosaicMenuItem.paintTo

    --[[
    Override MosaicMenuItem:paintTo
    This is the logic to apply the fade and draw the new centered icon.
    ]] --
    function MosaicMenuItem:paintTo(bb, x, y)
        -- 1. Call original paintTo.
        -- Our IconWidget:new hook (above) will run during this call,
        -- stripping the default corner icons before they are drawn.
        originalMosaicMenuItemPaintTo(self, bb, x, y)

        -- 2. Apply fading effect AND draw custom icon for "complete" books
        if self.status == "complete" then
            -- === Apply Fading Effect ===
            local target = self.cover_image or self[1]
            if target and target.dimen then
                -- Calculate cover position and dimensions
                local fx = x + math.floor((self.width - target.dimen.w) / 2)
                local fy = y + math.floor((self.height - target.dimen.h) / 2)
                local fw, fh = target.dimen.w, target.dimen.h

                -- Apply the faded effect directly to the framebuffer (bb)
                bb:lightenRect(fx, fy, fw, fh, FADING_AMOUNT)
            end

            -- === Draw Custom Centered Icon ===
            if self.do_hint_opened and self.been_opened then
                -- Calculate icon size and centered position
                local icon_size = math.floor(math.min(self.width, self.height) / 4)
                local ix = math.floor(self.width - self.width / 16 - icon_size / 2)
                local iy = math.floor(self.height - self.height / 1.06 - icon_size / 2)

                -- Set flag to TRUE to allow our icon to be created
                is_drawing_new_icon = true
                local mark = IconWidget:new{
                    icon = BD.mirroredUILayout() and "dogear.complete.rtl" or "dogear.complete",
                    width = icon_size,
                    height = icon_size,
                    alpha = true -- Enable alpha blending
                }
                -- Set flag back to FALSE
                is_drawing_new_icon = false

                -- If the 'mark' (icon) was created, draw it.
                -- This is now INSIDE the 'if self.status == "complete"' block
                if mark then
                    mark:paintTo(bb, x + ix, y + iy)
                end
            end
        end
    end
    -- Mark MosaicMenuItem table as patched
    MosaicMenuItem._is_patched_paintTo_by_finished_books_look = true
end

userpatch.registerPatchPluginFunc("coverbrowser", patchMosaicStatus)
