#!/usr/bin/env python3
"""
Exploration de l'API Netatmo Weather (station météo).

- Connexion OAuth2 (authorization code) via un petit serveur local
- Sauvegarde + rafraîchissement automatique des jetons (refresh token rotatif)
- Appel de getstationsdata : résumé lisible + JSON brut complet
- Appel de getmeasure : historique 24h de la température extérieure

Aucune dépendance externe (stdlib Python 3.8+).

Usage :
    python3 netatmo_explore.py            # connexion si besoin, puis exploration
    python3 netatmo_explore.py --login    # forcer une nouvelle connexion
    python3 netatmo_explore.py --raw      # afficher aussi le JSON brut dans le terminal
"""

import argparse
import getpass
import http.server
import json
import os
import secrets
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG_FILE = HERE / "netatmo_config.json"   # client_id / client_secret
TOKEN_FILE = HERE / "netatmo_tokens.json"    # access / refresh token
OUT_DIR = HERE / "netatmo_output"            # réponses brutes

API = "https://api.netatmo.com"
AUTH_URL = f"{API}/oauth2/authorize"
TOKEN_URL = f"{API}/oauth2/token"
REDIRECT_PORT = 8765
REDIRECT_URI = f"http://localhost:{REDIRECT_PORT}/callback"
SCOPE = "read_station"


# ---------------------------------------------------------------- utilitaires

def write_private(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    os.chmod(path, 0o600)


def http_post_form(url: str, fields: dict) -> dict:
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"},
    )
    return _send(req)


def http_get(url: str, token: str, params: dict) -> dict:
    full = f"{url}?{urllib.parse.urlencode(params)}" if params else url
    req = urllib.request.Request(full, headers={"Authorization": f"Bearer {token}"})
    return _send(req)


def _send(req) -> dict:
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"HTTP {e.code} sur {req.full_url.split('?')[0]} : {detail}") from None


def ts(t) -> str:
    if not t:
        return "-"
    return datetime.fromtimestamp(int(t)).strftime("%d/%m %H:%M")


# ---------------------------------------------------------------- identifiants

def load_config() -> dict:
    cid = os.environ.get("NETATMO_CLIENT_ID")
    csec = os.environ.get("NETATMO_CLIENT_SECRET")
    if cid and csec:
        return {"client_id": cid, "client_secret": csec}
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text())

    print("Identifiants de ton app Netatmo (https://dev.netatmo.com/apps) :")
    cid = input("  client_id     : ").strip()
    csec = getpass.getpass("  client_secret : ").strip()
    cfg = {"client_id": cid, "client_secret": csec}
    write_private(CONFIG_FILE, cfg)
    print(f"  -> enregistrés dans {CONFIG_FILE.name} (lisible par toi seul)\n")
    return cfg


# ---------------------------------------------------------------- OAuth2

def oauth_login(cfg: dict) -> dict:
    state = secrets.token_urlsafe(16)
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if not self.path.startswith("/callback"):
                self.send_response(404); self.end_headers(); return
            if q.get("state", [""])[0] != state:
                result["error"] = "state invalide (requête inattendue)"
            elif "error" in q:
                result["error"] = q["error"][0]
            else:
                result["code"] = q.get("code", [""])[0]
            ok = "code" in result
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "Connexion réussie, tu peux fermer cet onglet." if ok \
                else f"Échec : {result.get('error')}"
            self.wfile.write(f"<h2>Netatmo</h2><p>{msg}</p>".encode())

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("localhost", REDIRECT_PORT), Handler)
    t = threading.Thread(target=server.handle_request, daemon=True)
    t.start()

    url = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": cfg["client_id"],
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPE,
        "state": state,
    })
    print("Ouverture du navigateur pour autoriser l'accès à ta station…")
    print(f"(sinon ouvre ce lien à la main)\n  {url}\n")
    webbrowser.open(url)

    t.join(timeout=300)
    server.server_close()
    if "code" not in result:
        sys.exit(f"Connexion annulée : {result.get('error', 'délai dépassé (5 min)')}")

    tok = http_post_form(TOKEN_URL, {
        "grant_type": "authorization_code",
        "client_id": cfg["client_id"],
        "client_secret": cfg["client_secret"],
        "code": result["code"],
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPE,
    })
    return save_tokens(tok)


