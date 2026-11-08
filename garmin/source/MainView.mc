import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Quatre écrans « Tendance 24 h » (navigation : voir Pages.mc) :
//   0 : intérieur, température et humidité
//   1 : intérieur, CO2 et bruit
//   2 : extérieur, température et humidité
//   3 : pression atmosphérique
// Données des 4 écrans : chargées une seule fois (à l'ouverture), partagées par les vues.
class NetatmoStore {

    var _data as Dictionary or Null;
    var _status as String or Null;
    var _loading as Boolean = false;
    var _tried as Boolean = false;

    // chargement en cours
    var _req as NetatmoRequest or Null;
    var _dev as Dictionary or Null;
    var _cur as Dictionary or Null;
    var _in as Array or Null;
    var _start as Number = 0;
    // 3 images en mémoire graphique, réutilisées (jamais libérées : une image
    // créée juste après une libération peut perdre son contenu) ; _slotPage : écran
    // qu'elles contiennent pour les données _bmpFor (-1 : aucun)
    var _slots as Array = [null, null, null];
    var _slotPage as Array = [-1, -1, -1];
    var _bmpFor as Dictionary or Null;

    function initialize() {
        _data = Application.Storage.getValue("history") as Dictionary or Null;
        // La réponse de connexion peut arriver après un redémarrage de l'app.
        Communications.registerForOAuthMessages(method(:onOAuth));
    }

    // Un seul chargement à l'ouverture (et pas du tout si les données ont moins de
    // 10 min) ; changer d'écran ne fait que redessiner.
    function ensureLoaded() as Void {
        // une seule tentative par ouverture de l'app (chaque écran appelle ceci)
        if (_tried) {
            return;
        }
        _tried = true;
        var d = _data;
        var fetched = d != null ? d["fetched"] : null;
        if (fetched instanceof Number && Time.now().value() - fetched < REFRESH_SECONDS
                && !Netatmo.isDemo()) {
            return;
        }
        refresh();
    }

    // ------------------------------------------------------------ chargement

    function refresh() as Void {
        if (_loading) {
            return;
        }
        if (Netatmo.isDemo()) {
            done(Demo.data(true));
            return;
        }
        if (Netatmo.clientId() == null || Netatmo.clientSecret() == null) {
            fail(Netatmo.NOT_CONFIGURED, null);
            return;
        }
        if (!Netatmo.hasLogin()) {
            startLogin();
            return;
        }
        _loading = true;
        _status = null;
        get("/api/getstationsdata", { "get_favorites" => "false" }, method(:onStations));
        WatchUi.requestUpdate();
    }

    function get(path as String, params as Dictionary, cb as Method) as Void {
        _req = new NetatmoRequest(path, params, cb);
        (_req as NetatmoRequest).start();
    }

    function onStations(code as Number, data as Dictionary or String or Null) as Void {
        var dev = code == 200 ? Netatmo.firstDevice(data) : null;
        if (dev == null) {
            fail(code, data);
            return;
        }
        _dev = dev;
        _cur = Netatmo.current(dev);
        Application.Storage.setValue("current", _cur);
        WatchUi.requestUpdate();

        var now = Time.now().value();
        _start = (now / Netatmo.STEP) * Netatmo.STEP - (Netatmo.POINTS - 1) * Netatmo.STEP;
        get("/api/getmeasure", measureParams(dev["_id"] as String, null,
            "temperature,humidity,co2,noise,pressure", now), method(:onMeasureIn));
    }

    function measureParams(deviceId as String, moduleId as String or Null, types as String,
                           now as Number) as Dictionary {
        var p = {
            "device_id" => deviceId, "scale" => "30min", "type" => types,
            "date_begin" => _start - Netatmo.STEP, "date_end" => now,
            "optimize" => "true", "real_time" => "false"
        };
        if (moduleId != null) {
            p["module_id"] = moduleId;
        }
        return p;
    }

