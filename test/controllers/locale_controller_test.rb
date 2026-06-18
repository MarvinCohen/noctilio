# Tests du LocaleController — changement de langue de l'interface (i18n)
# On vérifie : enregistrement d'une langue valide, rejet d'une langue invalide
# (fallback FR), persistance sur le compte d'un connecté, et persistance via la
# session entre deux requêtes.
require "test_helper"

class LocaleControllerTest < ActionDispatch::IntegrationTest
  # Connecte un utilisateur via la session Devise (même pattern que les autres tests)
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — Enregistrement d'une langue valide
  # ===========================================================

  # Vérifie qu'une langue supportée est mémorisée en session puis appliquée.
  # Cas : visiteur (non connecté) choisit l'anglais via POST /langue.
  # Pourquoi : c'est le comportement de base du sélecteur de langue.
  test "POST /langue avec une langue valide mémorise le choix en session" do
    # Act — on poste la langue "en" (anglais), avec un referer (accueil FR)
    post locale_path, params: { locale: "en" }, headers: { "HTTP_REFERER" => root_path }

    # Assert — la session contient bien la langue choisie
    assert_equal :en, session[:locale],
                 "La langue valide choisie devrait être mémorisée en session"
    # Assert — on est renvoyé sur l'accueil PRÉFIXÉ de la nouvelle langue (/en).
    # La page publique tire sa langue du préfixe d'URL : la redirection doit donc
    # pointer vers /en pour que l'accueil s'affiche en anglais.
    assert_redirected_to "/en"
  end

  # Vérifie le correctif du bug "bloqué sur une langue" : depuis une page publique
  # déjà préfixée (/es/blog), choisir une autre langue redirige vers la même page
  # avec le nouveau préfixe (/de/blog) — et non vers l'ancienne URL espagnole.
  # Pourquoi : sur les pages publiques, le préfixe d'URL est prioritaire sur la
  # session ; sans réécriture du préfixe, la page resterait dans l'ancienne langue.
  test "POST /langue depuis une page préfixée redirige vers la même page dans la nouvelle langue" do
    # Act — on est sur /es/blog (espagnol) et on choisit l'allemand
    post locale_path, params: { locale: "de" },
         headers: { "HTTP_REFERER" => "http://www.example.com/es/blog" }

    # Assert — redirection vers /de/blog (même page, préfixe allemand)
    assert_redirected_to "/de/blog"

    # Assert — la page cible s'affiche bien en allemand après suivi de la redirection
    follow_redirect!
    assert_includes response.body, "Blog",
                     "La page blog devrait répondre dans la nouvelle langue (allemand)"
  end

  # Vérifie que la langue mémorisée est réellement appliquée à la requête suivante.
  # Cas : après avoir choisi l'espagnol, une page publique répond en espagnol.
  # Pourquoi : valide la chaîne session -> switch_locale -> I18n.locale.
  test "la langue mémorisée en session est appliquée à la requête suivante" do
    # Arrange — on choisit l'espagnol
    post locale_path, params: { locale: "es" }, headers: { "HTTP_REFERER" => root_path }

    # Act — on visite la page à propos sans préfixe d'URL ni paramètre locale
    get "/a-propos"

    # Assert — le contenu doit être en espagnol (titre de la version ES)
    assert_includes response.body, "Acerca",
                     "La page devrait s'afficher dans la langue mémorisée (espagnol)"
  end

  # ===========================================================
  # SECTION 2 — Rejet d'une langue invalide (fallback FR)
  # ===========================================================

  # Vérifie qu'une langue non supportée est ignorée (sécurité contre l'injection).
  # Cas : on tente ?locale=xx (langue inexistante).
  # Pourquoi : switch_locale doit retomber sur le français par défaut.
  test "POST /langue avec une langue invalide est ignoré" do
    # Act — on tente une langue arbitraire non déclarée dans available_locales
    post locale_path, params: { locale: "xx" }, headers: { "HTTP_REFERER" => root_path }

    # Assert — la session ne doit PAS contenir la langue invalide.
    # switch_locale force :fr (langue par défaut) car "xx" n'est pas disponible.
    assert_equal :fr, session[:locale],
                 "Une langue invalide devrait être ignorée et retomber sur le français"
  end

  # ===========================================================
  # SECTION 3 — Persistance sur le compte d'un utilisateur connecté
  # ===========================================================

  # Vérifie qu'un connecté voit sa préférence de langue enregistrée sur son compte.
  # Cas : Marie (connectée) choisit l'italien.
  # Pourquoi : la préférence doit la suivre sur tous ses appareils (colonne users.locale).
  test "POST /langue persiste la langue sur le compte d'un connecté" do
    # Arrange — Marie se connecte (locale par défaut "fr")
    sign_in_as(users(:marie))

    # Act — elle choisit l'italien
    post locale_path, params: { locale: "it" }, headers: { "HTTP_REFERER" => root_path }

    # Assert — la préférence est enregistrée en base sur son compte
    assert_equal "it", users(:marie).reload.locale,
                 "La langue choisie devrait être persistée sur le compte connecté"
  end

  # Vérifie qu'une langue invalide ne modifie PAS le compte d'un connecté.
  # Cas : Marie tente une langue non supportée.
  # Pourquoi : sécurité — current_user.update n'est appelé que si la langue est valide.
  test "POST /langue invalide ne modifie pas la langue du compte" do
    # Arrange — Marie connectée, locale par défaut "fr"
    sign_in_as(users(:marie))

    # Act — tentative avec une langue inexistante
    post locale_path, params: { locale: "zz" }, headers: { "HTTP_REFERER" => root_path }

    # Assert — la langue du compte reste inchangée (toujours "fr")
    assert_equal "fr", users(:marie).reload.locale,
                 "Une langue invalide ne devrait jamais modifier le compte"
  end
end
