require "test_helper"

# ============================================================
# Tests du service de génération d'image
# ============================================================
# Le cœur testable de ce service, ce sont ses méthodes PRIVÉES déterministes
# qui CONSTRUISENT le prompt envoyé aux modèles d'image (gpt-image-1 / FLUX) :
#   - build_image_prompt : assemble héros + cadrage + style
#   - action_theme?      : détecte un thème d'action dans le thème libre
#   - custom_scene       : nettoie le thème libre (prénom, verbes violents)
# On verrouille ici 3 comportements importants déjà débugués en production :
#   1. l'insistance sur la peau foncée (sinon FLUX/gpt-image-1 éclaircissent)
#   2. le cadrage "scène héroïque" déclenché par un thème d'action
#   3. l'adoucissement des verbes violents (sinon gpt-image-1 rejette en 400)
# Aucune API n'est appelée : ces méthodes ne font que construire des chaînes.
class ImageGeneratorServiceTest < ActiveSupport::TestCase
  setup do
    # Histoire de base : Léo, pas de thème libre → cadrage portrait calme par défaut
    @story = stories(:completed_saved)
    @child = @story.child
  end

  # --- build_image_prompt : cadrage portrait par défaut ---------------------
  test "build_image_prompt produit un portrait calme sans thème d'action" do
    service = ImageGeneratorService.new(@story)
    prompt  = service.send(:build_image_prompt)

    # Pas de thème d'action → branche "portrait", pas "epic action"
    assert_includes prompt, "A portrait of"
    refute_includes prompt, "Epic cinematic action scene"
    # Le prénom du héros doit apparaître (via Child#image_description)
    assert_includes prompt, "Léo"
    # Style par défaut = aquarelle (livre d'enfants)
    assert_includes prompt, "children's book illustration"
  end

  # --- build_image_prompt : composition "scène narrative" -------------------
  test "build_image_prompt illustre la scène du récit si image_scene est présent" do
    # Le LLM a fourni une phrase de scène fidèle au récit → on illustre CE moment
    @story.update!(image_scene: "Léo reaching toward a glowing crystal planet")

    service = ImageGeneratorService.new(@story)
    prompt  = service.send(:build_image_prompt)

    # La phrase de scène doit être injectée, avec pose dynamique (pas un portrait)
    assert_includes prompt, "Léo reaching toward a glowing crystal planet"
    assert_includes prompt, "Dynamic three-quarter pose"
    assert_includes prompt, "NOT a static portrait"
    # On ne retombe PAS sur le portrait calme ni sur la scène d'action
    refute_includes prompt, "Warm character portrait"
    refute_includes prompt, "Epic cinematic action scene"
  end

  # --- build_image_prompt : fallback portrait si pas de scène ---------------
  test "build_image_prompt retombe sur le portrait si image_scene est absent" do
    # Aucune scène fournie → comportement historique inchangé (aucune régression)
    @story.update!(image_scene: nil)

    service = ImageGeneratorService.new(@story)
    prompt  = service.send(:build_image_prompt)

    assert_includes prompt, "A portrait of"
  end

  # --- build_image_prompt : adoucissement de la scène violente --------------
  test "build_image_prompt adoucit les verbes violents de la scène narrative" do
    # "fight" est un verbe violent → remplacé pour ne pas déclencher la modération
    @story.update!(image_scene: "Léo fights a giant dragon")

    service = ImageGeneratorService.new(@story)
    prompt  = service.send(:build_image_prompt)

    assert_includes prompt, "bravely faces"
    refute_includes prompt, "fights"
  end

  # --- build_image_prompt : insistance sur la peau foncée -------------------
  test "build_image_prompt insiste sur la peau quand le héros est à peau ébène" do
    # On force une peau ébène sur le héros (les fixtures ne la définissent pas)
    @child.update!(skin_tone: "ebony")

    service = ImageGeneratorService.new(@story)
    prompt  = service.send(:build_image_prompt)

    # Le rappel nominatif doit être en TÊTE du prompt (premiers tokens = + de poids)
    assert prompt.start_with?("IMPORTANT — skin tones:"),
           "le rappel de teinte doit ouvrir le prompt"
    assert_includes prompt, "Léo has dark ebony black skin"
  end

  # --- build_image_prompt : cadrage scène héroïque sur thème d'action -------
  test "build_image_prompt bascule en scène héroïque pour un thème d'action" do
    # custom_theme contenant un mot-clé d'action → cadrage épique
    @story.update!(custom_theme: "Léo pilote un robot géant")

    service = ImageGeneratorService.new(@story)
    prompt  = service.send(:build_image_prompt)

    assert_includes prompt, "Epic cinematic action scene"
    refute_includes prompt, "Warm character portrait"
  end

  # --- action_theme? : détection du thème d'action --------------------------
  test "action_theme? détecte les mots-clés d'action et ignore les thèmes calmes" do
    # Thème d'action (robot/combat) → true
    @story.custom_theme = "Léo combat un robot"
    assert ImageGeneratorService.new(@story).send(:action_theme?)

    # Thème calme → false
    @story.custom_theme = "une promenade tranquille dans la forêt"
    refute ImageGeneratorService.new(@story).send(:action_theme?)

    # Thème vide → false (pas de bascule)
    @story.custom_theme = ""
    refute ImageGeneratorService.new(@story).send(:action_theme?)
  end

  # --- custom_scene : adoucissement des verbes violents ---------------------
  test "custom_scene adoucit les verbes violents pour passer la modération" do
    # "combat" est un verbe violent → remplacé par un équivalent héroïque non violent
    @story.custom_theme = "combat un dragon"
    scene = ImageGeneratorService.new(@story).send(:custom_scene)

    assert_includes scene, "affronte courageusement"
    refute_includes scene, "combat"
  end

  # --- custom_scene : retrait du prénom en tête -----------------------------
  test "custom_scene retire le prénom du héros placé en tête" do
    # "Léo est ..." → le prénom et le verbe d'état sont retirés (le héros est déjà décrit)
    @story.custom_theme = "Léo est un chevalier valeureux"
    scene = ImageGeneratorService.new(@story).send(:custom_scene)

    assert_equal "un chevalier valeureux", scene
  end
end
