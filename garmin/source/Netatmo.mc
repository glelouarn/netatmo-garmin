import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

// Accès direct à l'API Netatmo (https://dev.netatmo.com) depuis la montre,
// via l'app Garmin Connect du téléphone. Pas de serveur intermédiaire.
(:background, :glance)
module Netatmo {

    const API = "https://api.netatmo.com";
    const AUTH_URL = "https://api.netatmo.com/oauth2/authorize";
    const TOKEN_URL = "https://api.netatmo.com/oauth2/token";
    // Doit être identique au « Redirect URI » de l'app sur dev.netatmo.com.
    // Garmin Connect intercepte cette adresse : rien n'a besoin d'y répondre.
    const REDIRECT_URI = "http://localhost:8765/callback";
    const SCOPE = "read_station";

    const AUTH_REQUIRED = -900;     // pas (ou plus) de jeton valide : reconnecter
    const NOT_CONFIGURED = -901;    // client_id / client_secret absents

    const STEP = 1800;              // historique : pas de 30 min
    const POINTS = 49;              // 24 h + le point courant

    // ------------------------------------------------------------ réglages

    // Identifiants de l'app Netatmo (source-secrets/Secrets.mc, non versionné).
    function clientId() as String or Null {
        var v = Secrets.CLIENT_ID;
        return (v.length() == 0 || v.equals("TON_CLIENT_ID")) ? null : v;
    }

    function clientSecret() as String or Null {
        var v = Secrets.CLIENT_SECRET;
        return (v.length() == 0 || v.equals("TON_CLIENT_SECRET")) ? null : v;
    }

    // Réglage « Mode démo » (Garmin Connect) : données d'exemple, sans compte.
    function isDemo() as Boolean {
        return Application.Properties.getValue("demo") == true;
    }

    // ------------------------------------------------------------ jetons
    // Netatmo renvoie un nouveau refresh token à chaque renouvellement :
    // il faut toujours enregistrer celui reçu.

    function saveTokens(data as Dictionary) as Void {
        var exp = data["expires_in"];
        var secs = exp instanceof Number ? exp : 10800;
        var snap = {
            "access_token" => data["access_token"],
            "refresh_token" => data["refresh_token"] != null
                ? data["refresh_token"] : Application.Storage.getValue("refresh_token"),
            "expires_at" => Time.now().value() + secs - 300
        };
        restoreTokens(snap);
    }

    function restoreTokens(snap as Dictionary) as Void {
        Application.Storage.setValue("access_token", snap["access_token"]);
        Application.Storage.setValue("refresh_token", snap["refresh_token"]);
        Application.Storage.setValue("expires_at", snap["expires_at"]);
    }

    function tokenSnapshot() as Dictionary {
        return {
            "access_token" => Application.Storage.getValue("access_token"),
            "refresh_token" => Application.Storage.getValue("refresh_token"),
            "expires_at" => Application.Storage.getValue("expires_at")
        };
    }

    function clearTokens() as Void {
        Application.Storage.deleteValue("access_token");
        Application.Storage.deleteValue("refresh_token");
        Application.Storage.deleteValue("expires_at");
    }

    function hasLogin() as Boolean {
        return Application.Storage.getValue("refresh_token") != null;
    }

    function validAccessToken() as String or Null {
        var exp = Application.Storage.getValue("expires_at");
        if (exp instanceof Number && exp > Time.now().value()) {
            return Application.Storage.getValue("access_token") as String or Null;
        }
        return null;
    }

    // Échange du code reçu après connexion contre les jetons.
    function exchangeCode(code as String, callback as Method) as Void {
        postToken({
            "grant_type" => "authorization_code",
            "client_id" => clientId(),
            "client_secret" => clientSecret(),
            "code" => code,
            "redirect_uri" => REDIRECT_URI,
            "scope" => SCOPE
        }, callback);
    }

    function postToken(params as Dictionary, callback as Method) as Void {
        Communications.makeWebRequest(TOKEN_URL, params, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, callback);
    }

    // ------------------------------------------------------------ conversion

    // Dernières mesures, format compact partagé par l'aperçu et les écrans.
    function current(dev as Dictionary) as Dictionary {
        var i = dev["dashboard_data"] as Dictionary or Null;
        if (i == null) { i = {}; }
        var res = {
            "time" => i["time_utc"],
            "station" => dev["station_name"],
            "in" => { "t" => i["Temperature"], "tr" => i["temp_trend"], "h" => i["Humidity"],
                      "co2" => i["CO2"], "n" => i["Noise"], "p" => i["Pressure"],
                      "pt" => i["pressure_trend"] }
        };
        var m = outdoorModule(dev);
        if (m != null) {
            var o = m["dashboard_data"] as Dictionary or Null;
            if (o == null) { o = {}; }
            res["out"] = { "t" => o["Temperature"], "tr" => o["temp_trend"],
                           "min" => o["min_temp"], "max" => o["max_temp"], "h" => o["Humidity"] };
        }
        return res;
    }

