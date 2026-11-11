import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Aperçu : la maison calée à gauche, l'extérieur calé à droite.
//   [maison] 20.7° [hum.|goutte] [bruit|son]        [soleil/nuage] v9.8° [hum.|goutte]
//                                                  ↓7.8  ↑20.5   (sous le symbole)
(:glance)
class NetatmoGlanceView extends WatchUi.GlanceView {

    const NOISE_MIN = 30.0;     // dB : bas de la jauge
    const NOISE_MAX = 80.0;     // dB : haut de la jauge

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var W = dc.getWidth();
        var H = dc.getHeight();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var c = Application.Storage.getValue("current") as Dictionary or Null;
        if (c == null && Netatmo.isDemo()) {
            c = Demo.data(false);
        }
        if (c == null) {
            // pas encore de mesures : nom de l'app, et dessous ce qu'il reste à faire
            var hint = Netatmo.clientId() == null ? Rez.Strings.GlanceSetup
                : Netatmo.hasLogin() || Netatmo.isDemo() ? null : Rez.Strings.GlanceConnect;
            var j = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
            var name = WatchUi.loadResource(Rez.Strings.AppName) as String;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, hint == null ? H / 2 : H * 32 / 100, fitFont(dc, name, W, 0), name, j);
            if (hint != null) {
                var txt = WatchUi.loadResource(hint) as String;
                dc.setColor(Draw.DIM, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, H * 72 / 100, fitFont(dc, txt, W, 2), txt, j);
            }
            return;
        }
        var out = c["out"] as Dictionary or Null;
        var inn = c["in"] as Dictionary or Null;
        if (out == null) { out = {}; }
        if (inn == null) { inn = {}; }

        var time = c["time"] as Number or Null;
        var stale = time == null || Time.now().value() - time > 2 * 3600;
        var fg = stale ? Draw.DIM : Graphics.COLOR_WHITE;

        var outT = splitOrDash(out["t"]);
        var inT = splitOrDash(inn["t"]);
        var minTxt = Draw.fmt1(out["min"]);
        var maxTxt = Draw.fmt1(out["max"]);

        // ---- Tailles fixes (proportionnelles à la hauteur de l'aperçu)
        var symS = H * 26 / 100;                 // maison, soleil/nuage
        var colSym = H * 15 / 100;               // goutte, haut-parleur
        var barW = H * 6 / 100;
        if (barW < 5) { barW = 5; }
        var colW = colSym > barW ? colSym : barW;
        var gapV = H * 5 / 100;
        var barH = H * 92 / 100 - colSym - gapV;
        var g = H * 4 / 100;                     // écart dans un groupe
        var minGap = H * 14 / 100;               // écart minimal entre maison et extérieur

        // ---- Taille des chiffres : la plus grande qui tient
        var bs = H * 56 / 100;
        var big = Draw.font(bs), dec = big, mm = big;
        var digitH = 0, mmH = 0, outW = 0, outTopW = 0, inW = 0, chevW = 0, leftW = 0, rightW = 0;
        while (true) {
            big = Draw.font(bs);
            dec = Draw.font(bs * 50 / 100);
            mm = Draw.font(bs * 50 / 100);
            digitH = capHeight(big, bs);
            mmH = capHeight(mm, bs * 50 / 100);
            chevW = digitH * 28 / 100;
            outTopW = chevW + g / 2 + tempWidth(dc, outT, big, dec, digitH);
            // min/max sur toute la largeur, sous le symbole et la température
            var mmW = minMaxWidth(dc, minTxt, maxTxt, mm, mmH);
            outW = symS + g + outTopW;
            if (mmW > outW) { outW = mmW; }
            inW = tempWidth(dc, inT, big, dec, digitH);
            leftW = symS + g + inW + g + colW + g / 2 + colW;
            rightW = outW + g + colW;
            var top = digitH > symS ? digitH : symS;
            var stackH = top + mmH * 8 / 10 + mmH;
            if ((leftW + rightW + minGap <= W - 2 && stackH <= H * 94 / 100) || bs <= H * 24 / 100) {
                break;
            }
            bs -= 2;
        }

        // polices système (pas de polices vectorielles) : si min/max ne tiennent pas
        // même au plus petit, on les masque plutôt que de chevaucher la maison
        var showMM = leftW + rightW + minGap <= W - 2;
        if (!showMM) {
            outW = symS + g + outTopW;
            rightW = outW + g + colW;
        }

        var cy = H / 2;
        var barTop = (H - (barH + gapV + colSym)) / 2;
        var symY = barTop + barH + gapV + colSym / 2;

        // ---- Maison (à gauche)
        var x = 0;
        Draw.indoor(dc, x + symS / 2, cy, symS, fg);
        x += symS + g;
        drawTemp(dc, x, cy, inT, big, dec, digitH, fg);
        x += inW + g;
        drawGauge(dc, x, colW, barW, barTop, barH, symY, colSym,
                  frac(inn["h"], 0.0, 100.0), Draw.HUMI, :drop);
        x += colW + g / 2;
        drawGauge(dc, x, colW, barW, barTop, barH, symY, colSym,
                  frac(inn["n"], NOISE_MIN, NOISE_MAX), Draw.LOGO, :noise);

        // ---- Extérieur (à droite)
        // ligne du haut : symbole + température ; dessous : min et max
        x = W - rightW;
        var mmGap = mmH * 8 / 10;
        var topH = digitH > symS ? digitH : symS;
        var stack = showMM ? topH + mmGap + mmH : topH;
        var rowY = cy - stack / 2 + topH / 2;
        var mmY = cy - stack / 2 + topH + mmGap + mmH / 2;
        var tx = x + (outW - (symS + g + outTopW)) / 2;
        Draw.outdoor(dc, tx + symS / 2, rowY, symS, fg);
        var bx = tx + symS + g;
        Draw.trend(dc, bx + chevW / 2, rowY + digitH / 8, chevW, out["tr"] as String or Null, Draw.DIM);
        drawTemp(dc, bx + chevW + g / 2, rowY, outT, big, dec, digitH, fg);
        if (showMM) {
            var aw = mmH * 80 / 100;
            var mx = x + (outW - minMaxWidth(dc, minTxt, maxTxt, mm, mmH)) / 2;
            Draw.minMaxArrow(dc, mx + aw / 2, mmY, aw, false, Draw.DIM);
            mx += aw + 2;
            drawCapText(dc, mx, mmY, mm, mmH, minTxt, fg);
            mx += dc.getTextWidthInPixels(minTxt, mm) + mmH * 6 / 10;
            Draw.minMaxArrow(dc, mx + aw / 2, mmY, aw, true, Draw.DIM);
            mx += aw + 2;
            drawCapText(dc, mx, mmY, mm, mmH, maxTxt, fg);
        }
        x += outW + g;
        drawGauge(dc, x, colW, barW, barTop, barH, symY, colSym,
                  frac(out["h"], 0.0, 100.0), Draw.HUMI, :drop);
    }

    // Plus grande police (à partir de la n-ième de la liste) où le texte tient en largeur.
    function fitFont(dc as Graphics.Dc, txt as String, w as Number, from as Number)
            as Graphics.FontDefinition {
        var fonts = [Graphics.FONT_GLANCE, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        for (var i = from; i < fonts.size() - 1; i++) {
            if (dc.getTextWidthInPixels(txt, fonts[i] as Graphics.FontDefinition) <= w) {
                return fonts[i] as Graphics.FontDefinition;
            }
        }
        return Graphics.FONT_XTINY;
    }

    // Jauge verticale et son symbole centré en dessous.
    function drawGauge(dc as Graphics.Dc, x as Number, colW as Number, barW as Number,
                       barTop as Number, barH as Number, symY as Number, symS as Number,
                       f as Float or Null, color as Number, sym as Symbol) as Void {
        var cx = x + colW / 2;
        if (sym == :noise) {
            Draw.vbarNoise(dc, cx - barW / 2, barTop, barW, barH,
                f == null ? null : NOISE_MIN + f * (NOISE_MAX - NOISE_MIN), NOISE_MIN, NOISE_MAX);
        } else {
            Draw.vbar(dc, cx - barW / 2, barTop, barW, barH, f, color);
        }
        if (sym == :drop) {
            Draw.drop(dc, cx, symY, symS, color);
        } else {
            // haut-parleur dans le vert du bas de la jauge
            Draw.noise(dc, cx, symY, symS, f == null ? Draw.DIM : Draw.noiseColor(NOISE_MIN));
        }
    }

    // Hauteur des chiffres (police vectorielle : ~72 % de la taille).
    function capHeight(font as Graphics.FontType, size as Number) as Number {
        if ((Graphics has :VectorFont) && font instanceof Graphics.VectorFont) {
            return size * 72 / 100;
        }
        return (Graphics.getFontAscent(font as Graphics.FontDefinition) * 72 / 100).toNumber();
    }

    // Texte dont les chiffres sont centrés verticalement sur cy.
    function drawCapText(dc as Graphics.Dc, x as Number, cy as Number, font as Graphics.FontType,
                         capH as Number, txt as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var asc = Graphics.getFontAscent(font);
        dc.drawText(x, cy + capH / 2 - asc, font, txt, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function minMaxWidth(dc as Graphics.Dc, minTxt as String, maxTxt as String,
                         mm as Graphics.FontType, mmH as Number) as Number {
        var aw = mmH * 80 / 100;
        return aw + 2 + dc.getTextWidthInPixels(minTxt, mm) + mmH * 6 / 10 + aw + 2
            + dc.getTextWidthInPixels(maxTxt, mm);
    }

    function splitOrDash(v) as Array<String> {
        return v == null ? ["--", ""] : Draw.splitTemp(v as Numeric);
    }

    function frac(v, lo as Float, hi as Float) as Float or Null {
        if (v == null) {
            return null;
        }
        return ((v as Numeric).toFloat() - lo) / (hi - lo);
    }

    // Largeur de « 9 » + « .8 » (ou du signe degré s'il est plus large).
    function tempWidth(dc as Graphics.Dc, t as Array<String>, big as Graphics.FontType,
                       dec as Graphics.FontType, digitH as Number) as Number {
        var r = degreeRadius(digitH);
        var dw = dc.getTextWidthInPixels(t[1], dec);
        var degW = 2 * r + 4;
        return dc.getTextWidthInPixels(t[0], big) + 2 + (dw > degW ? dw : degW);
    }

    function degreeRadius(digitH as Number) as Number {
        var r = digitH / 9;
        return r < 2 ? 2 : r;
    }

    // Partie entière en gros, décimale en petit sur la même ligne de base, ° en haut.
    function drawTemp(dc as Graphics.Dc, x as Number, cy as Number, t as Array<String>,
                      big as Graphics.FontType, dec as Graphics.FontType, digitH as Number,
                      color as Number) as Void {
        var base = cy + digitH / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, base - Graphics.getFontAscent(big), big, t[0], Graphics.TEXT_JUSTIFY_LEFT);
        var x2 = x + dc.getTextWidthInPixels(t[0], big) + 2;
        dc.drawText(x2, base - Graphics.getFontAscent(dec), dec, t[1], Graphics.TEXT_JUSTIFY_LEFT);
        if (!t[0].equals("--")) {
            var r = degreeRadius(digitH);
            dc.setPenWidth(r / 2 > 2 ? r / 2 : 2);
            dc.drawCircle(x2 + r + 2, cy - digitH / 2 + r, r);
            dc.setPenWidth(1);
        }
    }
}
