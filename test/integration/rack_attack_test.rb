require "test_helper"

# ============================================================
# Tests des throttles PAR UTILISATEUR de Rack::Attack
# ============================================================
# On NE teste PAS ici le middleware complet (qui exigerait un cache et de
# contourner la safelist localhost). On teste directement la LOGIQUE des
# discriminateurs ajoutés à l'incrément 1 : chaque throttle a un bloc
# (Rack::Attack.throttles[nom].block) qui, pour une requête donnée, renvoie
# la clé de comptage (l'id du user connecté) ou nil (pas de comptage).
#
# On appelle ce bloc avec une fausse requête minimale exposant seulement ce
# que les discriminateurs lisent : path, post? et env (qui contient warden).
class RackAttackTest < ActiveSupport::TestCase
  # Fausse requête Rack minimale. Struct génère les lecteurs path/env ;
  # on ajoute post? à la main (le nom se termine par "?", interdit pour un membre Struct).
  FakeRequest = Struct.new(:path, :post, :env) do
    def post?
      post
    end
  end

  # Construit une fausse requête. `user` (ou nil) est exposé via un faux Warden
  # sous la clé "warden", exactement comme Devise le fait en production.
  def fake_request(path:, post: true, user: nil)
    # Faux Warden : répond à #user en renvoyant l'utilisateur (ou nil pour anonyme)
    warden = Object.new
    warden.define_singleton_method(:user) { user }
    FakeRequest.new(path, post, { "warden" => warden })
  end

  # Raccourci : exécute le discriminateur d'un throttle nommé sur une requête
  def discriminator_for(name, request)
    Rack::Attack.throttles[name].block.call(request)
  end

  # --- Le throttle "stories/user" cible POST /stories et renvoie l'id du user ---
  test "stories/user renvoie l'id du user connecté sur POST /stories" do
    user = users(:paul)
    request = fake_request(path: "/stories", post: true, user: user)

    # Le discriminateur doit renvoyer l'id du user (clé de comptage par compte)
    assert_equal user.id, discriminator_for("stories/user", request)
  end

  # --- Anonyme : pas de user → nil → pas de comptage par user (le filtre IP prend le relais) ---
  test "stories/user renvoie nil pour un visiteur anonyme" do
    request = fake_request(path: "/stories", post: true, user: nil)

    assert_nil discriminator_for("stories/user", request),
               "Sans user connecté, le throttle par user ne doit pas s'appliquer"
  end

  # --- Mauvaise méthode : un GET /stories ne doit pas être compté ---
  test "stories/user renvoie nil sur un GET (seul le POST de création compte)" do
    user = users(:paul)
    request = fake_request(path: "/stories", post: false, user: user)

    assert_nil discriminator_for("stories/user", request),
               "Seul le POST de création doit être limité, pas le GET de la liste"
  end

  # --- story-generate/user cible /stories/:id/(replay|continue|retry|choose) ---
  test "story-generate/user matche les actions de génération et renvoie l'id du user" do
    user = users(:paul)
    request = fake_request(path: "/stories/42/replay", post: true, user: user)

    assert_equal user.id, discriminator_for("story-generate/user", request)
  end

  # --- story-generate/user ignore une action inconnue ---
  test "story-generate/user renvoie nil sur une action non génératrice" do
    user = users(:paul)
    # /stories/42/status n'est pas dans la liste replay|continue|retry|choose
    request = fake_request(path: "/stories/42/status", post: true, user: user)

    assert_nil discriminator_for("story-generate/user", request),
               "Une action qui ne lance pas de génération IA ne doit pas être limitée"
  end

  # --- audio/user cible les chemins se terminant par /audio ---
  test "audio/user matche les chemins /audio et renvoie l'id du user" do
    user = users(:paul)
    request = fake_request(path: "/stories/42/audio", post: true, user: user)

    assert_equal user.id, discriminator_for("audio/user", request)
  end

  # --- explore_alternative/user cible les chemins se terminant par /explore_alternative ---
  test "explore_alternative/user matche le bon chemin et renvoie l'id du user" do
    user = users(:paul)
    request = fake_request(path: "/stories/42/explore_alternative", post: true, user: user)

    assert_equal user.id, discriminator_for("explore_alternative/user", request)
  end
end
