import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// Données fictives quand le clientId vaut « demo » : permet de voir l'app
// dans le simulateur ou sur la montre sans compte Netatmo.
(:background, :glance)
module Demo {

    function data(withHistory as Boolean) as Dictionary {
        var now = Time.now().value();
        var d = {
            "time" => now - 240, "station" => "Démo",
            "out" => { "t" => 9.8, "tr" => "down", "min" => 7.8, "max" => 20.5, "h" => 82 },
            "in" => { "t" => 20.7, "tr" => "stable", "h" => 56, "co2" => 899, "n" => 41,
                      "p" => 1022.1, "pt" => "stable" }
        };
        if (!withHistory) {
            return d;
        }
        var step = 1800;
        var n = 49;
        var start = (now / step) * step - (n - 1) * step;
        var ot = [], oh = [], p = [], it = [], ih = [], co2 = [], noise = [];
        for (var i = 0; i < n; i++) {
            var hour = ((start + i * step) % 86400) / 3600.0 + 1.0;   // ~ heure de Paris
            var day = Math.sin((hour - 9.0) / 24.0 * 2.0 * Math.PI);
            var occupied = hour >= 7.0 && hour <= 23.0;
            ot.add(r1(14.0 + 6.5 * day + Math.sin(i * 1.7) * 0.3));
            oh.add(r1(70.0 - 15.0 * day + Math.sin(i * 2.3) * 2.0));
            p.add(r1(1018.0 + 4.0 * i / n + Math.sin(i * 0.9) * 0.3));
            it.add(r1(19.5 + 1.5 * day + Math.sin(i * 1.3) * 0.2));
            ih.add(r1(55.0 + 4.0 * Math.cos(hour / 3.0)));
            co2.add(i == 10 || i == 11 ? null
                : r1((occupied ? 800.0 : 520.0) + 250.0 * Math.pow(Math.sin(hour / 2.0), 2)));
            noise.add(r1((occupied ? 44.0 : 33.0) + Math.sin(i * 0.8) * 3.0));
        }
        d["start"] = start;
        d["step"] = step;
        d["hist"] = { "ot" => ot, "oh" => oh, "p" => p, "it" => it, "ih" => ih,
                      "co2" => co2, "n" => noise };
        return d;
    }

    function r1(v as Float) as Float {
        return Math.round(v * 10.0) / 10.0;
    }
}
