"""Create language-local search pages after the i18n build has completed."""

import json
import shutil
from pathlib import Path

from mkdocs.plugins import BasePlugin, event_priority


class FixSearchPlugin(BasePlugin):
    def __init__(self):
        super().__init__()
        self.search_pages = {}

    def on_config(self, config, **kwargs):
        config.theme.static_templates.add("search.html")
        i18n = config.plugins.get("i18n")
        if not i18n or not i18n.building:
            self.search_pages = {}
        return config

    def on_post_template(self, output, template_name, config, **kwargs):
        if template_name == "search.html":
            i18n = config.plugins.get("i18n")
            locale = i18n.current_language if i18n else "en"
            self.search_pages[locale] = output
        return output

    @event_priority(-200)
    def on_post_build(self, config, **kwargs):
        # i18n's -100 hook recursively builds locales, then combines the index.
        # Only operate on that completed index, regardless of the output path.
        i18n = config.plugins.get("i18n")
        if i18n and i18n.building:
            return
        locales = i18n.build_languages if i18n else ["en"]
        default = i18n.default_language if i18n else "en"
        site = Path(config.site_dir)
        search = site / "search"
        combined = json.loads((search / "search_index.json").read_text(encoding="utf-8"))
        prefixes = tuple(f"{locale}/" for locale in locales if locale != default)

        for locale in locales:
            destination = site if locale == default else site / locale
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "search.html").write_text(self.search_pages[locale], encoding="utf-8")
            if locale != default:
                for directory in ("search", "stylesheets", "javascripts", "images"):
                    shutil.copytree(site / directory, destination / directory, dirs_exist_ok=True)
            prefix = "" if locale == default else f"{locale}/"
            entries = []
            for entry in combined["docs"]:
                location = entry["location"]
                selected = not location.startswith(prefixes) if not prefix else location.startswith(prefix)
                if selected:
                    entries.append(dict(entry, location=location[len(prefix):]))
            if not entries:
                raise ValueError(f"No search entries generated for {locale}")
            # Search links resolve against each locale's own search.html page.
            localized = {key: value for key, value in combined.items() if key not in ("docs", "index")}
            localized["docs"] = entries
            (destination / "search/search_index.json").write_text(
                json.dumps(localized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
        (site / ".nojekyll").touch()
