require "test_helper"

# ============================================================
# Tests du service de génération de texte (Groq / Llama 3.3)
# ============================================================
# On NE veut PAS appeler la vraie API Groq pendant les tests (coût, lenteur,
# réseau). On REMPLACE donc le client OpenAI interne du service par un faux
# client (FakeClient) qui renvoie une réponse contrôlée ou lève une exception.
# On vérifie ainsi le CONTRAT du service (le hash {success:, content:, error:})
# sans dépendre du réseau, plus les helpers privés déterministes.
class StoryGeneratorServiceTest < ActiveSupport::TestCase
  # Faux client OpenAI : sa méthode #chat exécute le bloc fourni à la construction.
  # Permet de simuler aussi bien une réponse normale qu'une exception réseau.
  class FakeClient
    def initialize(&behaviour)
      @behaviour = behaviour
    end

    # Le vrai client est appelé avec un argument nommé `parameters:` → même signature
    def chat(parameters:)
      @behaviour.call(parameters)
    end
  end
  setup do
    # initialize fait ENV.fetch("GROQ_API_KEY") → on garantit une valeur en test
    # (||= : on ne touche pas à la vraie clé si elle est déjà définie en local)
    ENV["GROQ_API_KEY"] ||= "test-key"

    # Histoire de base : terminée, non interactive, courage, 5 min (cf. fixtures)
    @story   = stories(:completed_saved)
    @service = StoryGeneratorService.new(@story)
  end

  # Remplace le vrai client du service par un faux qui exécute `behaviour`
  def stub_client(&behaviour)
    @service.instance_variable_set(:@client, FakeClient.new(&behaviour))
  end

  # --- call : cas nominal (l'IA renvoie du texte) ---------------------------
  test "call retourne success avec le contenu quand l'IA répond" do
    # Fausse réponse au format de l'API OpenAI/Groq (choices → message → content)
    stub_client { |_params| { "choices" => [{ "message" => { "content" => "Il était une fois Léo." } }] } }

    result = @service.call
    assert result[:success], "le service devrait réussir quand l'IA renvoie du texte"
    assert_equal "Il était une fois Léo.", result[:content]
  end

  # --- call : réponse vide → échec géré proprement --------------------------
  test "call retourne un échec quand l'IA renvoie un contenu vide" do
    # content vide → content.present? est false → le service renvoie une erreur
    stub_client { |_params| { "choices" => [{ "message" => { "content" => "" } }] } }

    result = @service.call
    refute result[:success], "un contenu vide doit être traité comme un échec"
    assert_equal "La réponse de l'IA était vide", result[:error]
  end

  # --- call : exception réseau → échec géré proprement ----------------------
  test "call capture les exceptions et retourne un échec" do
    # On simule une erreur réseau : le faux client lève une exception,
    # qui doit être captée par le rescue du service (pas de plantage).
    stub_client { |_params| raise StandardError, "timeout" }

    result = @service.call
    refute result[:success], "une exception doit produire un échec, pas planter"
    assert_includes result[:error], "timeout"
  end

  # --- Helpers privés déterministes (testés via send) -----------------------

  # language_name : mappe story.locale → nom de langue (en français, pour le prompt)
  test "language_name retourne français par défaut et la bonne langue sinon" do
    # completed_saved n'a pas de locale en fixture → défaut "fr" en base
    assert_equal "français", @service.send(:language_name)

    @story.locale = "en"
    assert_equal "anglais", StoryGeneratorService.new(@story).send(:language_name)

    # Locale inconnue → repli sur "français" (sécurité)
    @story.locale = "zz"
    assert_equal "français", StoryGeneratorService.new(@story).send(:language_name)
  end

  # educational_value_label : clé EN → libellé FR pour le prompt
  test "educational_value_label traduit la valeur éducative" do
    # completed_saved a educational_value = courage
    assert_equal "le courage", @service.send(:educational_value_label)
  end

  # tokens_for_duration : budget de tokens selon la durée de l'histoire
  test "tokens_for_duration suit la durée de l'histoire" do
    # completed_saved dure 5 min → 3500 tokens
    assert_equal 3500, @service.send(:tokens_for_duration)

    # interactive_story dure 15 min → 8000 tokens
    long_service = StoryGeneratorService.new(stories(:interactive_story))
    assert_equal 8000, long_service.send(:tokens_for_duration)
  end

  # continuation_tokens : moitié du budget total (évite les suites coupées)
  test "continuation_tokens vaut la moitié du budget total" do
    # 5 min → 3500 / 2 = 1750
    assert_equal 1750, @service.send(:continuation_tokens)
  end

  # interactive_choices_count : nombre de choix selon la durée
  test "interactive_choices_count suit la durée" do
    # 5 min → 1 choix
    assert_equal 1, @service.send(:interactive_choices_count)
    # 15 min → 3 choix
    long_service = StoryGeneratorService.new(stories(:interactive_story))
    assert_equal 3, long_service.send(:interactive_choices_count)
  end

  # chapter_count : 3 en classique, (nb choix + 1) en interactif
  test "chapter_count vaut 3 en classique et nb_choix+1 en interactif" do
    # completed_saved n'est pas interactive → 3 chapitres
    assert_equal 3, @service.send(:chapter_count)

    # interactive_story : 15 min → 3 choix → 4 chapitres
    interactive_service = StoryGeneratorService.new(stories(:interactive_story))
    assert_equal 4, interactive_service.send(:chapter_count)
  end
end
