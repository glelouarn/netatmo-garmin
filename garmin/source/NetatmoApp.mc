import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Mesures rafraîchies en tâche de fond toutes les 10 min pour l'aperçu
// (rythme d'envoi des stations Netatmo).
const REFRESH_SECONDS = 10 * 60;

(:background, :glance)
class NetatmoApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // Vue complète : 4 écrans « Tendance 24 h » (glissement de l'un à l'autre).
    (:typecheck(disableBackgroundCheck))
    function getInitialView() {
        registerRefresh();
        var store = new NetatmoStore();
        return [new PageView(0, store), new PageDelegate(store, 0)];
    }

    // Aperçu dans la liste des glances.
    (:glance, :typecheck(disableBackgroundCheck))
    function getGlanceView() {
        registerRefresh();
        return [new NetatmoGlanceView()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new NetatmoService()];
    }

    // Données reçues de la tâche de fond (déjà enregistrées par elle si possible).
    (:typecheck(disableBackgroundCheck))
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            try {
                var cur = data["current"];
                if (cur instanceof Dictionary) {
                    Application.Storage.setValue("current", cur);
                }
                // Jetons renouvelés en tâche de fond : on garde les plus récents.
                var tok = data["tok"];
                if (tok instanceof Dictionary && tok["refresh_token"] != null) {
                    var mine = Application.Storage.getValue("expires_at");
                    var theirs = tok["expires_at"];
                    if (theirs instanceof Number && (!(mine instanceof Number) || theirs > mine)) {
                        Netatmo.restoreTokens(tok);
                    }
                }
            } catch (e) {
            }
        }
        WatchUi.requestUpdate();
    }

    (:glance)
    function registerRefresh() as Void {
        var reg = Background.getTemporalEventRegisteredTime();
        if (reg == null || !(reg instanceof Time.Duration) || reg.value() != REFRESH_SECONDS) {
            Background.registerForTemporalEvent(new Time.Duration(REFRESH_SECONDS));
        }
    }
}
