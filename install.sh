#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# AkAki CachyOS dotfiles installer
#
# Restores configs from this repository into ~/.config.
# - Never requires sudo/root.
# - Always backs up existing configs before touching them.
# - Idempotent: safe to run multiple times.
# - Never touches anything outside of the specific config
#   directories it manages (never wipes ~/.config wholesale).
# - Does not install packages and does not restart Hyprland.
# ============================================================

# ---------- Basic safety checks ----------

if [[ "${EUID}" -eq 0 ]]; then
  echo "ERROR: Do not run this script as root/sudo." >&2
  echo "It only manages files under your own \$HOME/.config." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$SCRIPT_DIR"
CONFIG_SRC="$REPO_ROOT/config"

if [[ ! -d "$CONFIG_SRC" ]]; then
  echo "ERROR: '$CONFIG_SRC' not found." >&2
  echo "Run this script from inside the cloned dotfiles repository." >&2
  exit 1
fi

# ---------- Validate $HOME before trusting it for anything ----------
# We only guard against obviously broken environments, not a hostile
# local actor who can already modify our own environment variables.
if [[ -z "${HOME:-}" ]]; then
  echo "ERROR: \$HOME is empty or unset. Refusing to continue." >&2
  exit 1
fi
case "$HOME" in
  /*) ;;
  *)
    echo "ERROR: \$HOME ('$HOME') is not an absolute path. Refusing to continue." >&2
    exit 1
    ;;
esac
if [[ ! -d "$HOME" ]]; then
  echo "ERROR: \$HOME ('$HOME') does not exist or is not a directory." >&2
  exit 1
fi

# If $HOME itself is a symlink, treat it the same way we treat a
# symlinked ~/.config below: refuse outright rather than trying to
# transparently resolve through it. This keeps the safety model
# consistent - both of the two paths this script trusts most (HOME and
# ~/.config) must be real, non-symlinked directories.
if [[ -L "$HOME" ]]; then
  echo "ERROR: \$HOME ('$HOME') is a symbolic link. Refusing to continue." >&2
  echo "This installer requires a real (non-symlinked) home directory." >&2
  exit 1
fi

TARGET_HOME="$HOME"
CONFIG_DIR="$TARGET_HOME/.config"
# Includes nanoseconds so two installer runs within the same second
# cannot collide on the same backup directory name.
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S-%N)"
BACKUP_DIR="$TARGET_HOME/.config-backups/$TIMESTAMP"

# If ~/.config itself is a symlink, every path we build under it
# (e.g. $CONFIG_DIR/hypr) resolves inside whatever external location
# that symlink points to. Our own safety checks operate on the literal
# ~/.config/<name> path and deliberately do NOT resolve symlinks
# component-by-component (see safe_remove() below), so they cannot see
# through this case. Rather than trying to handle it "cleverly", we
# refuse outright: this is an unusual enough setup that it deserves a
# manual decision, not an automated one.
if [[ -L "$CONFIG_DIR" ]]; then
  echo "ERROR: '$CONFIG_DIR' is a symbolic link. Refusing to continue." >&2
  echo "This installer only supports a real (non-symlinked) \$HOME/.config directory." >&2
  echo "If this is intentional, resolve or replace the symlink manually, then re-run." >&2
  exit 1
fi

# Canonical (symlink-preserving, "."/".." resolved) reference paths used
# only for safety comparisons in safe_remove(). realpath -m tolerates
# path components that do not exist yet; -s/--no-symlinks means it does
# NOT follow symlinks, so a symlinked ~/.config/hypr is still compared
# by its own literal location, not by whatever it points to.
TARGET_HOME_RESOLVED="$(realpath -ms -- "$TARGET_HOME")"
CONFIG_DIR_RESOLVED="$(realpath -ms -- "$CONFIG_DIR")"

if [[ -z "$CONFIG_DIR_RESOLVED" || "$CONFIG_DIR_RESOLVED" == "/" || "$CONFIG_DIR_RESOLVED" == "$TARGET_HOME_RESOLVED" ]]; then
  echo "ERROR: Resolved config directory looks unsafe: '$CONFIG_DIR_RESOLVED'" >&2
  exit 1
fi

# ---------- Mappings: "src_rel_to_config|dst_rel_to_.config|type" ----------
# type: dir | file
# This array is the single source of truth for what this script is
# allowed to touch under ~/.config. Nothing outside of it is ever read,
# written, removed, or chowned.
MAPPINGS=(
  "hypr|hypr|dir"
  "noctalia|noctalia|dir"
  "kitty|kitty|dir"
  "fish|fish|dir"
  "gtk-3.0|gtk-3.0|dir"
  "gtk-4.0|gtk-4.0|dir"
  "qt5ct|qt5ct|dir"
  "qt6ct|qt6ct|dir"
  "xsettingsd|xsettingsd|dir"
  "fastfetch|fastfetch|dir"
  "kdeglobals|kdeglobals|file"
)

# Whitelist of top-level names under ~/.config that safe_remove() is
# ever allowed to delete. Derived from ALL of MAPPINGS (both "dir" and
# "file" entries) so the two lists cannot drift apart. A managed target
# may be a regular file, a directory, a normal symlink, or a broken
# symlink — safe_remove() treats all four the same way (see below), so
# there is no need to split the whitelist by type.
ALLOWED_REMOVE_NAMES=()
for _entry in "${MAPPINGS[@]}"; do
  IFS='|' read -r _s _d _t <<<"$_entry"
  ALLOWED_REMOVE_NAMES+=("$_d")
done
unset _entry _s _d _t

# ---------- Helpers ----------

log()  { printf '[INFO]  %s\n' "$*"; }
ok()   { printf '[ OK ]  %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }
err()  { printf '[FAIL]  %s\n' "$*" >&2; }

# Refuse to rm -rf anything that is not:
#   (a) a direct child of $CONFIG_DIR, AND
#   (b) explicitly present in ALLOWED_REMOVE_NAMES.
# This is the only place in the script that performs a recursive delete.
# It is used uniformly for every managed target regardless of what
# currently occupies that path: a regular file, a directory, a normal
# symlink, or a broken (dangling) symlink. `rm -rf --` handles all four
# correctly on its own (it deletes a symlink itself rather than
# following it, and a broken symlink is simply removed), so no special
# case is needed per type.
#
# Notes on what this defends against:
# - "../" traversal tricks: realpath -ms lexically resolves "." and ".."
#   components before we compare, so "$CONFIG_DIR/../something" cannot
#   masquerade as being inside $CONFIG_DIR.
# - Symlinks AT the target: -s/--no-symlinks means realpath does NOT
#   follow symlinks, so if ~/.config/hypr is a symlink to
#   /somewhere-important, this function still evaluates the literal
#   path ~/.config/hypr (not the symlink target). rm -rf on a symlink
#   removes only the link itself, never recurses into whatever it
#   points to.
# - Symlinks ABOVE the target (i.e. ~/.config itself being a symlink)
#   are handled separately: the script refuses to start at all in that
#   case (see the ~/.config symlink check earlier), so safe_remove()
#   never has to reason about it.
# - Anything not on the static whitelist (mozilla, zen, YandexMusic,
#   AmneziaVPN.ORG, dconf, pulse, or anything else) is rejected even if
#   it technically lives under ~/.config, because it is not in
#   ALLOWED_REMOVE_NAMES.
# What this does NOT defend against: a local process racing this script
# and swapping the target between the check and the rm -rf (TOCTOU), or
# a hostile actor who already controls this user's environment/shell
# session. That is out of scope for a single-user dotfiles installer;
# treat this as protection against bugs and unexpected environments,
# not against an adversary with existing code execution as you.
safe_remove() {
  local target="$1"
  local resolved
  local relative
  local name

  if [[ -z "$target" ]]; then
    err "Refusing to remove empty path"
    exit 1
  fi

  resolved="$(realpath -ms -- "$target" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    err "Could not resolve path for removal: '$target'"
    exit 1
  fi

  if [[ "$resolved" == "/" || "$resolved" == "$TARGET_HOME_RESOLVED" || "$resolved" == "$CONFIG_DIR_RESOLVED" ]]; then
    err "Refusing to remove suspicious path: '$resolved'"
    exit 1
  fi

  case "$resolved" in
    "$CONFIG_DIR_RESOLVED"/*) ;;
    *)
      err "Refusing to remove path outside of \$HOME/.config: '$resolved'"
      exit 1
      ;;
  esac

  relative="${resolved#"$CONFIG_DIR_RESOLVED"/}"

  # Must be exactly one path segment (a direct child of ~/.config),
  # not a nested path, and must be on the explicit whitelist.
  if [[ "$relative" == */* || -z "$relative" ]]; then
    err "Refusing to remove non-top-level path under \$HOME/.config: '$resolved'"
    exit 1
  fi

  local allowed=0
  for name in "${ALLOWED_REMOVE_NAMES[@]}"; do
    if [[ "$relative" == "$name" ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -ne 1 ]]; then
    err "Refusing to remove path not in the managed whitelist: '$resolved'"
    exit 1
  fi

  rm -rf -- "$target"
}

