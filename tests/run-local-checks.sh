#!/usr/bin/env bash
# run-local-checks.sh — tout ce qui est vérifiable SANS VM ni matériel.
# Exécuté par la CI (conteneur fedora:44) et à la main pendant le dev
# (fonctionne aussi sous macOS, en dégradé : les outils absents sont signalés
# comme sautés, jamais silencieusement ignorés).
#
# Options : --no-network  saute les validations mdapi.

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NETWORK=1
for arg in "$@"; do
  case "$arg" in
    --no-network) NETWORK=0 ;;
    --help|-h) echo "Usage : $0 [--no-network]"; exit 0 ;;
    *) echo "option inconnue : $arg" >&2; exit 1 ;;
  esac
done

FAIL=0
SKIPPED=""
section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ko()      { printf '\033[1;31mKO\033[0m %s\n' "$*"; FAIL=1; }
ok()      { printf '\033[1;32mok\033[0m %s\n' "$*"; }
skip()    { printf '\033[1;33msauté\033[0m %s\n' "$*"; SKIPPED="$SKIPPED $*"; }

SHELL_SCRIPTS="$(find scripts packaging iso tests -type f \( -name '*.sh' -o -name 'fedoriri-theme-set' \) | sort)"

section "bash -n (syntaxe)"
for f in $SHELL_SCRIPTS; do
  if bash -n "$f"; then ok "$f"; else ko "$f"; fi
done

section "shellcheck -S warning"
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  if shellcheck -S warning -x $SHELL_SCRIPTS; then ok "tous les scripts"; else ko "shellcheck"; fi
else
  skip "shellcheck absent (dnf install ShellCheck)"
fi

section "python (py_compile)"
for f in scripts/render-theme.py scripts/fedoriri-passthrough; do
  if python3 -m py_compile "$f"; then ok "$f"; else ko "$f"; fi
done

section "rendu des 22 thèmes × tous les templates (aucun jeton non résolu)"
WARN_FILE="$(mktemp)"
RENDER_FAIL=0
for theme in desktop/themes/*/colors.toml; do
  for tpl in desktop/templates/*.tpl; do
    python3 scripts/render-theme.py "$theme" "$tpl" /dev/null 2>>"$WARN_FILE" || RENDER_FAIL=1
  done
done
if [ "$RENDER_FAIL" -eq 0 ] && [ ! -s "$WARN_FILE" ]; then
  ok "$(find desktop/themes -name colors.toml | wc -l | tr -d ' ') thèmes × $(find desktop/templates -name '*.tpl' | wc -l | tr -d ' ') templates"
else
  sort -u "$WARN_FILE"
  ko "rendu des thèmes"
fi
rm -f "$WARN_FILE"

section "équilibre des accolades du config.kdl (garde-fou minimal)"
if python3 - <<'EOF'
import sys
depth = 0
for line in open("desktop/niri/config.kdl", encoding="utf-8"):
    code = line.split("//")[0]
    depth += code.count("{") - code.count("}")
    if depth < 0:
        sys.exit("accolade fermante excédentaire")
sys.exit(0 if depth == 0 else f"accolades non refermées : {depth}")
EOF
then ok "config.kdl"; else ko "config.kdl"; fi

section "kickstart (ksflatten + ksvalidator)"
if command -v ksvalidator >/dev/null 2>&1; then
  FLAT="$(mktemp)"
  if ( cd iso && ksflatten -c fedoriri.ks -o "$FLAT" ) && ksvalidator "$FLAT"; then
    ok "iso/fedoriri.ks"
  else
    ko "iso/fedoriri.ks"
  fi
  rm -f "$FLAT"
else
  skip "pykickstart absent (dnf install pykickstart)"
fi

section "unités systemd (systemd-analyze verify)"
if command -v systemd-analyze >/dev/null 2>&1; then
  for u in systemd/fedoriri-first-boot.service packaging/quickshell/fedoriri-quickshell-qt-guard.service; do
    # verify se plaint des ExecStart absents du système de build : on ne
    # vérifie que la syntaxe (exit code de l'analyse du fichier).
    if systemd-analyze verify --man=no "$u" 2>&1 | grep -vE 'command .* not found|Failed to (create|prepare)' | grep -q 'error'; then
      ko "$u"
    else
      ok "$u"
    fi
  done
else
  skip "systemd-analyze absent (normal hors Linux)"
fi

if [ "$NETWORK" -eq 1 ]; then
  section "paquets contre mdapi (kickstart + build-deps quickshell)"
  if bash scripts/validate-packages.sh >/dev/null; then ok "iso/includes/30-packages.ks"; else ko "30-packages.ks"; fi
  if bash scripts/validate-packages.sh packaging/quickshell/build-deps.txt >/dev/null; then ok "build-deps.txt"; else ko "build-deps.txt"; fi
fi

section "résultat"
[ -n "$SKIPPED" ] && printf 'sautés :%s\n' "$SKIPPED"
if [ "$FAIL" -eq 0 ]; then
  echo "TOUT EST VERT"
else
  echo "DES VÉRIFICATIONS ONT ÉCHOUÉ" >&2
  exit 1
fi
