## Objectif
Transformer le front Noctilio en expérience type app mobile/store (esprit Duolingo
mais dans l'ADN nocturne et doux de Noctilio). Branche : feature/mobile-app-experience.
EXCLU : tout ce qui concerne le Play Store / TWA.

## Phases

### Phase 1 — Bottom tab bar mobile
- [x] Partial shared/_bottom_nav.html.erb (5 onglets : Accueil, Histoires, Créer central, Trophées, Profil)
- [x] components/_bottom_nav.scss (visible ≤768px, onglet actif halo doré, bouton central surélevé)
- [x] Import dans components/_index.scss
- [x] Branchement dans layouts/application.html.erb (connectés uniquement)
- [x] padding-bottom sur .app-main pour ne pas masquer le contenu

### Phase 2 — Accueil rituel du soir
- [ ] Helper constellation du soir (modèle, non punitif)
- [ ] Carte progression (orbe niveau + barre XP + prochain badge)
- [ ] Carte suggestion histoire du soir (1 tap)
- [ ] Refonte dashboard/index.html.erb mobile-first

### Phase 3 — Sensation app
- [ ] Transitions de page Turbo
- [ ] Animations au tap (scale boutons)
- [ ] Splash screen PWA
- [ ] Skeletons de chargement génération

### Phase 4 — Onboarding première fois
- [ ] Détection nouvel utilisateur sans enfant
- [ ] Parcours plein écran (profil enfant -> univers -> 1re histoire offerte)

### Phase 5 — PWA niveau store (sans Play Store)
- [ ] start_url -> /dashboard
- [ ] Icônes dédiées par taille
- [ ] Splash screen iOS
- [ ] Lecture hors-ligne des histoires déjà ouvertes (service worker)