# ---------- Detect environment ----------

log "Repository root: $REPO_ROOT"
log "Target home:     $TARGET_HOME"
log "Target config:   $CONFIG_DIR"
log "Backup location: $BACKUP_DIR"
echo

log "Checking for expected tools (informational only, nothing will be installed automatically):"
REQUIRED_BINS=(Hyprland uwsm noctalia kitty fish qt5ct qt6ct xsettingsd)
MISSING_BINS=()
for bin in "${REQUIRED_BINS[@]}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    ok "found: $bin"
  else
    warn "not found in PATH: $bin"
    MISSING_BINS+=("$bin")
  fi
done
echo

if [[ ${#MISSING_BINS[@]} -gt 0 ]]; then
  warn "The following tools were not detected: ${MISSING_BINS[*]}"
  warn "This script will NOT install them automatically."
  warn "Install manually (e.g. via pacman/AUR) if you need them."
  echo
fi

# ---------- Show plan ----------

log "The following will be restored from '$CONFIG_SRC' into '$CONFIG_DIR':"
for entry in "${MAPPINGS[@]}"; do
  IFS='|' read -r src_rel dst_rel _ <<<"$entry"
  src_path="$CONFIG_SRC/$src_rel"
  if [[ -e "$src_path" ]]; then
    printf '  - config/%s  ->  ~/.config/%s\n' "$src_rel" "$dst_rel"
  else
    printf '  - config/%s  ->  (skipped, not present in repository)\n' "$src_rel"
  fi
done
echo
log "Any existing targets will be backed up to: $BACKUP_DIR"
echo

read -r -p "Continue? [y/N] " answer
case "$answer" in
  [yY][eE][sS]|[yY]) ;;
  *)
    log "Aborted by user. No changes were made."
    exit 0
    ;;
esac
echo

# Everything above this point is read-only (checks, planning, prompt).
# Only after explicit confirmation do we create directories or touch
# anything on disk.
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"

mkdir -p "$CONFIG_DIR"

# The parent "~/.config-backups" directory is allowed (and expected) to
# already exist across runs, so this uses -p. This is safe and does not
# weaken the guarantee below: -p only creates missing parent components,
# it does not touch BACKUP_DIR itself if BACKUP_DIR already existed, and
# in that case the plain "mkdir" right after would still fail.
mkdir -p "$TARGET_HOME/.config-backups"

# Deliberately NOT mkdir -p here: BACKUP_DIR must be a brand-new,
# uniquely-timestamped directory for this run. If it already exists
# (which should be effectively impossible given the nanosecond-precision
# TIMESTAMP above, but is checked anyway), mkdir fails and set -e halts
# the script rather than silently reusing/merging into a stale backup
# directory from a previous run.
mkdir "$BACKUP_DIR"

# ---------- Install ----------

for entry in "${MAPPINGS[@]}"; do
  IFS='|' read -r src_rel dst_rel _ <<<"$entry"
  src_path="$CONFIG_SRC/$src_rel"
  dst_path="$CONFIG_DIR/$dst_rel"

  if [[ ! -e "$src_path" ]]; then
    warn "Skipping '$src_rel' (not present in repository)"
    continue
  fi

  # -e is false for a broken (dangling) symlink, so we must also check
  # -L to detect "something is here" in every case: existing regular
  # file, existing directory, normal symlink, or broken symlink. This
  # single check drives both the backup step and the removal step
  # below, so the two can never disagree about whether a target exists.
  if [[ -e "$dst_path" || -L "$dst_path" ]]; then
    backup_target="$BACKUP_DIR/$dst_rel"
    mkdir -p "$(dirname "$backup_target")"
    log "Backing up ~/.config/$dst_rel -> $backup_target"
    cp -a -- "$dst_path" "$backup_target"

    # Every managed target is safely removed before copying, regardless
    # of whether it is currently a file, a directory, a symlink, or a
    # broken symlink. This guarantees cp -a always writes into a path
    # that does not exist yet, so it never "writes through" an existing
    # symlink or silently merges into a stale directory.
    safe_remove "$dst_path"
  fi

  mkdir -p "$(dirname "$dst_path")"

  log "Copying config/$src_rel -> ~/.config/$dst_rel"
  cp -a -- "$src_path" "$dst_path"

  chown -R -- "$CURRENT_UID:$CURRENT_GID" "$dst_path"
done

echo
log "Copy phase complete."
echo

# ---------- Verification ----------

VERIFY_FILES=(
  "$CONFIG_DIR/hypr/hyprland.lua"
  "$CONFIG_DIR/hypr/config/binds.lua"
  "$CONFIG_DIR/hypr/config/inputs.lua"
  "$CONFIG_DIR/hypr/config/monitors.lua"
  "$CONFIG_DIR/hypr/config/workspaces.lua"
  "$CONFIG_DIR/hypr/config/decorations.lua"
  "$CONFIG_DIR/hypr/config/colors.lua"
  "$CONFIG_DIR/hypr/xdph.conf"
  "$CONFIG_DIR/noctalia/config.toml"
  "$CONFIG_DIR/kitty/kitty.conf"
  "$CONFIG_DIR/fish/config.fish"
  "$CONFIG_DIR/qt6ct/qt6ct.conf"
  "$CONFIG_DIR/xsettingsd/xsettingsd.conf"
  "$CONFIG_DIR/kdeglobals"
)

log "Running verification checks:"
VERIFY_FAILED=0
for f in "${VERIFY_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    ok "$f"
  else
    err "MISSING: $f"
    VERIFY_FAILED=1
  fi
done
echo

if [[ "$VERIFY_FAILED" -ne 0 ]]; then
  err "One or more expected configuration files are missing after installation."
  err "Your previous configuration (if any existed) was backed up here:"
  err "  $BACKUP_DIR"
  err "Nothing beyond the managed directories was touched; inspect manually before retrying."
  exit 1
fi

ok "All expected configuration files are present."
echo
log "Installation finished successfully."
log "Backup of previous configuration (if any existed) is at:"
log "  $BACKUP_DIR"
echo
log "Hyprland was NOT restarted automatically. Log out/in or restart it manually when ready."

exit 0