def save_tokens(tok: dict) -> dict:
    data = {
        "access_token": tok["access_token"],
        "refresh_token": tok["refresh_token"],
        "expires_at": int(time.time()) + int(tok.get("expires_in", 10800)),
        "scope": tok.get("scope"),
    }
    write_private(TOKEN_FILE, data)
    return data


def refresh(cfg: dict, tokens: dict) -> dict:
    # Netatmo renvoie un NOUVEAU refresh_token à chaque fois : on le sauvegarde.
    tok = http_post_form(TOKEN_URL, {
        "grant_type": "refresh_token",
        "refresh_token": tokens["refresh_token"],
        "client_id": cfg["client_id"],
        "client_secret": cfg["client_secret"],
    })
    rotated = tok["refresh_token"] != tokens["refresh_token"]
    print(f"Jeton rafraîchi (refresh token {'renouvelé' if rotated else 'inchangé'}).")
    return save_tokens(tok)


def get_tokens(cfg: dict, force_login: bool) -> dict:
    if force_login or not TOKEN_FILE.exists():
        return oauth_login(cfg)
    tokens = json.loads(TOKEN_FILE.read_text())
    if time.time() > tokens.get("expires_at", 0) - 120:
        try:
            tokens = refresh(cfg, tokens)
        except RuntimeError as e:
            print(f"Rafraîchissement impossible ({e}), nouvelle connexion.")
            tokens = oauth_login(cfg)
    return tokens


# ---------------------------------------------------------------- affichage

MODULE_LABEL = {
    "NAMain": "Station (intérieur)",
    "NAModule1": "Module extérieur",
    "NAModule2": "Anémomètre",
    "NAModule3": "Pluviomètre",
    "NAModule4": "Module intérieur additionnel",
}

FIELD_FMT = {
    "Temperature": ("Température", "{} °C"),
    "Humidity": ("Humidité", "{} %"),
    "CO2": ("CO₂", "{} ppm"),
    "Noise": ("Bruit", "{} dB"),
    "Pressure": ("Pression (mer)", "{} mbar"),
    "AbsolutePressure": ("Pression (absolue)", "{} mbar"),
    "temp_trend": ("Tendance temp.", "{}"),
    "pressure_trend": ("Tendance pression", "{}"),
    "min_temp": ("Min du jour", "{} °C"),
    "max_temp": ("Max du jour", "{} °C"),
    "Rain": ("Pluie (dernière mesure)", "{} mm"),
    "sum_rain_1": ("Pluie 1 h", "{} mm"),
    "sum_rain_24": ("Pluie aujourd'hui", "{} mm"),
    "WindStrength": ("Vent", "{} km/h"),
    "WindAngle": ("Direction vent", "{} °"),
    "GustStrength": ("Rafales", "{} km/h"),
    "GustAngle": ("Direction rafales", "{} °"),
    "max_wind_str": ("Rafale max du jour", "{} km/h"),
}


def print_dashboard(dd: dict, indent="    "):
    if not dd:
        print(f"{indent}(aucune donnée : module injoignable ?)")
        return
    for key, val in dd.items():
        if key.startswith("date_") or key == "time_utc":
            continue
        label, fmt = FIELD_FMT.get(key, (key, "{}"))
        extra = ""
        if key == "min_temp":
            extra = f"  à {ts(dd.get('date_min_temp'))}"
        elif key == "max_temp":
            extra = f"  à {ts(dd.get('date_max_temp'))}"
        elif key == "max_wind_str":
            extra = f"  à {ts(dd.get('date_max_wind_str'))}"
        print(f"{indent}{label:<26} {fmt.format(val)}{extra}")
    print(f"{indent}{'Mesure du':<26} {ts(dd.get('time_utc'))}")


