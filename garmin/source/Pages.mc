import Toybox.Lang;
import Toybox.WatchUi;

const PAGES = 4;

// Navigation entre les 4 écrans avec la transition glissante du système
// (l'indicateur de la boucle de vues native est un grand arc non modifiable :
// on dessine à la place 4 petits points discrets, voir PageView).
// DOWN / balayage vers le haut : écran suivant.  UP / balayage vers le bas : précédent.
// START / toucher : écran suivant.  UP maintenu (menu) : actualiser.  BACK : quitter.
class PageDelegate extends WatchUi.BehaviorDelegate {

    var _store as NetatmoStore;
    var _page as Number;

    function initialize(store as NetatmoStore, page as Number) {
        BehaviorDelegate.initialize();
        _store = store;
        _page = page;
    }

    function go(dir as Number) as Boolean {
        var p = (_page + dir + PAGES) % PAGES;
        WatchUi.switchToView(new PageView(p, _store), new PageDelegate(_store, p),
            dir > 0 ? WatchUi.SLIDE_UP : WatchUi.SLIDE_DOWN);
        return true;
    }

    function onNextPage() as Boolean {
        return go(1);
    }

    function onPreviousPage() as Boolean {
        return go(-1);
    }

    function onSelect() as Boolean {
        return go(1);
    }

    function onMenu() as Boolean {
        _store.refresh();
        return true;
    }
}
