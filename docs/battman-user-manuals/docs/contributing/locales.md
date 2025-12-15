---
title: Contributing Locales
---

# Contributing Locales

Battman uses standard gettext `.po` files for localization.

## Folder layout

- Project‑level `.po` and `.pot` files live under the `Localizations` directory.
- The docs site uses language‑suffixed Markdown files (for example, `page.md` and `page.zh.md`).

```
Battman
├── Battman
│   └── Localizations
│       ├── base.pot
│       ├── de.po
│       ├── en.po
│       ├── generate_code.sh
│       ├── zh_CN.po
│       └── ...
└── docs
    └── battman-user-manuals
        ├── docs
        │   ├── index.md
        │   ├── index.zh.md
        │   └── ...
        └── mkdocs.yml
```

## Contributing App Locales

### Install Dependencies

First, Make sure you have GNU Gettext tools on your device, if not, install it from your distro.

```bash
# macOS Homebrew
brew install gettext
# macOS MacPorts
sudo port install gettext
# Debian derived / iOS jailbroken
sudo apt install gettext
```
After that, you should able to use `xgettext` and `msgfmt`:

```
$ xgettext --version
xgettext (GNU gettext-tools) 0.22.4
Copyright (C) 1995-2023 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
Written by Ulrich Drepper.
```

### Update `base.pot`

A `.pot` file is the template file for all `.po` files, make sure you always have a latest template before you actually going to create a locale.

```bash
# In Battman, we use:
# _: for Objective-C NSStrings
# _C: for C strings
# cond_localize_c: the actual function called by _C()

cd Battman/ && \
rm -f ./Localizations/base.pot && \
xgettext -v \
    --keyword=_ \
    --keyword=cond_localize_c \
    --keyword=_C \
    --add-comments=TRANSLATORS \
    --no-location \
    --copyright-holder="Torrekie <me@torrekie.dev>" \
    --package-name="Battman" \
    --package-version="$(cat ./VERSION)" \
    --output=./Localizations/base.pot \
    --from-code=UTF-8 \
    $(find ./ -name "*.m" -or -name "*.c" -or -name "*.h")
```

By using this command, you can generate a new `base.pot` from current Battman source codes.

### Creating PO file

This step is needed if Battman has not provided a `.po` file under `Battman/Localizations` for your language. If you are going to update an existing `.po` file, see **Updating PO file**.

Before actually creating a `.po` file for your desired language, please check the **locale code** for it.

A locale code used by Gettext is typically structed by:

- An [ISO 639-1](https://www.loc.gov/standards/iso639-2/php/English_list.php) two-letter code (e.g., `en`, `fr`, `ja`).

- Optional [ISO 3166](https://www.iso.org/obp/ui/#search) two-letter region code (e.g., `_US`, `_CA`, `_DE`)

For example:

- When you are going to create a locale file for Japanese, then the locale code is `ja`.

- When you are going to create a locale file for English (Canada), then the locale code should be `en_CA`, where `en` refers to the language itself and the `_CA` is for its region variant.

After you confirmed the locale code, you can create a `.po` file with following command:

```bash
# Assume you have already in Battman/
# This is an example of generating a Esperanto po file

loc="eo" # Change this to your locale code
msginit --input=./Localizations/base.pot \
    --output-file="./Localizations/$loc.po" \
    --locale="$loc" \
    --no-translator
```

After that, you will see a new `.po` file (`eo.po` in this example) has been created:

```
$ tree ./Battman/Localizations/
./Battman/Localizations/
├── base.pot
├── de.po
├── en.po
├── eo.po               # <--- Newly created
├── generate_code.sh
├── vi.po
└── zh_CN.po

1 directory, 7 files
```

Then you can edit `eo.po` with your preferred text editors.

### PO file structure

There is an [official detailed documentation](https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html) on PO files. We are trying to describe this here in a simpler way.

A newly created PO file has such headers (`eo.po` in this example):

```po
# Esperanto translations for Battman package.
# Copyright (C) 2025 Torrekie <me@torrekie.dev>
# This file is distributed under the same license as the Battman package.
# Automatically generated, 2025.
#
msgid ""
msgstr ""
"Project-Id-Version: Battman 1.0.3.2\n"
"Report-Msgid-Bugs-To: \n"
"POT-Creation-Date: 2025-12-02 18:25+0800\n"
"PO-Revision-Date: 2025-12-02 18:25+0800\n"
"Last-Translator: Automatically generated\n"
"Language-Team: none\n"
"Language: eo\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\n"
```

You may want to edit `Last-Translator` field to mark you were the last one who updated this locale:

```
"Last-Translator: Torrekie <me@torrekie.dev>\n"
```

Then you can start translating all texts, the key-value format is basically a pair of `msgid` and `msgstr`, where `msgid` is retrieved from our source codes, for example, when we have such code:

```c
char *my_string = _C("Hello, world!");
(void)printf("%s", my_string);
```

Your generated `.po` file will then include a segment:

```po
msgid "Hello, world!"
msgstr ""
```

All you need to do is to fill the `msgstr` field, where it should be the translated string.

```po
msgid "Hello, world!"
msgstr "Saluton, mondo!"
```

Sometimes, you may see a `TRANSLATORS` note on a string, that indicates we have added a notice on how we handle this string. For instance, in `de.po`, we had to replace  
"Benutzerdefinierter" to "…" since it was too long to display on most screens.

```po
#. TRANSLATORS: Please ensure this string won't be longer as "Custom"
msgid "Custom"
msgstr "…"
```

You can test your translated strings by building Battman with your newly added locales, see **Running from Source**.

## Updating PO file

You may want to update an existing PO file when you have added some new strings in Battman or a PO file appears too much outdated.

The procedure of updating a PO file is:

1. Recreate `base.pot` from source (see **Update base.pot**).
2. Create a skeleton PO file to elsewhere from the updated `base.pot`.
3. Combine the existing PO file with the newly created skeleton.
4. Translate those newly added strings as usual.

In Battman.xcodeproj, we are handling this like:

```bash
LOCS="zh_CN en de vi"
LOC_BASE="${PROJECT_DIR}/${PROJECT_NAME}/Localizations"
POT_FILE="${LOC_BASE}/base.pot"

for locs in $LOCS; do msginit --input="${POT_FILE}" --output-file="${LOC_BASE}/$locs.po.step" --locale="$locs" && msgmerge --no-location -N "${LOC_BASE}/$locs.po" "${LOC_BASE}/$locs.po.step" > "${LOC_BASE}/$locs.po.new" && mv "${LOC_BASE}/$locs.po.new" "${LOC_BASE}/$locs.po" && rm "${LOC_BASE}/$locs.po.step"; done
```

To teardown this:

```bash
# Example: updating Esperanto

# Create a new PO skeleton without override existing PO
# We should then have a eo.po.step
msginit --input=./Localizations/base.pot \
    --output-file=./Localizations/eo.po.step \
    --locale=eo

# Merge our existing Esperanto translations with the newly created skeleton
# We should then have a eo.po.new
msgmerge --no-location -N \
    ./Localizations/eo.po \
    ./Localizations/eo.po.step \
    > ./Localizations/eo.po.new

# Override existing old PO file with our newly created
mv ./Localizations/eo.po.new ./Localizations/eo.po

# Delete the skeleton
rm ./Localizations/eo.po.step
```

The `eo.po` is now updated with newly added strings, you can then translate those new strings with your preferred text editors.
