# Test du PORO AdminStats
# Vérifie que chaque agrégation renvoie les bons chiffres À PARTIR DES FIXTURES.
# Les valeurs attendues sont calculées à la main depuis test/fixtures/stories.yml
# et test/fixtures/story_choices.yml :
#
#   Histoires (7 au total) :
#     completed_saved      → completed, courage, 5 min, non interactif
#     completed_not_saved  → completed, sharing, 10 min, non interactif
#     pending_story        → pending  (ni valeur, ni durée)
#     failed_story         → failed   (ni valeur, ni durée)
#     interactive_story    → completed, courage, 15 min, INTERACTIF
#     old_story            → completed, kindness, 5 min, non interactif
#     paul_story           → completed, courage, 5 min, non interactif
#
#   → completed = 5, failed = 1, world_theme jamais renseigné, image_style jamais renseigné
#
#   Choix interactifs (1 au total) :
#     pending_choice → chosen_option nil (donc NON résolu)
require "test_helper"

class AdminStatsTest < ActiveSupport::TestCase
  # Instancie un objet stats neuf avant chaque test (état partagé impossible)
  def setup
    @stats = AdminStats.new
  end

  # ===========================================================
  # SECTION 1 — Vue d'ensemble (overview)
  # ===========================================================

  # overview doit renvoyer un hash contenant toutes les clés attendues
  test "overview contient tous les compteurs clés" do
    keys = @stats.overview.keys

    assert_includes keys, :users_total
    assert_includes keys, :admins
    assert_includes keys, :active_subscriptions
    assert_includes keys, :children_total
    assert_includes keys, :stories_total
    assert_includes keys, :stories_completed
    assert_includes keys, :stories_failed
    assert_includes keys, :failure_rate
  end

  # Les compteurs d'histoires doivent correspondre aux fixtures
  test "overview compte correctement les histoires" do
    overview = @stats.overview

    assert_equal 7, overview[:stories_total],     "7 histoires dans les fixtures"
    assert_equal 5, overview[:stories_completed], "5 histoires terminées (status 2)"
    assert_equal 1, overview[:stories_failed],    "1 histoire échouée (status 3)"
  end

  # Sans abonnement Pay en test, le compteur d'abonnements actifs vaut 0
  test "overview ne compte aucun abonnement actif en test" do
    assert_equal 0, @stats.overview[:active_subscriptions]
  end

  # Taux d'échec = échouées / (terminées + échouées) = 1 / (5 + 1) = 16,6 % → arrondi 17
  test "overview calcule le taux d'échec arrondi" do
    assert_equal 17, @stats.overview[:failure_rate]
  end

  # ===========================================================
  # SECTION 2 — Préférences histoires (classements)
  # ===========================================================

  # Aucun world_theme n'est renseigné → toutes les histoires tombent dans nil
  # (thème libre). Le classement renvoie donc une seule paire [nil, 7].
  test "world_themes regroupe les histoires sans univers sous nil" do
    assert_equal [[nil, 7]], @stats.world_themes
  end

  # Valeurs éducatives : courage = 3, sharing = 1, kindness = 1.
  # Les histoires sans valeur (pending, failed) sont exclues du classement.
  # Le tri est décroissant → courage en tête.
  test "educational_values classe les valeurs du plus fréquent au moins fréquent" do
    ranking = @stats.educational_values

    assert_equal ["courage", 3], ranking.first, "courage est la valeur la plus choisie"
    # Total des occurrences = 3 + 1 + 1 = 5 (les nil sont exclus)
    assert_equal 5, ranking.sum { |_value, count| count }
  end

  # Aucun image_style renseigné dans les fixtures → classement vide
  test "image_styles est vide quand aucun style n'est renseigné" do
    assert_equal [], @stats.image_styles
  end

  # Durées : la colonne duration_minutes a un DÉFAUT de 5 en base (voir schema.rb),
  # donc pending_story et failed_story comptent aussi comme 5 min.
  #   5 min = 5 (completed_saved, old_story, paul_story, pending_story, failed_story)
  #   10 min = 1 (completed_not_saved)
  #   15 min = 1 (interactive_story)
  # Aucune durée n'est nil → les 7 histoires sont classées.
  test "durations classe les durées du plus fréquent au moins fréquent" do
    ranking = @stats.durations

    assert_equal [5, 5], ranking.first, "5 minutes est la durée la plus demandée"
    assert_equal 7, ranking.sum { |_duration, count| count }
  end

  # ===========================================================
  # SECTION 3 — Mode interactif & choix
  # ===========================================================

  # Répartition interactif/classique : 1 interactive, 6 classiques.
  test "interactive_split sépare interactif et classique" do
    split = @stats.interactive_split

    assert_equal 1, split[true],  "1 histoire interactive (interactive_story)"
    assert_equal 6, split[false], "6 histoires classiques"
  end

  # Pourcentage interactif = 1 / 7 = 14,2 % → arrondi 14
  test "interactive_percentage arrondit la part d'histoires interactives" do
    assert_equal 14, @stats.interactive_percentage
  end

  # Aucun choix résolu (le seul choix a chosen_option nil) → répartition vide
  test "choice_split est vide quand aucun choix n'est résolu" do
    assert_equal({}, @stats.choice_split)
  end

  # Taux de résolution = résolus(0) / total(1) = 0 %
  test "choice_resolution_rate vaut 0 quand aucun choix n'est résolu" do
    assert_equal 0, @stats.choice_resolution_rate
  end
end
