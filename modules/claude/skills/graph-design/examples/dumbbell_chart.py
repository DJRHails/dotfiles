# /// script
# requires-python = ">=3.12"
# dependencies = ["matplotlib"]
# ///
"""Dumbbell chart — The Economist style."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

from graph_design import dumbbell, finalize, set_theme

set_theme()

countries = [
    "United States",
    "China",
    "Germany",
    "Japan",
    "India",
    "Brazil",
]
gdp_2000 = [10.25, 1.21, 1.95, 4.72, 0.47, 0.65]
gdp_2020 = [20.93, 14.72, 3.84, 5.06, 2.62, 1.44]

fig, ax = plt.subplots(figsize=(8, 4.5))
fig.subplots_adjust(top=0.62, bottom=0.12, left=0.18, right=0.88)

dumbbell(
    ax,
    countries,
    gdp_2000,
    gdp_2020,
    label_start="2000",
    label_end="2020",
)
ax.set_xlim(-0.5, 24)
ax.xaxis.set_major_formatter(
    ticker.FuncFormatter(lambda v, _: f"${v:.0f}tn")
)

finalize(
    ax,
    title="The great divergence",
    descriptor="GDP in current US dollars, selected economies",
    source="Source: World Bank",
    y_axis_right=False,
    title_x=0.02,
)

bbox = ax.get_position()
fig.legend(
    handles=ax._dumbbell_handles,
    labels=["2000", "2020"],
    loc="upper right",
    bbox_to_anchor=(bbox.x1, bbox.y1 + 0.005),
    bbox_transform=fig.transFigure,
    frameon=False,
    fontsize=8.5,
    ncol=2,
    handletextpad=0.4,
    columnspacing=1.0,
)

out = Path(__file__).resolve().parent / "economist_dumbbell.png"
plt.savefig(out, bbox_inches="tight", dpi=150)
plt.close()
print("Saved dumbbell chart")
