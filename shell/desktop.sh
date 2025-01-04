#!/usr/bin/env bash

######
##
## create desktop files
##
######

set -euo pipefail

judgment_parameters() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
    '-h' | '--help')
      HELP='1'
      break
      ;;
    '-e' | '--exec')
      if [[ -z "${2:?error: Please specify the correct exec.}" ]]; then
        exit 1
      fi
      EXEC="$2"
      shift
      ;;
    '-n' | '--name')
      if [[ -z "${2:?error: Please specify the correct name.}" ]]; then
        exit 1
      fi
      NAME="$2"
      shift
      ;;
    '-i' | '--icon')
      if [[ -z "${2:?error: Please specify the correct icon.}" ]]; then
        exit 1
      fi
      ICON="$2"
      shift
      ;;
    *)
      echo "$0: unknown option -- $1"
      exit 1
      ;;
    esac
    shift
  done

  [[ "${HELP:-}" -eq '1' ]] && show_help
}

show_help() {
  echo "usage: $0 [ options ]"
  echo '  -h, --help      Show help'
  echo '  -e, --exec      App exec script'
  echo '  -n, --name      App icon'
  echo '  -i, --icon      App name'
  exit 0
}

main() {
  judgment_parameters "$@"

  NAME="${NAME:-}"
  if [[ -z "$NAME" ]]; then
    echo "Please specify the correct name."
    exit 1
  fi

  EXEC="${EXEC:-}"
  if [[ -z "$EXEC" ]]; then
    echo "Please specify the correct exec."
    exit 1
  fi

  _APP_SHARE_PATH="$HOME/.local/share/applications"
  [[ -d "$_APP_SHARE_PATH" ]] || mkdir -p "$_APP_SHARE_PATH"

  DESKTOP_NAME=$(echo "$NAME" | awk '{print $1}')
  _DESKTOP_NAME="${DESKTOP_NAME,,}"
  _DESKTOP_PATH="$HOME/.local/share/applications/$_DESKTOP_NAME.desktop"

  {
    echo "[Desktop Entry]"
    echo "Exec=$EXEC"
    [[ -z "${ICON:-}" ]] || echo "Icon=$ICON"
    echo "Name=$DESKTOP_NAME"
    echo "Comment=$NAME"
    echo "Type=Application"
    echo "Terminal=false"
  } >"$_DESKTOP_PATH"

  chmod +x "$_DESKTOP_PATH"
  cat "$_DESKTOP_PATH"
}

main "$@" || exit 1
