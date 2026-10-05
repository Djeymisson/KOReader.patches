# KOReader Custom Patches

User patches for [KOReader](https://github.com/koreader/koreader) that I have adapted, fixed and tested for my own devices.

> **Disclaimer:** most of these patches are **modifications of work by other developers**, who are credited in [Credits](#credits). I adapted them to fit my needs: customizing behavior and appearance, fixing bugs I ran into, keeping them compatible with recent KOReader releases, and merging ideas from different versions shared by other users.

## Contents

- [Patches](#patches)
- [Installation](#installation)
- [Checking installed versions](#checking-installed-versions)
- [Versioning](#versioning)
- [Patch details](#patch-details)
- [Icons](#icons)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)
- [License](#license)

## Patches

| Patch | Version | Area | Summary |
|---|---|---|---|
| [2-bookloadcover-plus.lua](2-bookloadcover-plus.lua) | 1.4.2 | Reader open/close | Shows the book cover while opening and closing documents. |
| [2-browser-folder-cover.lua](2-browser-folder-cover.lua) | 1.0.0 | Cover Browser | Shows folders with a cover image in mosaic view. |
| [2-finished-books-look.lua](2-finished-books-look.lua) | 1.0.0 | Cover Browser | Fades finished books and adds a centered completion mark. |
| [2-progress-badge.lua](2-progress-badge.lua) | 1.0.0 | Cover Browser | Adds a reading progress badge to covers. |
| [2-reader-header-footer.lua](2-reader-header-footer.lua) | 1.0.0 | Reader | Adds a print-style header and footer to reflowable books. |
| [2-screensaver-cover.lua](2-screensaver-cover.lua) | 1.0.0 | Sleep screen | Adds extra options to the Sleep screen menu. |
| [2-sleep-overlay.lua](2-sleep-overlay.lua) | 1.0.0 | Sleep screen | Blends transparent PNG overlays over the sleep cover. |

Each patch is independent: install only the ones you want.

## Installation

1. Copy the `.lua` files you want to KOReader's patches directory:

   ```text
   koreader/patches/
   ```

2. If you use `2-finished-books-look.lua` or `2-progress-badge.lua`, copy the files from [`icons/`](icons/) to:

   ```text
   koreader/icons/
   ```

3. Restart KOReader.

Repository layout:

```text
.
├── 2-bookloadcover-plus.lua
├── 2-browser-folder-cover.lua
├── 2-finished-books-look.lua
├── 2-progress-badge.lua
├── 2-reader-header-footer.lua
├── 2-screensaver-cover.lua
├── 2-sleep-overlay.lua
└── icons/
    ├── dogear.complete.svg
    ├── percent.badge.svg
    └── percent.badge.done.svg
```

## Checking installed versions

Patches that have settings show their version as the last item of their own menu:

| Patch | Where |
|---|---|
| 2-bookloadcover-plus.lua | ☰ → Settings → BookLoadCover Plus → *Patch version* |
| 2-browser-folder-cover.lua | ☰ → Settings → File browser settings → Mosaic and detailed list settings → *Folder cover patch version* |
| 2-reader-header-footer.lua | ☰ → Settings → Reader Header & Footer → *Patch version* |
| 2-screensaver-cover.lua | ☰ → Settings → Screen → Sleep screen → *Screensaver patch version* |
| 2-sleep-overlay.lua | ☰ → Settings → Screen → Sleep Overlay → *Patch version* |

Patches without a settings menu (`2-finished-books-look.lua`, `2-progress-badge.lua`) only declare the version in the file — open it and check `PATCH_VERSION` near the top, or compare with the [Patches](#patches) table.

## Versioning

Patches follow [Semantic Versioning](https://semver.org/). The version lives in the `PATCH_VERSION` constant near the top of each file:

```lua
local PATCH_VERSION = "1.0.0"
```

- **MAJOR** — changes that reset or rename settings, or require a newer KOReader.
- **MINOR** — new options or features.
- **PATCH** — bug fixes and compatibility adjustments.

When changing a patch, bump `PATCH_VERSION` and update the [Patches](#patches) table.

## Patch details

### 2-bookloadcover-plus.lua

Replaces the opening and closing transitions with the current book cover. Settings live in **☰ → Settings → BookLoadCover Plus**.

- **When opening a book** / **When closing a book** — configured separately:
  - *Show*: KOReader default (message, no cover), cover + KOReader message, cover only, or nothing (no cover, no message). Closing can also use **Same as opening**.
  - *Cover style*: stretch cover to fit screen, fit to screen (black or white background), fill screen (zoom/crop) or **centered card**. Closing can also use **Same as opening** (the default). For example: full screen when opening and a centered card when closing.
- **Centered card options** — card size and rounded corners, used by whichever action has the *Centered card* style.
- **Cover source** — **Balanced (faster)** tries cached or already available covers first; **Best quality** extracts the cover directly from the document when possible, which looks better but can slow down opening.
- **Advanced settings** — extract the cover directly from the document when needed; show the cover on internal reloads/document switches.

Works with the [Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin) plugin. When Bookshelf is the home screen, its own opening effect no longer hides the cover. With Bookshelf's *Instant book close*, the book is only really closed later behind the shelf, so no closing cover is shown then, and reopening that book is instant (no opening cover).

Works with the [SimpleUI](https://github.com/doctorhetfield-cmd/simpleui.koplugin) plugin: closing a book to its home screen (gesture, bottom bar or the reader's file browser button) shows the closing cover. If SimpleUI's own *Book Cover Transition → Show on Close* is also on, the cover may be drawn twice, so keep only one of them enabled.

The menu is translated into Brazilian Portuguese (also used for European Portuguese). Common terms reuse KOReader's own translations, so they follow your interface language; other text falls back to English.

Most items show an explanation on long-press. Settings from versions before 1.3.0 are kept: the old single *Cover layout* setting becomes the opening *Cover style*, and closing defaults to *Same as opening*.

### 2-browser-folder-cover.lua

Corrected version of the folder cover patch for Cover Browser mosaic view. A folder is shown with a cover-style look, using a custom image placed inside it or the cover of one of its books.

Supported custom cover file names:

```text
.cover.jpg  .cover.jpeg  .cover.png  .cover.webp  .cover.gif
```

Compared to the original, it adds safer handling of missing menu/item data, a fallback when Cover Browser's book info manager is not reachable, and options under **☰ → File browser settings → Mosaic and detailed list settings** to crop the folder image, center the folder name, and show or hide it.

### 2-finished-books-look.lua

In mosaic view, books marked as complete are faded and get a large centered completion icon instead of the default corner marks.

The fade amount is set by `FADING_AMOUNT` at the top of the file (`0.0` = no fade, `1.0` = white). Requires `dogear.complete.svg`.

### 2-progress-badge.lua

Adds a badge in the top-right corner of covers in mosaic view: books in progress show their percentage, finished books show a done badge.

Badge size, position and text offsets can be adjusted in the *User Preferences* block at the top of the file. Requires `percent.badge.svg` and `percent.badge.done.svg`.

### 2-reader-header-footer.lua

Draws a print-edition style header and footer in reflowable documents:

- **Header** — author and title on even pages, chapter title on odd pages; Wi-Fi status, clock and battery on the right.
- **Footer** — pages left in the chapter and overall percentage.

Settings in **☰ → Settings → Reader Header & Footer**: enable/disable, toggle each item, use document margins or custom (optionally synced) margins, font color, font size and separator.

### 2-screensaver-cover.lua

Adds five options to **☰ → Settings → Screen → Sleep screen**:

- close widgets before showing the screensaver;
- refresh before showing the screensaver;
- prevent the message from overlapping the image;
- center the image;
- invert the message color when using no fill.

### 2-sleep-overlay.lua

Blends a transparent PNG overlay over the current sleep cover — useful for frames, textures, stamps or themed sleep screens. Put the overlays in:

```text
koreader/sleepoverlays/
```

Settings in **☰ → Settings → Screen → Sleep Overlay**: enable/disable, choose which overlays are active, scaling mode (fit, fill, center, stretch) and rotation (random or sequential).

## Icons

| Icon | Used by | Purpose |
|---|---|---|
| `dogear.complete.svg` | `2-finished-books-look.lua` | Centered completion mark for finished books. |
| `percent.badge.svg` | `2-progress-badge.lua` | Badge background for the reading percentage. |
| `percent.badge.done.svg` | `2-progress-badge.lua` | Badge for finished books. |

## Compatibility

- Tested with **KOReader 2025.10**. These patches change KOReader internals and may need adjustments after updates.
- `2-browser-folder-cover.lua`, `2-finished-books-look.lua` and `2-progress-badge.lua` depend on the **Cover Browser** plugin in mosaic mode and have no visible effect without it.

## Troubleshooting

**KOReader does not start after adding a patch** — remove the last patch you copied to `koreader/patches/`, restart, and check `crash.log`.

**I am not sure which version I have** — see [Checking installed versions](#checking-installed-versions).

**A custom icon does not appear** — make sure the icon file is in `koreader/icons/` and its name matches the one in the table above.

**Sleep overlays do not appear** — confirm the files are PNGs with transparency and are in `koreader/sleepoverlays/`.

**Folder covers do not appear** — make sure Cover Browser mosaic mode is enabled and the custom image is named `.cover` with a supported extension.

## Credits

| Patch | Based on |
|---|---|
| 2-bookloadcover-plus.lua | [Oleh Tiuriakov (reuerendo)](https://github.com/reuerendo/koreader-patches) |
| 2-browser-folder-cover.lua | [sebdelsol](https://github.com/sebdelsol/KOReader.patches) |
| 2-finished-books-look.lua | [SeriousHornet](https://github.com/SeriousHornet/KOReader.patches) |
| 2-progress-badge.lua | [SeriousHornet](https://github.com/SeriousHornet/KOReader.patches) |
| 2-reader-header-footer.lua | [Joshua Cant](https://github.com/joshuacant/KOReader.patches) (`2-reader-header-print-edition.lua`), with changes by Isaac_729 |
| 2-screensaver-cover.lua | [sebdelsol](https://github.com/sebdelsol/KOReader.patches) |
| 2-sleep-overlay.lua | [omer-faruq](https://github.com/omer-faruq/koreader-user-patches) |

## License

[GPL-3.0](LICENSE), the same license as KOReader.
