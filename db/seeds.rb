# ============================================================
# Seeds — données initiales pour Noctilio
# ============================================================
# Lancé avec : rails db:seed
# Idempotent : peut être lancé plusieurs fois sans créer de doublons

puts "🌱 Création des badges..."

# Chaque badge a une condition_key unique vérifiée dans Badge.check_and_award
badges_data = [
  {
    name: "Première histoire",
    description: "Tu as créé ta première histoire magique !",
    icon: "⭐",
    condition_key: "first_story"
  },
  {
    name: "5 histoires",
    description: "Tu as créé 5 histoires ! La magie continue...",
    icon: "📚",
    condition_key: "five_stories"
  },
  {
    name: "10 histoires",
    description: "10 aventures créées ! Tu es un vrai conteur !",
    icon: "🏅",
    condition_key: "ten_stories"
  },
  {
    name: "Hibou Nocturne",
    description: "Tu as créé une histoire après 21h. Les meilleures histoires naissent la nuit !",
    icon: "🦉",
    condition_key: "night_owl"
  },
  {
    # Renommé en « Cœur Bienveillant » : ce badge récompense la GENTILLESSE.
    # « Cœur Généreux » est réservé au badge sharing_heart (le PARTAGE) pour
    # éviter deux badges au nom identique sur la page des trophées.
    name: "Cœur Bienveillant",
    description: "Tu as choisi la gentillesse comme valeur 3 fois. Beau choix !",
    icon: "❤️",
    condition_key: "kind_heart"
  },
  {
    name: "Grand Lecteur",
    description: "Tu as sauvegardé 10 histoires dans ta bibliothèque. Un vrai amoureux des livres !",
    icon: "🔖",
    condition_key: "bookworm"
  },

  # ── Progression ──────────────────────────────────────────────────────────────
  { name: "20 histoires",    description: "20 aventures ! Tu es un vrai créateur d'histoires.", icon: "🌟", condition_key: "twenty_stories" },
  { name: "30 histoires",    description: "30 histoires ! Quelle imagination débordante !", icon: "🎯", condition_key: "thirty_stories" },
  { name: "50 histoires",    description: "50 aventures créées ! Légende des conteurs !", icon: "🏆", condition_key: "fifty_stories" },
  { name: "100 histoires",   description: "100 histoires ! Tu es une véritable machine à rêves !", icon: "💯", condition_key: "hundred_stories" },

  # ── Univers ───────────────────────────────────────────────────────────────────
  { name: "Explorateur Spatial",  description: "3 aventures dans l'espace. Les étoiles te connaissent bien !", icon: "🚀", condition_key: "space_explorer" },
  { name: "Fan de Dinos",         description: "3 aventures avec des dinosaures. ROAAARRR !", icon: "🦕", condition_key: "dino_fan" },
  { name: "Fan de Princesses",    description: "3 aventures de princesses. Le château t'appartient !", icon: "👸", condition_key: "princess_fan" },
  { name: "Capitaine Pirate",     description: "3 aventures de pirates. En avant, moussaillon !", icon: "🏴‍☠️", condition_key: "pirate_captain" },
  { name: "Ami des Animaux",      description: "3 aventures avec des animaux. Ils t'adorent !", icon: "🦁", condition_key: "animal_lover" },
  { name: "Grand Voyageur",       description: "Tu as exploré les 5 univers ! Rien ne t'arrête.", icon: "🌍", condition_key: "world_traveler" },

  # ── Mode interactif ───────────────────────────────────────────────────────────
  { name: "Premier Choix",        description: "Tu as complété ta première histoire interactive. C'est toi qui décides !", icon: "🎮", condition_key: "first_interactive" },
  { name: "Maître des Choix",     description: "10 choix interactifs effectués. Chaque chemin mène à une aventure !", icon: "🔀", condition_key: "choice_maker" },

  # ── Sagas ─────────────────────────────────────────────────────────────────────
  { name: "La Suite !",           description: "Tu as créé la suite d'une histoire. La saga commence !", icon: "📖", condition_key: "saga_starter" },
  { name: "Maître de la Saga",    description: "Une saga de 3 épisodes ! Tu es un vrai feuilletoniste.", icon: "🎬", condition_key: "saga_master" },

  # ── Styles ────────────────────────────────────────────────────────────────────
  { name: "Artiste Complet",      description: "Tu as utilisé les 5 styles d'illustration. Quel artiste !", icon: "🎨", condition_key: "style_explorer" },
  { name: "Fan de Ghibli",        description: "5 histoires dans le style Studio Ghibli. La magie est en toi.", icon: "🖼️", condition_key: "ghibli_fan" },
  { name: "Réalisateur en Herbe", description: "3 histoires en style cinématique. Hollywood t'attend !", icon: "🎬", condition_key: "cinematic_pro" },

  # ── Valeurs éducatives ────────────────────────────────────────────────────────
  { name: "Cœur Courageux",       description: "Tu as choisi le courage 3 fois. Rien ne t'effraie !", icon: "💪", condition_key: "courage_heart" },
  { name: "Cœur Généreux",        description: "Tu as choisi le partage 3 fois. Bravo pour ta générosité !", icon: "🤝", condition_key: "sharing_heart" },
  { name: "Cœur Confiant",        description: "Tu as choisi la confiance 3 fois. Tu crois en toi !", icon: "💫", condition_key: "confidence_builder" },

  # ── Thème libre ───────────────────────────────────────────────────────────────
  { name: "Esprit Libre",         description: "Première histoire avec ta propre idée. L'imagination n'a pas de limites !", icon: "✨", condition_key: "free_spirit" },
  { name: "Grand Imaginatif",     description: "5 histoires inventées de toutes pièces. Ton imagination est infinie !", icon: "🎭", condition_key: "imaginative" },

  # ── Durée ─────────────────────────────────────────────────────────────────────
  { name: "Vite Fait Bien Fait",  description: "5 histoires express de 5 minutes. La qualité avant tout !", icon: "⚡", condition_key: "quick_tales" },
  { name: "Lecteur Épique",       description: "Première histoire de 15 minutes. Tu aimes les grandes aventures !", icon: "📜", condition_key: "epic_reader" },

  # ── Famille ───────────────────────────────────────────────────────────────────
  { name: "Aventure Partagée",    description: "Première histoire avec plusieurs enfants. Plus on est de fous, plus on rit !", icon: "👫", condition_key: "together" },
  { name: "Grande Famille",       description: "Une histoire avec 3 héros ou plus ! Quelle bande de joyeux drilles !", icon: "👨‍👩‍👧", condition_key: "big_family" },

  # ── Horaires ──────────────────────────────────────────────────────────────────
  { name: "Lève-tôt",             description: "Histoire créée avant 8h du matin. Le monde appartient à ceux qui se lèvent tôt !", icon: "🌅", condition_key: "early_bird" },
  { name: "Conte de Minuit",      description: "Histoire créée après minuit. Les histoires les plus magiques naissent dans le noir !", icon: "🌙", condition_key: "midnight_tales" },

  # ── Bibliothèque ──────────────────────────────────────────────────────────────
  { name: "Collectionneur",       description: "5 histoires sauvegardées. Tu commences ta collection !", icon: "💾", condition_key: "collector" },
  { name: "Grande Bibliothèque",  description: "25 histoires sauvegardées. Ta bibliothèque est impressionnante !", icon: "📚", condition_key: "great_library" },

  # ── Week-end ──────────────────────────────────────────────────────────────────
  { name: "Héros du Week-end",    description: "3 histoires créées le week-end. Les aventures ne s'arrêtent jamais !", icon: "🎉", condition_key: "weekend_tales" }
]

# find_or_create_by! : crée seulement si n'existe pas encore (idempotent)
badges_data.each do |data|
  Badge.find_or_create_by!(condition_key: data[:condition_key]) do |badge|
    badge.name        = data[:name]
    badge.description = data[:description]
    badge.icon        = data[:icon]
  end
  puts "  ✓ #{data[:name]}"
end

puts ""
puts "✅ Seeds terminés — #{Badge.count} badges disponibles"
