# Objectif global

Réparer le mode interactif de bout en bout :
- PARTIE A — l'histoire générée doit construire un événement et s'ARRÊTER sur un
  choix qui compte (au lieu d'être déjà finie avant le choix).
- PARTIE B — la lecture audio doit enchaîner sur la suite après un choix, en
  laissant d'abord finir le passage en cours, et sans repartir au début.

Priorité : PARTIE A d'abord (bug le plus visible), PARTIE B ensuite.

---

# PARTIE A — Histoire interactive qui s'arrête au bon moment

## Cause racine

Le prompt se contredit : la règle système "FIN OBLIGATOIRE" + le bloc "FORMAT
OBLIGATOIRE" (avec Épilogue) demandent une histoire COMPLÈTE, puis le bloc
interactif demande de "s'arrêter net". L'IA obéit aux 2 premières → histoire
finie + épilogue, choix collé après. De plus, tous les choix sont créés d'un
coup depuis le texte initial au lieu d'un choix à la fois.

## Modèle cible : un choix à la fois (branching séquentiel)

- Génération initiale : pose le décor + un événement déclencheur, monte la
  tension, et s'arrête sur LE 1er bloc [CHOIX]. Pas d'épilogue, pas de
  résolution. → un seul StoryChoice créé.
- Chaque continuation : reprend après le choix ; si ce n'est pas le dernier
  choix prévu (selon la durée : 5min→1, 10min→2, 15min→3), elle se termine par
  un NOUVEAU bloc [CHOIX] ; sinon elle conclut l'histoire (épilogue).

## Fichiers impactés (Partie A)

- app/services/story_generator_service.rb
- app/jobs/generate_story_job.rb (parsing initial)
- app/jobs/generate_story_continuation_job.rb (parsing du choix suivant)
- test/ (services/jobs interactifs)

## Étapes (Partie A)

- [x] A1. **system_prompt** : règle 7 conditionnelle (fin obligatoire en
      classique, s'arrête sur le choix en interactif).

- [x] A2. **user_prompt** : séparé en classic_user_prompt et
      interactive_user_prompt. L'interactif ne génère que le début jusqu'au 1er
      [CHOIX], avec événement déclencheur, sans épilogue.

- [x] A3. **GenerateStoryJob#create_story_choice_from_content** : ne crée
      qu'UN choix (step_number 1) depuis le texte initial.

- [x] A4. **build_continuation_messages** : param request_next_choice (auto
      selon l'étape) → bloc [CHOIX] si intermédiaire, conclusion si dernier.
      Les timelines alternatives passent request_next_choice: false.

- [x] A5. **GenerateStoryContinuationJob** : parse le [CHOIX] de la
      continuation → crée le choix suivant, et retire le bloc du context_chosen.

- [x] A6. Tests : test/jobs/generate_story_continuation_job_test.rb (choix
      suivant créé + nettoyage ; conclusion sans nouveau choix). 216 runs, 0 fail.

---

# PARTIE B — Lecture audio fluide après un choix

## Idée directrice

Pré-générer l'audio de la suite dès qu'elle est écrite. Quand l'enfant écoute
et fait un choix : laisser FINIR le passage en cours, puis enchaîner sur l'audio
de la suite (la nouvelle partie seulement). Pas de retour au début.

## Fichiers impactés (Partie B)

- app/jobs/generate_story_continuation_job.rb (lance l'audio de la suite)
- app/controllers/stories_controller.rb (actions status et audio)
- app/javascript/controllers/story_choice_controller.js
- app/javascript/controllers/story_reader_controller.js
- test/controllers/stories_controller_test.rb

Pas de migration : StoryChoice has_one_attached :audio_file existe déjà.

## Étapes (Partie B)

- [x] B1. **GenerateStoryContinuationJob** : à la fin, si interactif ET accès
      complet (full_experience_for?), lance
      GenerateAudioJob.perform_later(story.id, source: "continuation",
      choice_id: story_choice.id).

- [x] B2. **#status** : expose choice_id du dernier choix résolu +
      continuation_audio_url (nil si pas prêt).

- [x] B3. **#audio** : accepte params[:choice_id]. Si source == "continuation"
      + choice_id → sert choice.audio_file (redirect si prêt, sinon job +
      202). Sinon comportement actuel. Garde Premium inchangée.

- [x] B4. **story_choice_controller.js** : transmet choiceId + audioUrl dans
      l'événement story:continuation-ready.

- [x] B5. **story_reader_controller.js → resumeAfterContinuation** : si l'audio
      principal joue, NE COUPE PAS : enchaîne sur l'événement onended du passage
      en cours via playFromUrl(suite) (ou loadAndPlay("continuation", choiceId)
      si l'URL n'est pas prête). Si rien ne joue, ne lance rien.

- [x] B6. Tests controller : status renvoie choice_id + continuation_audio_url ;
      audio source=continuation sert le fichier / 202 ; Premium bloque (403).

- [x] B7. bin/rails test → 220 runs, 0 failures (+ 4 nouveaux tests).

---

## Note

Tester du prompt LLM est non déterministe : les tests valident le parsing et le
câblage, pas le contenu généré. Vérification finale = test manuel d'une histoire
interactive en local.
