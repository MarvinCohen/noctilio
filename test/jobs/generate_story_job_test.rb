require "test_helper"

# ============================================================
# Tests du job de génération d'histoire
# ============================================================
# On verrouille ici le parsing du bloc [SCENE]...[FIN SCENE] :
#   - extract_scene     : récupère la phrase de scène (ou nil si absente)
#   - strip_scene_block : retire ce bloc du texte lu par le parent
# Ces deux méthodes sont privées et déterministes (aucun appel IA) : on les
# teste directement via send, comme pour les méthodes de ImageGeneratorService.
class GenerateStoryJobTest < ActiveSupport::TestCase
  setup do
    # Une instance de job suffit pour tester ses méthodes privées de parsing
    @job = GenerateStoryJob.new
  end

  # --- extract_scene : parse la phrase du bloc [SCENE] ----------------------
  test "extract_scene récupère la phrase de scène du bloc" do
    content = <<~TEXT
      Mon histoire magique

      Il était une fois Léo qui explorait l'espace.

      [SCENE]
      Léo reaching toward a glowing crystal planet in zero gravity
      [FIN SCENE]
    TEXT

    # La phrase doit être extraite et nettoyée (sans les marqueurs ni espaces)
    assert_equal "Léo reaching toward a glowing crystal planet in zero gravity",
                 @job.send(:extract_scene, content)
  end

  # --- extract_scene : retourne nil si le bloc est absent -------------------
  test "extract_scene retourne nil quand le bloc [SCENE] est absent" do
    # Pas de bloc → nil → fallback automatique côté ImageGeneratorService
    assert_nil @job.send(:extract_scene, "Une histoire toute simple sans scène.")
  end

  # --- strip_scene_block : retire le bloc du texte affiché ------------------
  test "strip_scene_block retire le bloc [SCENE] du contenu" do
    content = <<~TEXT
      Il était une fois Léo.

      [SCENE]
      Léo reaching toward a glowing crystal planet
      [FIN SCENE]
    TEXT

    cleaned = @job.send(:strip_scene_block, content)

    # Le bloc et ses marqueurs ne doivent plus apparaître dans le texte lu
    refute_includes cleaned, "[SCENE]"
    refute_includes cleaned, "[FIN SCENE]"
    refute_includes cleaned, "crystal planet"
    # Le récit lui-même reste intact
    assert_includes cleaned, "Il était une fois Léo."
  end
end
