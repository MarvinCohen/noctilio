// ============================================================
// Stimulus Controller : push
// ============================================================
// Gère l'activation/désactivation des notifications push ("histoire du soir").
// Branché sur le bouton de la page /mon-compte.
//
// Utilisation dans la vue :
//   data-controller="push"
//   data-push-vapid-public-key-value="<clé publique VAPID>"
//   data-push-target="button"  (le bouton bascule on/off)
//   data-action="click->push#toggle"
// ============================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    vapidPublicKey: String, // clé publique VAPID (sert à chiffrer côté navigateur)
    // Libellés traduits passés par la vue (on évite de coder le texte en dur ici)
    enableLabel: String,
    disableLabel: String,
    unsupportedLabel: String
  }
  static targets = ["button"]

  // Au montage : si le push n'est pas supporté, on désactive le bouton.
  // Sinon, on affiche le bon libellé selon que l'utilisateur est déjà abonné.
  async connect() {
    if (!this.isSupported()) {
      this.markUnsupported()
      return
    }
    const subscription = await this.currentSubscription()
    this.render(Boolean(subscription))
  }

  // Le navigateur supporte-t-il tout ce qu'il faut pour le push ?
  isSupported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  // Récupère l'abonnement push existant pour ce navigateur (ou null).
  async currentSubscription() {
    const registration = await navigator.serviceWorker.ready
    return registration.pushManager.getSubscription()
  }

  // Bascule : abonne si pas encore abonné, désabonne sinon.
  async toggle() {
    const subscription = await this.currentSubscription()
    if (subscription) {
      await this.unsubscribe(subscription)
    } else {
      await this.subscribe()
    }
  }

  // ── Abonnement ──
  async subscribe() {
    // 1. Demande la permission d'afficher des notifications
    const permission = await Notification.requestPermission()
    if (permission !== "granted") {
      // Refusé par l'utilisateur → on reste dans l'état "désactivé"
      this.render(false)
      return
    }

    // 2. Crée l'abonnement push auprès du navigateur (clé VAPID publique)
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true, // obligatoire : chaque push DOIT afficher une notif
      applicationServerKey: this.urlBase64ToUint8Array(this.vapidPublicKeyValue)
    })

    // 3. Envoie l'abonnement au serveur pour qu'il puisse nous notifier plus tard
    await this.sendToServer(subscription)
    this.render(true)
  }

  // ── Désabonnement ──
  async unsubscribe(subscription) {
    // On prévient le serveur (suppression en base) puis on annule côté navigateur
    await this.removeFromServer(subscription.endpoint)
    await subscription.unsubscribe()
    this.render(false)
  }

  // POST l'abonnement vers le serveur (PushSubscriptionsController#create)
  async sendToServer(subscription) {
    await fetch("/push_subscriptions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        subscription: {
          endpoint:   subscription.endpoint,
          p256dh_key: this.arrayBufferToBase64(subscription.getKey("p256dh")),
          auth_key:   this.arrayBufferToBase64(subscription.getKey("auth"))
        }
      })
    })
  }

  // DELETE l'abonnement côté serveur (identifié par son endpoint)
  async removeFromServer(endpoint) {
    await fetch("/push_subscriptions", {
      method: "DELETE",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ endpoint: endpoint })
    })
  }

  // ── Rendu du bouton selon l'état (abonné / non abonné) ──
  render(subscribed) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = false
    this.buttonTarget.textContent = subscribed ? this.disableLabelValue : this.enableLabelValue
    // data-subscribed sert au style CSS (ex: bouton "actif")
    this.buttonTarget.dataset.subscribed = subscribed ? "true" : "false"
  }

  // Navigateur incompatible : bouton désactivé avec un libellé explicite
  markUnsupported() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = this.unsupportedLabelValue
  }

  // ── Utilitaires ──

  // Jeton CSRF Rails (lu dans la balise meta du layout)
  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  // Convertit la clé VAPID (base64 URL-safe) en Uint8Array attendu par l'API Push.
  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const rawData = window.atob(base64)
    const outputArray = new Uint8Array(rawData.length)
    for (let i = 0; i < rawData.length; i++) {
      outputArray[i] = rawData.charCodeAt(i)
    }
    return outputArray
  }

  // Convertit un ArrayBuffer (clés de l'abonnement) en base64 pour l'envoi JSON.
  arrayBufferToBase64(buffer) {
    const bytes = new Uint8Array(buffer)
    let binary = ""
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i])
    }
    return window.btoa(binary)
  }
}
