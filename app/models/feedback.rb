# ============================================================
# Feedback — un retour laissé par un visiteur (bug, suggestion, autre)
# ============================================================
# Stocke les retours envoyés via la page publique /avis.
# Un retour peut être anonyme (visiteur non connecté) ou rattaché à un user.
class Feedback < ApplicationRecord
  # ============================================================
  # Catégories possibles d'un retour
  # ============================================================
  # On expose une constante plutôt qu'un enum : la liste sert à remplir le
  # menu déroulant du formulaire ET à valider la valeur reçue côté serveur.
  CATEGORIES = %w[bug suggestion autre].freeze

  # ============================================================
  # Associations
  # ============================================================
  # belongs_to :user mais optional: true car un visiteur anonyme peut écrire.
  # Sans optional, Rails 5+ exigerait un user_id présent et rejetterait l'anonyme.
  belongs_to :user, optional: true

  # ============================================================
  # Validations
  # ============================================================
  # Le message est le coeur du retour : obligatoire et borné en longueur
  # (10 caractères mini pour éviter les "test" vides, 2000 maxi pour éviter les abus)
  validates :message, presence: true, length: { minimum: 10, maximum: 2000 }

  # La catégorie doit faire partie de la liste autorisée (protège d'une valeur forgée)
  validates :category, inclusion: { in: CATEGORIES }

  # L'email est optionnel, mais s'il est fourni il doit ressembler à un email
  # allow_blank : ne valide pas si le champ est vide (retour anonyme accepté)
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
end
