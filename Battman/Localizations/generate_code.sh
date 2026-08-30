#!/usr/bin/env bash

declare -A lcs 2>/dev/null
if [ $? != 0 ]; then
	echo "generate_code.sh: WARNING: bash required" >&2
	if ! type bash &>/dev/null; then
		echo "generate_code.sh: ERROR: no bash found" >&2
		echo "Please, install bash." >&2
		exit 1
	fi
	echo "generate_code.sh: Invoking bash" >&2
	exec bash $0
fi

function read_pot() {
	declare -n rpo_ret=$2
	local current_msgid=""
	local in_msgid=1
	local po_order=0
	exec 5<$1
	while IFS= read i; do
		if [ "$i" == "" ]; then
			if [ "$current_msgid" != "" ]; then
				rpo_ret["$current_msgid"]=$((po_order++))
			fi
			current_msgid=""
			in_msgid=1
			continue
		fi
		if [[ "$i" =~ ^# ]]; then
			continue
		fi
		if [[ "$i" =~ ^msgid\ \" ]]; then
			if [[ "$current_msgid" != "" ]]; then
				echo Duplicated msgid definition in $1 >&2
				echo Aborted >&2
				exit 10
			fi
			current_msgid="${i:7:-1}"
			continue
		fi
		if [[ "$i" =~ ^msgstr\ \" ]]; then
			if [[ "$current_msgstr" != "" ]]; then
				echo Duplicated msgstr definition in $1 >&2
				echo Aborted >&2
				exit 10
			fi
			in_msgid=0
			continue
		fi
		if [[ "$i" =~ ^\" ]]; then
			if [ $in_msgid == 1 ]; then
				current_msgid+="${i:1:-1}"
			fi
		fi
	done <&5
	if [ "$current_msgid" != "" ]; then
		rpo_ret["$current_msgid"]=$po_order
	fi
	exec 5>&-
}

function parse_po() {
	declare -a rpo_ret
	declare -n keys=$2
	local current_order=-1
	local num_order=0
	local current_msgid=""
	local current_msgstr=""
	local in_msgid=1
	exec 5<$1
	while IFS= read i; do
		if [ "$i" == "" ]; then
			if (( current_order != -1 )); then
				curval="${current_msgstr//\"/\\\"}"
				curret="\t{(\"$curval\"),CFSTR(\"$curval\")},\n"
				if (( current_order==num_order )); then
					echo -en "$curret"
					((num_order++))
					while [[ "${rpo_ret[$num_order]}" != "" ]]; do
						echo -en "${rpo_ret[$num_order]}"
						((num_order++))
					done
				else
					rpo_ret[$current_order]="$curret"
					(( current_order=-1 ))
				fi
			fi
			current_msgid=""
			current_msgstr=""
			in_msgid=1
			continue
		fi
		if [[ "$i" =~ ^# ]]; then
			continue
		fi
		if [[ "$i" =~ ^msgid\ \" ]]; then
			if [[ "$current_msgid" != "" ]]; then
				echo Duplicated msgid definition in $1 >&2
				echo Aborted >&2
				exit 10
			fi
			current_msgid="${i:7:-1}"
			continue
		fi
		if [[ "$i" =~ ^msgstr\ \" ]]; then
			if [[ "$current_msgstr" != "" ]]; then
				echo Duplicated msgstr definition in $1 >&2
				echo Aborted >&2
				exit 10
			fi
			current_msgstr="${i:8:-1}"
			in_msgid=0
			if [[ "$current_msgid" == "" ]]; then continue; fi
			if [[ "${keys["$current_msgid"]}" == "" ]]; then
				continue
				echo WARNING: msgid "\"$current_msgid\"" is not defined in base.pot >&2
				echo WARNING: ^ seen in $1 >&2
				echo WARNING: Skipping >&2
			else
				current_order=${keys[$current_msgid]}
			fi
			continue
		fi
		if [[ "$i" =~ ^\" ]]; then
			if [ $in_msgid == 1 ]; then
				current_msgid+="${i:1:-1}"
			else
				current_msgstr+="${i:1:-1}"
			fi
		fi
	done <&5
	if (( current_order != -1 )); then
		curval="${current_msgstr//\"/\\\"}"
		curret="\t{(\"$curval\"),CFSTR(\"$curval\")},\n"
		rpo_ret[$current_order]="$curret"
	fi
	for ((i=num_order;i!=${#keys[@]};i++)); do
		if [[ "${rpo_ret[$i]}" == "" ]]; then
			fallback=""
			for msgid in "${!keys[@]}"; do
				if (( keys["$msgid"] == i )); then
					fallback="$msgid"
					break
				fi
			done
			if [[ "$fallback" == "" ]]; then
				echo ERROR: localization order "$i" has no base msgid >&2
				exit 11
			fi
			echo NOTE: msgid "$i" is untranslated in $1, using the base text. >&2
			curval="${fallback//\"/\\\"}"
			echo -en "\t{(\"$curval\"),CFSTR(\"$curval\")},\n"
			continue
		fi
		echo -en "${rpo_ret[$i]}"
	done
	exec 5>&-
}

declare -A lkeys
read_pot ./Localizations/base.pot lkeys

if [[ "$(<main.m)" =~ \#define\ PSTRMAP_SIZE\ ([[:digit:]]+) ]]; then
	if (( ${#lkeys[@]} >= ${BASH_REMATCH[1]} )); then
		echo "generate_code.sh: Count of localization strings exceeding PSTRMAP_SIZE" >&2
		echo "generate_code.sh: NOTE: num=${#lkeys[@]} vs. PSTRMAP_SIZE=${BASH_REMATCH[1]}" >&2
		exit 4
	elif (( ${#lkeys[@]} + 64 >= ${BASH_REMATCH[1]} )); then
		echo "generate_code.sh: WARNING: PSTRMAP_SIZE value is not efficient." >&2
		echo "generate_code.sh: NOTE: num=${#lkeys[@]} vs. PSTRMAP_SIZE=${BASH_REMATCH[1]}" >&2
	fi
else
	echo "generate_code.sh: PSTRMAP_SIZE not found in main.m" >&2
	exit 4
fi

locale_files=( Localizations/*.po )

base_locale="Localizations/en.po"

echo "#include <CoreFoundation/CFString.h>"
echo
echo "struct localization_arr_entry{const char *pstr;CFStringRef cfstr;};"
echo
echo "struct localization_arr_entry localization_arr[]={"

parse_po "$base_locale" lkeys
for i in "${locale_files[@]}"; do
	if [ "$i" = "$base_locale" ]; then
		continue
	fi
	parse_po "$i" lkeys
done

echo -e "};\n\nint cond_localize_cnt=${#lkeys[@]};\nint cond_localize_language_cnt=${#locale_files[@]};\\n"
