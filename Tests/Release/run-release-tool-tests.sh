#!/bin/sh

set -eu
export PYTHONDONTWRITEBYTECODE=1

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' \
	"$repo_root/.github/workflows/ci.yml" \
	"$repo_root/.github/workflows/release.yml" \
	"$repo_root/.github/ISSUE_TEMPLATE/plugin-report.yml" \
	"$repo_root/.github/ISSUE_TEMPLATE/config.yml" \
	"$repo_root/docs/battman-user-manuals/mkdocs.yml"
python3 "$repo_root/Tests/Release/check_release_boundary.py"
python3 "$repo_root/Tests/Release/test_release_tools.py"
python3 "$repo_root/Tests/Release/test_havoc_candidate_policy.py"
python3 "$repo_root/Tests/Release/test_compatibility_matrix.py"
python3 "$repo_root/Tests/Release/test_plugin_trust_resource_installer.py"
python3 "$repo_root/Tests/Release/test_official_trust_tools.py"
python3 "$repo_root/Tests/Release/test_production_key_ceremony.py"
python3 "$repo_root/Tests/Release/test_production_key_evidence.py"
python3 "$repo_root/Tests/Release/test_plugin_release_pins.py"
python3 "$repo_root/Tests/Release/test_official_charge_gauge.py"
python3 "$repo_root/Tests/Release/test_user_manual_sources.py"
python3 "$repo_root/Tests/Release/test_support_policy.py"

printf '%s\n' "Focused release-tool safety tests passed."
