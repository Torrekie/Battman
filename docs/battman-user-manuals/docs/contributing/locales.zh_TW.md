---
title: 本地化貢獻
---

# 參與本地化

Battman 使用標準的 gettext `.po` 文件進行本地化管理。

## 目錄結構

- 項目級的 `.po` 和 `.pot` 文件位於 `Localizations` 目錄下。
- 文檔站點通過帶語言後綴的 Markdown 文件區分語言（例如 `page.md` 和 `page.zh.md`）。

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

## 參與應用本地化

### 安裝依賴

首先，確保你的設備上已安裝 GNU Gettext 工具，如果沒有，請從你的發行源安裝。

```bash
# macOS Homebrew
brew install gettext
# macOS MacPorts
sudo port install gettext
# Debian 衍生 / iOS 越獄設備
sudo apt install gettext
```

安裝完成後，你應該可以使用 `xgettext` 和 `msgfmt`：

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

`.pot` 文件是所有 `.po` 文件的模板文件，在創建本地化文件之前，請確保你始終擁有最新的模板。

```bash
# 在 Battman 中，我們使用：
# _: 用於 Objective-C NSStrings
# _C: 用於 C 字符串
# cond_localize_c: _C() 實際調用的函數

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

使用此命令，你可以從當前的 Battman 源代碼生成新的 `base.pot`。

### 創建 PO 文件

如果 Battman 尚未在 `Battman/Localizations` 下為你的語言提供 `.po` 文件，則需要此步驟。如果你要更新現有的 `.po` 文件，請參閱**更新 PO 文件**。

在實際為所需語言創建 `.po` 文件之前，請檢查其**語言代碼**。

Gettext 使用的語言代碼通常由以下部分組成：

- 一個 [ISO 639-1](https://www.loc.gov/standards/iso639-2/php/English_list.php) 兩字母代碼（例如 `en`、`fr`、`ja`）。

- 可選的 [ISO 3166](https://www.iso.org/obp/ui/#search) 兩字母地區代碼（例如 `_US`、`_CA`、`_DE`）

例如：

- 當你為日語創建語言文件時，語言代碼是 `ja`。

- 當你為英語（加拿大）創建語言文件時，語言代碼應為 `en_CA`，其中 `en` 指語言本身，`_CA` 是其地區變體。

確認語言代碼後，可以使用以下命令創建 `.po` 文件：

```bash
# 假設你已經在 Battman/ 目錄下
# 這是一個生成世界語 po 文件的示例

loc="eo" # 將此更改為你的語言代碼
msginit --input=./Localizations/base.pot \
    --output-file="./Localizations/$loc.po" \
    --locale="$loc" \
    --no-translator
```

之後，你將看到已創建一個新的 `.po` 文件（在此示例中為 `eo.po`）：

```
$ tree ./Battman/Localizations/
./Battman/Localizations/
├── base.pot
├── de.po
├── en.po
├── eo.po               # <--- 新創建的
├── generate_code.sh
├── vi.po
└── zh_CN.po

1 directory, 7 files
```

然後，你可以使用你偏好的文本編輯器編輯 `eo.po`。

### PO 文件結構

關於 PO 文件，有[官方詳細文檔](https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html)。我們在此嘗試以更簡單的方式描述。

新創建的 PO 文件具有以下頭部（此示例中的 `eo.po`）：

```po
# Esperanto translations for Battman package.
# Copyright (C) 2025 Torrekie <me@torrekie.dev>
# This file is distributed under the same license as the Battman package.
# Automatically generated, 2025.
#
msgid ""
msgstr ""
"Project-Id-Version: Battman 1.0.4\n"
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

你可能想要編輯 `Last-Translator` 字段，以標記你是最後更新此本地化文件的人：

```
"Last-Translator: Torrekie <me@torrekie.dev>\n"
```

然後你可以開始翻譯所有文本，鍵值格式基本上是一對 `msgid` 和 `msgstr`，其中 `msgid` 是從我們的源代碼中檢索得來的，例如，當我們有這樣的代碼時：

```c
char *my_string = _C("Hello, world!");
(void)printf("%s", my_string);
```

你生成的 `.po` 文件將包含一個片段：

```po
msgid "Hello, world!"
msgstr ""
```

你需要做的就是填寫 `msgstr` 字段，它應該是翻譯後的字符串。

```po
msgid "Hello, world!"
msgstr "Saluton, mondo!"
```

有時，你可能會在字符串上看到 `TRANSLATORS` 注釋，這表明我們添加了關於如何處理此字符串的說明。例如，在 `de.po` 中，我們不得不將 "Benutzerdefinierter" 替換為 "…"，因為它太長了，以至於大多數屏幕不能正常顯示它。

```po
#. TRANSLATORS: Please ensure this string won't be longer as "Custom"
msgid "Custom"
msgstr "…"
```

你可以通過使用新添加的本地化構建 Battman 來測試翻譯後的字符串，請參閱**從源代碼運行**。

## 更新 PO 文件

當你在 Battman 中添加了一些新字符串或 PO 文件看起來過於過時的時候，你可能想要更新現有的 PO 文件。

更新 PO 文件的步驟是：

1. 從源代碼重新創建 `base.pot`（請參閱**更新 base.pot**）。
2. 從更新的 `base.pot` 在其他位置創建骨架 PO 文件。
3. 將現有的 PO 文件與新創建的骨架合併。
4. 像往常一樣翻譯那些新添加的字符串。

在 Battman.xcodeproj 中，我們這樣處理：

```bash
LOCS="zh_CN en de vi"
LOC_BASE="${PROJECT_DIR}/${PROJECT_NAME}/Localizations"
POT_FILE="${LOC_BASE}/base.pot"

for locs in $LOCS; do msginit --input="${POT_FILE}" --output-file="${LOC_BASE}/$locs.po.step" --locale="$locs" && msgmerge --no-location -N "${LOC_BASE}/$locs.po" "${LOC_BASE}/$locs.po.step" > "${LOC_BASE}/$locs.po.new" && mv "${LOC_BASE}/$locs.po.new" "${LOC_BASE}/$locs.po" && rm "${LOC_BASE}/$locs.po.step"; done
```

要分解此過程：

```bash
# 示例：更新世界語

# 創建新的 PO 骨架而不覆蓋現有 PO
# 我們應該會有一個 eo.po.step
msginit --input=./Localizations/base.pot \
    --output-file=./Localizations/eo.po.step \
    --locale=eo

# 將我們現有的世界語翻譯與新創建的骨架合併
# 我們應該會有一個 eo.po.new
msgmerge --no-location -N \
    ./Localizations/eo.po \
    ./Localizations/eo.po.step \
    > ./Localizations/eo.po.new

# 用新創建的文件覆蓋現有的舊 PO 文件
mv ./Localizations/eo.po.new ./Localizations/eo.po

# 刪除骨架
rm ./Localizations/eo.po.step
```

`eo.po` 現在已更新為新添加的字符串，然後你可以使用你喜歡的文本編輯器翻譯這些新字符串。
