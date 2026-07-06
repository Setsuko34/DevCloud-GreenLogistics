#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# demo-parcels.sh — Démo live sur 5 minutes :
#   crée 3 colis à intervalles et déplace leur position vers la destination.
#   L'API elle-même passe le colis en IN_TRANSIT dès la 1ère position, déclenche
#   le mail "arrivée dans 5 min" sous 1km de la destination, et DELIVERED à
#   l'arrivée (voir services/api/src/routes/dev.ts).
#
# Prérequis : stack up (./infra/up.sh), /etc/hosts avec api.greenlogistics.local,
#             port-forward MailHog actif (kubectl -n mail port-forward svc/mailhog 8025:8025)
# ─────────────────────────────────────────────────────────────────────────────

API="${API_URL:-http://api.greenlogistics.local}"
DURATION=300   # 5 minutes
TICK=15        # secondes entre deux mises à jour de position
MOVE_TIME=120  # secondes pour qu'un colis passe du départ à l'arrivée

NAMES=("Alice Dupont" "Bruno Martin" "Chloé Bernard")
EMAILS=("alice@example.com" "bruno@example.com" "chloe@example.com")
DEST_LAT=(48.8566 48.8738 48.8462)
DEST_LNG=(2.3522 2.2950 2.3371)
CREATE_AT=(0 60 120)   # instant (s) de création de chaque colis

declare -A pid drv slat slng done created

start_ts=$(date +%s)
n=${#NAMES[@]}
i=0

echo "==> Démo colis en cours (${DURATION}s) — API=$API"

while (( $(date +%s) - start_ts < DURATION )); do
  now=$(( $(date +%s) - start_ts ))

  if (( i < n && now >= CREATE_AT[i] )); then
    resp=$(curl -sf -X POST "$API/parcels" -H 'Content-Type: application/json' -d "$(jq -n \
      --arg sender "${NAMES[$i]}" --arg email "${EMAILS[$i]}" \
      --argjson lat "${DEST_LAT[$i]}" --argjson lng "${DEST_LNG[$i]}" \
      '{sender:$sender, recipient_email:$email, destination_lat:$lat, destination_lng:$lng}')")
    pid[$i]=$(jq -r .id <<< "$resp")
    tc=$(jq -r .tracking_code <<< "$resp")
    drv[$i]="DRV-DEMO-$((i+1))"
    # Départ loin de la destination (~15-20km) pour un vrai trajet visible sur la carte
    slat[$i]=$(echo "${DEST_LAT[$i]} + 0.15" | bc)
    slng[$i]=$(echo "${DEST_LNG[$i]} - 0.15" | bc)
    created[$i]=$now
    done[$i]=0
    echo "[${now}s] Colis créé : $tc (${pid[$i]}) -> ${EMAILS[$i]}"
    i=$((i+1))
  fi

  for ((j=0; j<i; j++)); do
    [[ "${done[$j]}" == "1" ]] && continue
    elapsed=$(( now - created[$j] ))
    progress=$(echo "scale=4; p=$elapsed/$MOVE_TIME; if (p>1) 1 else p" | bc)
    lat=$(echo "scale=6; ${slat[$j]} + $progress * (${DEST_LAT[$j]} - ${slat[$j]})" | bc)
    lng=$(echo "scale=6; ${slng[$j]} + $progress * (${DEST_LNG[$j]} - ${slng[$j]})" | bc)

    curl -sf -X POST "$API/dev/seed-position" -H 'Content-Type: application/json' \
      -d "$(jq -n --arg pid "${pid[$j]}" --argjson lat "$lat" --argjson lng "$lng" --arg drv "${drv[$j]}" \
        '{parcel_id:$pid, lat:$lat, lng:$lng, driver_id:$drv}')" > /dev/null
    echo "[${now}s] ${drv[$j]} -> $lat,$lng (progress $progress)"

    (( $(echo "$progress >= 1" | bc) )) && done[$j]=1
  done

  sleep "$TICK"
done

echo "==> Démo terminée. Statuts/mails visibles sur le dashboard et http://localhost:8025"
