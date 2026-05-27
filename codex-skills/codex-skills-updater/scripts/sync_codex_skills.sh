#!/usr/bin/env bash
set -euo pipefail

repo_path=""
skills_dir=""
refresh_links=0
no_pull=0
autostash_pull=0
max_depth=4

usage() {
  cat <<'EOF'
Usage: sync_codex_skills.sh [options]

Options:
  --repo PATH         Explicit codex-skills repo path
  --skills-dir PATH   Explicit Codex skills directory
  --refresh-links     Repoint symlinks that target a different source path
  --no-pull           Skip git fetch/pull
  --autostash-pull    Stash local changes, pull with --ff-only, then re-apply stash
  --max-depth N       Max home-directory search depth for auto-discovery (default: 4)
  -h, --help          Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo_path="${2:-}"; shift 2 ;;
    --skills-dir)
      skills_dir="${2:-}"; shift 2 ;;
    --refresh-links)
      refresh_links=1; shift ;;
    --no-pull)
      no_pull=1; shift ;;
    --autostash-pull)
      autostash_pull=1; shift ;;
    --max-depth)
      max_depth="${2:-4}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

abs_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  else
    (cd "$p" && pwd -P)
  fi
}

is_codex_repo() {
  local p="$1"
  [[ -d "$p/.git" && -f "$p/README.md" ]]
}

discover_repo() {
  local candidates=()
  if is_codex_repo "$PWD"; then candidates+=("$PWD"); fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    if is_codex_repo "$git_root"; then candidates+=("$git_root"); fi
  fi

  for p in "$HOME/git/codex-skills" "$HOME/src/codex-skills" "$HOME/code/codex-skills"; do
    if is_codex_repo "$p"; then candidates+=("$p"); fi
  done

  while IFS= read -r p; do
    if is_codex_repo "$p"; then candidates+=("$p"); fi
  done < <(find "$HOME" -maxdepth "$max_depth" -type d -name codex-skills 2>/dev/null || true)

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  local uniq=()
  local seen=$'\n'
  for c in "${candidates[@]}"; do
    c="$(abs_path "$c")"
    if [[ "$seen" != *$'\n'"$c"$'\n'* ]]; then
      uniq+=("$c")
      seen+="$c"$'\n'
    fi
  done

  local newest="${uniq[0]}"
  local newest_mtime=0
  for c in "${uniq[@]}"; do
    local mtime
    mtime="$(stat -c %Y "$c" 2>/dev/null || echo 0)"
    if [[ "$mtime" -gt "$newest_mtime" ]]; then
      newest="$c"
      newest_mtime="$mtime"
    fi
  done

  echo "$newest"
}

if [[ -z "$repo_path" ]]; then
  if ! repo_path="$(discover_repo)"; then
    echo "Could not auto-discover a codex-skills repo. Use --repo PATH." >&2
    exit 1
  fi
fi

repo_path="$(abs_path "$repo_path")"
if ! is_codex_repo "$repo_path"; then
  echo "Invalid repo path: $repo_path" >&2
  exit 1
fi

if [[ -z "$skills_dir" ]]; then
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  skills_dir="$codex_home/skills"
fi

mkdir -p "$skills_dir"
skills_dir="$(abs_path "$skills_dir")"

echo "Repo path:   $repo_path"
echo "Skills dir:  $skills_dir"

if [[ "$no_pull" -eq 0 ]]; then
  if [[ -n "$(git -C "$repo_path" status --porcelain)" ]]; then
    if [[ "$autostash_pull" -eq 1 ]]; then
      stash_msg="codex-skills-updater-autostash-$(date +%Y%m%d-%H%M%S)"
      echo "Working tree is dirty; attempting autostash pull."
      git -C "$repo_path" stash push -u -m "$stash_msg"
      echo "Fetching latest changes..."
      git -C "$repo_path" fetch --all --prune
      echo "Pulling with --ff-only..."
      git -C "$repo_path" pull --ff-only
      if git -C "$repo_path" stash list | grep -F "$stash_msg" >/dev/null 2>&1; then
        echo "Re-applying stashed changes..."
        if ! git -C "$repo_path" stash pop; then
          echo
          echo "Autostash re-apply had conflicts. Your stash entry is still available."
          echo "To resolve:"
          echo "  1) cd \"$repo_path\""
          echo "  2) git status"
          echo "  3) resolve conflict markers in files, then git add <resolved-files>"
          echo "  4) git commit -m \"Resolve autostash conflicts\" (or keep changes uncommitted)"
          echo "  5) if needed, inspect stash entries with: git stash list"
        fi
      fi
    else
      echo "Working tree is dirty; skipping pull."
      echo "Tip: rerun with --autostash-pull to stash local changes, pull safely, then re-apply."
    fi
  else
    echo "Fetching latest changes..."
    git -C "$repo_path" fetch --all --prune
    echo "Pulling with --ff-only..."
    git -C "$repo_path" pull --ff-only
  fi
fi

mapfile -t skill_dirs < <(
  find "$repo_path" -mindepth 1 -maxdepth 1 -type d -print | while read -r d; do
    if [[ -f "$d/SKILL.md" ]]; then
      basename "$d"
    fi
  done | sort
)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  echo "No skill folders (with SKILL.md) found in $repo_path"
  exit 1
fi

created=0
updated=0
unchanged=0
skipped=0

for name in "${skill_dirs[@]}"; do
  src="$repo_path/$name"
  dst="$skills_dir/$name"
  src_abs="$(abs_path "$src")"

  if [[ -L "$dst" ]]; then
    link_target="$(readlink "$dst" || true)"
    if [[ "$link_target" == "$src_abs" || "$link_target" == "$src" ]]; then
      unchanged=$((unchanged + 1))
      echo "[ok] $name already linked"
    elif [[ "$refresh_links" -eq 1 ]]; then
      rm "$dst"
      ln -s "$src_abs" "$dst"
      updated=$((updated + 1))
      echo "[updated] $name -> $src_abs"
    else
      skipped=$((skipped + 1))
      echo "[skip] $name has different symlink target ($link_target). Use --refresh-links to repoint."
    fi
  elif [[ -e "$dst" ]]; then
    skipped=$((skipped + 1))
    echo "[skip] $name destination exists and is not a symlink: $dst"
  else
    ln -s "$src_abs" "$dst"
    created=$((created + 1))
    echo "[created] $name -> $src_abs"
  fi
done

echo
echo "Sync summary:"
echo "  created:   $created"
echo "  updated:   $updated"
echo "  unchanged: $unchanged"
echo "  skipped:   $skipped"
