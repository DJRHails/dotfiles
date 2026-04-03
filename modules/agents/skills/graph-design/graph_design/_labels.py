"""Direct line labelling — replaces legends for line charts."""

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
):
    """Label each line at its rightmost point instead of using a legend.

    Applies iterative vertical nudges to prevent label collisions.

    Args:
        labels: Override list of strings (defaults to line labels).
        x_offset: Horizontal pixel offset from the last data point.
        fontsize: Label font size.
        stroke: White halo behind text to avoid clashing with gridlines.
        min_sep_pct: Minimum label separation as % of y-axis range.
    """
    lines = [
        line
        for line in ax.get_lines()
        if not line.get_label().startswith("_")
    ]
    if not lines:
        return

    y_lim = ax.get_ylim()
    min_sep = (y_lim[1] - y_lim[0]) * min_sep_pct / 100

    items: list[list] = []
    for i, line in enumerate(lines):
        lbl = (
            labels[i]
            if labels and i < len(labels)
            else line.get_label()
        )
        items.append([line.get_ydata()[-1], lbl, line])

    items.sort(key=lambda e: e[0])

    # Iterative repulsion to avoid overlapping labels
    for _ in range(20):
        changed = False
        for k in range(1, len(items)):
            gap = items[k][0] - items[k - 1][0]
            if gap < min_sep:
                push = (min_sep - gap) / 2
                items[k - 1][0] -= push
                items[k][0] += push
                changed = True
        if not changed:
            break

    path_fx = [pe.withStroke(linewidth=3, foreground=C_BG)] if stroke else []

    for nudged_y, lbl, line in items:
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
