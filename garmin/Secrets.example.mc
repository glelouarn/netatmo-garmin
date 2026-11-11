// Modèle : copier vers source-secrets/Secrets.mc (ignoré par git) et renseigner le
// client_id / client_secret de l'app créée sur https://dev.netatmo.com/apps
// (build.sh le fait tout seul depuis ../netatmo_config.json).
// Ces identifiants sont ceux de l'APP, pas d'un utilisateur : chaque utilisateur
// donne ensuite son accord sur les pages Netatmo à la première connexion.
(:background, :glance)
module Secrets {
    const CLIENT_ID = "TON_CLIENT_ID";
    const CLIENT_SECRET = "TON_CLIENT_SECRET";
}
