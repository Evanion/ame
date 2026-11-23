# Design and game, 1:1

The design canvas and the addon must match on design details: the same colours, fonts, sizes, spacing and states. A
board is a promise about what the game draws, and a difference between the two is a bug in one of them.

## How it's kept

- **One source.** `tokens.lua` holds the colours and fonts (sizes and spacing follow, screen by screen).
  `scripts/design-tokens.lua` writes `tokens.css` for the canvas; the addon's palette (`Core/UI/Widgets.lua`) is
  generated from the same file once the first redesigned screen is built. Neither side names a colour of its own.
- **One shared look.** `ame.css` is the canvas's stylesheet; each rule in it mirrors a widget in `Core/UI/Widgets.lua`
  (button, input, pill, panel, row, tab, title bar, status row).
- **Design first.** A UI change starts on the canvas, then the code follows it. If the code can't follow, the board
  changes: it never stays as a picture of something the game doesn't do.
- **Checked per screen.** A redesigned screen is done when an in-game screenshot at 100% scale matches its board:
  layout, sizes, colours and every state on the board.

## Only what the game can draw

The canvas is a web page and the game isn't. A board uses only these:

| Allowed on the canvas | In the game |
|---|---|
| Flat colour fills, with alpha | `SetColorTexture` |
| 1 px lines and borders, inset edges (as flat strips) | textures 1 px wide |
| Two-stop vertical or horizontal gradients | `SetGradient` |
| Square corners | every frame |
| The fonts the addon ships or the game has, at whole pixel sizes | `SetFont` |
| Text that cuts off with "…" on one line | `SetWordWrap(false)` |
| Icons as textures; item icons with a 1 px quality border | textures |
| A round shape (the unread badge, online dots) | a circle texture the addon ships |

Not allowed, because the game has no equivalent: rounded corners, shadows and glows, blur, letter-spacing, gradients
with more than two stops or at an angle, web-only fonts, font weights the shipped font files don't have, hover
transitions, fractional pixel sizes.

## Still open

- **Fonts: through LibSharedMedia-3.0** (decided; to build with the first redesigned screen).
  - The canvas draws in Inter (text) and Marcellus (headings). The addon ships both (both are open: SIL OFL),
    registers them with LibSharedMedia, and uses them by default: that default is what the boards show, 1:1.
  - Settings gets two font pickers (text, headings) listing every font LibSharedMedia knows, so a player's shared
    media packs work in AME too. Picking another font is the player's choice to differ from the boards.
  - Where a font lacks the script (Korean, Chinese), AME falls back to the game's own font.
  - Textures AME ships (the round badge and dots, later any frame art) are registered the same way; bars and
    backgrounds a player picks elsewhere aren't used for AME's own chrome, which stays as designed.
- **Sizes and spacing** move into `tokens.lua` as each screen is redesigned (row heights, paddings, font sizes), so
  the addon's layout constants and the boards read the same numbers.
