class StoriesController < ApplicationController
  # ============================================================
  # Controller des histoires — création, lecture, suppression
  # ============================================================

  # Charge l'histoire avant ces actions
  # save_story est inclus pour récupérer @story via set_story avant de la sauvegarder
  # audio est inclus pour vérifier que l'utilisateur est bien le propriétaire avant de générer l'audio
  before_action :set_story, only: [:show, :destroy, :choose, :status, :save_story, :audio, :continue, :replay, :explore_alternative]

  # Vérifie que l'utilisateur n'a pas dépassé sa limite mensuelle avant de créer
  # DÉSACTIVÉ pendant les tests — à réactiver avant le lancement
  # before_action :check_story_limit!, only: [:new, :create]

  # GET /stories — bibliothèque personnelle de l'utilisateur
  def index
    # N'affiche que les histoires terminées ET sauvegardées par l'utilisateur
    # Une histoire doit être explicitement sauvegardée pour apparaître ici
    @stories = current_user.stories.completed_recent.saved_stories
  end

  # GET /stories/:id — lecture de l'histoire
  def show
    # Si l'histoire est encore en cours de génération, la page affiche un spinner
    # Le statut est vérifié via polling JavaScript (StoryStatusController Stimulus)

    # Prochain choix interactif non effectué (nil si non interactive ou terminé)
    @pending_choice = @story.next_choice if @story.completed?
  end

  # GET /stories/new — formulaire de création
  def new
    # Pré-sélectionne des valeurs par défaut pour éviter les erreurs de validation
    @story    = Story.new(educational_value: "courage")
    @children = current_user.children.ordered

    # Si l'utilisateur n'a pas encore créé de profil enfant, on le redirige
    if @children.empty?
      redirect_to new_child_path, alert: "Créez d'abord le profil d'un enfant pour générer une histoire !"
    end
  end

  # POST /stories — crée l'histoire et lance la génération en arrière-plan
  def create
    # Récupère les IDs d'enfants sélectionnés (peut en avoir plusieurs)
    # Le premier ID devient l'enfant principal (child_id), les autres sont extra_child_ids
    selected_ids = Array(params[:story][:child_ids]).reject(&:blank?).map(&:to_i)

    if selected_ids.empty?
      @children = current_user.children.ordered
      @story    = Story.new(story_params.except(:child_ids))
      @story.errors.add(:child_id, "Sélectionne au moins un enfant")
      render :new, status: :unprocessable_entity
      return
    end

    # Le premier enfant sélectionné est le héros principal
    primary_child_id = selected_ids.first
    extra_ids        = selected_ids[1..]   # Les autres enfants (peut être vide)

    # On vérifie que tous les enfants appartiennent bien à l'utilisateur connecté
    child = current_user.children.find(primary_child_id)

    # Construit l'histoire avec le premier enfant comme propriétaire
    permitted = story_params.except(:child_ids)
    @story = child.stories.build(permitted)

    # Associe les enfants supplémentaires
    @story.extra_child_ids = current_user.children
                                         .where(id: extra_ids)
                                         .pluck(:id)

    if @story.save
      # Lance le job de génération en arrière-plan via Solid Queue
      # L'histoire aura le statut "pending" jusqu'à ce que le job commence
      GenerateStoryJob.perform_later(@story.id)

      # Redirige vers la page de l'histoire (qui affichera le spinner)
      redirect_to story_path(@story), notice: "La magie opère... votre histoire est en cours de création ! ✨"
    else
      @children = current_user.children.ordered
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to new_story_path, alert: "Profil enfant introuvable."
  end

  # POST /stories/:id/choose — enregistre le choix interactif de l'enfant
  def choose
    # Vérification : l'histoire doit être terminée et interactive
    unless @story.completed? && @story.interactive?
      redirect_to story_path(@story), alert: "Cette histoire n'a pas de choix interactif."
      return
    end

    # Récupère le choix en attente
    pending_choice = @story.next_choice
    unless pending_choice
      redirect_to story_path(@story), alert: "Il n'y a plus de choix à effectuer."
      return
    end

    # Valide que le choix est 'a' ou 'b'
    chosen = params[:chosen_option]
    unless %w[a b].include?(chosen)
      redirect_to story_path(@story), alert: "Choix invalide."
      return
    end

    # Enregistre le choix
    pending_choice.update!(chosen_option: chosen)

    # Marque l'histoire comme "en génération" pour la suite
    @story.update!(status: :generating)

    # Lance le job pour générer la suite de l'histoire
    GenerateStoryContinuationJob.perform_later(@story.id, pending_choice.id)

    # Répond en JSON (requête AJAX depuis story_choice_controller.js)
    # ou en HTML (fallback si JavaScript désactivé)
    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to story_path(@story), notice: "Excellent choix ! La suite de l'aventure se prépare... ✨" }
    end
  end

  # GET /stories/:id/status — retourne le statut JSON (pour polling Stimulus)
  def status
    # Récupère la continuation interactive si disponible (mode interactif terminé)
    # Utilisé par story_choice_controller.js pour mettre à jour le texte sans recharger
    continuation_html = nil
    if @story.completed? && @story.interactive?
      resolved = @story.story_choices.where.not(chosen_option: nil).order(:step_number).last
      if resolved&.context_chosen.present?
        # Convertit le markdown généré par l'IA en HTML propre côté serveur
        # Redcarpet est plus fiable que le parser JS artisanal dans story_choice_controller
        renderer = Redcarpet::Render::HTML.new(safe_links_only: true)
        markdown  = Redcarpet::Markdown.new(renderer, autolink: false, tables: false)
        continuation_html = markdown.render(resolved.context_chosen)
      end
    end

    # Construit l'URL de l'image si elle est disponible
    # Utilisé par story_image_controller.js pour afficher l'image sans recharger la page
    image_url = if @story.cover_image.attached?
      url_for(@story.cover_image)          # ActiveStorage (fal.ai / DALL-E via Cloudinary)
    elsif @story.cover_image_url.present?
      @story.cover_image_url               # URL externe (Pollinations)
    end

    # URL de l'audio si le fichier est déjà généré par GenerateAudioJob
    audio_url = @story.audio_file.attached? ? url_for(@story.audio_file) : nil

    render json: {
      status:       @story.status,
      completed:    @story.completed?,
      title:        @story.title,
      continuation: continuation_html,
      redirect_url: story_path(@story),
      image_url:    image_url,
      audio_url:    audio_url           # nil si l'audio n'est pas encore généré
    }
  end

  # POST /stories/:id/audio — sert l'audio pré-généré ou lance la génération en background
  # Appelée par story_reader_controller.js
  #
  # Si l'audio est déjà attaché (généré par GenerateAudioJob) : redirige vers l'URL du fichier
  # Sinon : lance GenerateAudioJob et retourne 202 Accepted → le JS poll /status jusqu'à ce que
  # audio_url soit disponible dans la réponse JSON
  def audio
    source = params[:source] || "story"

    if @story.audio_file.attached?
      # Audio prêt — redirige vers l'URL ActiveStorage (Cloudinary en prod)
      redirect_to url_for(@story.audio_file), allow_other_host: true
    else
      # Audio pas encore généré — lance le job en arrière-plan
      # Le JS recevra 202 et commencera à poller /status toutes les 3s
      GenerateAudioJob.perform_later(@story.id, source: source)
      head :accepted  # 202
    end
  end

  # POST /stories/:id/explore_alternative — génère la "timeline alternative" d'un choix
  # L'enfant a choisi A → on génère ce qui se serait passé avec B (et vice versa)
  # Si déjà généré, renvoie le texte en cache (évite un appel IA redondant)
  # Répond en JSON pour être consommé par story-alternative-controller.js
  def explore_alternative
    # Récupère le choix ciblé — doit appartenir à cette histoire
    story_choice = @story.story_choices.find(params[:choice_id])

    # Sécurité : le choix doit être résolu (on ne peut pas explorer l'alternative d'un choix pas encore fait)
    unless story_choice.resolved?
      render json: { success: false, error: "Ce choix n'a pas encore été effectué." }, status: :unprocessable_entity
      return
    end

    # Cache : si l'alternative a déjà été générée, on la renvoie directement sans rappeler l'IA
    if story_choice.context_alternative.present?
      render json: { success: true, html: render_markdown_to_html(story_choice.context_alternative), cached: true }
      return
    end

    # Génère la continuation alternative via le service IA (Groq — ~2-5s)
    result = StoryGeneratorService.new(@story).generate_alternative(story_choice)

    unless result[:success]
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
      return
    end

    # Sauvegarde en base pour la prochaine fois (cache)
    story_choice.update!(context_alternative: result[:content])

    # Retourne le HTML rendu côté serveur — Redcarpet parse le markdown de l'IA
    render json: { success: true, html: render_markdown_to_html(result[:content]), cached: false }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: "Choix introuvable." }, status: :not_found
  rescue StandardError => e
    # On logue le détail complet côté serveur pour le debug
    # Mais on renvoie un message générique au client — évite de fuiter des infos d'infrastructure
    Rails.logger.error("StoriesController error: #{e.class} — #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { success: false, error: "Une erreur est survenue, veuillez réessayer." }, status: :internal_server_error
  end

  # POST /stories/:id/replay — recrée une histoire identique from scratch
  # Mêmes paramètres (enfant, univers, valeur, durée, mode interactif) mais
  # regénère tout : nouveau texte, nouveaux choix, nouvelle illustration.
  # Permet de rejouer une histoire interactive pour faire d'autres choix.
  def replay
    # Délègue la construction au modèle — logique métier dans Story, pas dans le controller
    replay_story = @story.build_replay

    if replay_story.save
      # Lance la génération complète — tout sera différent (aléatoire côté IA)
      GenerateStoryJob.perform_later(replay_story.id)
      redirect_to story_path(replay_story), notice: "L'aventure recommence avec de nouveaux choix... ✨"
    else
      redirect_to story_path(@story), alert: "Impossible de recommencer : #{replay_story.errors.full_messages.to_sentence}"
    end
  end

  # POST /stories/:id/continue — crée un nouvel épisode lié à cette histoire
  # L'épisode suivant hérite de l'enfant, du thème et de la valeur éducative,
  # mais le StoryGeneratorService reçoit le contexte de l'histoire parente
  # pour assurer la continuité narrative.
  def continue
    # Vérifie que l'histoire parente est bien terminée avant de créer une suite
    unless @story.completed?
      redirect_to story_path(@story), alert: "L'histoire doit être terminée avant de créer une suite."
      return
    end

    # Empêche de créer plusieurs suites pour la même histoire
    if @story.has_sequel?
      existing_sequel = @story.sequel_stories.order(:created_at).first
      redirect_to story_path(existing_sequel), notice: "La suite de cette histoire existe déjà !"
      return
    end

    # Délègue la construction au modèle — logique métier dans Story, pas dans le controller
    sequel = @story.build_sequel

    if sequel.save
      # Lance la génération — le job appellera StoryGeneratorService
      # qui détectera parent_story_id et injectera le contexte narratif
      GenerateStoryJob.perform_later(sequel.id)
      redirect_to story_path(sequel), notice: "La suite de l'aventure se prépare... ✨"
    else
      redirect_to story_path(@story), alert: "Impossible de créer la suite : #{sequel.errors.full_messages.to_sentence}"
    end
  end

  # POST /stories/:id/save — sauvegarde l'histoire dans la bibliothèque de l'utilisateur
  # Marque saved: true pour que l'histoire apparaisse dans l'index (bibliothèque)
  def save_story
    # Met à jour le flag saved en base — update! lève une exception si ça échoue
    @story.update!(saved: true)
    # Redirige vers la page de l'histoire avec un message de confirmation
    redirect_to story_path(@story), notice: "Histoire sauvegardée dans ta bibliothèque ! 📚"
  end

  # DELETE /stories/:id — supprime l'histoire
  def destroy
    @story.destroy
    redirect_to stories_path, notice: "L'histoire a été supprimée."
  end

  private

  # Convertit du markdown en HTML via Redcarpet
  # Utilisé pour les réponses JSON (explore_alternative, status)
  def render_markdown_to_html(text)
    renderer = Redcarpet::Render::HTML.new(safe_links_only: true)
    markdown  = Redcarpet::Markdown.new(renderer, autolink: false, tables: false)
    markdown.render(text.to_s)
  end

  # Charge l'histoire depuis les histoires de l'utilisateur connecté
  # (via ses enfants) — évite qu'un utilisateur accède aux histoires d'un autre
  def set_story
    @story = current_user.stories.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to stories_path, alert: "Histoire introuvable."
  end

  # Paramètres autorisés pour la création d'une histoire
  # child_ids: [] = tableau d'IDs (sélection multiple d'enfants)
  # extra_child_ids: [] = géré manuellement dans create, pas directement via permit
  # Vérifie que l'utilisateur peut encore créer une histoire ce mois-ci
  # — Premium : illimité (can_create_story? retourne true)
  # — Gratuit  : bloqué à 3 histoires/mois
  # Redirige vers la page d'abonnement avec un message explicatif si limite atteinte
  def check_story_limit!
    unless current_user.can_create_story?
      redirect_to subscription_path,
        alert: "Tu as atteint ta limite de 3 histoires ce mois-ci. Passe en Premium pour des histoires illimitées !"
    end
  end

  def story_params
    params.require(:story).permit(
      :child_id,
      :world_theme,
      :educational_value,
      :duration_minutes,
      :custom_theme,
      :interactive,
      :image_style,     # Style visuel de l'illustration (ghibli, comics, pixar, watercolor)
      child_ids: []     # Tableau d'IDs pour la sélection multiple d'enfants
    )
  end
end
