"""IBM Plex Sans font management for matplotlib.

Downloads font files from github.com/IBM/plex only when the font
is not already registered in matplotlib's font manager.
"""

import logging
import os
import urllib.request

import matplotlib.font_manager as fm

_log = logging.getLogger(__name__)

_IBM_BASE = (
    "https://github.com/IBM/plex/raw/master/"
    "packages/plex-sans/fonts/complete/ttf/"
)
_IBM_FILES = [
    "IBMPlexSans-Regular.ttf",
    "IBMPlexSans-Bold.ttf",
    "IBMPlexSans-SemiBold.ttf",
    "IBMPlexSans-Light.ttf",
    "IBMPlexSans-Italic.ttf",
]
_FONT_NAME = "IBM Plex Sans"
_FALLBACK = "DejaVu Sans"


def _is_registered() -> bool:
    """Check if IBM Plex Sans is already in matplotlib's font manager."""
    return any(f.name == _FONT_NAME for f in fm.fontManager.ttflist)


def ensure_ibm_plex() -> str:
    """Return the font family name, downloading only if not already available."""
    if _is_registered():
        return _FONT_NAME

    font_dir = os.path.join(os.path.dirname(__file__), "_fonts_cache")
    os.makedirs(font_dir, exist_ok=True)

    for fname in _IBM_FILES:
        path = os.path.join(font_dir, fname)
        if not os.path.exists(path):
            try:
                urllib.request.urlretrieve(_IBM_BASE + fname, path)
            except Exception:
                _log.debug("Failed to download %s", fname, exc_info=True)
                continue
        try:
            fm.fontManager.addfont(path)
        except Exception:
            _log.debug("Failed to register font %s", fname, exc_info=True)

    return _FONT_NAME if _is_registered() else _FALLBACK


FONT: str = ""


def _get_font() -> str:
    global FONT  # noqa: PLW0603
    if not FONT:
        FONT = ensure_ibm_plex()
    return FONT
