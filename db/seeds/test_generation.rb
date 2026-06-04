# ============================================================
# Script de test — génération d'images variée
# ============================================================
# Crée 10 enfants aux profils physiques très différents,
# chacun avec une histoire dans un univers et un style distincts.
# Lance GenerateStoryJob pour chaque histoire.
#
# Utilisation :
#   rails runner db/seeds/test_generation.rb
#
# Pour suivre la progression :
#   rails console → Story.last(10).map { |s| [s.title, s.status] }
#
# Pour tout supprimer après les tests :
#   rails runner "Story.where(title: Story.where(child: Child.where(name: Child.pluck(:name).last(10))).pluck(:id)).destroy_all; Child.last(10).destroy_all"
# ============================================================

puts "==> Démarrage du test de génération — 10 enfants × 10 histoires"
puts "==> Utilisateur de test : premier utilisateur en base (id=1)"
puts ""

# On associe les enfants au premier utilisateur de la base
# Modifie user_id si tu veux les attribuer à un autre compte
user = User.first
abort("Aucun utilisateur trouvé — lance rails db:seed d'abord") unless user

# ============================================================
# Définition des 10 profils enfants de test
# Chaque enfant cumule : genre, âge, physique varié + accessoire distinctif (child_description)
# pour tester la fidélité de la génération d'image sur des détails fins
# ============================================================
CHILDREN_PROFILES = [
  {
    name:               "Camille",
    age:                6,
    gender:             "girl",
    hair_color:         "blond clair",
    eye_color:          "bleu",
    skin_tone:          "clair",
    personality_traits: ["curieuse", "aventurière"],
    hobbies:            ["les étoiles", "dessiner"],
    # Accessoire clé : lunettes rondes — doit apparaître dans l'illustration
    child_description:  "porte des petites lunettes rondes dorées"
  },
  {
    name:               "Malik",
    age:                8,
    gender:             "boy",
    hair_color:         "noir",
    eye_color:          "marron",
    skin_tone:          "ébène",
    personality_traits: ["courageux", "déterminé"],
    hobbies:            ["les robots", "la course"],
    # Accessoire : bandana rouge — marqueur visuel fort sur peau foncée
    child_description:  "porte un bandana rouge noué autour du poignet"
  },
  {
    name:               "Sofia",
    age:                7,
    gender:             "girl",
    hair_color:         "châtain",
    eye_color:          "vert",
    skin_tone:          "olive",
    personality_traits: ["créative", "empathique"],
    hobbies:            ["la danse", "les animaux"],
    # Accessoire : tresses avec perles colorées — test sur cheveux châtain + peau olive
    child_description:  "a des tresses ornées de petites perles colorées violettes et bleues"
  },
  {
    name:               "Noah",
    age:                5,
    gender:             "boy",
    hair_color:         "roux",
    eye_color:          "bleu",
    skin_tone:          "très clair",
    personality_traits: ["espiègle", "généreux"],
    hobbies:            ["les dinosaures", "construire des Lego"],
    # Accessoire : taches de rousseur — détail physique naturel rare dans les IA
    child_description:  "a des taches de rousseur sur le nez et les joues"
  },
  {
    name:               "Amara",
    age:                9,
    gender:             "girl",
    hair_color:         "noir",
    eye_color:          "marron",
    skin_tone:          "caramel",
    personality_traits: ["confiante", "drôle"],
    hobbies:            ["la natation", "les princesses guerrières"],
    # Accessoire : cape de princesse — test de vêtement fort sur la génération
    child_description:  "porte une cape dorée scintillante attachée à l'épaule"
  },
  {
    name:               "Lucas",
    age:                10,
    gender:             "boy",
    hair_color:         "blond foncé",
    eye_color:          "gris",
    skin_tone:          "beige",
    personality_traits: ["stratège", "patient"],
    hobbies:            ["les pirates", "les cartes au trésor"],
    # Accessoire : patch sur l'oeil façon pirate — test d'accessoire inhabituel
    child_description:  "porte un patch de pirate noir sur l'oeil gauche et un chapeau de capitaine"
  },
  {
    name:               "Inaya",
    age:                6,
    gender:             "girl",
    hair_color:         "noir",
    eye_color:          "marron",
    skin_tone:          "brun foncé",
    personality_traits: ["douce", "courageuse"],
    hobbies:            ["les fées", "jardiner"],
    # Accessoire : ailes de fée attachées dans le dos
    child_description:  "porte de petites ailes de fée transparentes attachées dans le dos"
  },
  {
    name:               "Théo",
    age:                11,
    gender:             "boy",
    hair_color:         "châtain foncé",
    eye_color:          "marron",
    skin_tone:          "doré",
    personality_traits: ["intrépide", "loyal"],
    hobbies:            ["l'astronomie", "les arts martiaux"],
    # Accessoire : casque spatial futuriste — test d'objet technologique
    child_description:  "porte un casque spatial argenté avec une visière orange"
  },
  {
    name:               "Léa",
    age:                4,
    gender:             "girl",
    hair_color:         "blond",
    eye_color:          "bleu",
    skin_tone:          "clair",
    personality_traits: ["joyeuse", "imaginative"],
    hobbies:            ["les licornes", "chanter"],
    # Accessoire : couronne de fleurs dans les cheveux — test sur très jeune enfant
    child_description:  "porte une couronne de petites fleurs roses et blanches dans les cheveux"
  },
  {
    name:               "Kenzo",
    age:                8,
    gender:             "boy",
    hair_color:         "noir",
    eye_color:          "marron",
    skin_tone:          "olive",
    personality_traits: ["calme", "ingénieux"],
    hobbies:            ["les animaux marins", "la cuisine"],
    # Accessoire : tablier de chef avec ustensiles — test d'un accessoire inattendu
    child_description:  "porte un tablier de petit chef cuisinier avec une spatule dans la poche"
  }
].freeze

