# Plan — Corriger les 5 bugs des suites interactives multi-enfants (histoire 138)

## Contexte
Histoire interactive avec PLUSIEURS enfants (Ismaël + Isaac). Cinq problèmes
constatés, validés avec l'utilisateur. Approche retenue : **B** (injection sans
rechargement) pour ① + ②, et fix prompt pour ④ et ⑤.

---

## Diagnostic (confirmé en lisant le code)

- ① Image visible après refresh seulement : dans `GenerateStoryContinuationJob`,
  l'illustration est générée APRÈS `story.update!(status: :completed)` → quand le
  front voit « completed », l'image n'est pas encore attachée.
- ② 2e choix non cliquable : `story_choice_controller#appendContinuation` injecte
  SEULEMENT le texte. Le formulaire du nouveau choix (rendu serveur via
  `@pending_choice`) n'est jamais réinjecté → pas de bouton actif.
- ③ 2e image cassée : l'`image_tag` de `choice.illustration` (show.html.erb ~444)
  n'a AUCUN fallback `image-fallback` → icône brisée si l'URL renvoie 404.
- ④ Isaac ignoré dans les choix : `build_continuation_messages` utilise un gabarit
  SINGULIER (« Que va faire [héros] ? ») et « L'enfant a choisi » → le LLM ne cite
  qu'un héros, alors que le `system_prompt` connaît bien les 2 enfants.
- ⑤ Isaac dupliqué (samouraï + enfant normal) : `build_image_prompt` ne BORNE pas
  les personnages. Il faut garantir « chaque enfant nommé apparaît UNE fois,
  correctement » SANS supprimer les autres persos/monstres/animaux du récit.

---

## Fichiers impactés
- app/jobs/generate_story_continuation_job.rb — générer l'illustration AVANT `completed`.
- app/views/stories/_interactive_choice.html.erb (NOUVEAU) — extraire le formulaire de choix.
- app/views/stories/show.html.erb — rendre le partial + fallback sur l'image du choix.
- app/controllers/stories_controller.rb — `#status` renvoie aussi `illustration_url` + `next_choice_html`.
- app/javascript/controllers/story_choice_controller.js — injecter image + nouveau choix.
- app/services/story_generator_service.rb — prompt de continuation : citer TOUS les héros.
- app/services/image_generator_service.rb — prompt image : tous les enfants présents, garder les autres persos.
- test/ — job (image avant completed), status JSON, prompts services.

---

## Étapes

### ① + ② — Injection sans rechargement (approche B)
- [x] Job : déplacer la génération d'illustration AVANT `story.update!(status: :completed)`
      (l'image et le nouveau choix sont prêts quand le front voit « completed »).
- [x] Extraire le formulaire de choix de show.html.erb dans
      `_interactive_choice.html.erb` (locals: story, choice) — réutilisable côté
      serveur ET dans le JSON de statut.
- [x] show.html.erb : remplacer le bloc inline par `render "interactive_choice"`.
- [x] `#status` : si un NOUVEAU choix en attente existe, renvoyer son HTML
      (`next_choice_html` via render_to_string du partial) ; renvoyer aussi
      `illustration_url` (url_for(resolved.illustration) si attachée).
- [x] `appendContinuation` : insérer l'illustration (img avec onerror → fallback),
      puis le texte, puis `next_choice_html` (Stimulus reconnecte un story-choice
      neuf → cliquable + re-poll). Si pas de nouveau choix, ne rien injecter.

### ③ — Fallback image cassée
- [x] show.html.erb : ajouter `image-fallback` (onerror → emoji/placeholder) sur
      l'`image_tag` de `choice.illustration`.
- [x] JS : l'img injectée porte aussi un onerror de repli (pas d'icône brisée).
- [ ] (Hors code) confirmer en prod la cause du 404 sur l'histoire 138.

### ④ — Tous les héros dans les choix
- [x] `build_continuation_messages` : construire `heroes_names` (« Ismaël et Isaac »)
      et l'injecter — rappeler que la question/les options concernent les héros
      ENSEMBLE (ou préciser qui agit), sans en oublier un. Remplacer le gabarit
      singulier.

### ⑤ — Image : tous les enfants présents, sans dupliquer, en gardant les autres persos
- [x] `build_image_prompt` : quand plusieurs enfants, préciser « exactly these N
      named children (Ismaël and Isaac), each appearing once, each matching their
      description, not duplicated/merged ; other story characters, creatures or
      animals from the scene may also appear ».

### Tests
- [ ] Job : illustration générée avant le passage en `completed`.
- [ ] `#status` : renvoie `illustration_url` + `next_choice_html` quand pertinent.
- [x] Service texte : le prompt de continuation cite tous les héros.
- [x] Service image : le prompt borne les enfants sans exclure les autres persos.
- [x] `rails test` vert (332 runs, 0 failures).

---

## Ordre proposé
②/① d'abord (bloquant), puis ③ (fallback), puis ④ (Isaac dans les choix),
puis ⑤ (image). Commits séparés possibles. Pas de push sans validation.
