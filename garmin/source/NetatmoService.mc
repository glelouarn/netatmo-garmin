import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

// Tâche de fond : récupère les dernières mesures pour l'aperçu.
// Renvoie aussi les jetons, au cas où le stockage ne serait pas écrivable ici
// (le refresh token change à chaque renouvellement et ne doit pas être perdu).
(:background)
class NetatmoService extends System.ServiceDelegate {

    var _request as NetatmoRequest or Null;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        if (Netatmo.isDemo()) {
            finish(Demo.data(false));
            return;
        }
        if (!Netatmo.hasLogin()) {
            Background.exit(null);
            return;
        }
        _request = new NetatmoRequest("/api/getstationsdata", { "get_favorites" => "false" },
            method(:onResponse));
        (_request as NetatmoRequest).start();
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        var dev = code == 200 ? Netatmo.firstDevice(data) : null;
        if (dev != null) {
            finish(Netatmo.current(dev));
        } else {
            Background.exit({ "tok" => Netatmo.tokenSnapshot() });
        }
    }

    function finish(cur as Dictionary) as Void {
        try {
            Application.Storage.setValue("current", cur);
        } catch (e) {
        }
        Background.exit({ "current" => cur, "tok" => Netatmo.tokenSnapshot() });
    }
}
