import Toybox.Graphics;
import Toybox.Lang;

// Symboles, jauges, polices et mise en forme partagés par l'aperçu et les écrans.
(:glance)
module Draw {

    const LOGO = 0xFE8E15;      // orange du logo : niveau sonore
    const TEMP = LOGO;          // courbe de température : orange du logo
    const HUMI = 0x2FB8F5;      // humidité
    const HUMI_LO = 0x1A3CE8;   // bas des barres d'humidité
    const CO2C = 0x5EE07A;      // CO2
    const CO2_LO = 0x0E7A30;    // bas des barres de CO2
    const PRES = 0xE6E6E6;      // pression
    const NEUTRAL = 0xD8D8D8;   // courbe de CO2
    const SUN  = 0xFFC83D;      // soleil du symbole extérieur
    const DIM  = 0x8A8A8A;      // textes secondaires
    const GRID = 0x9A9A9A;      // pointillés
    const TRACK = 0x3A3A3A;     // fond des jauges

    // ------------------------------------------------------------ polices

    // Police vectorielle de « size » pixels, ou la police système la plus proche.
    function font(size as Number) as Graphics.FontType {
        if (Graphics has :getVectorFont) {
            var f = Graphics.getVectorFont({ :face => ["RobotoRegular", "RobotoCondensedRegular"],
                                             :size => size });
            if (f != null) {
                return f;
            }
        }
        var list = [Graphics.FONT_XTINY, Graphics.FONT_TINY, Graphics.FONT_SMALL,
                    Graphics.FONT_MEDIUM, Graphics.FONT_LARGE];
        var best = list[0];
        for (var i = 0; i < list.size(); i++) {
            if (Graphics.getFontHeight(list[i]) <= size * 125 / 100) {
                best = list[i];
            }
        }
        return best;
    }

    // ------------------------------------------------------------ formats

    // "9.8" -> ["9", ".8"] ; "-3.2" -> ["-3", ".2"]
    function splitTemp(v as Numeric) as Array<String> {
        var s = v.toFloat().format("%.1f");
        var i = s.find(".");
        if (i == null) {
            return [s, ""];
        }
        return [s.substring(0, i) as String, s.substring(i, s.length()) as String];
    }

    function fmt1(v) as String {
        return v == null ? "--" : (v as Numeric).toFloat().format("%.1f");
    }

    function fmt0(v) as String {
        return v == null ? "--" : (v as Numeric).toFloat().format("%.0f");
    }

