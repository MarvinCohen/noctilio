class User < ApplicationRecord
  # ============================================================
  # Devise — gère l'authentification (connexion, mot de passe...)
  # ============================================================
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         # :trackable   → enregistre l'activité de connexion (nb de connexions, dates, IP)
         # :lockable    → verrouille le compte après 10 échecs (seuil défini dans devise.rb)
         # :confirmable → l'email doit être confirmé via un lien (7 jours de grâce, devise.rb)
         :trackable, :lockable, :confirmable,
         # omniauthable permet à Devise de gérer les connexions via fournisseurs externes
         # providers: liste des fournisseurs autorisés (on peut en ajouter d'autres plus tard)
         :omniauthable, omniauth_providers: [:google_oauth2]

  # ============================================================
  # Pay — gère l'abonnement Stripe
  # pay_customer crée automatiquement un client Stripe
  # et ajoute les méthodes : subscribed?, payment_methods, charges...
  # ============================================================
  pay_customer

  # ============================================================
  # Associations
  # ============================================================

  # Un utilisateur possède plusieurs enfants
  has_many :children, dependent: :destroy

  # Un utilisateur accède à toutes ses histoires via ses enfants
  has_many :stories, through: :children

  # Badges gagnés par l'utilisateur
  has_many :user_badges, dependent: :destroy
  has_many :badges, through: :user_badges

  # Abonnements aux notifications push (un par appareil/navigateur).
  # dependent: :destroy → on nettoie les abonnements si le compte est supprimé.
  has_many :push_subscriptions, dependent: :destroy

  # ============================================================
  # Callbacks
  # ============================================================

  # Envoie l'email de bienvenue après la création du compte
  # after_commit garantit que l'envoi se fait une fois l'utilisateur bien sauvegardé en base
  after_commit :send_welcome_email, on: :create

  # ============================================================
  # Validations
  # ============================================================
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name,  presence: true, length: { maximum: 50 }

  # ============================================================
  # Méthodes métier
  # ============================================================

  # ============================================================
  # Niveaux d'abonnement — 3 paliers (Gratuit / Essentiel / Premium)
  # ============================================================
  # Depuis l'ajout du palier intermédiaire "Essentiel" (4,99€/mois), on ne
  # raisonne plus en binaire premium/gratuit mais en NIVEAU. Toutes les autres
  # méthodes de verrouillage (illustrations, audio, quota) s'appuient dessus.

  # Retourne le niveau d'abonnement de l'utilisateur sous forme de symbole :
  #   :free      → compte gratuit (3 histoires/semaine, texte seul)
  #   :essentiel → 4,99€/mois (histoires illimitées + illustrations IA)
  #   :premium   → 9,99€/mois (tout : + audio + interactif + dashboard avancé)
  # Règles :
  #   - admin → toujours :premium (accès complet pour tester l'app).
  #   - aucun abonnement Pay actif → :free.
  #   - abonnement actif : on compare le price ID Stripe du plan (processor_plan)
  #     à STRIPE_ESSENTIEL_PRICE_ID. Tout autre plan payant (Premium OU plan
  #     inconnu) → :premium par sécurité : on ne downgrade JAMAIS un payeur.
  def subscription_tier
    # Les admins ont accès à tout — on les traite comme des premium.
    return :premium if admin?

    # Pas de client de paiement ou pas d'abonnement actif → compte gratuit.
    return :free unless payment_processor.present? && payment_processor.subscribed?

    # Abonnement actif : on lit le price ID Stripe du plan souscrit.
    # processor_plan est l'identifiant "price_..." renvoyé par Pay/Stripe.
    if payment_processor.subscription&.processor_plan == ENV["STRIPE_ESSENTIEL_PRICE_ID"]
      :essentiel
    else
      # Plan Premium OU plan inconnu → premium (ne jamais downgrader un payeur).
      :premium
    end
  end

  # Retourne true si l'utilisateur a le niveau Premium (haut de gamme).
  # Sémantique externe inchangée : audio + mode interactif + dashboard avancé.
  # (admin renvoie :premium via subscription_tier, donc admin? est couvert.)
  def premium?
    subscription_tier == :premium
  end

  # Retourne true si l'utilisateur a le niveau Essentiel (palier intermédiaire).
  def essentiel?
    subscription_tier == :essentiel
  end

  # Retourne true si l'utilisateur n'a plus de quota d'histoires (Essentiel OU
  # Premium) : tout palier payant débloque les histoires illimitées.
  def unlimited_stories?
    subscription_tier != :free
  end

  # Retourne true si l'utilisateur est administrateur de l'application
  # Pour passer un compte admin : User.find_by(email: "...").update!(admin: true)
  # OU via Rails console Heroku : heroku run rails console
  def admin?
    admin == true
  end

  # Compte les histoires créées cette semaine (tous enfants confondus)
  # beginning_of_week = lundi 00:00 → le quota gratuit se réinitialise chaque lundi
  def stories_this_week
    stories.where(created_at: Time.current.beginning_of_week..)
           .count
  end

  # Retourne true si l'utilisateur peut encore créer une histoire
  # — Essentiel et Premium : illimité (unlimited_stories?)
  # — Gratuit : limité à 3 histoires par semaine
  def can_create_story?
    return true if unlimited_stories?

    stories_this_week < 3
  end

  # ============================================================
  # Offre découverte — les premières histoires du compte sont enrichies
  # ============================================================
  # But : montrer la valeur du produit dès les premières histoires pour donner
  # envie de s'abonner. Deux paliers d'offre distincts :
  #   - AUDIO + mode interactif (fonctions Premium, coûteuses) : uniquement la
  #     TOUTE PREMIÈRE histoire (welcome_story?).
  #   - ILLUSTRATIONS (peu coûteuses, ~0,03€) : les 3 PREMIÈRES histoires, pour
  #     adoucir le retour au "texte seul" et prolonger l'effet découverte
  #     (welcome_illustration? ci-dessous).
  # Dès la 4e histoire, un compte gratuit repasse entièrement en "texte seul".

  # Nombre d'histoires offrant l'illustration gratuite au lancement.
  # Constante centrale : on évite de disperser le "3" dans plusieurs méthodes.
  WELCOME_ILLUSTRATION_COUNT = 3

  # Retourne true si `story` est la TOUTE PREMIÈRE histoire du compte.
  # On compare son id à la plus petite clé primaire des histoires de l'utilisateur :
  # la plus petite id = la 1re histoire créée. Pas besoin de colonne dédiée.
  # NB : si l'utilisateur supprime sa 1re histoire, la suivante redevient "la 1re"
  # (offre re-débloquée) — limite assumée au lancement, risque faible.
  def welcome_story?(story)
    # story.id peut être nil si l'histoire n'est pas encore sauvegardée → false
    # On compare à l'id de la 1re histoire, mémoïsé pour ne pas relancer la requête
    # `stories.minimum(:id)` à chaque appel (illustrations_for?/audio_for? l'appellent souvent).
    story.id.present? && story.id == first_story_id
  end

  # Id de la TOUTE PREMIÈRE histoire du compte (plus petite clé primaire), ou nil
  # si le compte n'a encore aucune histoire. Mémoïsé via `defined?` plutôt que `||=`
  # car la valeur peut légitimement être nil : avec `||=` un compte sans histoire
  # relancerait la requête à chaque appel. `defined?` met en cache même un nil.
  def first_story_id
    return @first_story_id if defined?(@first_story_id)

    @first_story_id = stories.minimum(:id)
  end

  # Ids des WELCOME_ILLUSTRATION_COUNT (3) PREMIÈRES histoires du compte, c.-à-d.
  # les 3 plus petites clés primaires (order(:id)). Retourne un tableau, éventuellement
  # vide si le compte n'a aucune histoire. Mémoïsé via `defined?` (et non `||=`)
  # pour mettre aussi en cache un tableau vide : sans ça, un compte sans histoire
  # relancerait la requête à chaque appel de welcome_illustration?/illustrations_for?.
  def first_story_ids
    return @first_story_ids if defined?(@first_story_ids)

    @first_story_ids = stories.order(:id).limit(WELCOME_ILLUSTRATION_COUNT).pluck(:id)
  end

  # Retourne true si `story` fait partie des 3 premières histoires du compte,
  # donc éligible à l'illustration offerte même sur un compte gratuit.
  # story.id peut être nil (histoire non sauvegardée) → include?(nil) est false.
  def welcome_illustration?(story)
    story.id.present? && first_story_ids.include?(story.id)
  end

  # Décide si une histoire donnée a droit à l'ILLUSTRATION IA.
  # Débloquée dès le palier Essentiel (unlimited_stories?), et pour les 3 premières
  # histoires offertes (offre découverte) même sur un compte gratuit.
  # Utilisée par le job de génération d'image et la vue de lecture.
  def illustrations_for?(story)
    unlimited_stories? || welcome_illustration?(story)
  end

  # Décide si une histoire donnée a droit à l'AUDIO (lecture à voix haute).
  # Réservé au Premium (l'audio est une fonctionnalité haut de gamme), et
  # toujours pour la 1re histoire offerte. Un compte Essentiel n'a PAS l'audio.
  # Utilisée par l'endpoint audio (controller) et le lecteur dans la vue.
  def audio_for?(story)
    premium? || welcome_story?(story)
  end

  # Retourne true tant que l'utilisateur n'a encore créé AUCUNE histoire :
  # sa prochaine histoire sera donc sa 1re et bénéficiera de l'offre découverte.
  # Utilisée par le formulaire de création pour activer le toggle "mode interactif"
  # et afficher la bannière d'offre AVANT que l'histoire n'existe en base.
  def first_story_pending?
    stories.none?
  end

  # Retourne le nom complet de l'utilisateur
  def full_name
    "#{first_name} #{last_name}"
  end

  # Calcule les points d'expérience (XP) de l'utilisateur
  # Règle : 100 XP par histoire terminée + 50 XP par badge obtenu
  # Mémoïsation (@xp_points ||=) : le résultat fait 2 requêtes SQL (count des
  # histoires terminées + count des badges). Comme level, xp_in_current_level,
  # xp_to_next_level et level_progress rappellent tous xp_points, on ne le calcule
  # qu'UNE fois par instance puis on réutilise la valeur en cache.
  def xp_points
    @xp_points ||= (stories.completed.count * 100) + (user_badges.count * 50)
  end

  # Niveau de l'utilisateur, dérivé de l'XP.
  # Règle : 1 niveau tous les 500 XP, en commençant au niveau 1.
  # Centralisé ici (Fat Model) pour être réutilisé par la sidebar ET la salle
  # des trophées, qui calculaient le niveau chacune de leur côté avant.
  def level
    (xp_points / XP_PER_LEVEL) + 1
  end

  # ============================================================
  # Notifications de badges (célébration en temps réel)
  # ============================================================
  # Badges gagnés mais pas encore "fêtés" à l'écran (notif + confettis).
  # includes(:badge) : précharge le badge pour lire icône/nom sans N+1 dans la vue.
  def pending_badge_notifications
    user_badges.unnotified.includes(:badge)
  end

  # Marque tous les badges en attente comme notifiés (après affichage côté front).
  # update_all : une seule requête UPDATE, sans charger les objets ni lancer de
  # callbacks (on ne fait que basculer un drapeau, aucune logique métier requise).
  def mark_badges_notified!
    user_badges.unnotified.update_all(notified: true)
  end

  # ============================================================
  # Progression — données pour la carte "rituel du soir" du dashboard
  # ============================================================
  # Palier d'XP par niveau — constante centrale pour rester cohérent avec level.
  # On l'utilise aussi dans level ci-dessus pour ne jamais dupliquer le 500.
  XP_PER_LEVEL = 500

  # XP accumulés DANS le niveau courant (de 0 à 499).
  # Exemple : 1 200 XP total → niveau 3 → 200 XP dans le niveau courant.
  def xp_in_current_level
    xp_points % XP_PER_LEVEL
  end

  # XP qu'il reste à gagner avant d'atteindre le niveau suivant.
  # Sert à afficher "encore 300 XP avant le niveau 4" sur le dashboard.
  def xp_to_next_level
    XP_PER_LEVEL - xp_in_current_level
  end

  # Avancement vers le niveau suivant, en pourcentage (0 à 100).
  # Pilote la largeur de la barre de progression XP du dashboard.
  def level_progress
    (xp_in_current_level * 100 / XP_PER_LEVEL)
  end

  # ============================================================
  # Constellation du soir — habitude douce, jamais punitive
  # ============================================================
  # Renvoie un tableau de `days` booléens, du plus ancien au plus récent :
  # true si AU MOINS une histoire TERMINÉE a été créée ce jour-là.
  # But : afficher une constellation (étoiles allumées) qui valorise les soirs
  # de lecture SANS culpabiliser les soirs manqués (pas de "streak" cassé).
  def recent_story_nights(days = 7)
    # Date du plus ancien jour de la fenêtre (ex : il y a 6 jours pour 7 jours)
    start_date = (days - 1).days.ago.to_date

    # On récupère en une seule requête les dates de création des histoires
    # TERMINÉES de la fenêtre, converties en jour (sans l'heure), dédoublonnées.
    # On filtre sur .completed : une génération échouée ou en attente ne doit
    # pas allumer une étoile (sinon la constellation mentirait sur le rituel).
    lit_dates = stories.completed.where(created_at: start_date.beginning_of_day..)
                       .pluck(:created_at)
                       .map(&:to_date)
                       .to_set

    # Pour chaque jour de la fenêtre (du plus ancien au plus récent),
    # true si une histoire existe ce jour-là.
    (0...days).map { |offset| lit_dates.include?((days - 1 - offset).days.ago.to_date) }
  end

  # ============================================================
  # Export RGPD — droit d'accès et portabilité (art. 15 et 20)
  # ============================================================
  # Assemble TOUTES les données personnelles de l'utilisateur dans un Hash
  # structuré, destiné à être sérialisé en JSON et téléchargé par l'utilisateur.
  # La politique de confidentialité (section 8) promet ce droit : cette méthode
  # le concrétise.
  #
  # SÉCURITÉ / périmètre : on part TOUJOURS de `self` et de ses propres
  # associations (children, stories, user_badges). Aucune donnée d'un autre
  # compte n'est jamais lue. On exclut volontairement les données sensibles
  # inutiles à l'export : mot de passe chiffré, tokens Devise, provider/uid
  # OAuth et le flag admin.
  #
  # PERF : `children.includes(:stories)` charge enfants + histoires en 2 requêtes
  # (au lieu d'une requête par enfant), pour éviter les N+1 lors de la boucle.
  def gdpr_export
    {
      # Bloc 1 — informations du compte
      compte: {
        email:        email,
        prenom:       first_name,
        nom:          last_name,
        langue:       locale,
        premium:      premium?,
        cree_le:      created_at
      },
      # Bloc 2 — profils enfants + leurs histoires (chargés en une fois)
      enfants: children.includes(:stories).map do |child|
        {
          nom:                  child.name,
          age:                  child.age,
          genre:                child.gender,
          couleur_cheveux:      child.hair_color,
          couleur_yeux:         child.eye_color,
          teint:                child.skin_tone,
          traits_personnalite:  child.personality_traits,
          loisirs:              child.hobbies,
          description:          child.child_description,
          cree_le:              child.created_at,
          # Histoires de cet enfant — uniquement le contenu et les métadonnées,
          # sans les choix interactifs (export volontairement léger).
          histoires: child.stories.map do |story|
            {
              titre:              story.title,
              contenu:            story.content,
              univers:            story.world_theme,
              valeur_educative:   story.educational_value,
              langue:             story.locale,
              duree_minutes:      story.duration_minutes,
              theme_libre:        story.custom_theme,
              statut:             story.status,
              mode_interactif:    story.interactive,
              cree_le:            story.created_at
            }
          end
        }
      end,
      # Bloc 3 — gamification (XP, niveau, badges obtenus)
      gamification: {
        xp_total: xp_points,
        niveau:   level,
        # Pour chaque badge : sa clé stable + la date à laquelle il a été obtenu
        # (user_badges.created_at = moment de l'attribution).
        badges: user_badges.includes(:badge).map do |user_badge|
          {
            cle:        user_badge.badge.condition_key,
            obtenu_le:  user_badge.created_at
          }
        end
      }
    }
  end

  # ============================================================
  # Méthode de classe — connexion / création via Google OAuth
  # ============================================================
  # Appelée par OmniauthCallbacksController après le retour de Google.
  # auth est le hash OmniAuth renvoyé par Google, qui contient :
  #   auth.provider   → "google_oauth2"
  #   auth.uid        → identifiant unique Google de l'utilisateur
  #   auth.info.email → email Google
  #   auth.info.first_name / auth.info.last_name → prénom/nom
  def self.from_omniauth(auth)
    # 1. On cherche d'abord un compte DÉJÀ lié à ce compte Google (provider + uid)
    #    Cas le plus courant : l'utilisateur s'est déjà connecté via Google avant.
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    # 2. Sinon, on cherche un compte existant avec le MÊME email.
    #    Cas : l'utilisateur s'était inscrit avec email/mot de passe, puis tente
    #    de se connecter via Google. Sans ça, on tomberait sur "email déjà utilisé".
    #    On lie alors son compte à Google (provider + uid) pour les prochaines fois.
    user = find_by(email: auth.info.email)
    if user
      user.update(provider: auth.provider, uid: auth.uid)
      # Google a vérifié cet email → on confirme le compte s'il ne l'était pas encore
      # (évite de lui réclamer une confirmation par mail qu'il a déjà prouvée via Google).
      user.confirm unless user.confirmed?
      return user
    end

    # 3. Aucun compte existant → on en crée un nouveau à partir des infos Google.
    #    Le bloc `do |new_user|` est exécuté avant la sauvegarde.
    create do |new_user|
      new_user.provider   = auth.provider
      new_user.uid        = auth.uid
      new_user.email      = auth.info.email
      new_user.first_name = auth.info.first_name.presence || auth.info.email.split("@").first
      new_user.last_name  = auth.info.last_name.presence  || "-"
      # On génère un mot de passe aléatoire fort — l'utilisateur Google n'en aura jamais besoin
      new_user.password   = Devise.friendly_token[0, 20]
      # Email déjà vérifié par Google → on confirme directement (skip l'email de confirmation).
      # skip_confirmation! doit être appelé AVANT la sauvegarde (donc dans ce bloc create).
      new_user.skip_confirmation!
    end
  end

  private

  # Envoie l'email de bienvenue en arrière-plan via Solid Queue
  # deliver_later évite de bloquer l'inscription si le SMTP est lent
  def send_welcome_email
    WelcomeMailer.welcome_email(self).deliver_later
  end
end
