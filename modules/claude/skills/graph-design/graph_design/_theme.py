"""Economist-style matplotlib/seaborn global theme."""

import matplotlib.pyplot as plt

from graph_design._fonts import _get_font
from graph_design._palette import (
    C_BG,
    C_GRID,
    C_LABEL,
    C_SPINE,
    C_TEXT,
    colors,
)


def set_theme() -> None:
    """Apply The Economist's visual style globally to matplotlib/seaborn."""
    plt.rcParams.update(
        {
            # Figure
            "figure.facecolor": C_BG,
            "figure.dpi": 150,
            "figure.figsize": (7, 5),
            # Axes
            "axes.facecolor": C_BG,
            "axes.edgecolor": C_SPINE,
            "axes.linewidth": 1.0,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.spines.left": False,
            "axes.spines.bottom": True,
            "axes.grid": True,
            "axes.grid.axis": "y",
            "axes.axisbelow": True,
            "axes.labelcolor": C_LABEL,
            "axes.labelsize": 9,
            "axes.labelpad": 4,
            "axes.prop_cycle": plt.cycler("color", colors),
            # Grid
            "grid.color": C_GRID,
            "grid.linewidth": 0.6,
            "grid.linestyle": "-",
            # Ticks
            "xtick.color": C_SPINE,
            "ytick.color": C_LABEL,
            "xtick.labelcolor": C_LABEL,
            "ytick.labelcolor": C_LABEL,
            "xtick.labelsize": 9,
            "ytick.labelsize": 9,
            "xtick.major.size": 3.5,
            "xtick.major.width": 0.8,
            "ytick.major.size": 0,
            "xtick.minor.size": 0,
            "ytick.minor.size": 0,
            "xtick.bottom": True,
            "xtick.direction": "out",
            # Typography
            "font.family": "sans-serif",
            "font.sans-serif": [_get_font(), "Verdana", "Arial", "DejaVu Sans"],
            "text.color": C_TEXT,
            # Legend
            "legend.frameon": False,
            "legend.fontsize": 8.5,
            "legend.labelcolor": C_TEXT,
            # Lines & patches
            "lines.linewidth": 2.0,
            "lines.solid_capstyle": "round",
            "patch.edgecolor": "none",
        }
    )
