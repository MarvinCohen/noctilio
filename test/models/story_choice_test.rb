# Test du modèle StoryChoice
# Ce fichier vérifie les règles métier du modèle StoryChoice :
# validations des champs obligatoires, scopes de filtrage,
# et méthodes métier (resolved?, chosen_text).
require "test_helper"

class StoryChoiceTest < ActiveSupport::TestCase

  # ===========================================================
  # SECTION 1 — VALIDATIONS
  # ===========================================================

  # Vérifie qu'un choix valide est accepté sans erreur
  # Cas : données minimales correctes depuis les fixtures
  # Pourquoi : s'assurer que la fixture de base est cohérente avec le modèle
  test "un choix valide est sauvegardé sans erreur" do
    # Arrange — charge un choix existant depuis les fixtures
    choice = story_choices(:pending_choice)

    # Assert — aucune erreur de validation
    assert choice.valid?, "Le choix devrait être valide mais a des erreurs : #{choice.errors.full_messages}"
  end

  # Vérifie qu'un choix sans question est invalide
  # Cas : question manquante
  # Pourquoi : la question est affichée à l'enfant pour qu'il puisse choisir
  test "un choix sans question est invalide" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.question = nil

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:question].any?, "question devrait être obligatoire"
  end

  # Vérifie qu'un choix sans option_a est invalide
  # Cas : option_a manquante
  # Pourquoi : les deux options sont affichées sous forme de boutons — elles sont toutes les deux obligatoires
  test "un choix sans option_a est invalide" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.option_a = nil

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:option_a].any?, "option_a devrait être obligatoire"
  end

  # Vérifie qu'un choix sans option_b est invalide
  # Cas : option_b manquante
  # Pourquoi : même raison que option_a — les deux options sont requises
  test "un choix sans option_b est invalide" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.option_b = nil

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:option_b].any?, "option_b devrait être obligatoire"
  end

  # Vérifie qu'un choix sans step_number est invalide
  # Cas : step_number manquant
  # Pourquoi : step_number détermine l'ordre des choix dans l'histoire — obligatoire
  test "un choix sans step_number est invalide" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.step_number = nil

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:step_number].any?, "step_number devrait être obligatoire"
  end

  # Vérifie qu'un step_number de 0 est refusé
  # Cas : step_number = 0 — en dessous du seuil minimum (greater_than: 0)
  # Pourquoi : les étapes commencent à 1 — 0 n'a pas de sens dans l'histoire
  test "un step_number de 0 est invalide" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.step_number = 0

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:step_number].any?,
           "step_number = 0 devrait être refusé (greater_than: 0)"
  end

  # Vérifie qu'un step_number décimal est refusé
  # Cas : step_number = 1.5 — doit être un entier (only_integer: true)
  # Pourquoi : les étapes sont des positions entières dans le récit
  test "un step_number décimal est invalide" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.step_number = 1.5

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:step_number].any?,
           "Un step_number décimal devrait être refusé (only_integer: true)"
  end

  # Vérifie que chosen_option ne peut être que 'a', 'b', ou nil
  # Cas : valeur invalide 'c'
  # Pourquoi : il n'existe que deux options — toute autre valeur est une erreur de formulaire
  test "chosen_option avec une valeur invalide est refusé" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.chosen_option = "c"  # 'c' n'existe pas — seuls 'a' et 'b' sont valides

    # Act
    choice.valid?

    # Assert
    assert choice.errors[:chosen_option].any?,
           "chosen_option = 'c' devrait être refusé (seuls 'a' et 'b' sont valides)"
  end

  # Vérifie que chosen_option peut être nil (choix pas encore effectué)
  # Cas : chosen_option nil — état initial avant que l'enfant choisisse
  # Pourquoi : allow_nil: true est déclaré — un choix non effectué est un état normal
  test "chosen_option nil est accepté" do
    # Arrange — pending_choice a chosen_option nil dans les fixtures
    choice = story_choices(:pending_choice)
    choice.chosen_option = nil

    # Act + Assert — nil ne doit pas générer d'erreur
    choice.valid?
    assert_empty choice.errors[:chosen_option],
                 "chosen_option nil devrait être accepté (état initial avant le choix)"
  end

  # ===========================================================
  # SECTION 2 — SCOPES
  # ===========================================================

  # Vérifie que le scope `pending` ne retourne que les choix non effectués
  # Cas : mélange de choix effectués et non effectués
  # Pourquoi : utilisé dans Story#next_choice pour trouver le prochain choix à présenter
  test "scope pending ne retourne que les choix sans chosen_option" do
    # Arrange — on marque le choix existant pour avoir les deux états
    story = stories(:interactive_story)

    # Crée un deuxième choix déjà effectué pour tester les deux états
    story.story_choices.create!(
      step_number: 2,
      question: "Que fait Léo ensuite ?",
      option_a: "Avance",
      option_b: "Recule",
      chosen_option: "a"  # Déjà effectué
    )

    # Act — récupère uniquement les choix en attente
    pending_choices = story.story_choices.pending

    # Assert — tous les choix retournés doivent avoir chosen_option nil
    pending_choices.each do |c|
      assert_nil c.chosen_option,
                 "Le scope pending ne doit retourner que les choix avec chosen_option nil"
    end
  end

  # Vérifie que le scope `resolved` ne retourne que les choix déjà effectués
  # Cas : mélange de choix effectués et non effectués
  # Pourquoi : utilisé pour afficher l'historique des décisions dans l'histoire
  test "scope resolved ne retourne que les choix avec chosen_option renseigné" do
    # Arrange — on crée un choix effectué
    story = stories(:interactive_story)
    story.story_choices.create!(
      step_number: 2,
      question: "Suite ?",
      option_a: "Oui",
      option_b: "Non",
      chosen_option: "b"  # Effectué
    )

    # Act
    resolved_choices = story.story_choices.resolved

    # Assert — tous les choix retournés doivent avoir chosen_option présent
    resolved_choices.each do |c|
      assert c.chosen_option.present?,
             "Le scope resolved ne doit retourner que les choix déjà effectués"
    end
  end

  # Vérifie que le scope `ordered` trie par step_number croissant
  # Cas : plusieurs choix dans le désordre
  # Pourquoi : les choix doivent être présentés dans l'ordre chronologique de l'histoire
  test "scope ordered trie par step_number croissant" do
    # Arrange — crée plusieurs choix dans le désordre
    story = stories(:interactive_story)
    story.story_choices.create!(step_number: 3, question: "Troisième ?", option_a: "A", option_b: "B")
    story.story_choices.create!(step_number: 2, question: "Deuxième ?", option_a: "A", option_b: "B")

    # Act — récupère les choix dans l'ordre
    ordered = story.story_choices.ordered

    # Assert — chaque step_number doit être <= au suivant
    step_numbers = ordered.pluck(:step_number)
    assert_equal step_numbers.sort, step_numbers,
                 "ordered devrait trier les choix par step_number croissant"
  end

  # ===========================================================
  # SECTION 3 — MÉTHODES MÉTIER
  # ===========================================================

  # Vérifie que resolved? retourne false quand chosen_option est nil
  # Cas : choix non encore effectué
  # Pourquoi : utilisé dans la vue pour afficher les boutons de choix
  test "resolved? retourne false si chosen_option est nil" do
    # Arrange — pending_choice n'a pas de chosen_option dans les fixtures
    choice = story_choices(:pending_choice)
    assert_nil choice.chosen_option, "Pré-condition : chosen_option doit être nil"

    # Assert
    assert_not choice.resolved?,
               "resolved? devrait retourner false quand chosen_option est nil"
  end

  # Vérifie que resolved? retourne true quand chosen_option est renseigné
  # Cas : enfant a choisi l'option 'a'
  # Pourquoi : la vue masque les boutons et affiche le texte choisi
  test "resolved? retourne true si chosen_option est 'a' ou 'b'" do
    # Arrange — on marque le choix comme effectué
    choice = story_choices(:pending_choice)
    choice.chosen_option = "a"

    # Assert
    assert choice.resolved?,
           "resolved? devrait retourner true quand chosen_option est 'a'"
  end

  # Vérifie que chosen_text retourne le texte de l'option 'a' si choisie
  # Cas : chosen_option = 'a'
  # Pourquoi : affiché dans le récit pour rappeler ce que l'enfant a choisi
  test "chosen_text retourne option_a si chosen_option est 'a'" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.chosen_option = "a"

    # Act
    text = choice.chosen_text

    # Assert — doit retourner le texte de l'option A
    assert_equal choice.option_a, text,
                 "chosen_text devrait retourner option_a quand chosen_option = 'a'"
  end

  # Vérifie que chosen_text retourne le texte de l'option 'b' si choisie
  # Cas : chosen_option = 'b'
  # Pourquoi : même raison que option_a — doit retourner le bon texte selon le choix
  test "chosen_text retourne option_b si chosen_option est 'b'" do
    # Arrange
    choice = story_choices(:pending_choice)
    choice.chosen_option = "b"

    # Act
    text = choice.chosen_text

    # Assert
    assert_equal choice.option_b, text,
                 "chosen_text devrait retourner option_b quand chosen_option = 'b'"
  end

  # Vérifie que chosen_text retourne nil si chosen_option est nil
  # Cas : choix non encore effectué
  # Pourquoi : la vue ne doit pas afficher de texte si aucun choix n'a été fait
  test "chosen_text retourne nil si aucun choix n'a été effectué" do
    # Arrange — pending_choice n'a pas de chosen_option dans les fixtures
    choice = story_choices(:pending_choice)
    assert_nil choice.chosen_option, "Pré-condition : chosen_option doit être nil"

    # Act
    text = choice.chosen_text

    # Assert
    assert_nil text, "chosen_text devrait retourner nil si chosen_option est nil"
  end
end
