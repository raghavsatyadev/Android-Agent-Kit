#!/usr/bin/env bash
# Copy the Android Agent Kit into a target Android repo.
# Usage: ./install.sh <target-repo> [--force] [--dry-run]
# Existing files are kept unless --force is given.
set -eu
KIT="$(cd "$(dirname "$0")" && pwd)"
TARGET=""; FORCE=0; DRY=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;; --dry-run) DRY=1 ;;
    -h|--help) sed -n 2,4p "$0"; exit 0 ;;
    *) TARGET="$a" ;;
  esac
done
[ -d "$TARGET" ] || { echo "usage: $0 <target-repo> [--force] [--dry-run]" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

copied=0; skipped=0
while IFS= read -r f; do
  f="${f#./}"
  dest="$TARGET/$f"
  if [ "$f" = AGENTS.md ] && [ -e "$dest" ]; then
    # The repo already has agent docs (even with --force): keep them, put the kit index beside.
    echo "copy  AGENTS.md -> AGENTS.kit.md (AGENTS.md exists; merge it by hand)"
    copied=$((copied + 1)); [ "$DRY" = 1 ] || cp -p "$KIT/$f" "$TARGET/AGENTS.kit.md"; continue
  fi
  if [ -e "$dest" ] && [ "$FORCE" = 0 ]; then
    echo "skip  $f (exists)"; skipped=$((skipped + 1)); continue
  fi
  echo "copy  $f"; copied=$((copied + 1))
  [ "$DRY" = 1 ] && continue
  mkdir -p "$(dirname "$dest")"
  cp -p "$KIT/$f" "$dest"
done < <(cd "$KIT" && find . -type f \
  ! -path './.git/*' ! -path ./install.sh ! -path ./README.md \
  ! -name '*.snippet' | sort)

[ "$DRY" = 1 ] || chmod +x "$TARGET"/scripts/*.sh "$TARGET"/.githooks/* \
  "$TARGET"/global_skills/install.sh "$TARGET"/global_skills/*/install.sh \
  "$TARGET"/global_skills/local-model/lm-ask "$TARGET"/global_skills/local-model/lm-on "$TARGET"/global_skills/local-model/lm-off "$TARGET"/global_skills/local-model/jgl "$TARGET"/.agents/skills/android-device-test/scripts/*.sh 2>/dev/null || true

echo; echo "Copied $copied, skipped $skipped$([ "$DRY" = 1 ] && echo ' (dry run)')."
echo
if [ -d "$TARGET/.agent" ]; then
  echo "Found an old .agent/ folder. The kit uses .agents/: move project-only rules into"
  echo ".agents/rules/ and delete the ones the kit replaces, so agents do not read both."
  echo
fi
echo "Fill these placeholders:"
echo "  agent-kit.env : APP_MODULE, APP_VARIANT, APPLICATION_ID, BASE_BRANCH (KTFMT_VERSION, NDK_VERSION optional)"
echo "  AGENTS.md     : {{APP_NAME}} {{ONE_LINE_DESCRIPTION}} {{MODULES}} {{APP_MODULE}} {{APP_VARIANT}} {{APPLICATION_ID}} {{BASE_BRANCH}}"
echo "  .agents/skills/android-device-test/flows.md : your app's flows"
echo "  rules/skills  : <BASE_BRANCH>, <app>, <applicationId> markers"
echo
echo "Then by hand:"
echo "  append gradle.properties.snippet to gradle.properties (org.gradle.caching=true)"
echo "  append gitignore.snippet to .gitignore"
echo "  git config core.hooksPath .githooks"
echo "  bash global_skills/install.sh   (each developer, once: global skills such as nimble)"
