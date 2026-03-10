---
name: graph-design
description: >
  Economist-style chart theme for matplotlib/seaborn. Provides a global theme,
  title-stack finaliser, direct line labels, CI bands, horizontal bars, and
  dumbbell charts. Uses IBM Plex Sans typography and a curated 8-colour palette.
---

# graph-design

Economist-style data-visualisation system for matplotlib and seaborn.

## Quick start

```python
from graph_design import set_theme, finalize, label_lines, get_font, colors

set_theme()

fig, ax = plt.subplots()
fig.subplots_adjust(top=0.68, bottom=0.14, left=0.06, right=0.88)
ax.plot(x, y, label="Series A")
label_lines(ax)
finalize(
    ax,
    title="Bold chart title",
    descriptor="Country, metric, unit",
    source="Source: Organisation",
)
```

## Visual system

### Title stack (top → bottom)

```
────        short red rule  (#bf352b, 3.5 lw)
Title       IBM Plex Sans Bold, 12 pt
Descriptor  IBM Plex Sans Regular, 9.5 pt
```

### Palette

| Swatch   | Hex       | Role    |
|----------|-----------|---------|
| Red      | `#bf352b` | Primary / accent |
| Blue     | `#006BA2` | Secondary |
| Teal     | `#3EBCD2` | |
| Green    | `#379A8B` | |
| Yellow   | `#EBB434` | |
| Mauve    | `#9A607F` | |
| Slate    | `#758D99` | |
| Coral    | `#DB444B` | |

Structural colours: background `#FFFFFF`, spine `#1A1A1A`, grid `#D9D9D9`,
labels `#666666`, CI band `#f5c5b8`.

### Typography

IBM Plex Sans is loaded automatically. If the font is already registered
in matplotlib's font manager (e.g. installed system-wide), no download
occurs. Otherwise the TTF files are fetched from `github.com/IBM/plex`
on first use and cached in `graph_design/_fonts_cache/`.

Fallback chain: IBM Plex Sans → Verdana → Arial → DejaVu Sans.

### Layout conventions

- `fig.subplots_adjust(top=0.68, bottom=0.14, left=0.06, right=0.88)` — leaves
  room for the title stack above and source line below.
- For faceted charts increase `top` to ~0.72 and pass `y_start=0.075` to `finalize`.
- Y-axis on the right by default (Economist convention); toggle with `y_axis_right=False`.

## Package structure

```
graph_design/
├── __init__.py      # re-exports all public API
├── _palette.py      # colours: C_BG, C_SPINE, C_RED, C_CI, colors, …
├── _fonts.py        # IBM Plex Sans lazy loader (skips download if registered)
├── _theme.py        # set_theme() — global rcParams
├── _finalize.py     # finalize(), panel_label()
├── _charts.py       # bar_h(), dumbbell(), ci_fill()
└── _labels.py       # label_lines()
```

## API reference

### `set_theme()`

Apply the Economist visual style globally. Call once at the top of a script.
Sets rcParams for figure size (7×5), DPI (150), grid, spines, ticks, fonts,
and the 8-colour cycle.

### `finalize(ax, title, descriptor, source, *, y_axis_right, title_x, y_start)`

Add the title stack, red rule, and source line. Moves y-axis to the right.

- `title_x` — override horizontal anchor (figure coords). Use `0.02` for
  charts with wide left margins or faceted layouts.
- `y_start` — vertical gap above axes where the stack begins. Increase to
  `0.075` for faceted charts to clear panel labels.

### `label_lines(ax, labels, *, x_offset, fontsize, stroke, min_sep_pct)`

Label each line at its rightmost point. Applies iterative vertical nudges to
prevent collisions. `stroke=True` adds a white halo for readability.

### `ci_fill(ax, x, y_lower, y_upper, *, color)`

Confidence-interval band. Defaults to the Economist salmon colour `#f5c5b8`.

### `bar_h(ax, categories, values, *, color, highlight_max)`

Horizontal bar chart. The highest bar is highlighted in red by default.

### `dumbbell(ax, categories, values_start, values_end, *, label_start, label_end, color_start, color_end)`

Dot-and-line chart for showing change between two periods. Legend handles
are stored on `ax._dumbbell_handles`.

### `panel_label(ax, label, *, fontsize)`

Bold sub-heading with a short dark rule above — use for faceted charts.

## Examples

See `examples/` for complete runnable scripts:

- [`line_chart.py`](./examples/line_chart.py) — multi-series line chart with CI bands and direct labels
- [`faceted_chart.py`](./examples/faceted_chart.py) — three-panel faceted layout with panel labels
- [`bar_chart.py`](./examples/bar_chart.py) — horizontal bar chart with max-value highlight
- [`dumbbell_chart.py`](./examples/dumbbell_chart.py) — before/after comparison with legend

## When generating charts

1. Always call `set_theme()` first.
2. Use `fig.subplots_adjust()` to leave headroom — the title stack is drawn
   in figure coordinates above the axes bounding box.
3. Prefer `label_lines()` over legends for line charts.
4. Use `ci_fill()` before plotting lines so bands sit behind.
5. Call `finalize()` last — it draws the title stack and positions spines.
6. For faceted charts, call `panel_label()` on each axes and `finalize()`
   on the first axes with `title_x` pinned to the figure left edge.
