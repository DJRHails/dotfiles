"""Reusable Economist-style chart helpers."""

from __future__ import annotations

from typing import Sequence

from graph_design._palette import C_CI, C_GRID, C_LABEL, C_RED, C_SPINE, colors


def ci_fill(ax, x, y_lower, y_upper, *, color: str | None = None):
    """Fill a confidence-interval band using Economist salmon (#f5c5b8)."""
    ax.fill_between(
        x,
        y_lower,
        y_upper,
        color=color or C_CI,
        linewidth=0,
        zorder=1,
    )


def bar_h(
    ax,
    categories: Sequence[str],
    values: Sequence[float],
    *,
    color: str | None = None,
    highlight_max: bool = True,
):
    """Horizontal bar chart in Economist style.

    Category labels sit right-aligned to the left of the bars.
    The highest-value bar is highlighted in red.
    """
    color = color or colors[1]
    bars = ax.barh(categories, values, color=color, height=0.6, zorder=2)

    if highlight_max and values:
        idx, _ = max(enumerate(values), key=lambda x: x[1])
        bars[idx].set_color(C_RED)

    ax.spines[["top", "left", "right", "bottom"]].set_visible(False)
    ax.set_yticks(range(len(categories)))
    ax.set_yticklabels(categories, ha="right", fontsize=9)
    ax.yaxis.set_tick_params(length=0, pad=6)
    ax.xaxis.set_tick_params(labelsize=9, length=3.5, direction="out")
    ax.grid(axis="x", color=C_GRID, linewidth=0.6, zorder=0)
    ax.grid(axis="y", visible=False)
    return ax


def dumbbell(
    ax,
    categories: Sequence[str],
    values_start: Sequence[float],
    values_end: Sequence[float],
    *,
    label_start: str = "Start",
    label_end: str = "End",
    color_start: str | None = None,
    color_end: str | None = None,
):
    """Dumbbell (dot-and-line) chart for showing change between two periods.

    Scatter handles are stored on ``ax._dumbbell_handles`` so you
    can pass them to ``fig.legend()`` afterwards.
    """
    color_start = color_start or colors[7]  # Coral
    color_end = color_end or colors[1]  # Blue

    ax.hlines(
        y=categories,
        xmin=values_start,
        xmax=values_end,
        color=C_LABEL,
        linewidth=2,
        alpha=0.6,
        zorder=2,
        label="_nolegend_",
    )

    s1 = ax.scatter(
        values_start,
        categories,
        s=80,
        color=color_start,
        zorder=4,
        label=label_start,
    )
    s2 = ax.scatter(
        values_end,
        categories,
        s=80,
        color=color_end,
        zorder=4,
        label=label_end,
    )

    ax.spines[["top", "left", "right"]].set_visible(False)
    ax.spines["bottom"].set_color(C_SPINE)
    ax.yaxis.set_tick_params(length=0, pad=6)
    ax.xaxis.set_tick_params(labelsize=9, length=3.5, direction="out")
    ax.grid(axis="x", color=C_GRID, linewidth=0.6, zorder=0)
    ax.grid(axis="y", visible=False)

    ax._dumbbell_handles = [s1, s2]
    return ax
