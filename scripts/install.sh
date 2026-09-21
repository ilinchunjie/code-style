#!/bin/sh
# code-style installer. Remote: curl -fsSL <raw-url> | sh
# Env: CODE_STYLE_TARGET, CODE_STYLE_AGENTS, CODE_STYLE_LANGUAGES, CODE_STYLE_UNINSTALL
set -eu

REPO_DEFAULT="ilinchunjie/code-style"
REF_DEFAULT="main"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_local_root() {
  script_path=$0
  if [ ! -f "$script_path" ]; then
    if [ -f "$(pwd)/$script_path" ]; then
      script_path=$(pwd)/$script_path
    else
      return 1
    fi
  fi

  script_dir=$(CDPATH= cd -- "$(dirname -- "$script_path")" && pwd) || return 1
  candidate=$(CDPATH= cd -- "$script_dir/.." && pwd) || return 1
  if [ -f "$candidate/manifest.json" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  return 1
}

download_repo() {
  zip_uri="https://github.com/${REPO_DEFAULT}/archive/refs/heads/${REF_DEFAULT}.zip"
  zip_path=$1
  extract_path=$2

  token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
  printf '正在下载 %s\n' "$zip_uri"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$token" ]; then
      curl -fsSL -A code-style-installer -H "Authorization: Bearer $token" "$zip_uri" -o "$zip_path" ||
        die "下载失败。若仓库为私有，请设置 GH_TOKEN；公开仓库请确认 main 分支存在。"
    else
      curl -fsSL -A code-style-installer "$zip_uri" -o "$zip_path" ||
        die "下载失败。若仓库为私有，请设置 GH_TOKEN；公开仓库请确认 main 分支存在。"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$token" ]; then
      wget -q -O "$zip_path" --user-agent=code-style-installer --header="Authorization: Bearer $token" "$zip_uri" ||
        die "下载失败。若仓库为私有，请设置 GH_TOKEN；公开仓库请确认 main 分支存在。"
    else
      wget -q -O "$zip_path" --user-agent=code-style-installer "$zip_uri" ||
        die "下载失败。若仓库为私有，请设置 GH_TOKEN；公开仓库请确认 main 分支存在。"
    fi
  else
    die "需要 curl 或 wget 才能远程安装"
  fi

  mkdir -p "$extract_path"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip_path" -d "$extract_path"
  else
    die "需要 unzip 才能远程安装"
  fi
}

find_source_root() {
  extract_path=$1
  manifest=$(find "$extract_path" -name manifest.json -type f | head -n 1)
  if [ -z "$manifest" ]; then
    die "下载的仓库中没有 manifest.json"
  fi
  CDPATH= cd -- "$(dirname -- "$manifest")" && pwd
}

json_get_common() {
  manifest=$1
  field=$2
  awk -v field="$field" '
    BEGIN { in_common = 0 }
    /"common"/ { in_common = 1 }
    in_common && $0 ~ "\"" field "\"" {
      split($0, a, "\"")
      for (i = 1; i <= length(a); i++) {
        if (a[i] == field && i + 2 <= length(a)) {
          print a[i + 2]
          exit
        }
      }
    }
  ' "$manifest"
}

json_list_languages() {
  manifest=$1
  awk '
    BEGIN { in_lang = 0; id = "" }
    /"languages"/ { in_lang = 1; next }
    in_lang {
      if ($0 ~ /"id"/) {
        split($0, a, "\"")
        for (i = 1; i <= length(a); i++) {
          if (a[i] == "id" && i + 2 <= length(a)) {
            id = a[i + 2]
          }
        }
      }
      if ($0 ~ /"path"/ && id != "") {
        split($0, a, "\"")
        for (i = 1; i <= length(a); i++) {
          if (a[i] == "path" && i + 2 <= length(a)) {
            print id "\t" a[i + 2]
            id = ""
          }
        }
      }
    }
  ' "$manifest"
}

json_get_string() {
  manifest=$1
  field=$2
  awk -v field="$field" '
    $0 ~ "\"" field "\"" {
      split($0, a, "\"")
      for (i = 1; i <= length(a); i++) {
        if (a[i] == field && i + 2 <= length(a)) {
          print a[i + 2]
          exit
        }
      }
    }
  ' "$manifest"
}

split_csv() {
  value=$1
  printf '%s\n' "$value" | tr ',' '\n' | while IFS= read -r item; do
    item=$(to_lower "$(trim "$item")")
    if [ -n "$item" ]; then
      printf '%s\n' "$item"
    fi
  done
}

contains_line() {
  needle=$1
  printf '%s\n' "$2" | grep -Fx "$needle" >/dev/null 2>&1
}

get_commit() {
  source_root=$1
  repo=$2
  ref=$3

  if [ -d "$source_root/.git" ] && command -v git >/dev/null 2>&1; then
    sha=$(git -C "$source_root" rev-parse HEAD 2>/dev/null || true)
    if [ -n "$sha" ]; then
      printf '%s' "$sha"
      return
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    sha=$(curl -fsSL -A code-style-installer "https://api.github.com/repos/${repo}/commits/${ref}" 2>/dev/null | awk -F '"' '/"sha"/ { print $4; exit }' || true)
    if [ -n "$sha" ]; then
      printf '%s' "$sha"
      return
    fi
  fi

  printf '%s' "unknown"
}

copy_skill() {
  source=$1
  dest_root=$2
  skill_id=$3
  dest="$dest_root/$skill_id"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$source/." "$dest/"
}

write_state() {
  target=$1
  repo=$2
  ref=$3
  commit=$4
  mode=$5
  agents=$6
  skills=$7
  languages=$8
  installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  state_path="$target/.code-style.json"

  agents_json=$(printf '%s\n' "$agents" | awk 'NF { printf "%s\"%s\"", (n++ ? ", " : ""), $0 }')
  skills_json=$(printf '%s\n' "$skills" | awk 'NF { printf "%s\"%s\"", (n++ ? ", " : ""), $0 }')
  languages_json=$(printf '%s\n' "$languages" | awk 'NF { printf "%s\"%s\"", (n++ ? ", " : ""), $0 }')

  cat >"$state_path" <<EOF
{
  "repo": "$repo",
  "ref": "$ref",
  "commit": "$commit",
  "installedAt": "$installed_at",
  "mode": "$mode",
  "agents": [$agents_json],
  "skills": [$skills_json],
  "languages": [$languages_json]
}
EOF
}

destinations_from_agents() {
  target=$1
  agents=$2
  wrote=
  if contains_line cursor "$agents" || contains_line codex "$agents"; then
    printf '%s\n' "$target/.agents/skills"
    wrote=1
  fi
  if contains_line claude "$agents"; then
    printf '%s\n' "$target/.claude/skills"
    wrote=1
  fi
  if [ -z "$wrote" ]; then
    die "没有可写入的 Agent 目录。CODE_STYLE_AGENTS 只能包含 cursor、claude、codex。"
  fi
}

json_list_skills() {
  state_path=$1
  awk '
    /"skills"/ { in_arr = 1 }
    in_arr {
      while (match($0, /"[^"]+"/)) {
        value = substr($0, RSTART + 1, RLENGTH - 2)
        $0 = substr($0, RSTART + RLENGTH)
        if (value != "skills") {
          print value
        }
      }
      if ($0 ~ /]/) {
        exit
      }
    }
  ' "$state_path"
}

