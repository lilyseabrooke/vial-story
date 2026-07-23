class_name UiPalette
extends RefCounted
## Cozy springtime potion-shop palette (see potion-shop-color-palette.md), as
## named constants for the handful of UI-chrome colors that are set in code
## rather than through theme/ui_theme.tres. Static-const-only, same pattern as
## IngredientDef.CATEGORY_COLORS — never instanced.
##
## Only *chrome* colors belong here. Diegetic/gameplay colors (ingredient
## categories, summoning symbols, interactable status meters, VN speaker tints)
## encode state and stay where they are.
##
## MAUVE_POTION is the palette's one saturated note and is reserved exclusively
## for magic/potion glow — do not reach for it as a generic accent.

# --- Named palette ---------------------------------------------------------
const SAGE_LEAF := Color(0.659, 0.765, 0.627)      # #A8C3A0 — lead
const HONEY_OAK := Color(0.788, 0.596, 0.416)      # #C9986A — lead
const WARM_WALNUT := Color(0.545, 0.369, 0.235)    # #8B5E3C
const DRIFTWOOD_TAN := Color(0.91, 0.831, 0.722)   # #E8D4B8
const BLUSH_BLOSSOM := Color(0.949, 0.788, 0.831)  # #F2C9D4
const BUTTER_SUN := Color(0.961, 0.882, 0.643)     # #F5E1A4
const LAVENDER_MIST := Color(0.847, 0.784, 0.91)   # #D8C8E8
const MORNING_SKY := Color(0.749, 0.878, 0.871)    # #BFE0DE
const MAUVE_POTION := Color(0.549, 0.31, 0.502)    # #8C4F80 — RESERVED: magic only
const CREAM_PAGE := Color(0.98, 0.953, 0.906)      # #FAF3E7
const COCOA_INK := Color(0.361, 0.271, 0.188)      # #5C4530

# --- Intent aliases (semantic roles for code-driven chrome) ----------------
const TEXT_PRIMARY := COCOA_INK
const TEXT_MUTED := Color(0.361, 0.271, 0.188, 0.6)
const TEXT_ON_DARK := CREAM_PAGE
const DANGER := Color(0.706, 0.29, 0.263)          # muted terracotta (crit fail / game over)
const SUCCESS := Color(0.361, 0.545, 0.353)        # sage-derived green
const WARNING := Color(0.831, 0.639, 0.286)        # warm amber (butter, saturated down)
const GOLD := Color(0.855, 0.667, 0.302)           # crit success highlight
const HEART := Color(0.792, 0.408, 0.518)          # rose (affection hearts)
const MAGIC := MAUVE_POTION                         # inflection points / magical accents
