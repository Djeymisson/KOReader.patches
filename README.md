# KOReader Custom Patches

This repository contains **modified patches** for [KOReader](https://github.com/koreader/koreader) that I have adapted and tested for my personal use.

> **Disclaimer:** These patches are not my original creations. They are **modifications based on the work of other developers**, to whom I give full credit. I have adapted them to fit my specific needs.


## Purpose of These Modifications

The goal of these modifications is to:

* Customize the behavior and appearance of certain KOReader features.
* Fix minor bugs I encountered in the original patch versions.
* Adapt functionality for my specific devices.
* Integrate ideas and features from different versions shared by other users.


## Installation

1. Copy the desired `.lua` files to your KOReader patches directory:

   ```text
   koreader/patches/
   ```

2. Copy the custom icons, when used, to KOReader's icon directory:

   ```text
   koreader/resources/icons/
   ```

3. Restart KOReader.

You do not need to install every patch. Each file can be copied independently, although some of them are designed to work with KOReader's Cover Browser plugin.

## Repository layout

```text
.
├── patches/
│   ├── 2-bookloadcover-plus.lua
│   ├── 2-browser-folder-cover.lua
│   ├── 2-finished-books-look.lua
│   ├── 2-progress-badge.lua
│   ├── 2-reader-header-footer.lua
│   ├── 2-screensaver-cover.lua
│   └── 2-sleep-overlay.lua
└── icons/
    ├── dogear.complete
    ├── percent.badge
    └── percent.badge.done
```

## Patches

| Patch | Summary | Main area | Base / Credit |
|---|---|---|---|
| [2-bookloadcover-plus.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-bookloadcover-plus.lua) | Replaces the opening and closing transitions with the current book cover. It can be disabled globally, configured separately for opening and closing, and set to prioritize either speed or cover quality. | Reader loading and closing | Based on the original patch by [Oleh Tiuriakov](https://github.com/reuerendo/koreader-patches). |
| [2-browser-folder-cover.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-browser-folder-cover.lua) | Corrected version of the folder cover patch for Cover Browser mosaic view. It keeps folder covers based on `.cover` images or book covers while applying compatibility/safety fixes. | File browser / Cover Browser | Original patch by [sebdelsol](https://github.com/sebdelsol/KOReader.patches); this repository includes a corrected version. |
| [2-finished-books-look.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-finished-books-look.lua) | Changes the appearance of completed books in mosaic view by fading the cover and showing a centered completion mark. | Cover Browser | Based on some patches by [SeriousHornet](https://github.com/SeriousHornet/KOReader.patches.git). |
| [2-progress-badge.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-progress-badge.lua) | Adds a progress badge to book covers in mosaic view. In-progress books show a percentage; completed books show a done badge. | Cover Browser | Based on some patches by [SeriousHornet](https://github.com/SeriousHornet/KOReader.patches.git). |
| [2-screensaver-cover.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-screensaver-cover.lua) | Extends the sleep screen behavior with extra options for widget closing, screen refresh, message placement, image centering, and message color. | Sleep screen | Based on the original patch by [sebdelsol](https://github.com/sebdelsol/KOReader.patches.git). |
| [2-sleep-overlay.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-sleep-overlay.lua) | Applies random or sequential transparent PNG overlays on top of the sleep cover. Useful for decorative frames, textures, stamps, or themed sleep screens. | Sleep screen | Based on the original patch by [omer-faruq](https://github.com/omer-faruq/koreader-user-patches.git). |

## Icons

The `icons/` folder contains custom icon assets used by some of the patches:

| Icon | Used by | Purpose |
|---|---|---|
| `dogear.complete` | `2-finished-books-look.lua` | Centered completion mark for finished books. |
| `percent.badge` | `2-progress-badge.lua` | Background badge for in-progress reading percentage. |
| `percent.badge.done` | `2-progress-badge.lua` | Badge for completed books. |

If these icons are not available in your KOReader installation, the related visual patches may fail to draw the custom marks correctly.

## Patch details

### [2-bookloadcover-plus.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-bookloadcover-plus.lua)

Shows the current book cover during opening and closing transitions. Use the menu to choose whether each transition is disabled, shows the cover together with KOReader's default widgets, or shows only the cover.

It also includes a **Cover source** option:

- **Balanced (faster):** tries cached or already available cover sources first, which is usually faster.
- **Best quality:** prioritizes extracting the cover directly from the document when possible, which may look better but can be slower when opening a book.

### [2-browser-folder-cover.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-browser-folder-cover.lua)

Corrected version of the original folder cover patch for Cover Browser mosaic mode. It keeps the same goal: folders can be displayed with a cover-style look, using either a custom `.cover` image or a book cover from inside the folder.

Supported custom folder cover names:

```text
.cover.jpg
.cover.jpeg
.cover.png
.cover.webp
.cover.gif
```

This version is not a separate feature patch. It is an adjusted version of the original patch with compatibility and safety fixes for some KOReader/Cover Browser combinations, including safer handling of missing menu/item data and a fallback when the Cover Browser book info manager is not available as an expected internal reference. The patch also adds menu options for cropping the folder image, centering the folder name, and showing or hiding the folder name.

### [2-finished-books-look.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-finished-books-look.lua)

Changes how completed books are displayed in mosaic mode. Instead of relying on the default corner status icons, completed books are visually faded and marked with a larger centered completion icon.

The fade intensity can be adjusted inside the patch file.

### [2-progress-badge.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-progress-badge.lua)

Adds a compact visual progress indicator to covers in mosaic mode. Books currently being read show a percentage badge, while completed books use a dedicated completion badge.

The patch includes editable layout preferences near the top of the file, such as badge size, position, and text placement.

### [2-screensaver-cover.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-screensaver-cover.lua)

Adds extra controls to KOReader's sleep screen menu. The patch is focused on improving how covers, images, and messages are displayed when the device enters sleep mode.

Added options include:

- close widgets before showing the screensaver;
- refresh before showing the screensaver;
- prevent the message from overlapping the image;
- center the image;
- invert message color when using no fill.

### [2-sleep-overlay.lua](https://github.com/Djeymisson/KOReader.patches/blob/main/2-sleep-overlay.lua)

Composes a transparent PNG overlay over the current sleep cover. Place overlay images in:

```text
sleepoverlays/
```

The patch includes menu options for enabling/disabling overlays, selecting active overlays, choosing the scaling mode, and choosing random or sequential rotation.

Supported scaling modes:

- fit;
- fill;
- center;
- stretch.

## Compatibility notes

These patches modify KOReader internals and may need adjustments after KOReader updates. If something breaks after updating KOReader, temporarily remove the most recently edited patch from `koreader/patches/` and restart the app.

Some patches depend on Cover Browser mosaic behavior. If you do not use Cover Browser, the following patches may have no visible effect:

- `2-browser-folder-cover.lua`;
- `2-finished-books-look.lua`;
- `2-progress-badge.lua`.

## Troubleshooting

### KOReader does not start after adding a patch

Remove the last patch you copied to `koreader/patches/`, restart KOReader, and check the KOReader crash log.

### A custom icon does not appear

Make sure the icon file exists in KOReader's icon directory and that its name matches the icon name referenced by the patch.

### Sleep overlays do not appear

Confirm that the overlay files are PNG images and that they are located in the `sleepoverlays/` folder.

### Folder covers do not appear

Make sure Cover Browser mosaic mode is enabled and that custom folder cover files are named `.cover` with one of the supported extensions.
