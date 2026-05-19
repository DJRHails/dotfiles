"""Direct line labelling — replaces legends for line charts."""

from __future__ import annotations

from collections import defaultdict

import matplotlib.patheffects as pe

from graph_design._palette import C_BG


def label_lines(
    ax,
    labels: list[str] | None = None,
    *,
    x_offset: int = 6,
    fontsize: int = 9,
    stroke: bool = True,
    min_sep_pct: float = 5.0,
    tick_pad_pct: float = 4.5,
):
    """Label each line at its rightmost point instead of using a legend.

    Visible y-tick rows are treated as fixed dividers. Each label is placed
    in the band between two consecutive ticks (with `tick_pad_pct` padding off
    each tick) so labels can never obscure axis tick text. Within a band,
    labels are spread evenly with at least `min_sep_pct` separation; if the
    band is too narrow for the labels in it, separation shrinks to fit
    without spilling onto the tick rows.

    Args:
        labels: Override list of strings (defaults to line labels).
        x_offset: Horizontal pixel offset from the last data point.
        fontsize: Label font size.
        stroke: White halo behind text to avoid clashing with gridlines.
        min_sep_pct: Minimum label separation as % of y-axis range.
        tick_pad_pct: Minimum gap between any label and a y-tick row,
            as % of y-axis range. Set to 0 to disable tick-avoidance.
    """
    lines = [line for line in ax.get_lines() if not line.get_label().startswith("_")]
    if not lines:
        return

    y_lo, y_hi = ax.get_ylim()
    span = y_hi - y_lo
    min_sep = span * min_sep_pct / 100
    tick_pad = span * tick_pad_pct / 100

    # Visible ticks define band boundaries. The axis limits cap the outer bands.
    yticks = sorted(t for t in ax.get_yticks() if y_lo <= t <= y_hi)
    tick_set = set(yticks)
    edges = [y_lo] + yticks + [y_hi]
    bands: list[tuple[float, float]] = []
    for i in range(len(edges) - 1):
        lo = edges[i] + (tick_pad if edges[i] in tick_set else 0)
        hi = edges[i + 1] - (tick_pad if edges[i + 1] in tick_set else 0)
        if hi > lo:
            bands.append((lo, hi))
    if not bands:  # degenerate: no usable band, fall back to full axis
        bands = [(y_lo, y_hi)]

    chart_center = (y_lo + y_hi) / 2

    def assign_band(y: float) -> tuple[float, float]:
        """Pick the band for a label at `y`.

        Strict containment wins. Otherwise pick the band whose nearest edge
        is closest to `y`; on ties (label sits exactly on a tick boundary),
        pick the band whose centre is closer to the chart centre — so labels
        for lines that end at the axis extremes land *interior* to the chart
        rather than spilling outside the spine.
        """
        for lo, hi in bands:
            if lo <= y <= hi:
                return (lo, hi)

        def edge_dist(b):
            lo, hi = b
            return min(abs(lo - y), abs(hi - y))

        d_min = min(edge_dist(b) for b in bands)
        candidates = [b for b in bands if edge_dist(b) == d_min]
        if len(candidates) == 1:
            return candidates[0]
        return min(candidates, key=lambda b: abs((b[0] + b[1]) / 2 - chart_center))

    items: list[list] = []
    for i, line in enumerate(lines):
        lbl = labels[i] if labels and i < len(labels) else line.get_label()
        y = float(line.get_ydata()[-1])
        items.append([y, lbl, line, assign_band(y)])

    # Distribute each band's labels evenly inside it, anchored near their mean y.
    by_band: dict[tuple[float, float], list[list]] = defaultdict(list)
    for it in items:
        by_band[it[3]].append(it)

    for (band_lo, band_hi), group in by_band.items():
        group.sort(key=lambda it: it[0])
        n = len(group)
        if n == 1:
            group[0][0] = max(band_lo, min(band_hi, group[0][0]))
            continue
        avail = band_hi - band_lo
        sep = min(min_sep, avail / (n - 1))
        total = (n - 1) * sep
        mean_y = sum(it[0] for it in group) / n
        center = max(band_lo + total / 2, min(band_hi - total / 2, mean_y))
        start = center - total / 2
        for i, it in enumerate(group):
            it[0] = start + i * sep

    path_fx = [pe.withStroke(linewidth=3, foreground=C_BG)] if stroke else []
    for nudged_y, lbl, line, _ in items:
        ax.annotate(
            lbl,
            xy=(line.get_xdata()[-1], nudged_y),
            xytext=(x_offset, 0),
            textcoords="offset points",
            va="center",
            fontsize=fontsize,
            color=line.get_color(),
            path_effects=path_fx,
            clip_on=False,
            annotation_clip=False,
        )
