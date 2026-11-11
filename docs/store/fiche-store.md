# Fiche Connect IQ Store : Trends for Netatmo

Textes à copier dans le portail développeur Garmin (apps.garmin.com/developer).
Anglais en premier (langue par défaut de la fiche), français ensuite.

---

## Informations générales

| Champ | Valeur |
|---|---|
| Nom de l'app | Trends for Netatmo |
| Type | Widget (avec aperçu / glance) |
| Catégorie | Weather (Météo) |
| Prix | Gratuit |
| Site / support | https://github.com/glelouarn/netatmo-garmin |
| Politique de confidentialité | https://github.com/glelouarn/netatmo-garmin/blob/main/docs/store/PRIVACY.md |
| Fichier | `garmin/bin/store/TrendsForNetatmo.iq` |
| Icône Store | `docs/store/icone-store.png` (500 × 500) |
| Captures | `docs/store/captures/` (454 × 454 : apercu, ecran-1 … ecran-4) |

---

## English

### Short description (≤ 80 characters)

Your Netatmo weather station at a glance, with 24-hour trends on your wrist.

### Description

Trends for Netatmo brings your Netatmo Smart Home Weather Station to your watch.

**A glance you can read in one second**
- Indoor temperature, humidity and noise level on the left
- Outdoor temperature with trend arrow, today's min / max and humidity on the right
- Colour gauges: humidity in blue, noise from green to red (30–80 dB)
- Updated in the background every 10 minutes, even when the widget is closed

**24-hour trends**
Open the widget to browse four screens inspired by the Garmin weather trends:
1. Indoor temperature and humidity
2. Outdoor temperature and humidity
3. Indoor CO₂ and noise
4. Atmospheric pressure

Hourly bars with smooth gradients, half-hourly curves, clear scales and time marks.
Swipe up / down or use the buttons to move between screens.

**Simple and private**
- Sign in once with your Netatmo account: the official Netatmo page opens on your phone,
  you approve access, and you are done
- Read-only access to your weather station (scope `read_station`)
- The watch talks directly to Netatmo through Garmin Connect: no third-party server,
  no account to create, no data collected

**Requirements**
- A Netatmo Smart Home Weather Station (outdoor module recommended)
- The Garmin Connect app on your phone, connected to the watch

**Getting started**
1. Install the widget and add it to your glance list
2. Open it: a notification appears on your phone, tap it and sign in to Netatmo
3. Approve access: your measurements appear within a few seconds

No station yet? Turn on *Demo mode* in the app settings (Garmin Connect) to try it with sample data.

Not affiliated with or endorsed by Netatmo. Netatmo is a trademark of its respective owner.

### What's new (version 1.0.0)

First release: glance with indoor / outdoor measurements, four 24-hour trend screens,
English and French.

---

## Français

### Description courte (≤ 80 caractères)

Votre station météo Netatmo d'un coup d'œil, et ses tendances 24 h au poignet.

### Description

Trends for Netatmo affiche votre station météo intelligente Netatmo sur votre montre.

**Un aperçu lisible en une seconde**
- À gauche, l'intérieur : température, humidité et niveau sonore
- À droite, l'extérieur : température avec flèche de tendance, min / max du jour et humidité
- Jauges en couleur : humidité en bleu, bruit du vert au rouge (30 à 80 dB)
- Mise à jour en tâche de fond toutes les 10 minutes, même widget fermé

**Les tendances sur 24 h**
Ouvrez le widget pour parcourir quatre écrans inspirés des tendances de la météo Garmin :
1. Température et humidité intérieures
2. Température et humidité extérieures
3. CO₂ et bruit intérieurs
4. Pression atmosphérique

Barres horaires en dégradé, courbes par demi-heure, échelles et repères horaires lisibles.
Glissez vers le haut / le bas ou utilisez les boutons pour changer d'écran.

**Simple et respectueux de vos données**
- Connexion unique avec votre compte Netatmo : la page officielle Netatmo s'ouvre sur votre
  téléphone, vous autorisez l'accès, c'est tout
- Accès en lecture seule à votre station (autorisation `read_station`)
- La montre interroge directement Netatmo via Garmin Connect : aucun serveur tiers, aucun
  compte à créer, aucune donnée collectée

**Prérequis**
- Une station météo intelligente Netatmo (module extérieur recommandé)
- L'app Garmin Connect sur votre téléphone, connectée à la montre

**Pour commencer**
1. Installez le widget et ajoutez-le à vos aperçus
2. Ouvrez-le : une notification apparaît sur votre téléphone, touchez-la et connectez-vous à Netatmo
3. Autorisez l'accès : vos mesures s'affichent en quelques secondes

Pas encore de station ? Activez le *Mode démo* dans les réglages de l'app (Garmin Connect)
pour l'essayer avec des données d'exemple.

Application indépendante, non affiliée à Netatmo. Netatmo est une marque de son propriétaire.

### Nouveautés (version 1.0.0)

Première version : aperçu avec les mesures intérieures et extérieures, quatre écrans de
tendances sur 24 h, anglais et français.

---

## Notes pour l'équipe de validation Garmin (en anglais)

> The app reads a Netatmo Smart Home Weather Station through the official Netatmo API
> (OAuth 2.0 authorization code flow via `Communications.makeOAuthRequest`).
>
> **To review without a Netatmo station:** open the app settings in Garmin Connect (or the
> simulator's App Settings editor) and enable **Demo mode**. The glance and the four trend
> screens then show sample data, with no sign-in required.
>
> **With a Netatmo account:** open the widget, tap the notification on the phone, sign in
> to Netatmo and approve the read-only `read_station` scope.
>
> Navigation: UP / DOWN (or swipe) switches between the four screens; MENU forces a refresh.
> Background refresh every 10 minutes (temporal event) keeps the glance up to date.