    // Mélange de deux couleurs (t = 0 : a, t = 1 : b).
    function mix(a as Number, b as Number, t as Float) as Number {
        var r = ((a >> 16) & 0xFF) + ((((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t).toNumber();
        var g = ((a >> 8) & 0xFF) + ((((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t).toNumber();
        var bl = (a & 0xFF) + (((b & 0xFF) - (a & 0xFF)) * t).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    // Échelle colorée du bruit : vert jusqu'à 55 dB, puis jaune, orange, rouge vers 80 dB.
    function noiseColor(db as Float) as Number {
        var stops = [55.0, 62.0, 70.0, 78.0];
        var cols = [0x5BC85B, 0xF2C230, 0xEE8530, 0xE5463E];
        if (db <= stops[0]) {
            return cols[0];
        }
        for (var i = 1; i < stops.size(); i++) {
            if (db <= stops[i]) {
                return mix(cols[i - 1], cols[i], (db - stops[i - 1]) / (stops[i] - stops[i - 1]));
            }
        }
        return cols[cols.size() - 1];
    }

    // ------------------------------------------------------------ symboles

    // Soleil derrière un nuage : symbole « extérieur ».
    function outdoor(dc as Graphics.Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        var sx = cx - s * 18 / 100;
        var sy = cy - s * 16 / 100;
        var sr = s * 20 / 100;
        dc.setColor(color == DIM ? DIM : SUN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, sr);
        dc.setPenWidth(s / 14 > 1 ? s / 14 : 1);
        var r1 = sr + s * 7 / 100;
        var r2 = sr + s * 16 / 100;
        var d1 = r1 * 71 / 100, d2 = r2 * 71 / 100;
        dc.drawLine(sx, sy - r1, sx, sy - r2);
        dc.drawLine(sx - r1, sy, sx - r2, sy);
        dc.drawLine(sx - d1, sy - d1, sx - d2, sy - d2);
        dc.drawLine(sx + d1, sy - d1, sx + d2, sy - d2);
        dc.drawLine(sx - d1, sy + d1, sx - d2, sy + d2);
        dc.setPenWidth(1);
        // nuage : contour noir pour le détacher du soleil
        var o = s / 16 > 1 ? s / 16 : 1;
        for (var pass = 0; pass < 2; pass++) {
            var e = pass == 0 ? o : 0;
            dc.setColor(pass == 0 ? Graphics.COLOR_BLACK : color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - s * 20 / 100, cy + s * 20 / 100, s * 18 / 100 + e);
            dc.fillCircle(cx + s * 6 / 100, cy + s * 6 / 100, s * 26 / 100 + e);
            dc.fillCircle(cx + s * 32 / 100, cy + s * 20 / 100, s * 18 / 100 + e);
            dc.fillRoundedRectangle(cx - s * 38 / 100 - e, cy + s * 14 / 100 - e,
                s * 88 / 100 + 2 * e, s * 24 / 100 + 2 * e, s * 12 / 100 + e);
        }
    }

    // Maison : symbole « intérieur ».
    function indoor(dc as Graphics.Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var half = s / 2;
        var roofY = cy - half;
        var eaveY = cy - s / 12;
        dc.fillPolygon([[cx, roofY], [cx - half, eaveY], [cx + half, eaveY]]);
        var bw = s * 72 / 100;
        var bx = cx - bw / 2;
        var by = eaveY - 1;
        var bh = cy + half - by;
        dc.fillRectangle(bx, by, bw, bh);
        // porte
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var dw = s / 5 > 3 ? s / 5 : 3;
        var dh = bh * 55 / 100;
        dc.fillRectangle(cx - dw / 2, cy + half - dh, dw, dh);
    }

    // Goutte d'eau : humidité.
    function drop(dc as Graphics.Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        // pointe : même angle qu'avant ; partie ronde réduite
        var r = s * 26 / 100;
        var tip = cy - s * 42 / 100;
        var ccy = tip + s * 54 / 100;
        dc.fillCircle(cx, ccy, r);
        dc.fillPolygon([[cx, tip], [cx - r * 88 / 100, ccy - r * 48 / 100],
                        [cx + r * 88 / 100, ccy - r * 48 / 100]]);
    }

    // Haut-parleur avec ondes : niveau sonore.
    function noise(dc as Graphics.Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var x0 = cx - s / 2;
        var bh = s * 34 / 100;
        var bw = s * 18 / 100;
        dc.fillRectangle(x0, cy - bh / 2, bw, bh);
        var cone = s * 30 / 100;
        dc.fillPolygon([[x0 + bw - 1, cy - bh / 2], [x0 + bw + cone, cy - s * 42 / 100],
                        [x0 + bw + cone, cy + s * 42 / 100], [x0 + bw - 1, cy + bh / 2]]);
        var pw = s / 12 > 1 ? s / 12 : 1;
        dc.setPenWidth(pw);
        var ax = x0 + bw + cone;
        dc.drawArc(ax, cy, s * 22 / 100, Graphics.ARC_COUNTER_CLOCKWISE, -45, 45);
        dc.drawArc(ax, cy, s * 42 / 100, Graphics.ARC_COUNTER_CLOCKWISE, -45, 45);
        dc.setPenWidth(1);
    }

    // ------------------------------------------------------------ formes

    // Jauge verticale : frac entre 0 et 1, remplie depuis le bas.
    function vbar(dc as Graphics.Dc, x as Number, top as Number, w as Number, h as Number,
                  frac as Float or Null, color as Number) as Void {
        var r = w / 2;
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, w, h, r);
        if (frac == null) {
            return;
        }
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fh = (h * frac).toNumber();
        if (fh < w) {
            fh = frac > 0.0 ? w : 0;
        }
        if (fh > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top + h - fh, w, fh, r);
        }
    }

    // Jauge verticale du bruit : remplie depuis le bas, en dégradé de l'échelle colorée
    // (dbLo en bas de la jauge, dbHi en haut).
    function vbarNoise(dc as Graphics.Dc, x as Number, top as Number, w as Number, h as Number,
                       db as Float or Null, dbLo as Float, dbHi as Float) as Void {
        var r = w / 2;
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, w, h, r);
        if (db == null) {
            return;
        }
        var frac = (db - dbLo) / (dbHi - dbLo);
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fh = (h * frac).toNumber();
        if (fh < w) {
            fh = frac > 0.0 ? w : 0;
        }
        if (fh <= 0) {
            return;
        }
        var bottom = top + h;
        var fTop = bottom - fh;
        // extrémités arrondies
        dc.setColor(noiseColor(dbLo), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r, bottom - r, r);
        dc.setColor(noiseColor(dbLo + (dbHi - dbLo) * (fh - r).toFloat() / h), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r, fTop + r, r);
        // corps : une nuance tous les 2 pixels
        for (var yy = bottom - r; yy > fTop + r; yy -= 2) {
            var hgt = yy - (fTop + r) < 2 ? yy - (fTop + r) : 2;
            dc.setColor(noiseColor(dbLo + (dbHi - dbLo) * (bottom - yy).toFloat() / h),
                        Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, yy - hgt, w, hgt);
        }
    }

    // Chevron de tendance : "up" ^, "down" v, sinon rien.
    function trend(dc as Graphics.Dc, cx as Number, cy as Number, s as Number,
                   trend as String or Null, color as Number) as Boolean {
        if (trend == null || !(trend.equals("up") || trend.equals("down"))) {
            return false;
        }
        var d = trend.equals("up") ? -1 : 1;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s / 4 > 2 ? s / 4 : 2);
        dc.drawLine(cx - s / 2, cy - d * s / 4, cx, cy + d * s / 4);
        dc.drawLine(cx, cy + d * s / 4, cx + s / 2, cy - d * s / 4);
        dc.setPenWidth(1);
        return true;
    }

    // Flèche min (vers une barre en bas) ou max (depuis une barre en haut).
    function minMaxArrow(dc as Graphics.Dc, cx as Number, cy as Number, s as Number,
                         isMax as Boolean, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var pw = s / 6 > 1 ? s / 6 : 1;
        dc.setPenWidth(pw);
        var half = s / 2;
        var head = s * 35 / 100;
        if (isMax) {
            dc.drawLine(cx - half + 1, cy - half, cx + half - 1, cy - half);
            dc.drawLine(cx, cy - half + pw + 1, cx, cy + half);
            dc.drawLine(cx, cy - half + pw + 1, cx - head, cy - half + pw + 1 + head);
            dc.drawLine(cx, cy - half + pw + 1, cx + head, cy - half + pw + 1 + head);
        } else {
            dc.drawLine(cx - half + 1, cy + half, cx + half - 1, cy + half);
            dc.drawLine(cx, cy - half, cx, cy + half - pw - 1);
            dc.drawLine(cx, cy + half - pw - 1, cx - head, cy + half - pw - 1 - head);
            dc.drawLine(cx, cy + half - pw - 1, cx + head, cy + half - pw - 1 - head);
        }
        dc.setPenWidth(1);
    }
}
