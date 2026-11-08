#!/bin/bash
# Compile l'app pour la montre.  Usage : ./build.sh [id_appareil]
# Puis, pour le simulateur :  ./build.sh sim [id_appareil]
set -euo pipefail
cd "$(dirname "$0")"

CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK="$(cat "$CIQ/current-sdk.cfg" 2>/dev/null || true)"
SDK="${SDK%/}"
if [ -z "$SDK" ] || [ ! -x "$SDK/bin/monkeyc" ]; then
    SDK="$(ls -d "$CIQ"/Sdks/*/ 2>/dev/null | sort | tail -1 || true)"
    SDK="${SDK%/}"
fi
[ -x "$SDK/bin/monkeyc" ] || { echo "SDK Connect IQ introuvable (installe-le avec le SDK Manager)"; exit 1; }

PROPS=resources/settings/properties.xml
CONFIG=../netatmo_config.json
if [ ! -f "$PROPS" ]; then
    if [ -f "$CONFIG" ]; then
        # Reprend le client_id / client_secret enregistrés par netatmo_explore.py
        python3 - "$CONFIG" "$PROPS" <<'PY'
import json, sys
from xml.sax.saxutils import escape
c = json.load(open(sys.argv[1]))
open(sys.argv[2], "w").write(
    "<properties>\n"
    f'    <property id="clientId" type="string">{escape(c["client_id"])}</property>\n'
    f'    <property id="clientSecret" type="string">{escape(c["client_secret"])}</property>\n'
    "</properties>\n")
PY
        chmod 600 "$PROPS"
        echo "Créé $PROPS depuis $CONFIG."
    else
        cp properties.example.xml "$PROPS"
        echo "Créé $PROPS depuis le modèle : renseigne clientId et clientSecret, puis relance."
        exit 1
    fi
fi
if grep -q "TON_CLIENT_ID\|TON_CLIENT_SECRET" "$PROPS"; then
    echo "Attention : $PROPS contient encore les valeurs d'exemple (l'app affichera « ID client non réglé »)."
fi
if [ ! -f developer_key.der ]; then
    echo "Pas de clé de signature : génération de developer_key.der (à conserver précieusement)."
    openssl genrsa -out developer_key.pem 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
    rm -f developer_key.pem
    chmod 600 developer_key.der
fi

SIM=0
if [ "${1:-}" = "sim" ]; then SIM=1; shift; fi
DEVICE="${1:-fenix847mm}"

mkdir -p bin
"$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -y developer_key.der -o bin/NetatmoMeteo.prg -w
echo "OK : bin/NetatmoMeteo.prg ($DEVICE)"

if [ "$SIM" = 1 ]; then
    open -a "$SDK/bin/ConnectIQ.app" 2>/dev/null || "$SDK/bin/connectiq" &
    sleep 4
    "$SDK/bin/monkeydo" bin/NetatmoMeteo.prg "$DEVICE"
fi
