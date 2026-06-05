# Controller des callbacks OmniAuth
# ============================================================
# Rails appelle ce controller automatiquement après que l'utilisateur
# ait autorisé l'accès sur la page Google.
#
# Flux complet :
#   1. L'utilisateur clique "Continuer avec Google"
#   2. Il est redirigé vers Google (accounts.google.com)
#   3. Il autorise l'accès
#   4. Google redirige vers /users/auth/google_oauth2/callback
#   5. OmniAuth parse la réponse et appelle google_oauth2 ici
#   6. On connecte ou crée l'utilisateur, puis on redirige vers l'app

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    # Action appelée après le retour de Google
    # Le nom de la méthode DOIT correspondre au nom du provider (google_oauth2)
    def google_oauth2
      # request.env["omniauth.auth"] contient le hash Google renvoyé par OmniAuth
      # On le passe à User.from_omniauth qui trouve ou crée l'utilisateur en base
      @user = User.from_omniauth(request.env["omniauth.auth"])

      if @user.persisted?
        # L'utilisateur existe ou vient d'être créé — on le connecte
        # :notice affiche un message flash de succès
        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      else
        # La création a échoué (email déjà pris par un compte classique, etc.)
        # On sauvegarde les données Google en session pour pré-remplir l'inscription
        session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
        # On redirige vers l'inscription avec un message d'erreur
        redirect_to new_user_registration_url, alert: @user.errors.full_messages.join(", ")
      end
    end

    # Action appelée si l'utilisateur annule sur la page Google
    # On le redirige simplement vers la page de connexion
    def failure
      redirect_to root_path, alert: "Connexion avec Google annulée."
    end
  end
end
