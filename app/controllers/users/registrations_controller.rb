module Users
  class RegistrationsController < Devise::RegistrationsController
    # ============================================================
    # Controller d'inscription personnalisé
    # ============================================================
    # On surcharge le controller Devise de base pour deux raisons :
    # 1. Autoriser les champs supplémentaires : first_name et last_name
    # 2. Rediriger vers le dashboard après inscription (pas la page d'accueil)

    # Surcharge before_action pour autoriser nos champs personnalisés
    # Devise filtre les paramètres pour la sécurité — il faut explicitement
    # lui dire quels champs supplémentaires accepter
    before_action :configure_sign_up_params, only: [:create]
    before_action :configure_account_update_params, only: [:update]

    # ============================================================
    # Inscription — surcharge pour tracker l'événement "signup"
    # ============================================================
    # On délègue tout le travail à Devise via super, mais on lui passe un bloc :
    # Devise yield la ressource (le User) une fois construite/sauvegardée.
    # Si resource.persisted? (compte réellement créé en base), on pose
    # flash[:umami_event] = "signup". Le layout lira ce flash après la redirection
    # et émettra l'événement Umami (via umami_event_tag). En cas d'échec de
    # validation, resource.persisted? est false → aucun événement.
    def create
      super do |resource|
        flash[:umami_event] = "signup" if resource.persisted?
      end
    end

    # ============================================================
    # Redirection après inscription réussie
    # ============================================================
    # Par défaut Devise redirige vers root_path.
    # On redirige vers le dashboard après la création du compte.
    def after_sign_up_path_for(_resource)
      dashboard_path
    end

    # Redirection après mise à jour du compte
    def after_update_path_for(_resource)
      dashboard_path
    end

    # Redirection quand l'utilisateur s'inscrit mais ne peut pas être connecté
    # automatiquement (ex : si Devise tente une confirmation email alors qu'on
    # n'utilise pas :confirmable — évite la route /confirmation-en-attente).
    # On redirige vers la page de connexion avec un message clair.
    def after_inactive_sign_up_path_for(_resource)
      new_user_session_path
    end

    # Suppression du compte — surcharge Devise pour personnaliser la redirection
    # Toutes les données sont supprimées en cascade (children → stories, user_badges)
    # conformément au RGPD (droit à l'oubli)
    def destroy
      resource.destroy
      Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
      set_flash_message! :notice, :destroyed
      yield resource if block_given?
      respond_with_navigational(resource) { redirect_to after_sign_out_path_for(resource_name), status: :see_other }
    end

    # Redirige vers la landing page après suppression du compte
    def after_sign_out_path_for(_resource_or_scope)
      root_path
    end

    protected

    # Ajoute first_name et last_name aux paramètres autorisés lors de l'inscription
    # sanitize_params est le mécanisme de Devise pour gérer les paramètres autorisés
    def configure_sign_up_params
      devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name])
    end

    # Ajoute first_name et last_name aux paramètres autorisés lors de la mise à jour
    def configure_account_update_params
      devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name])
    end
  end
end
