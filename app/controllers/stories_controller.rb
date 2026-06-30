class StoriesController < ApplicationController
  # ============================================================
  # Controller des histoires — création, lecture, suppression
  # ============================================================

  # Charge l'histoire avant ces actions
  # save_story est inclus pour récupérer @story via set_story avant de la sauvegarder
  # audio est inclus pour vérifier que l'utilisateur est bien le propriétaire avant de générer l'audio
  before_action :set_story,
                only: %i[show destroy choose status save_story audio continue replay explore_alternative retry]

  # Vérifie que l'utilisateur n'a pas dépassé sa limite hebdomadaire avant de créer
  # — Gratuit : 3 histoires/semaine (réinitialisé chaque lundi)
  # — Premium : illimité (can_create_story? renvoie toujours true)
  # NB : la 1re histoire d'un compte passe toujours (c'est la #1 de la semaine),
  # donc l'offre découverte n'est jamais bloquée par ce filtre.
  # On couvre aussi replay et continue : ces deux actions créent de NOUVELLES
  # histoires (build_replay / build_sequel) qui comptent dans le quota. Sans ce
  # filtre, un compte gratuit épuisé pourrait relancer des générations à volonté
  # via les boutons « Rejouer » / « Suite ». (retry ne crée pas de nouvelle
  # histoire : il relance une histoire échouée déjà comptée → hors quota.)
  before_action :check_story_limit!, only: [:new, :create, :replay, :continue]

  # GET /stories — bibliothèque personnelle de l'utilisateur
  # Supporte ?tab=saved (défaut) et ?tab=all (toutes les histoires terminées)
  def index
    # Onglet actif — "saved" par défaut pour la bibliothèque curative
    # "all" affiche toutes les histoires terminées (même non sauvegardées)
    @tab = params[:tab] == "all" ? "all" : "saved"

    # Base commune — histoires terminées triées du plus récent au plus ancien
    # includes précharge les associations utilisées dans la vue (évite les N+1) :
    #   :child               → story.child.name dans les méta de chaque carte
    #   :parent_story        → story.sequel? vérifie parent_story_id
    #   :sequel_stories      → story.has_sequel? vérifie l'existence d'une suite
    #   cover_image_attachment: :blob → story.cover_image.attached? sans requête extra
    base = current_user.stories
                       .completed_recent
                       .includes(:child, :parent_story, :sequel_stories,
                                 cover_image_attachment: :blob)

    # Filtre selon l'onglet actif
    scoped = @tab == "all" ? base : base.saved_stories

    # Mémorise les valeurs de filtre saisies pour les ré-afficher dans le formulaire
    # (champ recherche pré-rempli, options sélectionnées) après soumission.
    @q            = params[:q]
    @world_filter = params[:world]
    @child_filter = params[:child_id]

    # Applique recherche + filtres en chaînant les scopes du modèle.
    # Chaque scope est neutre si son paramètre est vide (voir Story).
    @stories = scoped.search_title(@q)
                     .for_world(@world_filter)
                     .for_child(@child_filter)

    # Enfants de l'utilisateur — alimente la liste déroulante du filtre "héros".
    @children = current_user.children.ordered

    # Compteurs pour les badges des onglets — deux requêtes COUNT légères.
    # NB : ils reflètent les TOTAUX (hors filtres) : ils servent à indiquer la
    # taille de chaque onglet, pas le nombre de résultats filtrés affichés.
    @saved_count = current_user.stories.completed.saved_stories.count
    @all_count   = current_user.stories.completed.count

    # Histoires échouées — affichées séparément avec un bouton "Réessayer"
    # Triées du plus récent au plus ancien pour voir les dernières tentatives en premier
    @failed_stories = current_user.stories
                                  .failed
                                  .includes(:child)
                                  .order(created_at: :desc)
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
    return unless @children.empty?

    redirect_to new_child_path, alert: t("flash.stories.need_child")
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
    extra_ids        = selected_ids[1..] # Les autres enfants (peut être vide)

    # On vérifie que tous les enfants appartiennent bien à l'utilisateur connecté
    child = current_user.children.find(primary_child_id)

    # Construit l'histoire avec le premier enfant comme propriétaire
    permitted = story_params.except(:child_ids)
    @story = child.stories.build(permitted)

    # Fige la langue de l'histoire = langue d'interface courante (résolue par
    # ApplicationController#switch_locale : params > session > compte > navigateur).
    # CRUCIAL : le texte est généré dans un job en arrière-plan où I18n.locale
    # retombe à :fr. En stockant la langue ici, le service IA et les jobs de
    # suite/relecture la retrouveront de façon fiable.
    @story.locale = I18n.locale.to_s

    # Associe les enfants supplémentaires
    @story.extra_child_ids = current_user.children
                                         .where(id: extra_ids)
                                         .pluck(:id)

    if @story.save
      # Lance le job de génération en arrière-plan via Solid Queue
      # L'histoire aura le statut "pending" jusqu'à ce que le job commence
      GenerateStoryJob.perform_later(@story.id)

      # Redirige vers la page de l'histoire (qui affichera le spinner)
      redirect_to story_path(@story), notice: t("flash.stories.creating")
    else
      @children = current_user.children.ordered
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to new_story_path, alert: t("flash.stories.child_not_found")
  end

  # POST /stories/:id/choose — enregistre le choix interactif de l'enfant
  def choose
    # Vérification : l'histoire doit être terminée et interactive
    unless @story.completed? && @story.interactive?
      redirect_to story_path(@story), alert: t("flash.stories.no_interactive")
      return
    end

    # Récupère le choix en attente
    pending_choice = @story.next_choice
    unless pending_choice
      redirect_to story_path(@story), alert: t("flash.stories.no_more_choices")
      return
    end

    # Valide que le choix est 'a' ou 'b'
    chosen = params[:chosen_option]
    unless %w[a b].include?(chosen)
      redirect_to story_path(@story), alert: t("flash.stories.invalid_choice")
      return
    end

    # with_lock pose un verrou en base (SELECT FOR UPDATE) sur ce choix
    # Garantit qu'un seul thread/processus peut modifier ce choix à la fois
    # Évite la race condition si l'utilisateur double-clique ou envoie 2 requêtes en parallèle
    already_chosen = false
    pending_choice.with_lock do
      # Recharge le choix depuis la base DANS le verrou
      # Si chosen_option est déjà rempli, quelqu'un nous a devancé — on sort
      if pending_choice.chosen_option.present?
        already_chosen = true
        next
      end

      # Enregistre le choix de façon atomique (dans le verrou)
      pending_choice.update!(chosen_option: chosen)

      # Marque l'histoire comme "en génération" pour la suite
      @story.update!(status: :generating)

      # Lance le job pour générer la suite de l'histoire
      GenerateStoryContinuationJob.perform_later(@story.id, pending_choice.id)
    end

    # Si le choix était déjà fait (double requête), on redirige sans relancer le job
    if already_chosen
      respond_to do |format|
        format.json { render json: { success: true, already_chosen: true } }
        format.html { redirect_to story_path(@story) }
      end
      return
    end

    # Répond en JSON (requête AJAX depuis story_choice_controller.js)
    # ou en HTML (fallback si JavaScript désactivé)
    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to story_path(@story), notice: t("flash.stories.choice_saved") }
    end
  end

  # GET /stories/:id/status — retourne le statut JSON (pour polling Stimulus)
  def status
    # Récupère la continuation interactive si disponible (mode interactif terminé)
    # Utilisé par story_choice_controller.js pour mettre à jour le texte sans recharger
    continuation_html        = nil  # HTML de la suite à afficher
    last_choice_id           = nil  # ID du dernier choix résolu (pour l'audio de la suite)
    continuation_audio_url   = nil  # URL de l'audio de la suite (nil si pas encore prêt)
    continuation_illustration_url = nil  # URL de l'illustration de la suite (nil si absente)
    next_choice_html         = nil  # HTML du PROCHAIN choix en attente (injection sans refresh)

    if @story.completed? && @story.interactive?
      # Dernier choix résolu = celui dont on vient de générer la suite
      resolved = @story.story_choices.where.not(chosen_option: nil).order(:step_number).last
      if resolved
        last_choice_id = resolved.id

        if resolved.context_chosen.present?
          # On utilise le MÊME helper que l'histoire initiale (render_story_markdown)
          # pour que la suite ait exactement la même mise en page (<p class="story-paragraph">).
          # Avant : Redcarpet produisait des <p> nus → style différent de l'intro.
          continuation_html = helpers.render_story_markdown(resolved.context_chosen)
        end

        # Illustration de la suite : générée AVANT le passage en `completed`, donc
        # déjà attachée quand le front détecte la fin. Le JS l'injecte au-dessus du
        # texte de la suite (avec fallback si l'URL casse).
        continuation_illustration_url = url_for(resolved.illustration) if resolved.illustration.attached?

        # Audio de la suite : prêt seulement si GenerateAudioJob a terminé (Partie B)
        # Le JS du lecteur l'enchaîne après le passage en cours s'il est disponible.
        continuation_audio_url = url_for(resolved.audio_file) if resolved.audio_file.attached?
      end

      # PROCHAIN choix en attente : si la suite proposait un NOUVEAU dilemme, un
      # StoryChoice non résolu existe. On rend son formulaire (même partial que la
      # vue) pour que le JS l'injecte → boutons cliquables sans rechargement.
      pending = @story.next_choice
      if pending
        next_choice_html = render_to_string(
          partial: "interactive_choice",
          locals: { story: @story, choice: pending },
          formats: [:html]
        )
      end
    end

    # Construit l'URL de l'image si elle est disponible
    # Utilisé par story_image_controller.js pour afficher l'image sans recharger la page
    image_url = if @story.cover_image.attached?
                  url_for(@story.cover_image) # ActiveStorage (fal.ai / DALL-E via Cloudinary)
                elsif @story.cover_image_url.present?
                  @story.cover_image_url # URL externe (Pollinations)
                end

    # URL de l'audio si le fichier est déjà généré par GenerateAudioJob
    audio_url = @story.audio_file.attached? ? url_for(@story.audio_file) : nil

    render json: {
      status: @story.status,
      completed: @story.completed?,
      title: @story.title,
      continuation: continuation_html,
      redirect_url: story_path(@story),
      image_url: image_url,
      audio_url: audio_url, # nil si l'audio principal n'est pas encore généré
      choice_id: last_choice_id, # dernier choix résolu (pour cibler l'audio de la suite)
      continuation_audio_url: continuation_audio_url, # nil si l'audio de la suite n'est pas prêt
      continuation_illustration_url: continuation_illustration_url, # nil si la suite n'a pas d'image
      next_choice_html: next_choice_html # HTML du prochain choix à injecter (nil si l'histoire est finie)
    }
  end

  # POST /stories/:id/audio — sert l'audio pré-généré ou lance la génération en background
  # Appelée par story_reader_controller.js
  #
  # Si l'audio est déjà attaché (généré par GenerateAudioJob) : redirige vers l'URL du fichier
  # Sinon : lance GenerateAudioJob et retourne 202 Accepted → le JS poll /status jusqu'à ce que
  # audio_url soit disponible dans la réponse JSON
  def audio
    # SÉCURITÉ BUSINESS — la génération audio (OpenAI TTS) coûte de l'argent
    # à chaque appel. Réservée aux abonnés Premium, vérifiée CÔTÉ SERVEUR
    # (cacher le bouton dans la vue ne suffirait pas : l'URL resterait appelable).
    # Exception : la 1re histoire du compte (offre découverte) a aussi accès à
    # l'audio — audio_for?(@story) couvre Premium ET 1re histoire offerte.
    # NB : l'audio est réservé au Premium (un compte Essentiel ne l'a PAS).
    # 403 Forbidden — le JS du lecteur audio l'interprète comme un refus.
    unless current_user.audio_for?(@story)
      head :forbidden and return
    end

    source = params[:source] || "story"

    # CAS 1 — audio d'une SUITE interactive (Partie B)
    # Le JS demande l'audio de la continuation liée à un choix précis.
    # On sert choice.audio_file (et NON story.audio_file) pour ne pas écraser
    # l'audio principal de l'histoire.
    if source == "continuation" && params[:choice_id].present?
      choice = @story.story_choices.find_by(id: params[:choice_id])
      head :not_found and return if choice.nil?

      if choice.audio_file.attached?
        # Audio de la suite prêt — redirige vers son URL
        redirect_to url_for(choice.audio_file), allow_other_host: true
      else
        # Pas encore prêt — lance le job ciblé et répond 202 (le JS pollera /status)
        GenerateAudioJob.perform_later(@story.id, source: "continuation", choice_id: choice.id)
        head :accepted # 202
      end
      return
    end

    # CAS 2 — audio principal de l'histoire (comportement par défaut)
    if @story.audio_file.attached?
      # Audio prêt — redirige vers l'URL ActiveStorage (Cloudinary en prod)
      redirect_to url_for(@story.audio_file), allow_other_host: true
    else
      # Audio pas encore généré — lance le job en arrière-plan
      # Le JS recevra 202 et commencera à poller /status toutes les 3s
      GenerateAudioJob.perform_later(@story.id, source: source)
      head :accepted # 202
    end
  end

  # POST /stories/:id/explore_alternative — génère la "timeline alternative" d'un choix
  # L'enfant a choisi A → on génère ce qui se serait passé avec B (et vice versa)
  # Si déjà généré, renvoie le texte en cache (évite un appel IA redondant)
  # Répond en JSON pour être consommé par story-alternative-controller.js
  def explore_alternative
    # SÉCURITÉ BUSINESS — comme l'audio, l'exploration alternative déclenche un
    # appel IA payant (Groq) à chaque première génération. L'exploration alternative
    # fait partie du mode interactif, lui-même réservé au Premium : on la verrouille
    # donc sur audio_for? (Premium OU 1re histoire offerte), vérifié CÔTÉ SERVEUR :
    # masquer le bouton dans la vue ne suffirait pas, l'URL resterait appelable.
    # 403 Forbidden — interprété comme un refus par le JS.
    unless current_user.audio_for?(@story)
      render json: { success: false, error: "Fonctionnalité réservée au Premium." }, status: :forbidden
      return
    end

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
    render json: { success: false, error: "Une erreur est survenue, veuillez réessayer." },
           status: :internal_server_error
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
      redirect_to story_path(replay_story), notice: t("flash.stories.replay_started")
    else
      redirect_to story_path(@story),
                  alert: t("flash.stories.replay_failed", errors: replay_story.errors.full_messages.to_sentence)
    end
  end

  # POST /stories/:id/continue — crée un nouvel épisode lié à cette histoire
  # L'épisode suivant hérite de l'enfant, du thème et de la valeur éducative,
  # mais le StoryGeneratorService reçoit le contexte de l'histoire parente
  # pour assurer la continuité narrative.
  def continue
    # Vérifie que l'histoire parente est bien terminée avant de créer une suite
    unless @story.completed?
      redirect_to story_path(@story), alert: t("flash.stories.sequel_need_complete")
      return
    end

    # Empêche de créer plusieurs suites pour la même histoire
    if @story.has_sequel?
      existing_sequel = @story.sequel_stories.order(:created_at).first
      redirect_to story_path(existing_sequel), notice: t("flash.stories.sequel_exists")
      return
    end

    # Délègue la construction au modèle — logique métier dans Story, pas dans le controller
    sequel = @story.build_sequel

    if sequel.save
      # Lance la génération — le job appellera StoryGeneratorService
      # qui détectera parent_story_id et injectera le contexte narratif
      GenerateStoryJob.perform_later(sequel.id)
      redirect_to story_path(sequel), notice: t("flash.stories.sequel_started")
    else
      redirect_to story_path(@story), alert: t("flash.stories.sequel_failed", errors: sequel.errors.full_messages.to_sentence)
    end
  end

  # POST /stories/:id/save — sauvegarde l'histoire dans la bibliothèque de l'utilisateur
  # Marque saved: true pour que l'histoire apparaisse dans l'index (bibliothèque)
  def save_story
    # Met à jour le flag saved en base — update! lève une exception si ça échoue
    @story.update!(saved: true)
    # Redirige vers la page de l'histoire avec un message de confirmation
    redirect_to story_path(@story), notice: t("flash.stories.saved")
  end

  # POST /stories/:id/retry — relance la génération d'une histoire échouée
  # Réinitialise le contenu et remet l'histoire en pending avant de relancer le job
  def retry
    # Vérifie que l'histoire est bien en échec — on ne relance pas une histoire déjà complétée
    return redirect_to stories_path, alert: t("flash.stories.not_failed") unless @story.failed?

    # Nettoie l'état précédent avant de relancer pour partir d'une ardoise propre
    @story.cover_image.purge if @story.cover_image.attached?
    @story.update!(
      status: :pending,
      content: nil,
      title: nil,
      image_prompt: nil,
      cover_image_url: nil
    )

    # Relance le job de génération en arrière-plan
    GenerateStoryJob.perform_later(@story.id)

    # Redirige vers la page de l'histoire — le spinner de génération s'affiche
    redirect_to story_path(@story), notice: t("flash.stories.retry_started")
  end

  # DELETE /stories/:id — supprime l'histoire
  def destroy
    @story.destroy
    redirect_to stories_path, notice: t("flash.stories.deleted")
  end

  private

  # Convertit du markdown en HTML via Redcarpet
  # Utilisé pour les réponses JSON (explore_alternative, status)
  def render_markdown_to_html(text)
    renderer = Redcarpet::Render::HTML.new(safe_links_only: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: false, tables: false)
    markdown.render(text.to_s)
  end

  # Charge l'histoire depuis les histoires de l'utilisateur connecté
  # (via ses enfants) — évite qu'un utilisateur accède aux histoires d'un autre
  def set_story
    # includes précharge toutes les associations utilisées dans show/choose/status
    # en une seule requête JOIN — évite les N+1 :
    #   :story_choices  → affichage des choix interactifs
    #   :parent_story   → navigation saga (épisode précédent)
    #   :sequel_stories → navigation saga (épisode suivant)
    #   child: :user    → données de l'enfant + son parent pour les badges
    @story = current_user.stories
                         .includes(:story_choices, :parent_story, :sequel_stories, child: :user)
                         .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to stories_path, alert: t("flash.stories.not_found")
  end

  # Paramètres autorisés pour la création d'une histoire
  # child_ids: [] = tableau d'IDs (sélection multiple d'enfants)
  # extra_child_ids: [] = géré manuellement dans create, pas directement via permit
  # Vérifie que l'utilisateur peut encore créer une histoire cette semaine
  # — Premium : illimité (can_create_story? retourne true)
  # — Gratuit  : bloqué à 3 histoires/semaine
  # Redirige vers la page d'abonnement avec un message explicatif si limite atteinte
  def check_story_limit!
    return if current_user.can_create_story?

    redirect_to subscription_path,
                alert: t("flash.stories.limit_reached")
  end

  def story_params
    params.require(:story).permit(
      :child_id,
      :world_theme,
      :educational_value,
      :duration_minutes,
      :custom_theme,
      :interactive,
      :image_style,     # Style visuel de l'illustration (ghibli, comics, pixar, watercolor, cinematic)
      child_ids: []     # Tableau d'IDs pour la sélection multiple d'enfants
    )
  end
end
