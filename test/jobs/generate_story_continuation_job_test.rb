require "test_helper"

# ============================================================
# Tests du job de continuation interactive
# ============================================================
# Vérifie le modèle "un choix à la fois" :
#   - une continuation intermédiaire crée le choix suivant et retire le bloc
#     [CHOIX] du texte affiché ;
#   - une continuation sans bloc [CHOIX] (conclusion) ne crée aucun choix.
# Le service IA est remplacé par un faux objet pour rester déterministe
# (aucun appel réseau, pas besoin de clé API).
class GenerateStoryContinuationJobTest < ActiveJob::TestCase
  setup do
    # interactive_story dure 15 min → 3 choix prévus au total
    @story  = stories(:interactive_story)
    # On marque le choix d'étape 1 comme résolu (l'enfant a choisi A)
    @choice = story_choices(:pending_choice)
    @choice.update!(chosen_option: "a")
  end

  test "crée le choix suivant et nettoie le bloc CHOIX du texte" do
    # Continuation intermédiaire : se termine par un NOUVEAU bloc [CHOIX]
    fake_content = <<~TEXT
      Léo s'enfonça dans la forêt, le cœur battant.
      Un pont de lianes apparut au-dessus du ravin.

      [CHOIX]
      Question : Que va faire Léo ?
      Option A : Traverser le pont de lianes
      Option B : Chercher un autre chemin
      [FIN CHOIX]
    TEXT

    with_fake_service(fake_content) do
      # Un seul choix supplémentaire doit être créé (l'étape 2)
      assert_difference -> { @story.story_choices.count }, 1 do
        GenerateStoryContinuationJob.perform_now(@story.id, @choice.id)
      end
    end

    @choice.reload
    # Le bloc [CHOIX] brut ne doit PAS rester dans le texte affiché
    refute_includes @choice.context_chosen, "[CHOIX]"
    assert_includes @choice.context_chosen, "pont de lianes"

    # Le choix suivant (étape 2) est créé avec les bonnes options
    next_choice = @story.story_choices.find_by(step_number: 2)
    assert_not_nil next_choice
    assert_equal "Traverser le pont de lianes", next_choice.option_a
    assert_equal "Chercher un autre chemin", next_choice.option_b
  end

  test "ne crée aucun choix quand la continuation conclut l'histoire" do
    # Continuation finale : aucun bloc [CHOIX], juste la conclusion
    fake_content = "Léo traversa, victorieux, comprenant que le courage se vit dans l'action."

    with_fake_service(fake_content) do
      assert_no_difference -> { @story.story_choices.count } do
        GenerateStoryContinuationJob.perform_now(@story.id, @choice.id)
      end
    end

    @choice.reload
    assert_includes @choice.context_chosen, "victorieux"
  end

  private

  # Remplace temporairement StoryGeneratorService.new par un faux service qui
  # renvoie le contenu fourni, puis restaure le comportement d'origine.
  # On surcharge .new (et pas une instance) pour éviter le constructeur réel,
  # qui exige la clé API GROQ_API_KEY.
  def with_fake_service(content)
    fake = Object.new
    fake.define_singleton_method(:continue_with_choice) { |_| { success: true, content: content } }

    StoryGeneratorService.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    # Retire notre surcharge → StoryGeneratorService.new redevient le Class#new par défaut
    StoryGeneratorService.singleton_class.send(:remove_method, :new)
  end
end
