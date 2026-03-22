"""
nanobot - A lightweight AI agent framework
"""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("nanobot-ai")
except PackageNotFoundError:
    __version__ = "0.1.4.post5"

__logo__ = "🐈"
