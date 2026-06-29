# Plan — (1) Nettoyer les couvertures cassées + (2) Illustration fidèle aux suites interactives

## Objectif global
1. Supprimer les 404 Cloudinary : des histoires ont une `cover_image` attachée
   dont le fichier n'existe PAS sur Cloudinary (blobs orphelins). À chaque
   chargement de page, ActiveStorage régénère leur URL → 404 répétés.
2. Étendre l'illustration fidèle au récit (bloc [SCENE]) aux SUITES interactives :
   aujourd'hui seule la 1re partie a une image fidèle ; après un choix, la suite
   garde l'ancienne image d'intro.

---

## PARTIE 1 — Nettoyer les couvertures cassées (404 Cloudinary)

### Diagnostic (confirmé)
- `Story#cover_image_source` renvoie l'attachement si `cover_image.attached?`
  est vrai. L'enregistrement existe en base mais le fichier est absent de
  Cloudinary → URL valide vers un objet inexistant → 404.
- Une poignée d'histoires concernées (mêmes IDs en boucle).

### Fichiers impactés
- lib/tasks/covers.rake (NOUVEAU) — tâches d'audit et de nettoyage.

### Étapes
- [x] **Tâche rake `covers:audit`** : parcourt les histoires dont `cover_image`
      est attachée, fait une requête HEAD sur l'URL Cloudinary, et LISTE celles
      qui répondent 404 (id, titre). Lecture seule, ne modifie rien.
- [x] **Tâche rake `covers:purge_broken`** : pour chaque couverture cassée
      détectée (HEAD 404), `cover_image.purge`. La carte retombera proprement
      sur le placeholder ✨ (plus de 404). Logguer chaque purge.
- [x] **Commenter** tout le code (règle CLAUDE.md).
- [ ] L'utilisateur lance `covers:audit` en prod (via `! bin/rails covers:audit`
      ou console Railway) pour CONFIRMER la liste avant de lancer `purge_broken`.

### Point à valider (Partie 1)
- Option choisie = **purge** des attachements orphelins (placeholder ✨ propre).
  Alternative = régénérer l'image via ImageGeneratorService (plus lourd, relance
  une génération IA). On part bien sur la purge ?

---

## PARTIE 2 — Illustration fidèle aux suites interactives

### Diagnostic (confirmé)
- `GenerateStoryContinuationJob` ne demande PAS de bloc [SCENE] et ne génère
  aucune image : la suite (stockée dans `story_choice.context_chosen`) garde
  l'image d'intro de l'histoire.
- `StoryChoice` a DÉJÀ `has_one_attached :audio_file` (audio par étape) → une
  illustration par étape est cohérente avec l'archi existante (option A).

### Approche recommandée (option A — illustration PAR ÉTAPE)
Chaque `StoryChoice` reçoit sa propre illustration du moment fort de SA suite,
affichée sous le texte de la continuation. Le mode interactif étant Premium-only,
le surcoût de génération d'images reste borné aux abonnés Premium.

### Fichiers impactés (option A)
- db/migrate/xxxx_add_image_scene_to_story_choices.rb (NOUVEAU) + schema.rb
  → `add_column :story_choices, :image_scene, :text`
- app/models/story_choice.rb → `has_one_attached :illustration`
- app/services/story_generator_service.rb → ajouter la consigne [SCENE] aussi
  dans le prompt de continuation (`continue_with_choice`).
- app/jobs/generate_story_continuation_job.rb → extraire [SCENE], nettoyer le
  texte, sauver `image_scene` sur le choix, puis générer l'image attachée au choix
  (si l'utilisateur a droit aux illustrations).
- app/services/image_generator_service.rb → permettre de cibler un StoryChoice
  (sa scène + son illustration) en plus de la Story (refactor léger du constructeur
  ou nouvelle méthode), en réutilisant la composition « scène » déjà en place.
- app/views/stories/show.html.erb → afficher `choice.illustration` sous chaque
  continuation résolue (bloc ligne ~424), avec skeleton comme la cover.
- test/ → extraction [SCENE] côté continuation + génération image par choix.

### Étapes (option A)
- [x] Migration `image_scene` sur story_choices + `rails db:migrate`.
- [x] `StoryChoice` : `has_one_attached :illustration` (commenté).
- [x] Prompt de continuation : ajouter le bloc [SCENE] (même consigne qu'en
      génération initiale).
- [x] `GenerateStoryContinuationJob` : extract_scene + strip + save image_scene
      + génération image attachée au choix (gardée par illustrations_for?).
- [x] `ImageGeneratorService` : accepter une cible StoryChoice (scène + attache).
- [x] Vue : afficher l'illustration de chaque suite (affichée si attachée).
- [x] Tests verts (`rails test` → 328 runs, 0 failures).

### Point à valider (Partie 2) — UNE décision
- **Option A (recommandée)** : une illustration PAR étape (cohérent avec l'audio
  par étape déjà en place). Plus riche, plus d'appels image (Premium only).
- **Option B (plus simple)** : régénérer la `cover_image` de l'histoire à chaque
  suite pour refléter la dernière scène. Moins de code, mais on PERD l'image
  d'intro et la couverture « bouge » à chaque choix.
  → On part sur A ou B ?

---

## Ordre proposé
Partie 1 d'abord (rapide, faible risque), puis Partie 2 après validation de
l'option A/B.
