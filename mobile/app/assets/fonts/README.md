# Polices embarquées

`Roboto-Regular.ttf` et `Roboto-Bold.ttf` (Roboto, © Google, licence Apache 2.0 —
<https://www.apache.org/licenses/LICENSE-2.0>) servent uniquement à écrire les **reçus PDF** :
un PDF doit embarquer sa police, et les polices de base de PDF ne savent pas afficher tous les
accents français ni les espaces insécables des montants. L'interface de l'app utilise la police
Roboto du système Flutter, pas ces fichiers.
