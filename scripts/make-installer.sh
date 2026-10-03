#!/bin/zsh
# Produit dist/Installer Classeur <version>.pkg, à ouvrir sur un autre Mac (Intel ou Apple Silicon).
# Le paquet installe Classeur.app dans /Applications, puis le moteur dans la session de la personne
# connectée : ~/Library/Application Support/Classeur/moteur. Internet est nécessaire pendant
# l'installation (Python 3.12 et dépendances du moteur, vérifiées par empreinte).
set -euo pipefail
# Pas de fichiers AppleDouble (._*) dans le paquet : ils casseraient la signature de l'application.
export COPYFILE_DISABLE=1

ROOT="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/app/Info.plist")"
UV_VERSION="0.9.29"
DIST="$ROOT/dist"
PKG="$DIST/Installer Classeur $VERSION.pkg"

for tool in uv swift pkgbuild productbuild curl shasum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool est requis pour fabriquer l'installateur." >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'command rm -rf "$WORK"' EXIT
PAYLOAD="$WORK/payload"
APP="$PAYLOAD/Applications/Classeur.app"
SUPPORT="$PAYLOAD/Library/Application Support/Classeur/installation"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SUPPORT"

echo "Application universelle (Intel et Apple Silicon)"
(cd "$ROOT/app" && swift build -c release --arch arm64 --arch x86_64)
BINARY="$ROOT/app/.build/apple/Products/Release/Classeur"
lipo "$BINARY" -verify_arch arm64 x86_64
cp "$BINARY" "$APP/Contents/MacOS/Classeur"
sed 's|__ENGINE__|~/Library/Application Support/Classeur/moteur/bin/classeur|' "$ROOT/app/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/app/Resources/Classeur.icns" "$APP/Contents/Resources/Classeur.icns"
xattr -cr "$APP"

# Même identité locale que build.sh : les autorisations macOS restent valables d'une version à l'autre.
KEYCHAIN="$("$ROOT/app/Tools/setup_signing.sh")"
ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | sed 's/^ *"//; s/"$//')}")
restore_keychains() { security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"; }
trap 'restore_keychains; command rm -rf "$WORK"' EXIT
security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/1\)/{print $2; exit}')"
codesign --force --deep --keychain "$KEYCHAIN" --sign "$IDENTITY" "$APP"
restore_keychains
trap 'command rm -rf "$WORK"' EXIT
codesign --verify --strict "$APP"

echo "Moteur : paquet classeur et dépendances figées par uv.lock"
(cd "$ROOT/engine" && uv build --wheel --quiet --out-dir "$WORK/wheel")
cp "$WORK/wheel"/classeur-*.whl "$SUPPORT/"
(cd "$ROOT/engine" && uv export --locked --no-dev --no-emit-project --quiet -o "$SUPPORT/requirements.txt")
ls "$SUPPORT"/classeur-*.whl >/dev/null

echo "uv $UV_VERSION pour les deux architectures"
for pair in "aarch64:arm64" "x86_64:x86_64"; do
  triple="${pair%%:*}-apple-darwin"
  arch="${pair##*:}"
  base="https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-$triple.tar.gz"
  curl -fsSL "$base" -o "$WORK/uv-$arch.tar.gz"
  expected="$(curl -fsSL "$base.sha256" | awk '{print $1}')"
  actual="$(shasum -a 256 "$WORK/uv-$arch.tar.gz" | awk '{print $1}')"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    echo "Empreinte invalide pour uv-$triple ($actual au lieu de $expected)." >&2
    exit 1
  fi
  tar -xzf "$WORK/uv-$arch.tar.gz" -C "$WORK"
  cp "$WORK/uv-$triple/uv" "$SUPPORT/uv-$arch"
  chmod 755 "$SUPPORT/uv-$arch"
done
cp "$ROOT/scripts/installer/install-engine.sh" "$SUPPORT/install-engine.sh"
chmod 755 "$SUPPORT/install-engine.sh"
xattr -cr "$SUPPORT"

echo "Paquet"
pkgbuild --analyze --root "$PAYLOAD" "$WORK/components.plist" >/dev/null
# Sans cela, Installer « déplace » l'installation vers une copie existante de Classeur.app ailleurs sur le disque.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/components.plist"
pkgbuild --root "$PAYLOAD" --component-plist "$WORK/components.plist" \
  --scripts "$ROOT/scripts/installer/scripts" \
  --identifier com.nicolascleton.classeur.pkg --version "$VERSION" --install-location / \
  "$WORK/classeur.pkg" >/dev/null
sed "s|__VERSION__|$VERSION|g" "$ROOT/scripts/installer/distribution.xml" > "$WORK/distribution.xml"
mkdir -p "$DIST"
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" \
  --resources "$ROOT/scripts/installer/resources" "$PKG" >/dev/null
echo "Installateur : $PKG"
