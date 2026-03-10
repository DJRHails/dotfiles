"""Chart finalisation — title stack, source line, panel labels."""

import matplotlib.font_manager as fm
import matplotlib.pyplot as plt

from graph_design._fonts import _get_font
from graph_design._palette import C_BG, C_LABEL, C_RED, C_SPINE, C_TEXT


def finalize(
    ax,
    title: str = "",
    descriptor: str = "",
    source: str = "",
    *,
    y_axis_right: bool = True,
    title_x: float | None = None,
    y_start: float = 0.010,
):
    """Add Economist finishing touches to an axes object.

    Title stack (top to bottom)::

        ----        short red rule
        Title       IBM Plex Sans Bold
        Descriptor  IBM Plex Sans Regular

    Args:
        title: Chart headline.
        descriptor: Subtitle line (country, metric, unit).
        source: Attribution line below the chart.
        y_axis_right: Move y-axis labels to the right.
        title_x: Override x anchor in figure coords.
            Defaults to the axes bounding-box x0.
            Set to e.g. 0.02 for charts with wide left margins.
        y_start: Gap above bbox.y1 where title stack begins.
            Increase to ~0.07 for faceted charts.
    """
    fig = ax.get_figure()
    fig.patch.set_facecolor(C_BG)

    if y_axis_right:
        ax.yaxis.set_label_position("right")
        ax.yaxis.tick_right()
        ax.spines["right"].set_visible(True)
        ax.spines["right"].set_color(C_BG)
        ax.spines["right"].set_linewidth(0)
        ax.spines["left"].set_visible(False)

    ax.yaxis.set_tick_params(pad=-2, labelsize=9)
    ax.spines["bottom"].set_color(C_SPINE)
    ax.spines["bottom"].set_linewidth(1.0)

    fig.canvas.draw()
    bbox = ax.get_position()
    tx = title_x if title_x is not None else bbox.x0

    # Build title stack upward from just above the axes
    line_gap = 0.013
    rule_gap = 0.026
    y_cursor = bbox.y1 + y_start

    if descriptor:
        fig.text(
            tx,
            y_cursor,
            descriptor,
            transform=fig.transFigure,
            fontsize=9.5,
            fontweight="normal",
            color=C_TEXT,
            va="bottom",
            ha="left",
        )
        y_cursor += 0.032 + line_gap

    if title:
        fp = fm.FontProperties(family=_get_font(), weight=700)
        fig.text(
            tx,
            y_cursor,
            title,
            transform=fig.transFigure,
            fontsize=12,
            fontproperties=fp,
            color=C_TEXT,
            va="bottom",
            ha="left",
        )
        y_cursor += 0.040 + rule_gap

    # Short red rule at the top (~40 px wide)
    rule_w = 40 / (fig.get_figwidth() * fig.dpi)
    fig.add_artist(
        plt.Line2D(
            [tx, tx + rule_w],
            [y_cursor, y_cursor],
            transform=fig.transFigure,
            color=C_RED,
            linewidth=3.5,
            solid_capstyle="butt",
            clip_on=False,
        )
    )

    if source:
        fig.text(
            tx,
            bbox.y0 - 0.06,
            source,
            transform=fig.transFigure,
            fontsize=7.5,
            color=C_LABEL,
            va="top",
            ha="left",
        )

    return fig, ax


def panel_label(ax, label: str, *, fontsize: int = 10) -> None:
    """Bold panel sub-heading with a short dark rule — for faceted charts.

    Renders above the axes::

        --------
        Economic
    """
    fig = ax.get_figure()
    fig.canvas.draw()
    bbox = ax.get_position()

    rule_w = 35 / (fig.get_figwidth() * fig.dpi)
    fig.add_artist(
        plt.Line2D(
            [bbox.x0, bbox.x0 + rule_w],
            [bbox.y1 + 0.052, bbox.y1 + 0.052],
            transform=fig.transFigure,
            color=C_SPINE,
            linewidth=1.2,
            solid_capstyle="butt",
            clip_on=False,
        )
    )
    fig.text(
        bbox.x0,
        bbox.y1 + 0.010,
        label,
        transform=fig.transFigure,
        fontsize=fontsize,
        fontweight="bold",
        color=C_TEXT,
        va="bottom",
        ha="left",
    )