json_list_agents() {
  state_path=$1
  awk '
    /"agents"/ { in_arr = 1 }
    in_arr {
      while (match($0, /"[^"]+"/)) {
        value = substr($0, RSTART + 1, RLENGTH - 2)
        $0 = substr($0, RSTART + RLENGTH)
        if (value != "agents") {
          print value
        }
      }
      if ($0 ~ /]/) {
        exit
      }
    }
  ' "$state_path"
}

uninstall_code_style() {
  target=$1
  default_agents=$2
  state_path="$target/.code-style.json"
  skill_ids="code-style-common"
  agents=$default_agents

  if [ -f "$state_path" ]; then
    skill_ids=$(json_list_skills "$state_path")
    listed_agents=$(json_list_agents "$state_path")
    if [ -n "$listed_agents" ]; then
      agents=$listed_agents
    fi
  else
    printf '%s\n' "未找到 .code-style.json，将只删除 code-style-common。"
  fi

  destinations_from_agents "$target" "$agents" | while IFS= read -r root; do
    printf '%s\n' "$skill_ids" | while IFS= read -r id; do
      [ -n "$id" ] || continue
      skill_dir="$root/$id"
      if [ -e "$skill_dir" ]; then
        rm -rf "$skill_dir"
        printf '已删除 %s\n' "$skill_dir"
      fi
    done
  done

  if [ -f "$state_path" ]; then
    rm -f "$state_path"
    printf '已删除 %s\n' "$state_path"
  fi

  printf '%s\n' "卸载完成。"
}