# ============================================================
# Définition des 10 histoires — une par enfant
# On varie : univers (world_theme), style visuel (image_style),
# valeur éducative (educational_value) et durée (duration_minutes)
# ============================================================
STORIES_PARAMS = [
  # Camille — espace + ghibli + 5 min : test style doux sur décor SF
  {
    world_theme:        "space",
    image_style:        "ghibli",
    educational_value:  "courage",
    duration_minutes:   5,
    interactive:        false,
    custom_theme:       nil
  },
  # Malik — robots + comics + 10 min : test peau ébène avec style Spider-Verse
  {
    world_theme:        nil,
    image_style:        "comics",
    educational_value:  "confidence",
    duration_minutes:   10,
    interactive:        false,
    custom_theme:       "Malik pilote un robot géant nommé Titan pour défendre sa ville"
  },
  # Sofia — animaux + aquarelle + 5 min : test style livre illustré
  {
    world_theme:        "animals",
    image_style:        "watercolor",
    educational_value:  "kindness",
    duration_minutes:   5,
    interactive:        false,
    custom_theme:       nil
  },
  # Noah — dinosaures + pixar + 10 min : test style 3D sur enfant roux
  {
    world_theme:        "dinos",
    image_style:        "pixar",
    educational_value:  "sharing",
    duration_minutes:   10,
    interactive:        false,
    custom_theme:       nil
  },
  # Amara — princesses + cinématique + 5 min : test style réaliste sur peau caramel
  {
    world_theme:        "princesses",
    image_style:        "cinematic",
    educational_value:  "confidence",
    duration_minutes:   5,
    interactive:        false,
    custom_theme:       nil
  },
  # Lucas — pirates + comics + 10 min : test accessoire (patch) dans univers pirate
  {
    world_theme:        "pirates",
    image_style:        "comics",
    educational_value:  "courage",
    duration_minutes:   10,
    interactive:        true,   # Mode interactif — 2 choix
    custom_theme:       nil
  },
  # Inaya — fées + aquarelle + 5 min : test ailes de fée + style doux
  {
    world_theme:        "princesses",
    image_style:        "watercolor",
    educational_value:  "kindness",
    duration_minutes:   5,
    interactive:        false,
    custom_theme:       nil
  },
  # Théo — espace + cinématique + 15 min : test histoire longue + casque spatial
  {
    world_theme:        "space",
    image_style:        "cinematic",
    educational_value:  "courage",
    duration_minutes:   15,
    interactive:        false,
    custom_theme:       nil
  },
  # Léa — licornes + ghibli + 5 min : test très jeune enfant + thème libre
  {
    world_theme:        nil,
    image_style:        "ghibli",
    educational_value:  "sharing",
    duration_minutes:   5,
    interactive:        false,
    custom_theme:       "Léa rencontre une licorne blessée et doit traverser la Forêt des Rêves pour trouver la fleur magique qui la guérira"
  },
  # Kenzo — animaux marins + pixar + 10 min : test tablier de chef sous l'eau
  {
    world_theme:        "animals",
    image_style:        "pixar",
    educational_value:  "confidence",
    duration_minutes:   10,
    interactive:        false,
    custom_theme:       nil
  }
].freeze

# ============================================================
# Création des enfants et des histoires
# ============================================================
CHILDREN_PROFILES.each_with_index do |profile, index|
  # -- Crée l'enfant --
  child = user.children.create!(
    name:               profile[:name],
    age:                profile[:age],
    gender:             profile[:gender],
    hair_color:         profile[:hair_color],
    eye_color:          profile[:eye_color],
    skin_tone:          profile[:skin_tone],
    personality_traits: profile[:personality_traits],
    hobbies:            profile[:hobbies],
    child_description:  profile[:child_description]
  )

  puts "✓ Enfant créé : #{child.name} (#{child.age} ans, #{child.skin_tone}, #{child.hair_color}, #{profile[:child_description]})"

  # -- Crée l'histoire associée --
  story_params = STORIES_PARAMS[index]

  # Story appartient à l'enfant — pas besoin de passer user: directement
  story = child.stories.create!(
    world_theme:        story_params[:world_theme],
    image_style:        story_params[:image_style],
    educational_value:  story_params[:educational_value],
    duration_minutes:   story_params[:duration_minutes],
    interactive:        story_params[:interactive],
    custom_theme:       story_params[:custom_theme],
    status:             :pending
  )

  puts "  Histoire créée : ##{story.id} (#{story_params[:image_style]}, #{story_params[:world_theme] || story_params[:custom_theme]&.truncate(40) || 'thème libre'}, #{story_params[:duration_minutes]} min)"

  # -- Lance la génération en background --
  # GenerateStoryJob génère le texte (Groq) puis l'image (gpt-image-1 ou fal.ai)
  GenerateStoryJob.perform_later(story.id)
  puts "  Job lancé en background pour story ##{story.id}"
  puts ""
end

puts "==> #{CHILDREN_PROFILES.length} histoires lancées."
puts ""
puts "Suis la progression dans la console Rails :"
puts "  Story.last(10).map { |s| [s.child.name, s.status, s.title&.truncate(40)] }"
puts ""
puts "Voir les images générées :"
puts "  Ouvre http://localhost:3000 et navigue vers chaque profil enfant"
