#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Initialise a freshly-generated stonecraft-template repository.
# Performs all checklist steps automatically.
# ---------------------------------------------------------------------------
set -euo pipefail
shopt -s globstar dotglob   # ** globs + include dot-files

usage() {
  cat >&2 <<EOF
Usage: $0 \
  --group com.example \
  --name MyMod \
  --id mymodid \
  --slug my-mod-slug \
  --java 21 \
  --datagen true|false \
  --gametests true|false \
  --discord-user "Bot name" \
  --discord-avatar https://…png
EOF
  exit 1
}

# -------- CLI parsing -------------------------------------------------------
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

for v in GROUP MOD_NAME MOD_ID MOD_SLUG DISCORD_USER DISCORD_AVATAR; do
  [[ -z "${!v}" ]] && { echo "🚨  Missing --${v//_/-}" >&2; usage; }
done

echo "\n🔧  Parameters\n    group        : $GROUP\n    mod name     : $MOD_NAME\n    mod id       : $MOD_ID\n    mod slug     : $MOD_SLUG\n    java version : $JAVA\n    datagen?     : $DATAGEN\n    gametests?   : $GAMETESTS\n    discord user : $DISCORD_USER\n    discord av   : $DISCORD_AVATAR\n"

###############################################################################
# 1. Capture OLD_GROUP before we overwrite gradle.properties -----------------
###############################################################################
OLD_GROUP=$(grep '^mod.group=' gradle.properties | cut -d= -f2)

###############################################################################
# 2. Update gradle.properties -------------------------------------------------
###############################################################################
sed -i -e "s/^mod.group=.*/mod.group=$GROUP/" \
       -e "s/^mod.name=.*/mod.name=$MOD_NAME/" \
       -e "s/^mod.id=.*/mod.id=$MOD_ID/" \
       gradle.properties

###############################################################################
# 3. Update settings.gradle.kts ----------------------------------------------
###############################################################################
sed -i -E "s/^rootProject.name *= *\".*\"/rootProject.name = \"$MOD_NAME\"/" settings.gradle.kts

###############################################################################
# 4. Move Java/Kotlin sources into the new package path ----------------------
###############################################################################
SRC_ROOT=src/main/java
OLD_PATH="$SRC_ROOT/$(echo "$OLD_GROUP" | tr '.' '/')"
NEW_PATH="$SRC_ROOT/$(echo "$GROUP" | tr '.' '/')"

if [[ -d "$OLD_PATH" && "$OLD_PATH" != "$NEW_PATH" ]]; then
  echo "↪️  Moving $OLD_PATH/* → $NEW_PATH/"
  mkdir -p "$NEW_PATH"
  git mv "$OLD_PATH"/* "$NEW_PATH/" 2>/dev/null || mv "$OLD_PATH"/* "$NEW_PATH/"
  # Clean up empty dirs
  find "$OLD_PATH" -type d -empty -delete || true
fi

###############################################################################
# 5. Rename access widener ----------------------------------------------------
###############################################################################
AW_SRC=src/main/resources/yourmodid.accesswidener
AW_DST=src/main/resources/${MOD_ID}.accesswidener
[[ -f "$AW_SRC" ]] && mv "$AW_SRC" "$AW_DST"

###############################################################################
# 6. Patch GitHub Actions build.yml ------------------------------------------
###############################################################################
BUILD_WF=.github/workflows/build.yml

# a) Update Java matrix (simple regex keeps YAML layout)
sed -i -E "s/(java: *)\[[^]]*\]/\1[$JAVA]/" "$BUILD_WF"

# b) Remove Data-Gen step block if not requested
if [[ "$DATAGEN" != "true" ]]; then
  awk 'BEGIN{skip=0}
       /^ *- name:.*Data Gen/{skip=1;next}
       skip && /^ *- name:/{skip=0}
       !skip' "$BUILD_WF" > "$BUILD_WF.tmp" && mv "$BUILD_WF.tmp" "$BUILD_WF"
fi

# c) Remove chiseledGameTest arg when tests are disabled
[[ "$GAMETESTS" != "true" ]] && sed -i 's/ chiseledGameTest\b//g' "$BUILD_WF"

###############################################################################
# 7. .releaserc.json – update Discord notifier -------------------------------
###############################################################################
if jq -e '.' .releaserc.json >/dev/null 2>&1; then
  jq --arg user "$DISCORD_USER" \
     --arg av   "$DISCORD_AVATAR" \
     --arg slug "$MOD_SLUG" \
     '(.plugins[] | select(type=="array" and .[0]=="semantic-release-discord-notifier")) |=
        (.[1].embedJson.username       = $user   |
         .[1].embedJson.avatar_url     = $av     |
         .[1].embedJson.components[0].components[].url |= gsub("yourmodslug"; $slug))' \
     .releaserc.json > .releaserc.tmp && mv .releaserc.tmp .releaserc.json
else
  echo "⚠️  .releaserc.json not valid JSON – skipped Discord patch"
fi

###############################################################################
# 8. Rename ExampleMod class --------------------------------------------------
###############################################################################
CLASS_NAME=$(echo "$MOD_ID" | sed -E 's/[-_ ]+/ /g' | awk '{for(i=1;i<=NF;i++){printf toupper(substr($i,1,1)) substr($i,2)}}')

find src/main/java -type f \( -name 'ExampleMod.java' -o -name 'ExampleMod.kt' \) | while read -r FILE; do
  EXT="${FILE##*.}"
  DIR=$(dirname "$FILE")
  NEW_FILE="$DIR/${CLASS_NAME}.${EXT}"

  echo "📝  Refactor $(basename "$FILE") → $(basename "$NEW_FILE")"
  git mv "$FILE" "$NEW_FILE" 2>/dev/null || mv "$FILE" "$NEW_FILE"
  # package line
  sed -i "1s/^package .*/package $GROUP;/" "$NEW_FILE"
  # Replace all occurrences of ExampleMod class name with the new class name
  sed -i "s/ExampleMod/$CLASS_NAME/g" "$NEW_FILE"
  # Replace mod ID in @Mod annotation
  sed -i "s/\"examplemod\"/\"$MOD_ID\"/g" "$NEW_FILE"
done

###############################################################################
# 9. Remove bootstrap script from the commit ---------------------------------
###############################################################################
git rm --cached --ignore-unmatch scripts/bootstrap.sh || true

echo -e "\n✅  Template initialised – commit and push generated files."
