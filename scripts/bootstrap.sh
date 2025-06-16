#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Initialise a freshly-generated stonecraft-template repository.
# Updates Gradle props, CI YAML, Discord notifier JSON, renames packages, etc.
#
# Usage (all flags are required unless a default is shown):
#
#   ./scripts/bootstrap.sh \
#     --group          com.example \
#     --name           AwesomeBlocks \
#     --id             awesomeblocks      \
#     --slug           awesomeblocks      \
#     --java           21                 \
#     --datagen        true|false         \
#     --gametests      true|false         \
#     --discord-user   "AwesomeBlocks Bot" \
#     --discord-avatar https://example.com/avatar.png
# ---------------------------------------------------------------------------
set -euo pipefail
shopt -s globstar   # for ** globs

# -------- helper ------------------------------------------------------------
usage() {
  echo "Usage: $0 --group com.example --name MyMod --id mymod --slug mymodslug \\
                --java 21 --datagen true --gametests true \\
                --discord-user \"Bot\" --discord-avatar https://...png" >&2
  exit 1
}

# -------- parse CLI ---------------------------------------------------------
GROUP="" MOD_NAME="" MOD_ID="" MOD_SLUG=""
JAVA="21" DATAGEN="true" GAMETESTS="true"
DISCORD_USER="" DISCORD_AVATAR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --group)          GROUP="$2"; shift 2;;
    --name)           MOD_NAME="$2"; shift 2;;
    --id)             MOD_ID="$2"; shift 2;;
    --slug)           MOD_SLUG="$2"; shift 2;;
    --java)           JAVA="$2"; shift 2;;
    --datagen)        DATAGEN="$2"; shift 2;;
    --gametests)      GAMETESTS="$2"; shift 2;;
    --discord-user)   DISCORD_USER="$2"; shift 2;;
    --discord-avatar) DISCORD_AVATAR="$2"; shift 2;;
    *) usage;;
  esac
done

# -------- sanity checks -----------------------------------------------------
for var in GROUP MOD_NAME MOD_ID MOD_SLUG DISCORD_USER DISCORD_AVATAR; do
  [[ -z "${!var}" ]] && { echo "🚨  Missing --${var//_/\-}" >&2; usage; }
done

echo "🔧  Mod group       : $GROUP"
echo "🔧  Mod name        : $MOD_NAME"
echo "🔧  Mod id          : $MOD_ID"
echo "🔧  Mod slug        : $MOD_SLUG"
echo "🔧  Java version    : $JAVA"
echo "🔧  Include datagen : $DATAGEN"
echo "🔧  Include tests   : $GAMETESTS"
echo "🔧  Discord user    : $DISCORD_USER"
echo "🔧  Discord avatar  : $DISCORD_AVATAR"
echo

# ---------------------------------------------------------------------------
# 1. gradle.properties
# ---------------------------------------------------------------------------
PROP_FILE=gradle.properties
sed -i -e "s/^mod.group=.*/mod.group=$GROUP/" \
       -e "s/^mod.name=.*/mod.name=$MOD_NAME/" \
       -e "s/^mod.id=.*/mod.id=$MOD_ID/"     \
       "$PROP_FILE"

# ---------------------------------------------------------------------------
# 2. settings.gradle.kts
# ---------------------------------------------------------------------------
sed -i -E "s/^rootProject.name *= *\".*\"/rootProject.name = \"$MOD_NAME\"/" \
       settings.gradle.kts

# ---------------------------------------------------------------------------
# 3. Rename Java package directory
#    (assumes there is exactly one existing top-level package folder)
# ---------------------------------------------------------------------------
SRC_ROOT=src/main/java
NEW_PATH="$SRC_ROOT/$(echo "$GROUP" | tr '.' '/')"
mkdir -p "$NEW_PATH"

# Move anything not already under NEW_PATH into NEW_PATH
for dir in "$SRC_ROOT"/*; do
  [[ "$dir" == "$NEW_PATH" ]] && continue
  [[ -d "$dir" ]] || continue
  echo "↪  Moving $dir → $NEW_PATH"
  git mv "$dir" "$NEW_PATH" 2>/dev/null || mv "$dir" "$NEW_PATH"
done

# ---------------------------------------------------------------------------
# 4. Rename access widener file
# ---------------------------------------------------------------------------
AW_OLD="src/main/resources/yourmodid.accesswidener"
AW_NEW="src/main/resources/${MOD_ID}.accesswidener"
[[ -f "$AW_OLD" ]] && mv "$AW_OLD" "$AW_NEW"

# ---------------------------------------------------------------------------
# 5. GitHub Actions build.yml tweaks
# ---------------------------------------------------------------------------
BUILD_WF=".github/workflows/build.yml"

# Bump Java matrix
yq -i ".jobs.build.strategy.matrix.java = [\"$JAVA\"]" "$BUILD_WF"

# Drop datagen step if asked
if [[ "$DATAGEN" != "true" ]]; then
  yq -i 'del(.jobs.build.steps[] | select(.name|test("Data.?Gen";"i")))' "$BUILD_WF"
fi

# Drop gametest references if asked
if [[ "$GAMETESTS" != "true" ]]; then
  yq -i '(.jobs.build.steps[]? | select(has("with"))).with.arguments
         |= select(. != null) | gsub(" *chiseledGameTest\\b"; "")' "$BUILD_WF"
fi

# ---------------------------------------------------------------------------
# 6. .releaserc.json – Discord notifier block
# ---------------------------------------------------------------------------
REL_FILE=".releaserc.json"
jq --arg user  "$DISCORD_USER" \
   --arg av    "$DISCORD_AVATAR" \
   --arg slug  "$MOD_SLUG" '
  # ① locate the notifier plugin’s config object
  (.plugins[] | select(.[0] == "semantic-release-discord-notifier"))[1] as $cfg
  |
  # ② replace username & avatar directly
  ($cfg.embedJson.username) = $user
  |
  ($cfg.embedJson.avatar_url) = $av
  |
  # ③ update any URL that still contains the placeholder slug
  ($cfg.embedJson.components[0][] .url) |= gsub("yourmodslug"; $slug)
' "$REL_FILE" > "${REL_FILE}.tmp" && mv "${REL_FILE}.tmp" "$REL_FILE"

echo -e "\n✅  Template initialised — ready for the first real commit."