TARGET=${CODE_STYLE_TARGET:-$(pwd)}
case "$TARGET" in
  /*) ;;
  *) TARGET=$(CDPATH= cd -- "$TARGET" && pwd) ;;
esac

AGENTS=$(split_csv "${CODE_STYLE_AGENTS:-cursor,claude,codex}")
OLDIFS=$IFS
IFS='
'
for agent in $AGENTS; do
  case "$agent" in
    cursor|claude|codex) ;;
    *) die "不支持的 Agent: $agent。可选: cursor, claude, codex" ;;
  esac
done
IFS=$OLDIFS

if [ "${CODE_STYLE_UNINSTALL:-}" = "1" ]; then
  uninstall_code_style "$TARGET" "$AGENTS"
  exit 0
fi

cleanup() {
  if [ -n "${ZIP_PATH:-}" ] && [ -f "$ZIP_PATH" ]; then
    rm -f "$ZIP_PATH"
  fi
  if [ -n "${EXTRACT_PATH:-}" ] && [ -d "$EXTRACT_PATH" ]; then
    rm -rf "$EXTRACT_PATH"
  fi
}
trap cleanup EXIT

MODE=local
if SOURCE_ROOT=$(resolve_local_root); then
  :
else
  MODE=remote
  ZIP_PATH=${TMPDIR:-/tmp}/code-style-$$.zip
  EXTRACT_PATH=${TMPDIR:-/tmp}/code-style-$$
  download_repo "$ZIP_PATH" "$EXTRACT_PATH"
  SOURCE_ROOT=$(find_source_root "$EXTRACT_PATH")
fi

MANIFEST="$SOURCE_ROOT/manifest.json"
[ -f "$MANIFEST" ] || die "未找到 manifest.json: $MANIFEST"

COMMON_ID=$(json_get_common "$MANIFEST" id)
COMMON_PATH_REL=$(json_get_common "$MANIFEST" path)
REPO=$(json_get_string "$MANIFEST" repo)
REF=$(json_get_string "$MANIFEST" ref)
[ -n "$COMMON_ID" ] || COMMON_ID=code-style-common
[ -n "$COMMON_PATH_REL" ] || COMMON_PATH_REL=plugins/code-style-common/skills/code-style-common
[ -n "$REPO" ] || REPO=$REPO_DEFAULT
[ -n "$REF" ] || REF=$REF_DEFAULT

COMMON_PATH="$SOURCE_ROOT/$COMMON_PATH_REL"
[ -d "$COMMON_PATH" ] || die "公共 skill 不存在: $COMMON_PATH"

LANG_FILTER=$(split_csv "${CODE_STYLE_LANGUAGES:-}")
LANG_TABLE=$(json_list_languages "$MANIFEST")

SKILL_IDS=$COMMON_ID
SKILL_PATHS=$COMMON_PATH
LANG_IDS=

SELECTED_LANGS=$LANG_TABLE
if [ -n "$LANG_FILTER" ]; then
  SELECTED_LANGS=$(printf '%s\n' "$LANG_TABLE" | awk -F '\t' -v filter="$(printf '%s' "$LANG_FILTER" | tr '\n' ' ')" '
    BEGIN {
      n = split(filter, f, " ")
      for (i = 1; i <= n; i++) {
        if (f[i] != "") wanted[f[i]] = 1
      }
    }
    {
      id = $1
      key = id
      sub(/^code-style-/, "", key)
      if (wanted[id] || wanted[key]) print $0
    }
  ')
  missing=$(printf '%s\n' "$LANG_FILTER" | awk -v table="$SELECTED_LANGS" '
    BEGIN {
      n = split(table, rows, "\n")
      for (i = 1; i <= n; i++) {
        split(rows[i], cols, "\t")
        id = cols[1]
        key = id
        sub(/^code-style-/, "", key)
        have[id] = 1
        have[key] = 1
      }
    }
    NF && !have[$0] { print $0 }
  ')
  if [ -n "$missing" ]; then
    if [ -z "$LANG_TABLE" ]; then
      die "manifest.json 中没有语言包，无法安装: $(printf '%s' "$missing" | tr '\n' ' ')"
    fi
    die "未知语言包: $(printf '%s' "$missing" | tr '\n' ' ')"
  fi
fi

if [ -n "$SELECTED_LANGS" ]; then
  while IFS="$(printf '\t')" read -r lang_id lang_rel; do
    [ -n "$lang_id" ] || continue
    lang_path="$SOURCE_ROOT/$lang_rel"
    [ -d "$lang_path" ] || die "语言 skill 不存在: $lang_path"
    SKILL_IDS="$SKILL_IDS
$lang_id"
    SKILL_PATHS="$SKILL_PATHS
$lang_path"
    lang_key=$lang_id
    lang_key=${lang_key#code-style-}
    LANG_IDS="$LANG_IDS
$lang_key"
  done <<EOF
$SELECTED_LANGS
EOF
fi

DESTS=$(destinations_from_agents "$TARGET" "$AGENTS")

skill_ids_clean=$(printf '%s\n' "$SKILL_IDS" | sed '/^$/d')
skill_paths_clean=$(printf '%s\n' "$SKILL_PATHS" | sed '/^$/d')

printf '%s\n' "$DESTS" | while IFS= read -r dest; do
  mkdir -p "$dest"
  i=0
  printf '%s\n' "$skill_ids_clean" | while IFS= read -r skill_id; do
    i=$((i + 1))
    skill_path=$(printf '%s\n' "$skill_paths_clean" | sed -n "${i}p")
    copy_skill "$skill_path" "$dest" "$skill_id"
    printf '已安装 %s -> %s\n' "$skill_id" "$dest"
  done
done

COMMIT=$(get_commit "$SOURCE_ROOT" "$REPO" "$REF")
write_state "$TARGET" "$REPO" "$REF" "$COMMIT" "$MODE" "$AGENTS" "$skill_ids_clean" "$(printf '%s\n' "$LANG_IDS" | sed '/^$/d')"

printf '安装完成（%s）。状态写入 %s\n' "$MODE" "$TARGET/.code-style.json"
