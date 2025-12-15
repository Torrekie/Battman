"""
Setup for MkDocs plugins
"""
from setuptools import setup, find_packages

setup(
    name="battman-mkdocs-plugins",
    version="0.1.0",
    py_modules=["fix_search_plugin"],
    entry_points={
        "mkdocs.plugins": [
            "fix_search = fix_search_plugin:FixSearchPlugin",
        ]
    },
)

