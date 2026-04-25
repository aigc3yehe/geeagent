#!/usr/bin/env bash

set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository. Policy validation skipped."
  exit 0
fi

tracked_files="$(git ls-files)"

doc_violations="$(printf '%s\n' "$tracked_files" | grep -E '\.(md|mdx|rst|adoc|txt)$' | grep -v '^README\.md$' || true)"
non_ascii_violations="$(printf '%s\n' "$tracked_files" | LC_ALL=C grep '[^ -~]' || true)"

if [[ -n "$doc_violations" ]]; then
  echo "Tracked documentation files are not allowed except README.md:"
  printf '%s\n' "$doc_violations"
  exit 1
fi

if [[ -n "$non_ascii_violations" ]]; then
  echo "Tracked paths must be English-only ASCII paths:"
  printf '%s\n' "$non_ascii_violations"
  exit 1
fi

echo "Repository policy checks passed."