    function outdoorModule(dev as Dictionary) as Dictionary or Null {
        var mods = dev["modules"] as Array or Null;
        if (mods == null) {
            return null;
        }
        for (var k = 0; k < mods.size(); k++) {
            var m = mods[k] as Dictionary;
            if ("NAModule1".equals(m["type"])) {
                return m;
            }
        }
        return null;
    }

    // Première station du compte (réponse de getstationsdata).
    function firstDevice(data) as Dictionary or Null {
        if (!(data instanceof Dictionary)) {
            return null;
        }
        var body = data["body"] as Dictionary or Null;
        if (body == null) {
            return null;
        }
        var devs = body["devices"] as Array or Null;
        return (devs == null || devs.size() == 0) ? null : devs[0] as Dictionary;
    }

    // Réponse getmeasure (optimize=true) -> une série de POINTS valeurs par type.
    function series(data, start as Number, nTypes as Number) as Array<Array> {
        var out = [] as Array<Array>;
        for (var k = 0; k < nTypes; k++) {
            var a = new [POINTS];
            out.add(a);
        }
        if (!(data instanceof Dictionary) || !(data["body"] instanceof Array)) {
            return out;
        }
        var blocks = data["body"] as Array;
        for (var b = 0; b < blocks.size(); b++) {
            var blk = blocks[b] as Dictionary;
            var beg = blk["beg_time"] as Number;
            var st = blk["step_time"];
            var stepT = st instanceof Number ? st : STEP;
            var vals = blk["value"] as Array;
            for (var j = 0; j < vals.size(); j++) {
                var idx = ((beg + j * stepT - start) + STEP / 2) / STEP;
                if (idx < 0 || idx >= POINTS) {
                    continue;
                }
                var row = vals[j] as Array;
                for (var k = 0; k < nTypes && k < row.size(); k++) {
                    out[k][idx] = row[k];
                }
            }
        }
        return out;
    }

    // Message court et lisible pour un code de réponse en échec.
}

// Une requête GET à l'API Netatmo, avec renouvellement automatique du jeton.
// Le callback reçoit (code as Number, data).
(:background)
class NetatmoRequest {

    var _path as String;
    var _params as Dictionary or Null;
    var _callback as Method;
    var _retried as Boolean = false;
    var _retriedNet as Boolean = false;
    var _token as String = "";

    function initialize(path as String, params as Dictionary or Null, callback as Method) {
        _path = path;
        _params = params;
        _callback = callback;
    }

    function start() as Void {
        if (Netatmo.clientId() == null || Netatmo.clientSecret() == null) {
            _callback.invoke(Netatmo.NOT_CONFIGURED, null);
            return;
        }
        var tok = Netatmo.validAccessToken();
        if (tok != null) {
            send(tok);
        } else {
            refresh();
        }
    }

    function refresh() as Void {
        var rt = Application.Storage.getValue("refresh_token");
        if (rt == null) {
            _callback.invoke(Netatmo.AUTH_REQUIRED, null);
            return;
        }
        Netatmo.postToken({
            "grant_type" => "refresh_token",
            "refresh_token" => rt,
            "client_id" => Netatmo.clientId(),
            "client_secret" => Netatmo.clientSecret()
        }, method(:onToken));
    }

    function onToken(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary && data["access_token"] != null) {
            Netatmo.saveTokens(data);
            send(data["access_token"] as String);
        } else if (code == 400 || code == 401 || code == 403) {
            // refresh token refusé (révoqué, expiré, ou déjà utilisé) : reconnecter
            Netatmo.clearTokens();
            _callback.invoke(Netatmo.AUTH_REQUIRED, data);
        } else {
            _callback.invoke(code, data);
        }
    }

    function send(token as String) as Void {
        _token = token;
        Communications.makeWebRequest(Netatmo.API + _path, _params, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Authorization" => "Bearer " + token },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onData));
    }

    function onData(code as Number, data as Dictionary or String or Null) as Void {
        if ((code == 401 || code == 403) && !_retried) {
            // jeton d'accès expiré ou révoqué : on en reprend un et on réessaie une fois
            _retried = true;
            Application.Storage.deleteValue("expires_at");
            refresh();
            return;
        }
        if ((code >= 500 || (code < 0 && code != Communications.BLE_CONNECTION_UNAVAILABLE))
                && !_retriedNet) {
            // erreur passagère de Netatmo ou du réseau : on réessaie une fois
            _retriedNet = true;
            send(_token);
            return;
        }
        _callback.invoke(code, data);
    }
}
