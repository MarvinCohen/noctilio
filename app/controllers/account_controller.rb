# ============================================================
# AccountController — espace personnel "Mon compte"
# Affiche les infos du compte connecté et permet de basculer le mode test
# ============================================================
class AccountController < ApplicationController
  # Toutes les actions exigent d'être connecté (authenticate_user! global hérité)

  # Liste blanche des emails autorisés à activer le mode test (= passer admin).
  # SÉCURITÉ : sans cette restriction, n'importe quel utilisateur pourrait se
  # rendre admin et débloquer les fonctionnalités premium gratuitement.
  # On gèle la liste ici, côté serveur — la vue ne fait que masquer le bouton.
  AUTHORIZED_TEST_EMAILS = %w[marvincohen95@gmail.com].freeze

  # ============================================================
  # GET /mon-compte
  # Affiche les informations du compte de l'utilisateur connecté
  # ============================================================
  def show
    # current_user est fourni par Devise — l'utilisateur actuellement connecté
    @user = current_user

    # Indique à la vue si ce compte a le droit de voir le bouton "mode test"
    # (utilisé uniquement pour l'affichage — la vraie garde est côté serveur)
    @can_use_test_mode = test_mode_authorized?
  end

  # ============================================================
  # POST /mon-compte/mode-test
  # Bascule le statut admin du compte (active/désactive le mode test)
  # Le mode test rend premium? = true → débloque le mode interactif
  # ============================================================
  def toggle_test_mode
    # GARDE DE SÉCURITÉ — bloque toute requête venant d'un email non autorisé,
    # même si quelqu'un forge la requête POST sans passer par le bouton
    unless test_mode_authorized?
      redirect_to account_path, alert: "Action non autorisée." and return
    end

    # Inverse le statut admin actuel : true devient false, false devient true
    current_user.update!(admin: !current_user.admin?)

    # Message de confirmation adapté au nouveau statut
    message = current_user.admin? ? "Mode test activé — fonctionnalités premium débloquées." : "Mode test désactivé."

    redirect_to account_path, notice: message
  end

  # ============================================================
  # GET /mon-compte/export
  # Télécharge toutes les données personnelles de l'utilisateur au format JSON
  # (droit d'accès et portabilité — RGPD art. 15 et 20).
  # ============================================================
  def export
    # Toute la logique d'assemblage vit dans le modèle (Fat Model) : le controller
    # se contente d'appeler la méthode et de déclencher le téléchargement.
    # current_user garantit que seules SES données sont exportées.
    data = current_user.gdpr_export

    # send_data déclenche un téléchargement de fichier (Content-Disposition:
    # attachment) au lieu d'afficher le JSON dans le navigateur.
    # JSON.pretty_generate : JSON indenté, lisible par un humain.
    # Nom de fichier daté pour que l'utilisateur s'y retrouve s'il exporte plusieurs fois.
    send_data JSON.pretty_generate(data),
              filename: "noctilio-mes-donnees-#{Date.current}.json",
              type: "application/json",
              disposition: "attachment"
  end

  private

  # ============================================================
  # Vérifie si l'utilisateur connecté est autorisé à utiliser le mode test
  # downcase pour éviter les soucis de casse dans l'email
  # ============================================================
  def test_mode_authorized?
    AUTHORIZED_TEST_EMAILS.include?(current_user.email.downcase)
  end
end
