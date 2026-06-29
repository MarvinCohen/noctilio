# ============================================================
# Configuration Cloudinary — force les URLs en HTTPS
# ============================================================
# En production, Cloudinary est configuré via la variable d'environnement
# CLOUDINARY_URL (injectée sur Railway). Par défaut, le gem génère alors des
# URLs en http:// (héritage de l'ancien format de l'URL Cloudinary).
#
# Pourquoi c'est un problème concret pour Noctilio :
# Le lecteur audio (story_reader_controller) fait un fetch() vers l'URL Cloudinary
# du MP3. En http://, ce fetch est bloqué par la CSP : la directive connect-src
# n'autorise que https://res.cloudinary.com (http:// ne correspond pas).
# Les <img> y survivaient grâce à l'auto-upgrade "mixed content" du navigateur
# (qui passe http→https tout seul pour les images), mais fetch() n'en bénéficie
# PAS → l'audio restait bloqué ("image OK, audio KO").
#
# En forçant secure ici, TOUTES les URLs (images ET audio) sortent en https://
# et passent la CSP. On ne touche qu'au flag secure : cloud_name / api_key /
# api_secret restent ceux lus depuis CLOUDINARY_URL.
#
# NB : en dev/test, on utilise le stockage Disk (pas Cloudinary), donc ce réglage
# est sans effet — il ne fait que positionner un flag inoffensif.
Cloudinary.config.secure = true
