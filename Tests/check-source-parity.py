#!/usr/bin/env python3

"""Fail when Battman's explicit Makefile and Xcode source manifests drift."""

import json
import posixpath
import re
import subprocess
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
PROJECT_FILE = REPOSITORY_ROOT / "Battman.xcodeproj" / "project.pbxproj"
APP_TARGETS = ("Battman", "Battman-nonfree", "Battman-havoc", "Battman-havoc-tipa")
PLUGIN_PLATFORM_PREFIXES = ("Features/Analytics/", "PluginHost/")
SOURCE_SUFFIXES = {".m", ".c", ".S"}


def load_project():
	output = subprocess.check_output(
		["plutil", "-convert", "json", "-o", "-", str(PROJECT_FILE)],
		text=True,
	)
	return json.loads(output)


def source_paths_by_target(project):
	objects = project["objects"]
	parents = {}
	for object_id, value in objects.items():
		if value.get("isa") in {"PBXGroup", "PBXVariantGroup"}:
			for child in value.get("children", []):
				parents[child] = object_id

	main_group = next(
		value["mainGroup"] for value in objects.values() if value.get("isa") == "PBXProject"
	)

	def group_base(group_id):
		if group_id == main_group:
			return ""
		group = objects[group_id]
		component = group.get("path", "")
		if group.get("sourceTree") == "SOURCE_ROOT":
			return component
		parent = parents.get(group_id)
		base = group_base(parent) if parent else ""
		return posixpath.normpath(posixpath.join(base, component)) if component else base

	def file_path(file_id):
		file_reference = objects[file_id]
		path = file_reference.get("path") or file_reference.get("name")
		if file_reference.get("sourceTree") == "SOURCE_ROOT":
			return posixpath.normpath(path)
		return posixpath.normpath(posixpath.join(group_base(parents[file_id]), path))

	result = {}
	for target_name in APP_TARGETS:
		target = next(
			(
				value
				for value in objects.values()
				if value.get("isa") == "PBXNativeTarget" and value.get("name") == target_name
			),
			None,
		)
		if target is None:
			raise ValueError("Missing Xcode application target: {}".format(target_name))
		phase_id = next(
			phase_id
			for phase_id in target["buildPhases"]
			if objects[phase_id].get("isa") == "PBXSourcesBuildPhase"
		)
		paths = set()
		for build_file_id in objects[phase_id]["files"]:
			path = file_path(objects[build_file_id]["fileRef"])
			if Path(path).suffix in SOURCE_SUFFIXES:
				paths.add(path)
		result[target_name] = paths
	return result


def makefile_sources():
	membership = subprocess.run(
		[
			"make",
			"-s",
			"-C",
			str(REPOSITORY_ROOT / "Battman"),
			"--no-print-directory",
			"source-membership-check",
		],
		text=True,
		stdout=subprocess.PIPE,
		stderr=subprocess.PIPE,
	)
	if membership.returncode != 0:
		sys.stderr.write(membership.stdout)
		sys.stderr.write(membership.stderr)
		raise SystemExit(membership.returncode)
	if membership.stdout:
		print(membership.stdout, end="")

	database = subprocess.check_output(
		[
			"make",
			"-s",
			"-C",
			str(REPOSITORY_ROOT / "Battman"),
			"--no-print-directory",
			"-pn",
			"source-membership-check",
		],
		text=True,
	)
	match = re.search(r"^SOURCES := (.*)$", database, re.MULTILINE)
	if not match:
		raise ValueError("Could not read SOURCES from the Makefile database")
	return set(match.group(1).split())


def assert_sdk_header_dependencies():
	makefile = (REPOSITORY_ROOT / "Battman" / "Makefile").read_text(encoding="utf-8")
	marker = "$(filter build/objects/Features/Analytics/%,$(OBJECTS)):"
	if marker not in makefile:
		raise ValueError("Makefile does not rebuild Analytics objects for public SDK header changes")
	for header in (
		"../PluginSDK/include/BAAnalyticsCard.h",
		"../PluginSDK/include/BAAnalyticsMetricSnapshot.h",
		"../PluginSDK/include/BattmanPluginABI.h",
	):
		if header not in makefile:
			raise ValueError("Makefile is missing Analytics SDK dependency: {}".format(header))


def battman_relative(paths):
	result = set()
	for path in paths:
		if not path.startswith("Battman/"):
			raise ValueError("Unexpected Xcode source outside Battman/: {}".format(path))
		result.add(path[len("Battman/") :])
	return result


def report_difference(label, expected, actual):
	missing = sorted(expected - actual)
	extra = sorted(actual - expected)
	if not missing and not extra:
		return False
	if missing:
		print("{} missing:".format(label), *missing, sep="\n  ", file=sys.stderr)
	if extra:
		print("{} unexpected:".format(label), *extra, sep="\n  ", file=sys.stderr)
	return True


def main():
	assert_sdk_header_dependencies()
	project_sources = source_paths_by_target(load_project())
	make_sources = makefile_sources()
	battman_sources = battman_relative(project_sources["Battman"])
	failed = report_difference("Xcode Battman target", make_sources, battman_sources)

	plugin_platform_sources = {
		"Battman/{}".format(path)
		for path in make_sources
		if path.startswith(PLUGIN_PLATFORM_PREFIXES)
	}
	for target_name in APP_TARGETS:
		missing = plugin_platform_sources - project_sources[target_name]
		if missing:
			failed = True
			print(
				"{} missing plug-in platform sources:".format(target_name),
				*sorted(missing),
				sep="\n  ",
				file=sys.stderr,
			)

	if failed:
		return 1
	print("Makefile/Xcode Battman target parity passed: {} shared sources.".format(len(make_sources)))
	print(
		"Plug-in platform membership passed across {} app targets: {} required sources each.".format(
			len(APP_TARGETS), len(plugin_platform_sources)
		)
	)
	return 0


if __name__ == "__main__":
	sys.exit(main())
