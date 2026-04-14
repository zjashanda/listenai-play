#!/usr/bin/env bash
set -euo pipefail

BEGIN_MARKER="# >>> laid >>>"
END_MARKER="# <<< laid <<<"

read -r -d '' LAID_BLOCK <<'EOF' || true
# >>> laid >>>
laid_stream_channels() {
  local card="$1"
  local section="$2"
  local file value

  for file in /proc/asound/card"${card}"/stream*; do
    [ -f "$file" ] || continue
    value="$(
      awk -v section="$section" '
        BEGIN { in_section = 0; max_channels = 0 }
        /^[A-Za-z][A-Za-z ]*:/ {
          if ($0 == section ":") {
            in_section = 1
            next
          }
          if (in_section) {
            in_section = 0
          }
        }
        in_section && $1 == "Channels:" {
          if (($2 + 0) > max_channels) {
            max_channels = $2 + 0
          }
        }
        END {
          if (max_channels > 0) {
            print max_channels
          }
        }
      ' "$file"
    )"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  printf '?\n'
}

laid() {
  local found=0
  local dev props vid pid token card name key playback_channels capture_channels

  printf '%-9s %-36s %-10s %-8s %s\n' "Direction" "DeviceKey" "Card" "Channels" "Name"
  for dev in /dev/snd/controlC*; do
    [ -e "$dev" ] || continue

    props="$(udevadm info -q property -n "$dev" 2>/dev/null || true)"
    [ -n "$props" ] || continue

    vid="$(printf '%s\n' "$props" | awk -F= '/^ID_VENDOR_ID=/{print toupper($2); exit}')"
    pid="$(printf '%s\n' "$props" | awk -F= '/^ID_MODEL_ID=/{print toupper($2); exit}')"
    [ -n "$vid" ] && [ -n "$pid" ] || continue

    token="$(printf '%s\n' "$props" | awk -F= '/^ID_SERIAL_SHORT=/{print toupper($2); exit}')"
    if [ -z "$token" ]; then
      token="$(printf '%s\n' "$props" | awk -F= '/^ID_PATH_TAG=/{print toupper($2); exit}')"
    fi
    if [ -z "$token" ]; then
      card="${dev##*controlC}"
      token="CARD${card}"
    fi

    card="${dev##*controlC}"
    name="$(cat "/proc/asound/card${card}/id" 2>/dev/null || true)"
    key="VID_${vid}&PID_${pid}:${token}"
    playback_channels="$(laid_stream_channels "$card" "Playback")"
    capture_channels="$(laid_stream_channels "$card" "Capture")"

    if [ "$playback_channels" != "?" ]; then
      printf '%-9s %-36s %-10s %-8s %s\n' "Render" "$key" "card${card}" "$playback_channels" "${name:-unknown}"
      found=1
    fi
    if [ "$capture_channels" != "?" ]; then
      printf '%-9s %-36s %-10s %-8s %s\n' "Capture" "$key" "card${card}" "$capture_channels" "${name:-unknown}"
      found=1
    fi
    if [ "$playback_channels" = "?" ] && [ "$capture_channels" = "?" ]; then
      printf '%-9s %-36s %-10s %-8s %s\n' "Unknown" "$key" "card${card}" "?" "${name:-unknown}"
      found=1
    fi
  done

  if [ "$found" -eq 0 ]; then
    printf 'No active USB audio cards found.\n'
  fi
}
# <<< laid <<<
EOF

update_rc_file() {
  local target="$1"
  local tmp

  mkdir -p "$(dirname "$target")"
  [ -f "$target" ] || : > "$target"
  tmp="$(mktemp)"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip       { print }
  ' "$target" > "$tmp"

  {
    cat "$tmp"
    if [ -s "$tmp" ]; then
      printf '\n'
    fi
    printf '%s\n' "$LAID_BLOCK"
  } > "$target"

  rm -f "$tmp"
  printf 'laid installed to: %s\n' "$target"
}

if [ "$#" -eq 0 ]; then
  update_rc_file "$HOME/.bashrc"
  update_rc_file "$HOME/.zshrc"
else
  for shell_name in "$@"; do
    case "$shell_name" in
      bash)
        update_rc_file "$HOME/.bashrc"
        ;;
      zsh)
        update_rc_file "$HOME/.zshrc"
        ;;
      *)
        printf 'Unsupported shell target: %s\n' "$shell_name" >&2
        exit 1
        ;;
    esac
  done
fi

printf 'Open a new shell, or run: source ~/.bashrc / source ~/.zshrc\n'
