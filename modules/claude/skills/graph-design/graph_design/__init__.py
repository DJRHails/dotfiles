"""graph_design — Economist-style chart theme for matplotlib/seaborn.

Usage::

    from graph_design import set_theme, finalize, colors
    set_theme()

    fig, ax = plt.subplots()
    fig.subplots_adjust(top=0.68, bottom=0.14, left=0.06, right=0.88)
    ax.plot(...)
    finalize(ax, title="Bold headline", descriptor="Country, metric, unit",
             source="Source: Organisation")
"""

from graph_design._charts import bar_h, ci_fill, dumbbell
from graph_design._finalize import finalize, panel_label
from graph_design._fonts import _get_font as get_font
from graph_design._labels import label_lines
from graph_design._palette import (
    C_BG,
    C_CI,
    C_GRID,
    C_LABEL,
    C_RED,
    C_SPINE,
    C_TEXT,
    colors,
)
from graph_design._theme import set_theme

__all__ = [
    "bar_h",
    "ci_fill",
    "colors",
    "C_BG",
    "C_CI",
    "C_GRID",
    "C_LABEL",
    "C_RED",
    "C_SPINE",
    "C_TEXT",
    "dumbbell",
    "finalize",
    "get_font",
    "label_lines",
    "panel_label",
    "set_theme",
]
