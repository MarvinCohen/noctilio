class WaitlistEntry < ApplicationRecord
  # ============================================================
  # Modèle pour la liste d'attente pré-lancement
  # Stocke les emails des personnes intéressées par Noctilio
  # ============================================================

  # Validation de présence — l'email est obligatoire
  validates :email, presence: true

  # Validation du format email — vérifie que c'est un vrai email
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "n'est pas valide" }

  # Validation d'unicité — un email ne peut s'inscrire qu'une seule fois
  # case_sensitive: false → "Test@email.fr" = "test@email.fr"
  validates :email, uniqueness: { case_sensitive: false, message: "est déjà inscrit" }

  # Normalisation avant sauvegarde — met l'email en minuscules
  before_save :downcase_email

  private

  # Met l'email en minuscules pour éviter les doublons de casse
  def downcase_email
    self.email = email.downcase.strip
  end
end
