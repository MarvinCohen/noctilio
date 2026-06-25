# ============================================================
# Service PushNotificationService — envoie une notification push
# ============================================================
# Encapsule l'envoi via le gem web-push (Web Push Protocol + clés VAPID).
# Usage :
#   PushNotificationService.new(subscription).deliver(
#     title: "Une histoire ce soir ?",
#     body:  "Léo attend sa nouvelle aventure ✦",
#     url:   "/stories/new"
#   )
#
# Si l'abonnement est expiré/invalide (l'utilisateur a désinstallé la PWA ou
# révoqué la permission), le service le SUPPRIME de la base pour ne pas réessayer
# indéfiniment.
# ============================================================
class PushNotificationService
  # Sujet VAPID — identifie l'expéditeur auprès du service de push (obligatoire).
  VAPID_SUBJECT = "mailto:contact@noctilio-app.fr".freeze

  # subscription : un PushSubscription à qui envoyer la notification
  def initialize(subscription)
    @subscription = subscription
  end

  # Envoie la notification. Retourne true si envoyée, false sinon.
  # title/body : texte affiché ; url : page ouverte au clic sur la notif.
  def deliver(title:, body:, url: "/")
    # Sans clés VAPID configurées (dev/test), on ne tente rien : le push est inactif.
    return false unless vapid_configured?

    # Le payload est sérialisé en JSON et lu côté service worker (événement "push").
    payload = { title: title, body: body, url: url }.to_json

    WebPush.payload_send(
      message:     payload,
      endpoint:    @subscription.endpoint,
      p256dh:      @subscription.p256dh_key,
      auth:        @subscription.auth_key,
      vapid: {
        public_key:  ENV["VAPID_PUBLIC_KEY"],
        private_key: ENV["VAPID_PRIVATE_KEY"],
        subject:     VAPID_SUBJECT
      }
    )
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    # 404/410 : l'abonnement n'existe plus côté navigateur → on le purge en base.
    @subscription.destroy
    false
  rescue WebPush::ResponseError => e
    # Autre erreur du service de push : on la remonte à Sentry sans planter le job.
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  private

  # Les deux clés VAPID doivent être présentes en ENV pour pouvoir envoyer.
  def vapid_configured?
    ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
  end
end
