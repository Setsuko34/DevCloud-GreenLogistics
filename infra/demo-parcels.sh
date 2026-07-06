#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# demo-parcels.sh — Démo live sur 5 minutes :
#   crée 3 colis à intervalles, déplace leur position vers la destination,
#   puis déclenche la notification "arrivée dans 5 min" (mail visible sur MailHog).
#
# Prérequis : stack up (./infra/up.sh), /etc/hosts avec api.greenlogistics.local,
#             port-forward MailHog actif (kubectl -n mail port-forward svc/mailhog 8025:8025)
# ─────────────────────────────────────────────────────────────────────────────

API="${API_URL:-http://api.greenlogistics.local}"
DURATION=300   # 5 minutes
TICK=15        # secondes entre deux mises à jour de position
MOVE_TIME=90   # secondes pour qu'un colis passe du départ à l'arrivée

NAMES=("Alice Dupont" "Bruno Martin" "Chloé Bernard")
EMAILS=("alice@example.com" "bruno@example.com" "chloe@example.com")
DEST_LAT=(48.8566 48.8738 48.8462)
DEST_LNG=(2.3522 2.2950 2.3371)
CREATE_AT=(0 60 120)   # instant (s) de création de chaque colis

declare -A pid tc drv slat slng notified created

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
    tc[$i]=$(jq -r .tracking_code <<< "$resp")
    drv[$i]="DRV-DEMO-$((i+1))"
    slat[$i]=$(echo "${DEST_LAT[$i]} + 0.05" | bc)
    slng[$i]=$(echo "${DEST_LNG[$i]} - 0.05" | bc)
    created[$i]=$now
    notified[$i]=0
    echo "[${now}s] Colis créé : ${tc[$i]} (${pid[$i]}) -> ${EMAILS[$i]}"
    i=$((i+1))
  fi

  for ((j=0; j<i; j++)); do
    [[ "${notified[$j]}" == "1" ]] && continue
    elapsed=$(( now - created[$j] ))
    progress=$(echo "scale=4; p=$elapsed/$MOVE_TIME; if (p>1) 1 else p" | bc)
    lat=$(echo "scale=6; ${slat[$j]} + $progress * (${DEST_LAT[$j]} - ${slat[$j]})" | bc)
    lng=$(echo "scale=6; ${slng[$j]} + $progress * (${DEST_LNG[$j]} - ${slng[$j]})" | bc)

    curl -sf -X POST "$API/dev/seed-position" -H 'Content-Type: application/json' \
      -d "$(jq -n --arg pid "${pid[$j]}" --argjson lat "$lat" --argjson lng "$lng" --arg drv "${drv[$j]}" \
        '{parcel_id:$pid, lat:$lat, lng:$lng, driver_id:$drv}')" > /dev/null
    echo "[${now}s] ${drv[$j]} -> $lat,$lng (progress $progress)"

    if (( $(echo "$progress >= 0.9" | bc) )); then
      jq -nc --arg pid "${pid[$j]}" --arg tc "${tc[$j]}" --arg email "${EMAILS[$j]}" \
        '{parcel_id:$pid, tracking_code:$tc, event:"near_5min", recipient_email:$email}' \
        | kubectl -n messaging exec -i redpanda-0 -c redpanda -- rpk topic produce parcels.events > /dev/null
      notified[$j]=1
      echo "[${now}s] -> mail 'arrivée dans 5 min' déclenché pour ${pid[$j]}"
    fi
  done

  sleep "$TICK"
done

echo "==> Démo terminée. Mails visibles sur http://localhost:8025"
