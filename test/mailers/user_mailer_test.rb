require "test_helper"

# ============================================================
# Tests du UserMailer — relances des comptes sans histoire (J+7 / J+30)
# ============================================================
# On vérifie le CONTRAT de l'email selon l'étape (stage) : destinataire,
# objet adapté et présence du lien de création de héros dans le corps.
class UserMailerTest < ActionMailer::TestCase
  # --- Relance J+7 : ton léger, invite à créer la 1re histoire ---
  test "no_story_reminder J+7 : bon destinataire, objet léger, lien héros" do
    user  = users(:paul)
    email = UserMailer.no_story_reminder(user, 7)

    # Destinataire = l'email du compte relancé
    assert_equal [user.email], email.to
    # L'objet J+7 personnalise avec le prénom et parle de "première histoire"
    assert_match user.first_name, email.subject
    assert_match(/première histoire/i, email.subject)
    # Le corps contient le lien vers la création de héros (domaine de prod)
    assert_match "noctilio-app.fr", email.body.encoded
  end

  # --- Relance J+30 : ton plus incitatif (objet différent de J+7) ---
  test "no_story_reminder J+30 : objet plus incitatif" do
    user  = users(:paul)
    email = UserMailer.no_story_reminder(user, 30)

    assert_equal [user.email], email.to
    # L'objet J+30 est plus direct ("attend toujours")
    assert_match(/attend toujours/i, email.subject)
  end
end
