#! /bin/bash

SED=sed
if [[ $(command -v gsed 2>&1 > /dev/null) == 0 ]]; then
  SED=gsed
fi
if [[ ! $(${SED} --version 2>&1 > /dev/null) ]]; then
  echo "Need GNU sed!"
  exit 1
fi

msgids=`${SED} -n 's/msgid "\(.\+\)"/\1/p' Localizations/base.pot`
locale_files=`ls Localizations/*.po`
declare -A lcs

lid=1

while read i; do
	for fn in $locale_files; do
		v=`${SED} -nz "s/.*msgid \"$i\"\\nmsgstr \"\\([^\"]\\+\\)\".*/\\1/p" ${fn}`
		lcs["$fn"]="${lcs[$fn]}CFSTR(\"$v\"),"
	done
	lid=$((lid+1))
done<<< "$msgids"


for i in $locale_files; do
	localize_code="${localize_code}${lcs[${i}]}"
done
localize_code="${localize_code}\\\\n#define LOCALIZATION_COUNT $((lid-1))"

printf "$localize_code"
