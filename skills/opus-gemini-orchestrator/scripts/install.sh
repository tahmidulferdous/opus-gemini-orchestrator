#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
skills_parent="$(cd "$SKILL_DIR/.." && pwd -P)"
PACK_SKILLS=(opus-gemini-orchestrator opus-gemini-lite opus-gemini-mid opus-gemini-full opus-gemini-deepresearch opus-sonnet opus-solo)

agy_permissions=0
uninstall=0

for arg in "$@"; do
  case "$arg" in
    --agy-permissions)
      agy_permissions=1
      ;;
    --uninstall)
      uninstall=1
      ;;
    -h|--help)
      echo "Usage: bash install.sh [--agy-permissions] [--uninstall]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: bash install.sh [--agy-permissions] [--uninstall]" >&2
      exit 1
      ;;
  esac
done

if [[ $uninstall -eq 1 ]]; then
  # 1. Remove bin symlinks only if pointing into SKILL_DIR
  for b in gdo gtask gresearch; do
    bin_path="$HOME/.local/bin/$b"
    if [[ -L "$bin_path" ]]; then
      target="$(readlink "$bin_path" || true)"
      resolved="$(readlink -f "$bin_path" 2>/dev/null || true)"
      if [[ "$target" == "$SKILL_DIR"/* ]] || [[ "$resolved" == "$SKILL_DIR"/* ]]; then
        rm "$bin_path"
        echo "Removed: $bin_path"
      fi
    fi
  done

  # 2. Remove skills symlinks pointing into skills_parent (only for PACK_SKILLS)
  if [[ -d "$HOME/.claude/skills" ]]; then
    for skill_name in "${PACK_SKILLS[@]}"; do
      skill_path="$HOME/.claude/skills/$skill_name"
      if [[ -L "$skill_path" ]]; then
        target="$(readlink "$skill_path" || true)"
        resolved="$(readlink -f "$skill_path" 2>/dev/null || true)"
        if [[ "$target" == "$skills_parent"/* ]] || [[ "$resolved" == "$skills_parent"/* ]]; then
          rm "$skill_path"
          echo "Removed: $skill_path"
        fi
      fi
    done
  fi

  # 3. Back up settings.json and remove exec-mode-hook.sh from UserPromptSubmit hooks
  settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "missing: jq" >&2
      exit 1
    fi
    hook_count="$(jq '[.. | .command? // empty | select(type == "string" and contains("exec-mode-hook.sh"))] | length' "$settings_file" 2>/dev/null || echo 0)"
    if [[ "$hook_count" -gt 0 ]]; then
      cp "$settings_file" "$settings_file.bak-$(date +%Y%m%d%H%M%S)"
      tmp_settings="$(mktemp "$settings_file.tmp.XXXXXX")"
      jq '
        if .hooks?.UserPromptSubmit then
          .hooks.UserPromptSubmit = [
            .hooks.UserPromptSubmit[] |
            if .hooks then
              .hooks = [.hooks[] | select((.command? // "" | contains("exec-mode-hook.sh")) | not)]
            else
              .
            end |
            select(.hooks == null or (.hooks | length > 0))
          ]
        else
          .
        end
      ' "$settings_file" > "$tmp_settings"
      mv "$tmp_settings" "$settings_file"
      echo "Removed: exec-mode-hook.sh hook from $settings_file"
    fi
  fi

  exit 0
fi

# Install (default)
# 1. Dependency check
missing_jq=0
for dep in agy jq sqlite3 python3 git; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "missing: $dep"
    if [[ "$dep" == "jq" ]]; then
      missing_jq=1
    fi
  fi
done

if [[ $missing_jq -eq 1 ]]; then
  exit 1
fi

# 2. Bin symlinks
mkdir -p "$HOME/.local/bin"
chmod +x "$SKILL_DIR"/bin/*
ln -sfn "$SKILL_DIR/bin/gdo" "$HOME/.local/bin/gdo"
ln -sfn "$SKILL_DIR/bin/gtask" "$HOME/.local/bin/gtask"
ln -sfn "$SKILL_DIR/bin/gresearch" "$HOME/.local/bin/gresearch"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "warning: $HOME/.local/bin is not in PATH" ;;
esac

# 3. Skills symlinks
mkdir -p "$HOME/.claude/skills"
for skill_name in "${PACK_SKILLS[@]}"; do
  skill_dir="$skills_parent/$skill_name"
  if [[ -f "$skill_dir/SKILL.md" ]]; then
    target="$HOME/.claude/skills/$skill_name"
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      ln -s "$skill_dir" "$target"
    fi
  fi
done

# 4. Settings hook
mkdir -p "$HOME/.claude"
settings_file="$HOME/.claude/settings.json"
if [[ ! -f "$settings_file" || ! -s "$settings_file" ]]; then
  echo "{}" > "$settings_file"
fi

hook_count="$(jq '[.. | .command? // empty | select(type == "string" and contains("exec-mode-hook.sh"))] | length' "$settings_file" 2>/dev/null || echo 0)"
if [[ "$hook_count" -eq 0 ]]; then
  cp "$settings_file" "$settings_file.bak-$(date +%Y%m%d%H%M%S)"
  tmp_settings="$(mktemp "$settings_file.tmp.XXXXXX")"
  jq --arg cmd "$SKILL_DIR/bin/exec-mode-hook.sh" '
    .hooks = (.hooks // {}) |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks":[{"type":"command","command":$cmd,"timeout":10}]}])
  ' "$settings_file" > "$tmp_settings"
  mv "$tmp_settings" "$settings_file"
fi

# 5. Exec mode
exec_mode_file="$HOME/.claude/exec-mode"
if [[ ! -e "$exec_mode_file" && ! -L "$exec_mode_file" ]]; then
  echo "gemini-full" > "$exec_mode_file"
fi

# 6. Agy permissions (optional)
if [[ $agy_permissions -eq 1 ]]; then
  agy_dir="$HOME/.gemini/antigravity-cli"
  agy_settings="$agy_dir/settings.json"
  mkdir -p "$agy_dir"
  if [[ ! -f "$agy_settings" || ! -s "$agy_settings" ]]; then
    echo "{}" > "$agy_settings"
  fi
  cp "$agy_settings" "$agy_settings.bak-$(date +%Y%m%d%H%M%S)"

  allow_commands=(
    git ls pwd cd cat head tail grep rg find wc diff echo mkdir cp mv
    touch sort uniq sed awk tr cut file stat tree which jq printf basename dirname realpath du date
    seq od nl column python python3 pytest pip uv node npm npx pnpm tsc make cargo go
  )
  allow_json="$(jq -cn --args '[$ARGS.positional[] | "command(\(.))"] + ["read_url(*)"]' "${allow_commands[@]}")"
  deny_json="$(jq -cn '["command(sudo)", "command(rm)", "command(curl)", "command(wget)", "command(git push)", "command(git reset)"]')"

  tmp_agy="$(mktemp "$agy_settings.tmp.XXXXXX")"
  jq --argjson allow "$allow_json" --argjson deny "$deny_json" '
    .permissions = (.permissions // {}) |
    .permissions.allow = (((.permissions.allow // []) + $allow) | unique) |
    .permissions.deny = (((.permissions.deny // []) + $deny) | unique)
  ' "$agy_settings" > "$tmp_agy"
  mv "$tmp_agy" "$agy_settings"

  echo "Add read_file(<project root>/) and write_file(<project root>/) rules for each folder Gemini may work in."
fi

# 7. Next steps
cat << 'EOF'

Next steps:
1. Restart Claude Code.
2. Pick a mode with /opus-gemini-full, /opus-gemini-mid, or /opus-gemini-lite.
EOF
