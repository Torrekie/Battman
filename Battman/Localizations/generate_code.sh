#! /bin/bash

declare -A lcs 2>/dev/null
if [ $? != 0 ]; then
	echo "generate_code.sh: WARNING: bash required" >&2
	if ! type bash 2>&1 >/dev/null; then
		echo "generate_code.sh: ERROR: no bash found" >&2
		echo "Please, install bash." >&2
		exit 1
	fi
	echo "generate_code.sh: Invoking bash" >&2
	exec bash $0
fi

support_k_subst=1
bash -c 'echo ${HOME@K}' >/dev/null 2>&1
if [ $? != 0 ]; then
	# bash too old, no @K substitution
	support_k_subst=0
	bash -c 'echo ${HOME@Q}' >/dev/null 2>&1
	if [ $? != 0 ]; then
		echo "bash too old." >&2
		exit 3
	fi
fi

function read_po() {
	declare -A rpo_ret
	local current_msgid=""
	local current_msgstr=""
	local in_msgid=1
	while IFS= read i; do
		if [ "$i" == "" ]; then
			if [ "$current_msgid" != "" ]; then
				rpo_ret["$current_msgid"]="$current_msgstr"
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
			if [ "$current_msgid" != "" ]; then
				echo Duplicated msgid definition in $1 >&2
				echo Aborted >&2
				exit 10
			fi
			current_msgid="${i:7:-1}"
			continue
		fi
		if [[ "$i" =~ ^msgstr\ \" ]]; then
			if [ "$current_msgstr" != "" ]; then
				echo Duplicated msgstr definition in $1 >&2
				echo Aborted >&2
				exit 10
			fi
			current_msgstr="${i:8:-1}"
			in_msgid=0
			continue
		fi
		if [[ "$i" =~ ^\" ]]; then
			if [ $in_msgid == 1 ]; then
				current_msgid="${current_msgid}${i:1:-1}"
			else
				current_msgstr="${current_msgstr}${i:1:-1}"
			fi
		fi
	done<<<`cat $1`
	if [ $support_k_subst == 0 ]; then
		for i in "${!rpo_ret[@]}"; do
			echo -n "[${i@Q}]=${rpo_ret[$i]@Q} "
		done
		return 0
	fi
	echo "${rpo_ret[@]@K}"
}

declare -A lkeys="(`read_po ./Localizations/base.pot`)"

if [[ "$(<main.m)" =~ \#define\ PSTRMAP_SIZE\ ([[:digit:]]+) ]]; then
	if (( ${#lkeys[@]} >= ${BASH_REMATCH[1]} )); then
		echo "generate_code.sh: Count of localization strings exceeding PSTRMAP_SIZE" >&2
		echo "generate_code.sh: NOTE: num=${#lkeys[@]} vs. PSTRMAP_SIZE=${BASH_REMATCH[1]}" >&2
		exit 4
	elif (( $(( ${#lkeys[@]} + 64)) >= ${BASH_REMATCH[1]} )); then
		echo "generate_code.sh: WARNING: PSTRMAP_SIZE value is not efficient." >&2
		echo "generate_code.sh: NOTE: num=${#lkeys[@]} vs. PSTRMAP_SIZE=${BASH_REMATCH[1]}" >&2
	fi
else
	echo "generate_code.sh: PSTRMAP_SIZE not found in main.m" >&2
	exit 4
fi

locale_files=`ls Localizations/*.po`
base_locale="Localizations/en.po"
for fn in $locale_files; do
	declare -A cur="(`read_po ${fn}`)"
	for i in "${!lkeys[@]}"; do
		curval="${cur[$i]//\"/\\\"}"
		lcs["$fn"]="${lcs[$fn]}\t{(\"$curval\"),CFSTR(\"$curval\")},\n"
	done
done
localize_code="${localize_code}${lcs[${base_locale}]}"
for i in $locale_files; do
	if [ "$i" = "$base_locale" ]; then
		continue
	fi
	localize_code="${localize_code}${lcs[${i}]}"
done
echo "#include <CoreFoundation/CFString.h>"
echo
echo "struct localization_arr_entry{const char *pstr;CFStringRef cfstr;};"
echo
echo "struct localization_arr_entry localization_arr[]={"
echo -e "$localize_code"
echo -e "};\n\nint cond_localize_cnt=${#lkeys[@]};\nint cond_localize_language_cnt=`wc -l<<<$locale_files`;\\n"