    function onMeasureIn(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200) {
            fail(code, data);
            return;
        }
        _in = Netatmo.series(data, _start, 5);
        var m = Netatmo.outdoorModule(_dev as Dictionary);
        if (m == null) {
            onMeasureOut(200, null);
            return;
        }
        get("/api/getmeasure", measureParams((_dev as Dictionary)["_id"] as String,
            m["_id"] as String, "temperature,humidity", Time.now().value()), method(:onMeasureOut));
    }

    function onMeasureOut(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200) {
            fail(code, data);
            return;
        }
        var o = Netatmo.series(data, _start, 2);
        var i = _in as Array;
        var d = _cur as Dictionary;
        d["start"] = _start;
        d["step"] = Netatmo.STEP;
        d["hist"] = { "ot" => o[0], "oh" => o[1], "p" => i[4],
                      "it" => i[0], "ih" => i[1], "co2" => i[2], "n" => i[3] };
        d["fetched"] = Time.now().value();
        Application.Storage.setValue("history", d);
        done(d);
    }

    function done(d as Dictionary) as Void {
        _loading = false;
        _req = null;
        _in = null;
        _dev = null;
        _data = d;
        _status = null;
        if (Netatmo.isDemo()) {
            Application.Storage.setValue("current", Demo.data(false));
        }
        WatchUi.requestUpdate();
    }

    function fail(code as Number, data) as Void {
        _loading = false;
        _req = null;
        if (code == Netatmo.AUTH_REQUIRED) {
            startLogin();
            return;
        }
        _status = Netatmo.errorText(code, data);
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ connexion
    // La page de connexion Netatmo s'ouvre dans Garmin Connect sur le téléphone.

    function startLogin() as Void {
        var state = Math.rand().format("%08x") + Math.rand().format("%08x");
        Application.Storage.setValue("oauth_state", state);
        Communications.makeOAuthRequest(Netatmo.AUTH_URL, {
                "client_id" => Netatmo.clientId(),
                "redirect_uri" => Netatmo.REDIRECT_URI,
                "scope" => Netatmo.SCOPE,
                "state" => state
            }, Netatmo.REDIRECT_URI, Communications.OAUTH_RESULT_TYPE_URL,
            { "code" => "code", "state" => "state", "error" => "error" });
        _status = "Connexion Netatmo :\nouvre la notification\nsur ton téléphone";
        WatchUi.requestUpdate();
    }

    function onOAuth(message as Communications.OAuthMessage) as Void {
        var d = message.data;
        var code = d != null ? d["code"] : null;
        var expected = Application.Storage.getValue("oauth_state");
        if (code == null || expected == null || !expected.equals(d["state"])) {
            _status = "Connexion refusée";
            WatchUi.requestUpdate();
            return;
        }
        Application.Storage.deleteValue("oauth_state");
        _status = "Connexion…";
        WatchUi.requestUpdate();
        Netatmo.exchangeCode(code as String, method(:onAuthToken));
    }

    function onAuthToken(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary && data["access_token"] != null) {
            Netatmo.saveTokens(data);
            _status = null;
            refresh();
        } else {
            _status = "Connexion : " + Netatmo.errorText(code, data);
            WatchUi.requestUpdate();
        }
    }
}

// Un écran « Tendance 24 h ». Passer d'un écran à l'autre fait glisser la vue
// (transition système) ; les données restent celles du NetatmoStore partagé.
class PageView extends WatchUi.View {

    var _page as Number;
    var _store as NetatmoStore;
    var _line as Line or Null;
    var _timer as Timer.Timer or Null;

    function initialize(page as Number, store as NetatmoStore) {
        View.initialize();
        _page = page;
        _store = store;
    }

