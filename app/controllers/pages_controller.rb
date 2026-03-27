class PagesController < ApplicationController
  # La page d'accueil est publique — pas besoin d'être connecté
  skip_before_action :authenticate_user!, only: [:home]

  def home
    # Si l'utilisateur est déjà connecté, on le redirige directement
    # vers son dashboard — pas besoin de lui montrer la landing page
    redirect_to dashboard_path if user_signed_in?
  end
end
