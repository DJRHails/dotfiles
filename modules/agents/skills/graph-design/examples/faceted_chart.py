# /// script
# requires-python = ">=3.12"
# dependencies = ["matplotlib", "numpy"]
# ///
"""Faceted line chart with panel labels — The Economist style."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

from graph_design import (
    C_BG,
    C_LABEL,
    C_RED,
    C_SPINE,
    ci_fill,
    finalize,
    panel_label,
    set_theme,
)

set_theme()

np.random.seed(7)
x = np.linspace(-6, 10, 80)
panels = {
    "Economic": np.where(
        x < 0, x * 0.01, np.cumsum(np.random.randn(80) * 0.015)
    ),
    "Violent": np.cumsum(np.random.randn(80) * 0.008),
    "Sexual": np.cumsum(np.random.randn(80) * 0.006),
}

fig, axes = plt.subplots(1, 3, figsize=(10, 5.5), sharey=False)
fig.subplots_adjust(
    top=0.72, bottom=0.16, left=0.04, right=0.97, wspace=0.35
)

for ax, (panel_name, y) in zip(axes, panels.items()):
    ci = np.abs(np.random.randn(len(x))) * 0.025 + 0.01
    ci_fill(ax, x, y - ci, y + ci)
    ax.plot(x, y, color=C_RED, linewidth=2)
    ax.axhline(0, color=C_SPINE, linewidth=0.8, zorder=3)
    ax.scatter([0], [0], color=C_SPINE, s=40, zorder=5)

    ax.yaxis.set_label_position("right")
    ax.yaxis.tick_right()
    ax.spines["right"].set_visible(True)
    ax.spines["right"].set_color(C_BG)
    ax.spines["bottom"].set_color(C_SPINE)
    ax.spines[["top", "left"]].set_visible(False)
    ax.yaxis.set_tick_params(pad=-2, labelsize=8.5)
    ax.set_ylim(-0.22, 0.22)
    ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.1f"))
    ax.set_xlabel(
        "Years since cancer diagnosis (1980-2018)",
        fontsize=8,
        color=C_LABEL,
    )
    panel_label(ax, panel_name)

finalize(
    axes[0],
    title=(
        "Denmark, criminal-conviction rate since\n"
        "cancer diagnosis, by type of offense"
    ),
    descriptor="Percentage-point change from baseline",
    source=(
        'Source: "Breaking bad", '
        "American Economics Journal, 2026"
    ),
    y_axis_right=False,
    title_x=0.04,
    y_start=0.075,
)

out = Path(__file__).resolve().parent / "economist_facet.png"
plt.savefig(out, bbox_inches="tight", dpi=150)
plt.close()
print("Saved facet chart")
