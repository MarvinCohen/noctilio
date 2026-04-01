# ============================================================
# Migration — crée les tables Solid Queue (job system Rails 8)
# ============================================================
# Ces tables sont nécessaires pour que GenerateStoryJob puisse
# s'enregistrer en base de données via Solid Queue.
#
# POURQUOI CETTE MIGRATION ?
# Solid Queue a normalement ses propres fichiers de migration
# dans db/queue_migrate/, mais Heroku ne les exécute pas avec
# rails db:migrate (qui ne lit que db/migrate/).
# On regroupe donc tout ici pour que ça fonctionne en production.
#
# SÉCURITÉ : if_not_exists: true — idempotent, sans risque de
# détruire des tables existantes.
# ============================================================
class CreateSolidQueueTables < ActiveRecord::Migration[8.1]
  def change

    # Table principale — stocke chaque job en attente ou terminé
    create_table :solid_queue_jobs, if_not_exists: true do |t|
      t.string   :queue_name,      null: false
      t.string   :class_name,      null: false
      t.text     :arguments
      t.integer  :priority,        default: 0, null: false
      t.string   :active_job_id
      t.string   :concurrency_key
      t.datetime :scheduled_at
      t.datetime :finished_at
      t.timestamps

      t.index :active_job_id
      t.index :class_name
      t.index :finished_at
      t.index [:queue_name, :finished_at], name: "index_solid_queue_jobs_for_filtering"
      t.index [:scheduled_at, :finished_at], name: "index_solid_queue_jobs_for_alerting"
    end

    # Jobs prêts à être exécutés immédiatement
    create_table :solid_queue_ready_executions, if_not_exists: true do |t|
      t.bigint   :job_id,          null: false
      t.string   :queue_name,      null: false
      t.integer  :priority,        default: 0, null: false
      t.datetime :created_at,      null: false

      t.index :job_id, unique: true
      t.index [:priority, :job_id], name: "index_solid_queue_poll_all"
      t.index [:queue_name, :priority, :job_id], name: "index_solid_queue_poll_by_queue"
    end

    # Jobs programmés pour plus tard (perform_in, perform_at)
    create_table :solid_queue_scheduled_executions, if_not_exists: true do |t|
      t.bigint   :job_id,          null: false
      t.string   :queue_name,      null: false
      t.integer  :priority,        default: 0, null: false
      t.datetime :scheduled_at,    null: false
      t.datetime :created_at,      null: false

      t.index :job_id, unique: true
      t.index [:scheduled_at, :priority, :job_id], name: "index_solid_queue_dispatch_all"
    end

    # Jobs en cours d'exécution par un worker
    create_table :solid_queue_claimed_executions, if_not_exists: true do |t|
      t.bigint   :job_id,          null: false
      t.bigint   :process_id
      t.datetime :created_at,      null: false

      t.index :job_id, unique: true
      t.index [:process_id, :job_id]
    end

    # Jobs bloqués par une contrainte de concurrence
    create_table :solid_queue_blocked_executions, if_not_exists: true do |t|
      t.bigint   :job_id,          null: false
      t.string   :queue_name,      null: false
      t.integer  :priority,        default: 0, null: false
      t.string   :concurrency_key, null: false
      t.datetime :expires_at,      null: false
      t.datetime :created_at,      null: false

      t.index :job_id, unique: true
      t.index [:expires_at, :concurrency_key], name: "index_solid_queue_blocked_executions_for_maintenance"
      t.index [:concurrency_key, :priority, :job_id], name: "index_solid_queue_blocked_executions_for_release"
    end

    # Jobs qui ont échoué (erreur ou exception)
    create_table :solid_queue_failed_executions, if_not_exists: true do |t|
      t.bigint   :job_id,          null: false
      t.text     :error
      t.datetime :created_at,      null: false

      t.index :job_id, unique: true
    end

    # Processus workers actifs (heartbeat)
    create_table :solid_queue_processes, if_not_exists: true do |t|
      t.string   :kind,              null: false
      t.datetime :last_heartbeat_at, null: false
      t.bigint   :supervisor_id
      t.integer  :pid,               null: false
      t.string   :hostname
      t.string   :name,              null: false
      t.text     :metadata
      t.datetime :created_at,        null: false

      t.index :last_heartbeat_at
      t.index [:name, :supervisor_id], unique: true
      t.index :supervisor_id
    end

    # Files en pause (admin)
    create_table :solid_queue_pauses, if_not_exists: true do |t|
      t.string   :queue_name,      null: false
      t.datetime :created_at,      null: false

      t.index :queue_name, unique: true
    end

    # Sémaphores pour la concurrence
    create_table :solid_queue_semaphores, if_not_exists: true do |t|
      t.string   :key,             null: false
      t.integer  :value,           default: 1, null: false
      t.datetime :expires_at,      null: false
      t.timestamps

      t.index :key, unique: true
      t.index [:key, :value]
      t.index :expires_at
    end

    # Tâches récurrentes (cron-like)
    create_table :solid_queue_recurring_tasks, if_not_exists: true do |t|
      t.string   :key,             null: false
      t.string   :schedule,        null: false
      t.string   :class_name
      t.string   :command,         limit: 2048
      t.text     :arguments
      t.string   :queue_name
      t.integer  :priority,        default: 0
      t.boolean  :static,          default: true, null: false
      t.text     :description
      t.timestamps

      t.index :key, unique: true
      t.index :static
    end

    # Exécutions des tâches récurrentes
    create_table :solid_queue_recurring_executions, if_not_exists: true do |t|
      t.bigint   :job_id,          null: false
      t.string   :task_key,        null: false
      t.datetime :run_at,          null: false
      t.datetime :created_at,      null: false

      t.index :job_id, unique: true
      t.index [:task_key, :run_at], unique: true
    end

    # ============================================================
    # Clés étrangères — intégrité référentielle entre les tables
    # on_delete: :cascade = si un job est supprimé, ses exécutions
    # associées sont supprimées automatiquement
    # ============================================================
    unless foreign_key_exists?(:solid_queue_ready_executions, :solid_queue_jobs)
      add_foreign_key :solid_queue_ready_executions,     :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
    unless foreign_key_exists?(:solid_queue_scheduled_executions, :solid_queue_jobs)
      add_foreign_key :solid_queue_scheduled_executions, :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
    unless foreign_key_exists?(:solid_queue_claimed_executions, :solid_queue_jobs)
      add_foreign_key :solid_queue_claimed_executions,   :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
    unless foreign_key_exists?(:solid_queue_blocked_executions, :solid_queue_jobs)
      add_foreign_key :solid_queue_blocked_executions,   :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
    unless foreign_key_exists?(:solid_queue_failed_executions, :solid_queue_jobs)
      add_foreign_key :solid_queue_failed_executions,    :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
    unless foreign_key_exists?(:solid_queue_recurring_executions, :solid_queue_jobs)
      add_foreign_key :solid_queue_recurring_executions, :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
  end
end
