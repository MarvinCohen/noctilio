# Test du modèle Feedback
# Vérifie les validations : message obligatoire et borné, catégorie autorisée,
# email optionnel mais bien formé, et association user facultative (retour anonyme).
require "test_helper"

class FeedbackTest < ActiveSupport::TestCase
  # Construit un feedback valide de base, réutilisé dans chaque test.
  # On part toujours d'un objet valide puis on casse UN seul champ à la fois.
  def valid_feedback(attrs = {})
    Feedback.new({ message: "Ceci est un retour de test valide.", category: "bug" }.merge(attrs))
  end

  # ===========================================================
  # SECTION 1 — message (obligatoire + longueur)
  # ===========================================================

  # Cas nominal : un message correct + une catégorie valide → l'objet est valide
  test "un feedback avec message et catégorie valides est valide" do
    assert valid_feedback.valid?, "Un feedback bien rempli devrait être valide"
  end

  # Le message est obligatoire : sans lui, le retour n'a aucun contenu
  test "un feedback sans message est invalide" do
    feedback = valid_feedback(message: nil)
    assert_not feedback.valid?, "Un feedback sans message ne devrait pas être valide"
    assert feedback.errors[:message].any?, "Une erreur devrait porter sur le message"
  end

  # Message trop court (< 10 caractères) : évite les "ok" ou "test" sans valeur
  test "un message trop court est invalide" do
    feedback = valid_feedback(message: "court")
    assert_not feedback.valid?, "Un message de moins de 10 caractères devrait être refusé"
  end

  # Message trop long (> 2000 caractères) : protège d'un abus / spam volumineux
  test "un message trop long est invalide" do
    feedback = valid_feedback(message: "a" * 2001)
    assert_not feedback.valid?, "Un message de plus de 2000 caractères devrait être refusé"
  end

  # ===========================================================
  # SECTION 2 — category (liste blanche)
  # ===========================================================

  # Chaque catégorie autorisée doit être acceptée
  test "les catégories autorisées sont valides" do
    Feedback::CATEGORIES.each do |cat|
      assert valid_feedback(category: cat).valid?, "La catégorie #{cat} devrait être valide"
    end
  end

  # Une catégorie hors liste (forgée via un POST) doit être rejetée
  test "une catégorie hors liste est invalide" do
    feedback = valid_feedback(category: "piratage")
    assert_not feedback.valid?, "Une catégorie non autorisée devrait être refusée"
  end

  # ===========================================================
  # SECTION 3 — email (optionnel mais bien formé)
  # ===========================================================

  # Email absent : un retour anonyme est accepté
  test "un feedback sans email est valide" do
    assert valid_feedback(email: nil).valid?, "L'email est optionnel, l'absence est valide"
  end

  # Email mal formé : si fourni, il doit ressembler à un email
  test "un email mal formé est invalide" do
    feedback = valid_feedback(email: "pas-un-email")
    assert_not feedback.valid?, "Un email mal formé devrait être refusé"
  end

  # Email bien formé : accepté
  test "un email bien formé est valide" do
    assert valid_feedback(email: "parent@exemple.fr").valid?, "Un email valide devrait être accepté"
  end

  # ===========================================================
  # SECTION 4 — association user (facultative)
  # ===========================================================

  # Sans user : retour anonyme accepté (belongs_to optional: true)
  test "un feedback sans user est valide" do
    assert valid_feedback(user: nil).valid?, "Un retour anonyme (sans user) devrait être valide"
  end

  # Avec user : retour rattaché à un compte connecté
  test "un feedback rattaché à un user est valide" do
    assert valid_feedback(user: users(:marie)).valid?, "Un retour rattaché à un user devrait être valide"
  end
end
