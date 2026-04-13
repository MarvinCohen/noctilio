class CreateSolidCacheEntries < ActiveRecord::Migration[8.0]
  # ============================================================
  # Migration SolidCache — crée la table de cache distribué
  # ============================================================
  # SolidCache stocke le cache Rails directement en base de données.
  # C'est le cache store utilisé en production (config/environments/production.rb).
  # Rack::Attack l'utilise pour compter les requêtes par IP (rate limiting).
  #
  # Structure de la table :
  #   key      : clé du cache encodée en binaire (hash blake2b)
  #   key_hash : version entière de la clé, indexée pour recherche rapide
  #   value    : valeur sérialisée (jusqu'à 512 Mo)
  #   byte_size: taille de la valeur, utile pour les politiques d'éviction
  # ============================================================

  def change
    # Crée la table solid_cache_entries sur la connexion "cache"
    # (même base PostgreSQL que l'app principale en production sur Heroku)
    create_table :solid_cache_entries do |t|
      t.binary  :key,       limit: 1024,       null: false  # Clé du cache (binaire)
      t.binary  :value,     limit: 536870912,  null: false  # Valeur sérialisée (512 Mo max)
      t.datetime :created_at,                  null: false  # Date de création
      t.integer :key_hash,  limit: 8,          null: false  # Hash entier de la clé (8 bytes = bigint)
      t.integer :byte_size, limit: 4,          null: false  # Taille en bytes de la valeur
    end

    # Index pour accès rapide par hash de clé (la recherche se fait toujours par key_hash)
    add_index :solid_cache_entries, :key_hash,              unique: true,  name: "index_solid_cache_entries_on_key_hash"
    add_index :solid_cache_entries, :byte_size,                            name: "index_solid_cache_entries_on_byte_size"
    add_index :solid_cache_entries, %i[key_hash byte_size],                name: "index_solid_cache_entries_on_key_hash_and_byte_size"
  end
end
