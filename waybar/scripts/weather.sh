#!/usr/bin/env bash
# ~/.config/waybar/scripts/weather.sh
# Détecte la ville via IP, récupère wttr.in?format=j1, renvoie JSON pour Waybar
# Affiche : icône + température, tooltip avec ressenti, vent, mini-prévisions (3 jours)

set -eu

CURL_OPTS="-sS --max-time 8"
DAYS=3  # nombre de jours de prévision à afficher dans le tooltip (inclut aujourd'hui)

# 1) géoloc via ip-api
loc_json=$(curl $CURL_OPTS "http://ip-api.com/json/?fields=status,message,city,country,lat,lon" 2>/dev/null || true)

json_get() {
  key="$1"
  python - "$key" <<'PY' 2>/dev/null || true
import sys, json
key = sys.argv[1]
try:
    j = json.load(sys.stdin)
    v = j.get(key)
    if v is None:
        sys.exit(1)
    print(v)
except Exception:
    sys.exit(1)
PY
}

city=""
country=""
lat=""
lon=""

if [ -n "$loc_json" ]; then
  if echo "$loc_json" | grep -q '"status":"success"' 2>/dev/null || echo "$loc_json" | grep -q '"status": "success"' 2>/dev/null; then
    city=$(echo "$loc_json" | json_get city || true)
    country=$(echo "$loc_json" | json_get country || true)
    lat=$(echo "$loc_json" | json_get lat || true)
    lon=$(echo "$loc_json" | json_get lon || true)
  fi
fi

# fallback si échec
[ -z "$city" ] && city="Paris"
[ -z "$country" ] && country="FR"

# urlencode la ville
city_esc=$(python - <<PY 2>/dev/null
import urllib.parse, sys
s = """${city}"""
print(urllib.parse.quote_plus(s))
PY
)

# 2) Récupère JSON de wttr.in
wttr_json=$(curl $CURL_OPTS "https://wttr.in/${city_esc}?format=j1" 2>/dev/null || true)

# si wttr échoue, fallback textuel simple
if [ -z "$wttr_json" ]; then
  display="🌈 ?°C"
  tooltip="${city}, ${country}\nMétéo indisponible"
  python - "$display" "$tooltip" <<'PY' 2>/dev/null
import sys, json
print(json.dumps({"text": sys.argv[1], "tooltip": sys.argv[2]}, ensure_ascii=False))
PY
  exit 0
fi

# 3) Parse & formate via Python (sécurisé : json.dumps gère l'échappement)
python - "$wttr_json" "$city" "$country" "$DAYS" <<'PY' 2>/dev/null
import sys, json

raw = sys.argv[1]
city = sys.argv[2]
country = sys.argv[3]
try:
    data = json.loads(raw)
except Exception:
    print(json.dumps({"text":"🌈 ?°C","tooltip":f"{city}, {country}\nErreur parsing"} , ensure_ascii=False))
    sys.exit(0)

# current
cur = data.get("current_condition", [{}])[0]
temp = cur.get("temp_C") or cur.get("temp_F") or "?"
feels = cur.get("FeelsLikeC") or cur.get("FeelsLikeF") or "?"
humidity = cur.get("humidity", "?")
wind_speed_kmph = cur.get("windspeedKmph") or cur.get("windspeedMiles") or "?"
wind_dir = cur.get("winddir16Point") or cur.get("winddirDegree") or ""
desc = ""
try:
    desc = cur.get("weatherDesc", [{}])[0].get("value","")
except Exception:
    desc = ""

# helper : map description -> emoji
def desc_to_emoji(s):
    s = (s or "").lower()
    if "rain" in s or "pluie" in s or "shower" in s: return "🌧️"
    if "snow" in s or "neige" in s: return "❄️"
    if "thunder" in s or "orage" in s: return "⛈️"
    if "fog" in s or "brume" in s or "brouillard" in s: return "🌫️"
    if "cloud" in s or "nuage" in s or "overcast" in s: return "☁️"
    if "clear" in s or "sun" in s or "soleil" in s: return "☀️"
    return "🌤️"

emoji = desc_to_emoji(desc)
text = f"{emoji} {temp}°C"

# forecast: take first N days from data['weather']
forecast_lines = []
weather_days = data.get("weather", [])[:int(sys.argv[4])]
from datetime import datetime
for d in weather_days:
    date = d.get("date", "")
    # readable day name (try)
    try:
        dayname = datetime.strptime(date, "%Y-%m-%d").strftime("%a")
    except Exception:
        dayname = date
    maxt = d.get("maxtempC") or d.get("maxtempF") or "?"
    mint = d.get("mintempC") or d.get("mintempF") or "?"
    # try to get a short desc from hourly (midday ~ index 4 if exists)
    desc_short = ""
    hourly = d.get("hourly", [])
    if hourly:
        idx = min(len(hourly)-1, 4)
        try:
            desc_short = hourly[idx].get("weatherDesc", [{}])[0].get("value","")
        except Exception:
            desc_short = ""
    if not desc_short and d.get("hourly"):
        try:
            desc_short = d["hourly"][0].get("weatherDesc", [{}])[0].get("value","")
        except Exception:
            desc_short = ""
    icon = desc_to_emoji(desc_short)
    forecast_lines.append(f"{dayname}: {icon} {mint}°/{maxt}°")

# tooltip assemble
tooltip_lines = []
tooltip_lines.append(f"{city}, {country}")
if desc:
    tooltip_lines.append(desc)
tooltip_lines.append(f"Ressenti: {feels}°C • Vent: {wind_speed_kmph} km/h {wind_dir} • Humid: {humidity}%")
tooltip_lines.append("")  # blank line
tooltip_lines.append("Prévisions:")
tooltip_lines.extend(forecast_lines)

tooltip = "\n".join(tooltip_lines)

print(json.dumps({"text": text, "tooltip": tooltip}, ensure_ascii=False))
PY
