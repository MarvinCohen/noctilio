# Test du modèle WaitlistEntry
# Ce fichier vérifie les règles de validation du formulaire d'inscription
# à la liste d'attente : présence, format email, unicité, et normalisation.
require "test_helper"

class WaitlistEntryTest < ActiveSupport::TestCase

  # ===========================================================
  # SECTION 1 — VALIDATIONS DE PRÉSENCE
  # ===========================================================

  # Vérifie qu'une entrée avec un email valide est acceptée
  # Cas : email correct au format standard
  # Pourquoi : s'assurer que le cas nominal fonctionne avant de tester les cas d'erreur
  test "une entrée valide avec un email correct est sauvegardée" do
    # Arrange — construit une entrée avec un email valide
    entry = WaitlistEntry.new(email: "test@example.com")

    # Assert — aucune erreur de validation
    assert entry.valid?, "Une entrée avec un email valide devrait être acceptée : #{entry.errors.full_messages}"
  end

  # Vérifie qu'une entrée sans email est invalide
  # Cas : email manquant
  # Pourquoi : l'email est le seul champ du formulaire — il est obligatoire
  test "une entrée sans email est invalide" do
    # Arrange
    entry = WaitlistEntry.new(email: nil)

    # Act
    entry.valid?

    # Assert
    assert entry.errors[:email].any?, "L'email devrait être obligatoire"
  end

  # Vérifie qu'une entrée avec un email vide est invalide
  # Cas : email = "" (chaîne vide)
  # Pourquoi : un email vide est différent de nil mais doit être rejeté de la même façon
  test "une entrée avec un email vide est invalide" do
    # Arrange
    entry = WaitlistEntry.new(email: "")

    # Act
    entry.valid?

    # Assert
    assert entry.errors[:email].any?, "Un email vide devrait être refusé"
  end

  # ===========================================================
  # SECTION 2 — VALIDATION DE FORMAT
  # ===========================================================

  # Vérifie qu'un email sans arobase est refusé
  # Cas : "pasundomain" — pas d'@
  # Pourquoi : URI::MailTo::EMAIL_REGEXP exige le format user@domain
  test "un email sans arobase est invalide" do
    # Arrange
    entry = WaitlistEntry.new(email: "pasundomain")

    # Act
    entry.valid?

    # Assert
    assert entry.errors[:email].any?,
           "Un email sans @ devrait être refusé par la validation de format"
  end

  # Vérifie qu'un email avec un domaine incomplet est refusé
  # Cas : "user@" — pas de domaine après l'arobase
  # Pourquoi : le format doit être complet pour être utilisable
  test "un email avec un domaine manquant est invalide" do
    # Arrange
    entry = WaitlistEntry.new(email: "user@")

    # Act
    entry.valid?

    # Assert
    assert entry.errors[:email].any?,
           "Un email sans domaine devrait être refusé"
  end

  # Vérifie qu'un email avec des espaces est refusé
  # Cas : "user @example.com" — espace dans l'email
  # Pourquoi : les espaces sont interdits dans un email standard
  test "un email avec un espace est invalide" do
    # Arrange
    entry = WaitlistEntry.new(email: "user @example.com")

    # Act
    entry.valid?

    # Assert
    assert entry.errors[:email].any?,
           "Un email avec un espace devrait être refusé"
  end

  # ===========================================================
  # SECTION 3 — VALIDATION D'UNICITÉ
  # ===========================================================

  # Vérifie qu'un email déjà inscrit est refusé
  # Cas : même email soumis deux fois
  # Pourquoi : un email ne peut s'inscrire qu'une seule fois sur la liste d'attente
  test "un email déjà inscrit est refusé" do
    # Arrange — inscrit un premier email
    WaitlistEntry.create!(email: "doublon@example.com")

    # Tente de créer un doublon
    duplicate = WaitlistEntry.new(email: "doublon@example.com")

    # Act
    duplicate.valid?

    # Assert — l'erreur d'unicité doit être présente
    assert duplicate.errors[:email].any?,
           "Un email déjà inscrit devrait être refusé (unicité)"
  end

  # Vérifie que l'unicité est insensible à la casse
  # Cas : "Test@example.com" vs "test@example.com"
  # Pourquoi : case_sensitive: false — les deux doivent être considérés comme identiques
  test "un email déjà inscrit en majuscules est refusé (unicité insensible à la casse)" do
    # Arrange — inscrit d'abord en minuscules
    WaitlistEntry.create!(email: "casse@example.com")

    # Tente de créer un doublon en majuscules
    duplicate = WaitlistEntry.new(email: "CASSE@EXAMPLE.COM")

    # Act
    duplicate.valid?

    # Assert — même email en casse différente → doit être refusé
    assert duplicate.errors[:email].any?,
           "Un email en majuscules identique à un existant devrait être refusé (case_sensitive: false)"
  end

  # ===========================================================
  # SECTION 4 — CALLBACK downcase_email
  # ===========================================================

  # Vérifie que l'email est mis en minuscules avant la sauvegarde
  # Cas : email soumis avec des majuscules
  # Pourquoi : la normalisation évite les doublons de casse — "Test@Email.fr" et "test@email.fr"
  #            seraient deux entrées différentes sans ce callback
  test "l'email est mis en minuscules avant la sauvegarde" do
    # Arrange — crée une entrée avec un email en majuscules
    entry = WaitlistEntry.create!(email: "MAJUSCULES@EXAMPLE.COM")

    # Assert — l'email en base doit être en minuscules
    assert_equal "majuscules@example.com", entry.email,
                 "Le callback before_save devrait mettre l'email en minuscules"
  end

  # NOTE : on ne teste pas le strip des espaces via create! car la validation de format
  # (URI::MailTo::EMAIL_REGEXP) s'exécute AVANT before_save et rejette les emails avec espaces.
  # Le strip est donc couvert implicitement : un email avec espaces ne passe même pas la validation.
end
