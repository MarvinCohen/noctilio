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
    name: "Cœur Généreux",
    description: "Tu as choisi la gentillesse comme valeur 3 fois. Beau choix !",
    icon: "❤️",
    condition_key: "kind_heart"
  }
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
