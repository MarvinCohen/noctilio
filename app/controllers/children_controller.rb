class ChildrenController < ApplicationController
  # ============================================================
  # Controller des profils enfants — CRUD complet
  # ============================================================
  # Chaque action vérifie que l'enfant appartient bien à l'utilisateur connecté
  # (grâce à set_child qui cherche dans current_user.children)

  # Charge l'enfant depuis la base AVANT ces actions
  before_action :set_child, only: %i[show edit update destroy]

  # GET /children — liste tous les enfants de l'utilisateur
  def index
    # Récupère les enfants du plus récent au plus ancien
    @children = current_user.children.ordered

    # Nombre d'histoires terminées PAR enfant, en UNE seule requête groupée.
    # Avant : la vue appelait child.stories.completed.count dans la boucle
    # (1 requête SQL par enfant = N+1). Ici on récupère un hash { child_id => count }
    # d'un coup, et la vue lit @completed_counts[child.id] (0 par défaut).
    @completed_counts = current_user.stories.completed.group(:child_id).count
  end

  # GET /children/:id — affiche le profil d'un enfant et ses histoires
  def show
    # Histoires terminées de cet enfant, les plus récentes en premier
    @stories = @child.stories.completed_recent.limit(10)
  end

  # GET /children/new — formulaire de création d'un nouveau profil
  def new
    # Crée un objet Child vide pour le formulaire (pas encore en base)
    @child = Child.new
  end

  # POST /children — enregistre le nouveau profil en base
  def create
    @child = current_user.children.build(child_params)

    if @child.save
      redirect_to children_path, notice: t("flash.children.created", name: @child.name)
    else
      # En cas d'erreur de validation, réaffiche le formulaire avec les erreurs
      render :new, status: :unprocessable_entity
    end
  end

  # GET /children/:id/edit — formulaire de modification
  def edit
    # @child déjà chargé par set_child
  end

  # PATCH /children/:id — met à jour le profil en base
  def update
    if @child.update(child_params)
      redirect_to child_path(@child), notice: t("flash.children.updated", name: @child.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /children/:id — supprime le profil et toutes ses histoires
  def destroy
    name = @child.name
    @child.destroy
    redirect_to children_path, notice: t("flash.children.deleted", name: name)
  end

  private

  # Charge l'enfant depuis les enfants DE l'utilisateur connecté
  # Si l'enfant n'existe pas ou appartient à quelqu'un d'autre → 404
  def set_child
    @child = current_user.children.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to children_path, alert: t("flash.children.not_found")
  end

  # Liste des paramètres autorisés pour le formulaire
  # On utilise permit pour éviter la mass assignment (sécurité)
  def child_params
    params.require(:child).permit(
      :name,
      :age,
      :gender,
      :hair_color,
      :eye_color,
      :skin_tone,
      :child_description,
      :parental_consent,        # Attribut virtuel RGPD — case de consentement (validé on: :create)
      personality_traits: [],   # Tableau de chaînes (checkboxes)
      hobbies: []               # Tableau de chaînes (checkboxes)
    )
  end
end