def print_device_meta(d: dict, indent="    "):
    meta = []
    if "battery_percent" in d:
        meta.append(f"pile {d['battery_percent']} %")
    if "rf_status" in d:
        meta.append(f"radio {d['rf_status']}")
    if "wifi_status" in d:
        meta.append(f"wifi {d['wifi_status']}")
    meta.append("joignable" if d.get("reachable", True) else "INJOIGNABLE")
    if "firmware" in d:
        meta.append(f"fw {d['firmware']}")
    print(f"{indent}[{' · '.join(meta)}]")


def show_stations(data: dict):
    body = data["body"]
    user = body.get("user", {})
    adm = user.get("administrative", {})
    print("\n=== Compte ===")
    print(f"  unités : unit={adm.get('unit')}  vent={adm.get('windunit')}  "
          f"pression={adm.get('pressureunit')}  langue={adm.get('lang')}")

    for dev in body.get("devices", []):
        place = dev.get("place", {})
        print(f"\n=== {dev.get('station_name') or dev.get('home_name')} "
              f"({place.get('city', '?')}, alt. {place.get('altitude', '?')} m) ===")
        print(f"  id station : {dev['_id']}")
        print(f"\n  ▸ {dev.get('module_name', '')} — {MODULE_LABEL.get(dev['type'], dev['type'])}")
        print_device_meta(dev)
        print_dashboard(dev.get("dashboard_data"))
        for m in dev.get("modules", []):
            print(f"\n  ▸ {m.get('module_name', '')} — {MODULE_LABEL.get(m['type'], m['type'])}"
                  f"  (id {m['_id']})")
            print_device_meta(m)
            print_dashboard(m.get("dashboard_data"))


def show_history(token: str, data: dict):
    for dev in data["body"].get("devices", []):
        outdoor = next((m for m in dev.get("modules", []) if m["type"] == "NAModule1"), None)
        if not outdoor:
            continue
        now = int(time.time())
        res = http_get(f"{API}/api/getmeasure", token, {
            "device_id": dev["_id"],
            "module_id": outdoor["_id"],
            "scale": "1hour",
            "type": "temperature,humidity",
            "date_begin": now - 24 * 3600,
            "date_end": now,
            "optimize": "false",
            "real_time": "false",
        })
        (OUT_DIR / "getmeasure_outdoor_24h.json").write_text(
            json.dumps(res, indent=2, ensure_ascii=False))
        print(f"\n=== Historique 24 h — {outdoor.get('module_name', 'extérieur')} (getmeasure) ===")
        series = res.get("body", {})
        if not series:
            print("  (vide)")
        for t, (temp, hum) in sorted(series.items(), key=lambda kv: int(kv[0])):
            bar = "█" * max(0, int(round((temp or 0) + 10)) // 2) if temp is not None else ""
            print(f"  {ts(t)}  {str(temp):>5} °C  {str(hum):>3} %  {bar}")


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="Explorer l'API Netatmo Weather")
    ap.add_argument("--login", action="store_true", help="forcer une nouvelle connexion OAuth")
    ap.add_argument("--raw", action="store_true", help="afficher aussi le JSON brut")
    args = ap.parse_args()

    cfg = load_config()
    tokens = get_tokens(cfg, args.login)
    token = tokens["access_token"]
    print(f"Connecté ✔  (scope : {tokens.get('scope')}, "
          f"jeton valide jusqu'à {ts(tokens['expires_at'])})")

    OUT_DIR.mkdir(exist_ok=True)
    data = http_get(f"{API}/api/getstationsdata", token, {"get_favorites": "false"})
    raw_path = OUT_DIR / "getstationsdata.json"
    raw_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))

    show_stations(data)
    try:
        show_history(token, data)
    except RuntimeError as e:
        print(f"\n(getmeasure a échoué : {e})")

    print(f"\nRéponses brutes complètes : {OUT_DIR.name}/")
    if args.raw:
        print(json.dumps(data, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
