# Plan — Illustration fidèle à l'histoire (scène narrative, héros reconnaissable, pas un portrait)

## Objectif
Faire en sorte que l'illustration générée :
1. **reconnaisse l'enfant** (traits physiques préservés — déjà solide, on ne casse pas) ;
2. **ne soit pas un simple portrait de buste** (pose dynamique, scène vivante) ;
3. **illustre VRAIMENT un moment de l'histoire** (et non un décor générique par univers).

## Diagnostic (validé par 3 agents d'analyse)
- Le prompt image est construit 100 % en Ruby (`ImageGeneratorService#build_image_prompt`),
  **sans jamais lire le texte ni le titre de l'histoire**.
- Par défaut → portrait de buste statique (« upper body, looking toward the viewer, bokeh »).
- La branche « scène d'action » ne se déclenche QUE sur un `custom_theme` à mots-clés
  (robot, épée…) — jamais sur les univers space/pirates/dinos/princesses/animals.
- Le décor est générique : toute histoire d'un même univers = même fond.
- Un ancien 2ᵉ appel Groq (`image_scene_prompt`) a été supprimé pour la latence
  (generate_story_job.rb:79-80). On ne le réintroduit PAS.

## Principe de la solution : séparer le QUI (Ruby) du QUOI (récit)
- Le **héros** (traits physiques) reste 100 % déterministe en Ruby → zéro dérive,
  enfant toujours reconnaissable, renfort peau foncée conservé.
- La **scène** (moment fort + action + ambiance) est produite par le LLM de l'histoire
  DANS LA MÊME réponse Groq (comme le bloc [CHOIX] déjà parsé) → aucune latence ajoutée,
  scène fidèle au récit, rédigée en ANGLAIS (règle au mauvais endroit FR/EN aussi).
- Fallback : si pas de bloc [SCENE] → on retombe sur le système actuel → aucune régression.

## Fichiers impactés
- db/migrate/xxxx_add_image_scene_to_stories.rb (NOUVEAU) + db/schema.rb
- app/services/story_generator_service.rb (consigne [SCENE] dans le prompt)
- app/jobs/generate_story_job.rb (extraction + nettoyage du bloc [SCENE])
- app/services/image_generator_service.rb (composition basée sur la scène)
- test/ (ajustements : extraction de scène, build_image_prompt avec/sans scène)

## Format du bloc demandé au LLM (placé en fin de réponse, après l'histoire)
```
[SCENE]
One English sentence describing the single most visual, dramatic moment of the story:
what the hero is DOING, the key action, posture and emotion, and the surrounding setting.
Do NOT describe the child's physical traits (hair, eyes, skin) — only the action and scene.
[FIN SCENE]
```
Exemple attendu : `Léa reaching toward a glowing crystal planet in zero gravity, eyes wide with wonder`

## Étapes
- [x] **Migration** : `add_column :stories, :image_scene, :text` (stocke la phrase de scène
      extraite du récit, lisible par ImageGeneratorService). `rails db:migrate`.
- [x] **story_generator_service.rb** : ajouter au prompt (mode classique ET interactif)
      la consigne de terminer par un bloc `[SCENE]...[FIN SCENE]` contenant UNE phrase
      visuelle en anglais du moment fort, SANS décrire les traits physiques.
      (Le héros physique reste géré par Ruby.)
- [x] **generate_story_job.rb** :
      - `extract_scene(content)` : regex `/\[SCENE\](.*?)\[FIN SCENE\]/m`, strip → image_scene.
      - **Retirer** le bloc [SCENE] du `content` avant `story.update!` pour qu'il ne
        s'affiche JAMAIS dans le texte lu (comme on l'attend du bloc [CHOIX]).
      - Sauver `image_scene` sur la story (avant le `story.reload` / appel image).
- [x] **image_generator_service.rb** — `build_image_prompt` :
      - Si `@story.image_scene.present?` → composition « scène » :
        `"{heroes physiques}, {image_scene}, dynamic three-quarter pose, full of life,
          child clearly recognizable, face clearly visible, NOT a static portrait.
          Warm storybook lighting, child-safe. Art style: {style}."`
      - Sinon → logique actuelle inchangée (portrait/action_theme) = fallback.
      - Conserver : prepend renfort peau foncée, softeners de violence (les appliquer
        aussi à image_scene par sécurité), « Same character design… » pour les sagas.
- [x] **Commenter** tout le code ajouté (règle CLAUDE.md).
- [x] **Tests** : un test que `extract_scene` parse bien le bloc et le retire du contenu ;
      un test que `build_image_prompt` utilise la scène si présente et fallback sinon.
- [x] `rails test` vert (324 runs, 0 failures).
- [ ] Test manuel : générer 2-3 histoires (univers différents) et comparer les images.

## Points à valider avant de coder
- OK pour une **nouvelle colonne** `stories.image_scene` (text) ? (alternative : pas de
  colonne, mais il faudrait passer la scène autrement — la colonne est la plus propre et
  permet de débuguer/regénérer comme `image_prompt`).
- OK pour **retirer** le bloc [SCENE] du texte affiché (sinon le parent verrait
  « [SCENE] … [FIN SCENE] » sous l'histoire) ?
- Hors scope ici : régénération d'image pour les suites interactives
  (GenerateStoryContinuationJob) — à traiter plus tard si tu veux.