    function onShow() as Void {
        _store.ensureLoaded();
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    // ------------------------------------------------------------ cache
    // Dessiner un écran (≈ 1 500 rectangles, courbe, textes) prend du temps : la montre
    // doit l'avoir fini avant de lancer le glissement. On le dessine donc une seule fois
    // dans une image, puis on se contente de la recopier. Les écrans voisins sont
    // préparés juste après l'affichage, pour que le glissement suivant parte aussitôt.

    function bitmap(page as Number, W as Number, H as Number, create as Boolean)
            as Graphics.BufferedBitmap or Null {
        var d = _store._data;
        if (d == null) {
            return null;
        }
        var st = _store;
        if (st._bmpFor != d) {
            st._slotPage = [-1, -1, -1];
            st._bmpFor = d;
        }
        var free = -1;
        for (var i = 0; i < 3; i++) {
            var sp = st._slotPage[i] as Number;
            if (sp == page) {
                var b = st._slots[i] == null ? null
                    : (st._slots[i] as Graphics.BufferedBitmapReference).get();
                if (b != null) {
                    return b as Graphics.BufferedBitmap;
                }
                st._slotPage[i] = -1;       // image libérée par le système
                sp = -1;
            }
            // emplacement réutilisable : vide, ou écran ni affiché ni voisin
            if (free < 0 && (sp < 0 || (sp != _page && sp != (_page + 1) % PAGES
                                        && sp != (_page + PAGES - 1) % PAGES))) {
                free = i;
            }
        }
        if (!create || free < 0 || !(Graphics has :createBufferedBitmap)) {
            return null;
        }
        try {
            var b = st._slots[free] == null ? null
                : (st._slots[free] as Graphics.BufferedBitmapReference).get();
            if (b == null) {
                var r = Graphics.createBufferedBitmap({:width => W, :height => H});
                st._slots[free] = r;
                b = r.get();
                if (b == null) {
                    return null;
                }
            }
            var bdc = (b as Graphics.BufferedBitmap).getDc();
            bdc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            bdc.clear();
            if (bdc has :setAntiAlias) {
                bdc.setAntiAlias(true);
            }
            drawPage(bdc, W, H, page);
            st._slotPage[free] = page;
            return b as Graphics.BufferedBitmap;
        } catch (e) {
            return null;
        }
    }

    // Prépare un écran voisin pas encore dessiné (un par appel, pour rester sous
    // le temps alloué), puis se reprogramme.
    function prepareNext() as Void {
        _timer = null;
        if (_store._data == null) {
            return;
        }
        var nb = [(_page + 1) % PAGES, (_page + PAGES - 1) % PAGES];
        for (var i = 0; i < nb.size(); i++) {
            var p = nb[i] as Number;
            if (bitmap(p, _w, _h, false) == null) {
                if (bitmap(p, _w, _h, true) != null) {
                    schedule();
                }
                return;
            }
        }
    }

    var _w as Number = 0;
    var _h as Number = 0;

    function schedule() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:prepareNext), 60, false);
        }
    }

    // ------------------------------------------------------------ affichage
    // Sur le modèle de l'écran « Tendance » de la météo Garmin :
    // titre, légende, barres + courbe, pointillés gradués à droite, heures en bas.

    function onUpdate(dc as Graphics.Dc) as Void {
        var W = dc.getWidth();
        var H = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var d = _store._data;
        if (d == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(W / 2, H / 2, Graphics.FONT_SMALL,
                _store._status != null ? _store._status : "Chargement…",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        _w = W;
        _h = H;
        var bmp = bitmap(_page, W, H, true);
        if (bmp != null) {
            dc.drawBitmap(0, 0, bmp);
            schedule();
        } else {
            drawPage(dc, W, H, _page);
        }
        drawDots(dc, W, H);
        drawStatus(dc, W, H, d);
    }

    // En-tête et graphique d'un écran (partie mise en cache).
    function drawPage(dc as Graphics.Dc, W as Number, H as Number, page as Number) as Void {
        var d = _store._data as Dictionary;
        var hist = d["hist"] as Dictionary;

        // barres (ou null) puis courbe de chaque écran
        var bars = null as Bars or Null;
        var line;
        var indoor = page <= 1;
        if (page == 0) {
            bars = new Bars("Humidité", "Hum.", hist["ih"] as Array, Draw.HUMI, Draw.HUMI_LO, 0.0, 100.0);
            line = new Line("Temp.", hist["it"] as Array, Draw.TEMP, 2.0, "°");
        } else if (page == 1) {
            bars = new Bars("Bruit", "Bruit", hist["n"] as Array, Draw.LOGO, Draw.LOGO, 30.0, 80.0);
            bars.noise = true;
            line = new Line("CO2", hist["co2"] as Array, Draw.NEUTRAL, 200.0, "ppm");
        } else if (page == 2) {
            bars = new Bars("Humidité", "Hum.", hist["oh"] as Array, Draw.HUMI, Draw.HUMI_LO, 0.0, 100.0);
            line = new Line("Temp.", hist["ot"] as Array, Draw.TEMP, 2.0, "°");
        } else {
            line = new Line("Pression", hist["p"] as Array, Draw.PRES, 4.0, "hPa");
        }

        _line = line;
        // ---- En-tête : symbole + légende sur une ligne
        var lf = Graphics.FONT_TINY;
        var ly = H * 19 / 100;
        var iconS = dc.getFontHeight(lf) * 75 / 100;
        var name1 = line.name;
        var name2 = bars != null ? (bars as Bars).name : null;
        var avail = W * 72 / 100;
        var hw = headerWidth(dc, iconS, name1, name2, lf);
        if (hw > avail && bars != null) {
            name2 = (bars as Bars).shortName;
            hw = headerWidth(dc, iconS, name1, name2, lf);
        }
        if (hw > avail) {
            name1 = line.shortName;
            hw = headerWidth(dc, iconS, name1, name2, lf);
        }
        var hx = (W - hw) / 2;
        if (indoor) {
            Draw.indoor(dc, hx + iconS / 2, ly, iconS, Graphics.COLOR_WHITE);
        } else {
            Draw.outdoor(dc, hx + iconS / 2, ly, iconS, Graphics.COLOR_WHITE);
        }
        hx += iconS + 14;
        drawLegend(dc, hx, ly, name1, line.color, lf);
        var u1 = unitText(line);
        if (u1 != null) {
            var ux = hx + legendWidth(dc, name1, lf) + 6;
            dc.setColor(Draw.DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(ux, ly, Graphics.FONT_XTINY, u1 as String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (name2 != null) {
            drawLegend(dc, hx + legendWidth(dc, name1, lf) + unitWidth(dc, line) + 16, ly, name2 as String,
                       (bars as Bars).noise ? -1 : (bars as Bars).hi, lf);
        }

        // ---- Graphique
        var cx0 = W * 15 / 100;
        var cx1 = W * 76 / 100;
        // graduations à 4 chiffres (pression) : on rétrécit le graphique
        var lblW = dc.getTextWidthInPixels(line.unit.equals("°") ? "22°" : "1024", Graphics.FONT_XTINY);
        if (cx1 > W * 88 / 100 - lblW - 8) {
            cx1 = W * 88 / 100 - lblW - 8;
        }
        var cy0 = H * 29 / 100;
        var cy1 = H * 74 / 100;
        var n = line.values.size();
        if (bars != null && (bars as Bars).values.size() > n) {
            n = (bars as Bars).values.size();
        }
        if (n >= 2) {
            if (bars != null) {
                drawBars(dc, cx0, cy0, cx1 - cx0, cy1 - cy0, bars as Bars, n);
            }
            drawLine(dc, cx0, cy0, cx1 - cx0, cy1 - cy0, line, n);
            // ligne de base
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(cx0, cy1, cx1, cy1);
            dc.setPenWidth(1);
            drawHours(dc, cx0, cy1, cx1 - cx0, n, d["start"] as Number, d["step"] as Number);
        }
    }

    function drawDots(dc as Graphics.Dc, W as Number, H as Number) as Void {
        // ---- Indicateur de page : 4 petits points discrets à gauche, sur un arc
        // parallèle au bord de l'écran (comme l'app Météo native)
        // Points sur un arc plus courbé que le bord (rayon 55 %), tangent à un cercle
        // proche du bord au milieu : l'arrondi se voit malgré le faible écart des points.
        var R = (W < H ? W : H) / 2 - (W * 3 / 100 + 3);
        var Rc = R * 55 / 100;
        var stepA = 26.0 / Rc;                   // ~26 px entre deux points
        for (var p = 0; p < PAGES; p++) {
            var a = Math.PI + (p - (PAGES - 1) / 2.0) * stepA;   // haut -> bas
            var px = W / 2 - R + Rc + (Rc * Math.cos(a)).toNumber();
            var py = H / 2 - (Rc * Math.sin(a)).toNumber();
            dc.setColor(p == _page ? Graphics.COLOR_WHITE : 0x555555, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(px, py, p == _page ? 3 : 2);
        }
    }

    function drawStatus(dc as Graphics.Dc, W as Number, H as Number, d as Dictionary) as Void {
        // ---- État (chargement / erreur)
        var st = _store._status;
        if (st == null && _store._loading) {
            st = "Actualisation…";
        }
        if (st != null) {
            // échec alors que des courbes sont affichées : simple rappel, en gris,
            // avec l'heure des données
            var color = Draw.DIM;
            var dt = d["time"] as Number or Null;
            if (_store._status != null && dt != null) {
                var info = Gregorian.info(new Time.Moment(dt), Time.FORMAT_SHORT);
                var hhmm = info.hour.format("%02d") + ":" + info.min.format("%02d");
                st = st + " · " + hhmm;
                if (dc.getTextWidthInPixels(st as String, Graphics.FONT_XTINY) > W * 64 / 100) {
                    st = "Données de " + hhmm;
                }
            } else if (_store._status != null) {
                color = Graphics.COLOR_RED;
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(W / 2, H * 87 / 100, Graphics.FONT_XTINY, st,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function legendWidth(dc as Graphics.Dc, txt as String, f) as Number {
        return 22 + dc.getTextWidthInPixels(txt, f);
    }

    // ▬ Tempér.
    function drawLegend(dc as Graphics.Dc, x as Number, cy as Number, txt as String,
                        color as Number, f) as Void {
        if (color < 0) {
            // échelle du bruit : vert -> rouge
            for (var i = 0; i < 4; i++) {
                dc.setColor(Draw.noiseColor(50.0 + i * 10.0), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x + i * 4, cy - 3, 4, 6);
            }
        } else {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, cy - 3, 16, 6, 2);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 22, cy, f, txt, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Une barre par heure (moyenne des deux mesures de la demi-heure), en dégradé.
    // La couleur ne dépend que de la hauteur dans le graphique : on la calcule une fois
    // par ligne (3 px) et on peint ligne par ligne toutes les barres qui l'atteignent.
    // (calculer chaque nuance pour chaque barre dépasse le temps alloué par la montre)
    function drawBars(dc as Graphics.Dc, x as Number, y as Number, w as Number, h as Number,
                      b as Bars, n as Number) as Void {
        var ROW = 3;
        var slots = (n - 1) / 2;
        var slotW = w.toFloat() / slots;
        var gap = slotW > 8 ? 2 : 1;
        var bw = (slotW - gap).toNumber();
        if (bw < 1) { bw = 1; }

        // hauteur de chaque barre (-1 : pas de mesure)
        var heights = new [slots];
        var maxH = 0;
        for (var j = 0; j < slots; j++) {
            var sum = 0.0, cnt = 0;
            for (var k = 1; k <= 2; k++) {
                var idx = 2 * j + k;
                if (idx < b.values.size() && b.values[idx] != null) {
                    sum += (b.values[idx] as Numeric).toFloat();
                    cnt++;
                }
            }
            var bh = -1;
            if (cnt > 0) {
                var f = (sum / cnt - b.lo) / (b.vmax - b.lo);
                if (f < 0.02) { f = 0.02; }
                if (f > 1.0) { f = 1.0; }
                bh = (h * f).toNumber();
                if (bh > maxH) { maxH = bh; }
            }
            heights[j] = bh;
        }

        var bottom = y + h;
        var rows = (maxH + ROW - 1) / ROW;
        for (var r = 0; r < rows; r++) {
            // couleur à cette hauteur (0 : bas du graphique, 1 : haut)
            var level = ((r * ROW) + ROW / 2.0) / h;
            if (b.noise) {
                dc.setColor(Draw.noiseColor(b.lo + level * (b.vmax - b.lo)), Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Draw.mix(b.hi, b.low, 1.0 - level), Graphics.COLOR_TRANSPARENT);
            }
            var rowLo = r * ROW;             // hauteur du bas de la ligne
            var y1 = bottom - rowLo;
            for (var j = 0; j < slots; j++) {
                var bh = heights[j] as Number;
                if (bh > rowLo) {
                    var top = bh - rowLo < ROW ? bh - rowLo : ROW;
                    dc.fillRectangle(x + (j * slotW).toNumber() + gap / 2, y1 - top, bw, top);
                }
            }
        }
    }

    // Courbe épaisse, pointillés et graduations à droite.
    function drawLine(dc as Graphics.Dc, x as Number, y as Number, w as Number, h as Number,
                      l as Line, n as Number) as Void {
        if (l.lo == null) {
            return;
        }
        var lo = l.lo as Float;
        var hi = l.hi as Float;
        if (hi - lo < l.minSpan) {
            var mid = (lo + hi) / 2.0;
            lo = mid - l.minSpan / 2.0;
            hi = mid + l.minSpan / 2.0;
        }
        var steps = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0];
        var step = 1.0;
        for (var i = 0; i < steps.size(); i++) {
            step = steps[i] as Float;
            if (Math.ceil(hi / step) - Math.floor(lo / step) <= 4) {
                break;
            }
        }
        var aLo = Math.floor(lo / step) * step;
        var aHi = Math.ceil(hi / step) * step;
        // nombre pair d'intervalles : graduation au milieu
        var nInt = Math.round((aHi - aLo) / step).toNumber();
        if (nInt < 2) {
            nInt = 2;
        } else if (nInt % 2 == 1) {
            nInt++;
        }
        aHi = aLo + nInt * step;
        var scale = h / (aHi - aLo);

        // pointillés et graduations
        var af = Graphics.FONT_XTINY;
        var v = aLo;
        var k = 0;
        while (v <= aHi + step / 10.0) {
            var gy = y + h - ((v - aLo) * scale).toNumber();
            if (v > aLo + step / 10.0) {
                dc.setColor(Draw.GRID, Graphics.COLOR_TRANSPARENT);
                for (var dx = x; dx < x + w; dx += 6) {
                    dc.fillRectangle(dx, gy, 3, 2);
                }
            }
            // étiquettes : extrêmes et milieu seulement
            if (k == 0 || k == nInt || k * 2 == nInt) {
                var txt = step < 1.0 ? v.format("%.1f") : v.format("%.0f");
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + w + 8, gy, af, txt + (l.unit.equals("°") ? "°" : ""),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            v += step;
            k++;
        }

        // courbe : contour noir puis couleur, pour ressortir sur les barres
        for (var pass = 0; pass < 2; pass++) {
            dc.setPenWidth(pass == 0 ? 9 : 5);
            dc.setColor(pass == 0 ? Graphics.COLOR_BLACK : l.color, Graphics.COLOR_TRANSPARENT);
            var px = 0, py = 0;
            var prev = false;
            for (var i = 0; i < l.values.size(); i++) {
                var val = l.values[i];
                if (val == null) {
                    prev = false;
                    continue;
                }
                var cx = x + w * i / (n - 1);
                var cy = y + h - (((val as Numeric).toFloat() - aLo) * scale).toNumber();
                if (prev) {
                    dc.drawLine(px, py, cx, cy);
                } else {
                    dc.fillCircle(cx, cy, pass == 0 ? 4 : 2);
                }
                px = cx;
                py = cy;
                prev = true;
            }
        }
        dc.setPenWidth(1);
    }

    // Repères horaires : début + 1 h, milieu et fin - 1 h (heures rondes), avec un index.
    function drawHours(dc as Graphics.Dc, x as Number, y as Number, w as Number, n as Number,
                       start as Number, step as Number) as Void {
        var af = Graphics.FONT_XTINY;
        var span = (n - 1) * step;
        var end = start + span;
        var marks = [roundHour(start) + 3600, roundHour(start + span / 2), roundHour(end) - 3600];
        for (var i = 0; i < marks.size(); i++) {
            var t = marks[i] as Number;
            var mx = x + ((t - start).toLong() * w / span).toNumber();
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(mx, y, mx, y + 7);
            dc.setPenWidth(1);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(mx, y + 8, af, hourText(t), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Unité affichée en petit après le nom de la courbe (ppm, hPa) ; « ° » est sur l'échelle.
    function unitText(l as Line) as String or Null {
        return (l.unit.length() == 0 || l.unit.equals("°")) ? null : l.unit;
    }

    function unitWidth(dc as Graphics.Dc, l as Line) as Number {
        var u = unitText(l);
        return u == null ? 0 : 6 + dc.getTextWidthInPixels(u as String, Graphics.FONT_XTINY);
    }

    function roundHour(t as Number) as Number {
        return ((t + 1800) / 3600) * 3600;
    }

    function hourText(t as Number) as String {
        var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT);
        return info.hour.format("%d") + "h";
    }

    function headerWidth(dc as Graphics.Dc, iconS as Number, n1 as String, n2 as String or Null,
                         f) as Number {
        var w = iconS + 14 + legendWidth(dc, n1, f) + unitWidth(dc, _line as Line);
        if (n2 != null) {
            w += 16 + legendWidth(dc, n2, f);
        }
        return w;
    }
}

// Mesures affichées en barres : échelle lo..max (max agrandi si besoin), dégradé hi -> low.
class Bars {
    var name as String;
    var shortName as String;
    var values as Array;
    var hi as Number;
    var low as Number;
    var lo as Float;
    var vmax as Float;
    var noise as Boolean = false;   // couleurs de l'échelle du bruit

    function initialize(name as String, shortName as String, values as Array or Null,
                        hi as Number, low as Number, lo as Float, vmax as Float) {
        self.name = name;
        self.shortName = shortName;
        self.values = values == null ? [] : values;
        self.hi = hi;
        self.low = low;
        self.lo = lo;
        self.vmax = vmax;
    }
}

// Mesures affichées en courbe, graduées à droite.
class Line {
    var name as String;
    var shortName as String;
    var values as Array;
    var color as Number;
    var minSpan as Float;
    var unit as String;
    var lo as Float or Null = null;
    var hi as Float or Null = null;

    function initialize(name as String, values as Array or Null, color as Number,
                        minSpan as Float, unit as String) {
        self.name = name;
        var sp = name.find(" (");
        self.shortName = sp == null ? name : name.substring(0, sp) as String;
        self.values = values == null ? [] : values;
        self.color = color;
        self.minSpan = minSpan;
        self.unit = unit;
        for (var i = 0; i < self.values.size(); i++) {
            var v = self.values[i];
            if (v == null) {
                continue;
            }
            var f = (v as Numeric).toFloat();
            if (lo == null || f < lo) { lo = f; }
            if (hi == null || f > hi) { hi = f; }
        }
    }
}
