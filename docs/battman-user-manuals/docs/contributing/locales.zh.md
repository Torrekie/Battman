---
title: 本地化贡献
---

# 参与本地化

Battman 使用标准的 gettext `.po` 文件进行本地化管理。

## 目录结构

- 项目级的 `.po` 和 `.pot` 文件位于 `Localizations` 目录下。
- 文档站点通过带语言后缀的 Markdown 文件区分语言（例如 `page.md` 和 `page.zh.md`）。

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

## 参与应用本地化

### 安装依赖

首先，确保你的设备上已安装 GNU Gettext 工具，如果没有，请从你的发行源安装。

```bash
# macOS Homebrew
brew install gettext
# macOS MacPorts
sudo port install gettext
# Debian 衍生 / iOS 越狱设备
sudo apt install gettext
```

安装完成后，你应该可以使用 `xgettext` 和 `msgfmt`：

```
$ xgettext --version
xgettext (GNU gettext-tools) 0.22.4
Copyright (C) 1995-2023 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
Written by Ulrich Drepper.
```

### 更新 `base.pot`

`.pot` 文件是所有 `.po` 文件的模板文件，在创建本地化文件之前，请确保你始终拥有最新的模板。

```bash
# 在 Battman 中，我们使用：
# _: 用于 Objective-C NSStrings
# _C: 用于 C 字符串
# cond_localize_c: _C() 实际调用的函数

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

使用此命令，你可以从当前的 Battman 源代码生成新的 `base.pot`。

### 创建 PO 文件

如果 Battman 尚未在 `Battman/Localizations` 下为你的语言提供 `.po` 文件，则需要此步骤。如果你要更新现有的 `.po` 文件，请参阅**更新 PO 文件**。

在实际为所需语言创建 `.po` 文件之前，请检查其**语言代码**。

Gettext 使用的语言代码通常由以下部分组成：

- 一个 [ISO 639-1](https://www.loc.gov/standards/iso639-2/php/English_list.php) 两字母代码（例如 `en`、`fr`、`ja`）。

- 可选的 [ISO 3166](https://www.iso.org/obp/ui/#search) 两字母地区代码（例如 `_US`、`_CA`、`_DE`）

例如：

- 当你为日语创建语言文件时，语言代码是 `ja`。

- 当你为英语（加拿大）创建语言文件时，语言代码应为 `en_CA`，其中 `en` 指语言本身，`_CA` 是其地区变体。

确认语言代码后，可以使用以下命令创建 `.po` 文件：

```bash
# 假设你已经在 Battman/ 目录下
# 这是一个生成世界语 po 文件的示例

loc="eo" # 将此更改为你的语言代码
msginit --input=./Localizations/base.pot \
    --output-file="./Localizations/$loc.po" \
    --locale="$loc" \
    --no-translator
```

之后，你将看到已创建一个新的 `.po` 文件（在此示例中为 `eo.po`）：

```
$ tree ./Battman/Localizations/
./Battman/Localizations/
├── base.pot
├── de.po
├── en.po
├── eo.po               # <--- 新创建的
├── generate_code.sh
├── vi.po
└── zh_CN.po

1 directory, 7 files
```

然后，你可以使用你偏好的文本编辑器编辑 `eo.po`。

### PO 文件结构

关于 PO 文件，有[官方详细文档](https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html)。我们在此尝试以更简单的方式描述。

新创建的 PO 文件具有以下头部（此示例中的 `eo.po`）：

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

你可能想要编辑 `Last-Translator` 字段，以标记你是最后更新此本地化文件的人：

```
"Last-Translator: Torrekie <me@torrekie.dev>\n"
```

然后你可以开始翻译所有文本，键值格式基本上是一对 `msgid` 和 `msgstr`，其中 `msgid` 是从我们的源代码中检索得来的，例如，当我们有这样的代码时：

```c
char *my_string = _C("Hello, world!");
(void)printf("%s", my_string);
```

你生成的 `.po` 文件将包含一个片段：

```po
msgid "Hello, world!"
msgstr ""
```

你需要做的就是填写 `msgstr` 字段，它应该是翻译后的字符串。

```po
msgid "Hello, world!"
msgstr "Saluton, mondo!"
```

有时，你可能会在字符串上看到 `TRANSLATORS` 注释，这表明我们添加了关于如何处理此字符串的说明。例如，在 `de.po` 中，我们不得不将 "Benutzerdefinierter" 替换为 "…"，因为它太长了，以至于大多数屏幕不能正常显示它。

```po
#. TRANSLATORS: Please ensure this string won't be longer as "Custom"
msgid "Custom"
msgstr "…"
```

你可以通过使用新添加的本地化构建 Battman 来测试翻译后的字符串，请参阅**从源代码运行**。

## 更新 PO 文件

当你在 Battman 中添加了一些新字符串或 PO 文件看起来过于过时的时候，你可能想要更新现有的 PO 文件。

更新 PO 文件的步骤是：

1. 从源代码重新创建 `base.pot`（请参阅**更新 base.pot**）。
2. 从更新的 `base.pot` 在其他位置创建骨架 PO 文件。
3. 将现有的 PO 文件与新创建的骨架合并。
4. 像往常一样翻译那些新添加的字符串。

在 Battman.xcodeproj 中，我们这样处理：

```bash
LOCS="zh_CN en de vi"
LOC_BASE="${PROJECT_DIR}/${PROJECT_NAME}/Localizations"
POT_FILE="${LOC_BASE}/base.pot"

for locs in $LOCS; do msginit --input="${POT_FILE}" --output-file="${LOC_BASE}/$locs.po.step" --locale="$locs" && msgmerge --no-location -N "${LOC_BASE}/$locs.po" "${LOC_BASE}/$locs.po.step" > "${LOC_BASE}/$locs.po.new" && mv "${LOC_BASE}/$locs.po.new" "${LOC_BASE}/$locs.po" && rm "${LOC_BASE}/$locs.po.step"; done
```

要分解此过程：

```bash
# 示例：更新世界语

# 创建新的 PO 骨架而不覆盖现有 PO
# 我们应该会有一个 eo.po.step
msginit --input=./Localizations/base.pot \
    --output-file=./Localizations/eo.po.step \
    --locale=eo

# 将我们现有的世界语翻译与新创建的骨架合并
# 我们应该会有一个 eo.po.new
msgmerge --no-location -N \
    ./Localizations/eo.po \
    ./Localizations/eo.po.step \
    > ./Localizations/eo.po.new

# 用新创建的文件覆盖现有的旧 PO 文件
mv ./Localizations/eo.po.new ./Localizations/eo.po

# 删除骨架
rm ./Localizations/eo.po.step
```

`eo.po` 现在已更新为新添加的字符串，然后你可以使用你喜欢的文本编辑器翻译这些新字符串。
