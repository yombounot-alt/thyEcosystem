#!/usr/bin/env bash
# Lance une commande ; si elle échoue, publie la fin de sa sortie comme annotation GitHub.
# Les annotations sont lisibles par l'API publique (check-runs/…/annotations), contrairement aux
# journaux de job qui exigent un jeton : un échec reste diagnosticable sans accès authentifié.
#   .github/scripts/run-annotated.sh "Titre" commande arg1 arg2 …
set -uo pipefail

title="$1"
shift
log="$(mktemp)"

"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  # Les 40 dernières lignes non vides, encodées pour une annotation sur une seule ligne.
  message=$(grep -vE '^[[:space:]]*$' "$log" | tail -40 | tr -d '\r' \
    | sed -e 's/%/%25/g' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/%0A/g')
  echo "::error title=${title}::${message}"
fi
rm -f "$log"
exit "$status"
