require "test_helper"

# Tests du service PushNotificationService.
# On vérifie surtout le comportement SANS clés VAPID (cas dev/test) et
# le nettoyage des abonnements expirés, sans réel appel réseau.
class PushNotificationServiceTest < ActiveSupport::TestCase
  setup do
    # Abonnement de test rattaché à Marie (fixtures)
    @subscription = users(:marie).push_subscriptions.create!(
      endpoint: "https://push.example.com/test",
      p256dh_key: "p256dh",
      auth_key: "auth"
    )
  end

  # Sans clés VAPID configurées, deliver doit renvoyer false sans tenter d'envoi.
  # Pourquoi : en dev/test on n'a pas de clés VAPID → le push est simplement inactif.
  test "deliver renvoie false quand les clés VAPID ne sont pas configurées" do
    # On s'assure que les clés sont absentes pendant ce test
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")

    resultat = PushNotificationService.new(@subscription).deliver(
      title: "Test", body: "Corps", url: "/"
    )

    assert_equal false, resultat,
                 "Sans clés VAPID, deliver doit renvoyer false sans planter"
  end

  # Quand l'abonnement est expiré (404/410 côté push), le service le supprime.
  # Pourquoi : inutile de réessayer indéfiniment vers un abonnement mort.
  test "deliver supprime l'abonnement expiré" do
    # On simule des clés VAPID présentes pour passer la garde vapid_configured?
    ENV["VAPID_PUBLIC_KEY"] = "cle-publique-factice"
    ENV["VAPID_PRIVATE_KEY"] = "cle-privee-factice"

    # On force WebPush.payload_send à lever ExpiredSubscription.
    # ResponseError#initialize lit response.body : on fournit donc une fausse
    # réponse (HTTP 410) qui répond à .body pour ne pas planter le constructeur.
    fausse_reponse = Struct.new(:body).new("Gone")
    leve_expiration = ->(**) { raise WebPush::ExpiredSubscription.new(fausse_reponse, "push.example.com") }
    stub_method(WebPush, :payload_send, leve_expiration) do
      assert_difference "PushSubscription.count", -1 do
        resultat = PushNotificationService.new(@subscription).deliver(
          title: "Test", body: "Corps"
        )
        assert_equal false, resultat, "Un abonnement expiré doit renvoyer false"
      end
    end
  ensure
    # On nettoie les clés factices pour ne pas polluer les autres tests
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  # Quand l'envoi réussit, deliver renvoie true et conserve l'abonnement.
  test "deliver renvoie true quand l'envoi réussit" do
    ENV["VAPID_PUBLIC_KEY"] = "cle-publique-factice"
    ENV["VAPID_PRIVATE_KEY"] = "cle-privee-factice"

    # On simule un envoi réussi (WebPush ne lève rien)
    stub_method(WebPush, :payload_send, ->(**) { true }) do
      resultat = PushNotificationService.new(@subscription).deliver(
        title: "Test", body: "Corps"
      )
      assert_equal true, resultat, "Un envoi réussi doit renvoyer true"
    end
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end
end
