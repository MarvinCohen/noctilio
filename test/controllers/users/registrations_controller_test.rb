# Test du Users::RegistrationsController — événement de funnel "signup"
# On vérifie que la création RÉUSSIE d'un compte pose flash[:umami_event] = "signup"
# (lu ensuite par le layout pour émettre le track Umami), et qu'une inscription
# invalide (mot de passe trop court) NE pose PAS cet événement.
require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  # Devise monte l'inscription sur user_registration_path (POST /users).

  # Une inscription valide doit poser l'événement funnel "signup".
  # Pourquoi : c'est la première étape mesurée du funnel de conversion.
  test "une inscription réussie pose flash[:umami_event] à signup" do
    # Act — création d'un compte avec un email absent des fixtures
    post user_registration_path, params: {
      user: {
        first_name: "Nouveau",
        last_name: "Parent",
        email: "nouveau.parent@example.com",
        password: "motdepasse123",
        password_confirmation: "motdepasse123"
      }
    }

    # Assert 1 — le compte a bien été créé en base
    assert User.exists?(email: "nouveau.parent@example.com"),
           "Le compte devrait avoir été créé en base"

    # Assert 2 — l'événement de funnel est posé pour la requête suivante
    assert_equal "signup", flash[:umami_event],
                 "Une inscription réussie doit poser l'événement funnel signup"
  end

  # Une inscription INVALIDE ne doit PAS poser l'événement (pas de conversion).
  # Cas : mot de passe trop court → resource.persisted? est false.
  test "une inscription invalide ne pose pas flash[:umami_event]" do
    # Act — mot de passe trop court (Devise exige au moins 6 caractères)
    post user_registration_path, params: {
      user: {
        first_name: "Echec",
        last_name: "Parent",
        email: "echec.parent@example.com",
        password: "123",
        password_confirmation: "123"
      }
    }

    # Assert — aucun compte créé, donc aucun événement de funnel
    assert_not User.exists?(email: "echec.parent@example.com"),
               "Aucun compte ne devrait être créé avec un mot de passe invalide"
    assert_nil flash[:umami_event],
               "Une inscription échouée ne doit pas poser d'événement funnel"
  end
end
