#!/bin/zsh
# Installe ou met à jour le moteur Classeur.
# Usage : install-engine.sh <uv> <dossier de l'installateur> <dossier du moteur>
set -euo pipefail

UV="$1"
SRC="$2"
ENGINE_HOME="$3"

echo "Classeur : installation du moteur dans $ENGINE_HOME"
if ! "$UV" venv --quiet --clear --managed-python --python 3.12 "$ENGINE_HOME"; then
  echo "Impossible de préparer Python 3.12 (détail ci-dessus). Si le Mac est hors ligne, connecte-le à Internet puis relance l'installateur." >&2
  exit 1
fi
# Uniquement des composants précompilés : aucune compilation sur le Mac de la personne.
if ! "$UV" pip install --quiet --python "$ENGINE_HOME/bin/python" --only-binary :all: --require-hashes -r "$SRC/requirements.txt"; then
  echo "Impossible d'installer les dépendances du moteur (détail ci-dessus). Si le Mac est hors ligne, connecte-le à Internet puis relance l'installateur." >&2
  exit 1
fi
"$UV" pip install --quiet --python "$ENGINE_HOME/bin/python" --no-deps --reinstall "$SRC"/classeur-*.whl

OUTPUT="$("$ENGINE_HOME/bin/classeur" config)"
if [[ "$OUTPUT" != *'"config"'* ]]; then
  echo "Le moteur installé ne répond pas correctement : $OUTPUT" >&2
  exit 1
fi
echo "Classeur : moteur installé et vérifié."
