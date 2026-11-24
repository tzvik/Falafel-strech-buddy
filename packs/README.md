# Character packs

A pack is a folder in `packs\` with a `pack.json`. It shows up as its own kit in the
**Choose character…** gallery and in the tray's Character menu. No code changes needed.

```
packs\
  my-pack\
    pack.json
    bagel.png      (only for sticker-image characters)
```

## pack.json

```json
{
  "kit": "mypack",
  "names": { "en": "My pack", "he": "החבילה שלי" },
  "characters": [
    {
      "names": { "en": "Benny the Bagel", "he": "בני הבייגלה" },
      "image": "bagel.png",
      "face": false
    },
    {
      "names": { "en": "Pete the Pita", "he": "פיתי הפיתה" },
      "shape": "M 14,72 Q 14,30 55,30 Q 96,30 96,72 L 96,124 Q 96,130 90,130 L 20,130 Q 14,130 14,124 Z",
      "colors": ["#E2BE82", "#F6E3BA", "#D8B272"],
      "eyes": "googly", "hands": "glove", "mouth": "lips"
    }
  ]
}
```

Every character gets arms, legs, blinking and all the exercise animations automatically.

### Two kinds of character

| Kind | Fields | Notes |
|---|---|---|
| **Sticker image** (like a WhatsApp sticker) | `image`: PNG file in the pack folder | Transparent background works best. Set `"face": false` if the art already has a face. |
| **Vector** | `shape`: SVG path data, `colors`: 3 colors (left, highlight, right) | Optional `detail`: extra XAML shapes drawn on the body. |

The body lives in a 110×160 box: keep it roughly inside x 14–96, y 10–134.
The face sits around (56, 65), shoulders at y 72, hips at (44, 124) and (66, 124).

### Optional style fields

| Field | Values |
|---|---|
| `eyes` | `dots` (default), `googly` |
| `mouth` | `smile` (default), `lips` |
| `hands` | `mitt` (default), `glove` (white cartoon gloves), `felt` (puppet mitten with a thumb) |
| `limbColor` | hex color for the arms instead of black ink, e.g. `"#D6A25A"` for felt puppet arms |
| `mouth` also | `beak` (with a wattle, like the turkey) |
| `back` | extra XAML drawn *behind* the body (tail feathers, leaves) |
| `face` | `false` to hide the drawn face (for sticker images that have one) |
| `ax` | number: pull shoulders inward for narrow bodies (e.g. `10`) |

Pack-level option: `"first": true` shows the pack first in the gallery and makes its first character the default.

## Sharing a pack

Zip the pack folder (the zip must contain `pack.json`). Anyone can install it from the tray:
**Character > Add character pack…**

For safety, packs are checked before loading: `detail`/`back` may only use drawing elements
(Canvas, Ellipse, Rectangle, Path, Line, Polygon, TextBlock and transforms), no `{...}` markup
extensions; colors must be hex; images must be PNG/JPG inside the pack folder. Anything else
makes that character get skipped.

## Copyright

Only add art you have the right to use. Sticker packs you find online belong to their
artists: don't commit them to a public repo without permission. Your own `packs\` folders
stay on your machine unless you choose to share them.
