#!/bin/zsh
# Construit Classeur.app, installe le moteur sur le disque interne et l'application dans ~/Applications.
# Le moteur ne doit pas s'exécuter depuis un volume externe : macOS y bloque l'accès des applications
# tant que l'autorisation « volumes amovibles » n'a pas été donnée.
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/Classeur.app"
ENGINE_HOME="$HOME/Library/Application Support/Classeur/moteur"
ENGINE="$ENGINE_HOME/bin/classeur"
INSTALLED="$HOME/Applications/Classeur.app"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv est requis pour installer le moteur : brew install uv" >&2
  exit 1
fi
if [[ ! -x "$ENGINE_HOME/bin/python" ]]; then
  uv venv --quiet --python 3.12 "$ENGINE_HOME"
fi
uv pip install --quiet --python "$ENGINE_HOME/bin/python" --reinstall-package classeur "$ROOT/engine"
if [[ ! -x "$ENGINE" ]]; then
  echo "Le moteur n'a pas été installé : $ENGINE est absent." >&2
  exit 1
fi

(cd "$ROOT/app" && swift build -c release)

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/app/.build/release/Classeur" "$APP/Contents/MacOS/Classeur"
sed "s|__ENGINE__|$ENGINE|" "$ROOT/app/Info.plist" > "$APP/Contents/Info.plist"
if [[ -f "$ROOT/app/Resources/Classeur.icns" ]]; then
  cp "$ROOT/app/Resources/Classeur.icns" "$APP/Contents/Resources/Classeur.icns"
fi

# Signature stable : macOS garde l'accès complet au disque et l'automatisation entre deux versions.
KEYCHAIN="$("$ROOT/app/Tools/setup_signing.sh")"
ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | sed 's/^ *"//; s/"$//')}")
restore_keychains() { security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"; }
trap restore_keychains EXIT
security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/1\)/{print $2; exit}')"
codesign --force --deep --keychain "$KEYCHAIN" --sign "$IDENTITY" "$APP"
restore_keychains
trap - EXIT
codesign -dr - "$APP" 2>&1 | grep designated

mkdir -p "$HOME/Applications"
ditto "$APP" "$INSTALLED"
echo "Application installée : $INSTALLED"
echo "Moteur : $ENGINE"
