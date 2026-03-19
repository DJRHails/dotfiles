# /// script
# requires-python = ">=3.12"
# dependencies = ["matplotlib", "numpy"]
# ///
"""Line chart with CI bands and direct labels — The Economist style."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

from graph_design import ci_fill, finalize, label_lines, set_theme

set_theme()

np.random.seed(42)
years = np.arange(2000, 2024)
data = {
    "United States": np.cumsum(np.random.randn(24) * 1.5) + 100,
    "China": np.cumsum(np.random.randn(24) * 2.0) + 100,
    "Germany": np.cumsum(np.random.randn(24) * 1.0) + 100,
}

fig, ax = plt.subplots()
fig.subplots_adjust(top=0.68, bottom=0.14, left=0.06, right=0.88)

for col, y in data.items():
    ci = np.abs(np.random.randn(len(years))) * 2.5 + 0.5
    ci_fill(ax, years, y - ci, y + ci)
    ax.plot(years, y, label=col)

label_lines(ax, stroke=True, min_sep_pct=6.0)
ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.0f"))

finalize(
    ax,
    title="GDP across major economies",
    descriptor="Index, 2000=100",
    source="Sources: IMF; World Bank",
    y_axis_right=True,
)

out = Path(__file__).resolve().parent / "economist_line.png"
plt.savefig(out, bbox_inches="tight", dpi=150)
plt.close()
print("Saved line chart")
