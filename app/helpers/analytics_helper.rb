# ============================================================
# AnalyticsHelper — décide si le tracking analytics doit s'activer
# ============================================================
# Utilisé par le partial shared/_analytics.html.erb pour insérer (ou non)
# le script Umami Cloud dans le <head> des layouts.
module AnalyticsHelper
  # Liste blanche des événements de funnel qu'on autorise à tracker.
  # SÉCURITÉ : le nom d'événement finit dans un <script> côté client. On ne rend
  # JAMAIS un nom arbitraire (ex : venant d'un flash empoisonné) — seuls ces noms
  # connus passent. Toute autre valeur est ignorée silencieusement.
  # Ces 4 événements couvrent le funnel : inscription → création → intention
  # d'achat → abonnement activé.
  ALLOWED_UMAMI_EVENTS = %w[
    signup
    story_created
    checkout_started
    subscription_activated
  ].freeze

  # ============================================================
  # umami_enabled? — true si le script de tracking Umami doit être rendu
  # ============================================================
  # Deux conditions cumulatives doivent être réunies :
  #   1. ENV["UMAMI_WEBSITE_ID"] est défini
  #      → cette variable n'existe que sur Railway (prod), donc en dev et en test
  #        elle est absente : l'analytics est automatiquement désactivé localement
  #   2. L'utilisateur connecté n'est PAS admin
  #      → évite de polluer les statistiques avec le mode test de Marvin
  #        (un visiteur anonyme sur la landing a current_user == nil → tracké)
  def umami_enabled?
    # Sans identifiant de site, aucun tracking possible
    return false if ENV["UMAMI_WEBSITE_ID"].blank?

    # respond_to? : garde défensive — current_user n'est fourni par Devise que
    # dans un contexte de vue. Évite une erreur si le helper est appelé ailleurs.
    return false if respond_to?(:current_user) && current_user&.admin?

    true
  end

  # ============================================================
  # umami_event_tag(name) — rend un <script> qui déclenche un événement Umami
  # ============================================================
  # Utilisé dans les layouts pour émettre un événement de funnel après une
  # redirection serveur (ex : signup, story_created, subscription_activated
  # portés par flash[:umami_event]).
  #
  # Rend une chaîne vide (nil) — donc RIEN dans le HTML — dans tous ces cas :
  #   - analytics désactivé (dev/test/admin) → umami_enabled? est false
  #   - name absent (nil / vide) → aucun événement à émettre
  #   - name hors liste blanche → refusé par sécurité (voir ALLOWED_UMAMI_EVENTS)
  #
  # SÉCURITÉ : name est validé contre la liste blanche PUIS encodé via to_json
  # (échappement JS correct). Aucune injection possible via un flash empoisonné.
  #
  # Le tracking part sur l'événement "load" : on attend que script.js (chargé en
  # defer) ait défini window.umami avant d'appeler umami.track.
  def umami_event_tag(name)
    # Garde 1 : analytics coupé (dev/test/admin) → on ne rend rien.
    return unless umami_enabled?
    # Garde 2 : pas de nom, ou nom inconnu → on ne rend rien (anti-injection).
    return unless name.present? && ALLOWED_UMAMI_EVENTS.include?(name.to_s)

    # to_json échappe le nom pour un contexte JavaScript (guillemets, etc.).
    event = name.to_s.to_json
    # nonce exigé par la CSP (inline script autorisé seulement avec ce nonce).
    nonce = content_security_policy_nonce

    # html_safe : on maîtrise entièrement le contenu (nom en liste blanche + to_json),
    # donc on peut désactiver l'auto-échappement d'ERB sans risque XSS.
    <<~HTML.html_safe
      <script nonce="#{nonce}">
        window.addEventListener('load', function () {
          if (window.umami) { window.umami.track(#{event}); }
        });
      </script>
    HTML
  end
end
