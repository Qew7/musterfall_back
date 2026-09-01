# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_22_001000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abilities", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_abilities_on_key", unique: true
  end

  create_table "army_template_abilities", force: :cascade do |t|
    t.bigint "ability_id", null: false
    t.bigint "army_template_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ability_id"], name: "index_army_template_abilities_on_ability_id"
    t.index ["army_template_id", "ability_id"], name: "idx_template_abilities_unique", unique: true
    t.index ["army_template_id"], name: "index_army_template_abilities_on_army_template_id"
  end

  create_table "army_templates", force: :cascade do |t|
    t.jsonb "abilities", default: [], null: false
    t.string "armor_type", null: false
    t.integer "attacks", default: 1, null: false
    t.integer "base_depth", default: 1, null: false
    t.integer "cost", null: false
    t.datetime "created_at", null: false
    t.bigint "faction_id", null: false
    t.integer "initiative", null: false
    t.string "kind", null: false
    t.integer "melee", default: 0, null: false
    t.integer "missile_attacks", default: 1, null: false
    t.integer "model_base_depth"
    t.integer "model_base_width"
    t.string "model_class", default: "infantry", null: false
    t.integer "model_health", null: false
    t.integer "models", null: false
    t.integer "morale", default: 5, null: false
    t.boolean "mounted", default: false, null: false
    t.integer "movement", default: 3, null: false
    t.string "name", null: false
    t.integer "ranged", default: 0, null: false
    t.string "recruit_tier", default: "line", null: false
    t.boolean "requires_line_of_sight", default: true, null: false
    t.integer "shooting_range", default: 0, null: false
    t.string "shooting_template", default: "single", null: false
    t.integer "skill", default: 3, null: false
    t.integer "spell", default: 0, null: false
    t.integer "spell_range", default: 0, null: false
    t.string "spell_template", default: "single", null: false
    t.string "template_key", null: false
    t.datetime "updated_at", null: false
    t.string "weapon_type", null: false
    t.integer "width", null: false
    t.index ["faction_id", "kind"], name: "index_army_templates_on_faction_id_and_kind"
    t.index ["faction_id"], name: "index_army_templates_on_faction_id"
    t.index ["template_key"], name: "index_army_templates_on_template_key", unique: true
  end

  create_table "balance_battle_rollups", force: :cascade do |t|
    t.bigint "balance_simulation_run_id"
    t.bigint "catalog_version_id", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id"
    t.string "matchup_type", null: false
    t.jsonb "metrics", default: {}, null: false
    t.bigint "round_matchup_id"
    t.string "source", default: "campaign", null: false
    t.datetime "updated_at", null: false
    t.index ["balance_simulation_run_id"], name: "index_balance_battle_rollups_on_balance_simulation_run_id"
    t.index ["catalog_version_id", "created_at"], name: "idx_on_catalog_version_id_created_at_efe4a32f37"
    t.index ["catalog_version_id"], name: "index_balance_battle_rollups_on_catalog_version_id"
    t.index ["game_id"], name: "index_balance_battle_rollups_on_game_id"
    t.index ["round_matchup_id"], name: "index_balance_battle_rollups_on_round_matchup_id", unique: true, where: "(round_matchup_id IS NOT NULL)"
  end

  create_table "balance_counters", force: :cascade do |t|
    t.string "bucket", null: false
    t.bigint "catalog_version_id", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "matchup_type", default: "all", null: false
    t.bigint "n", default: 0, null: false
    t.bigint "sum", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_version_id", "bucket", "key", "matchup_type"], name: "index_balance_counters_unique", unique: true
    t.index ["catalog_version_id"], name: "index_balance_counters_on_catalog_version_id"
  end

  create_table "balance_duel_matrix_runs", force: :cascade do |t|
    t.integer "batches_completed", default: 0, null: false
    t.integer "batches_total", default: 0, null: false
    t.bigint "catalog_version_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "matchups_completed", default: 0, null: false
    t.integer "matchups_failed", default: 0, null: false
    t.integer "matchups_total", default: 0, null: false
    t.integer "seed", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "unit_templates", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_version_id"], name: "index_balance_duel_matrix_runs_on_catalog_version_id"
    t.index ["status", "created_at"], name: "index_balance_duel_matrix_runs_on_status_and_created_at"
  end

  create_table "balance_duel_runs", force: :cascade do |t|
    t.decimal "avg_rounds", precision: 8, scale: 2, default: "0.0", null: false
    t.bigint "catalog_version_id", null: false
    t.jsonb "config", default: {}, null: false
    t.string "contact", default: "front", null: false
    t.datetime "created_at", null: false
    t.integer "iterations", null: false
    t.integer "left_models"
    t.string "left_template", null: false
    t.decimal "left_winrate", precision: 8, scale: 4, default: "0.0", null: false
    t.integer "left_wins", default: 0, null: false
    t.integer "right_models"
    t.string "right_template", null: false
    t.decimal "right_winrate", precision: 8, scale: 4, default: "0.0", null: false
    t.integer "right_wins", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_version_id", "created_at"], name: "index_balance_duel_runs_on_catalog_version_id_and_created_at"
    t.index ["catalog_version_id", "left_template", "right_template", "contact"], name: "index_balance_duel_runs_on_matchup"
    t.index ["catalog_version_id"], name: "index_balance_duel_runs_on_catalog_version_id"
  end

  create_table "balance_simulation_runs", force: :cascade do |t|
    t.integer "battles_completed", default: 0, null: false
    t.integer "battles_failed", default: 0, null: false
    t.bigint "catalog_version_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.bigint "seed", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_version_id"], name: "index_balance_simulation_runs_on_catalog_version_id"
    t.index ["status", "created_at"], name: "index_balance_simulation_runs_on_status_and_created_at"
  end

  create_table "battle_phases", force: :cascade do |t|
    t.jsonb "actions", default: [], null: false
    t.bigint "battle_turn_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "events", default: [], null: false
    t.string "label", null: false
    t.string "phase_type", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["battle_turn_id", "position"], name: "index_battle_phases_on_battle_turn_id_and_position", unique: true
    t.index ["battle_turn_id"], name: "index_battle_phases_on_battle_turn_id"
  end

  create_table "battle_rounds", force: :cascade do |t|
    t.bigint "battle_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "events", default: [], null: false
    t.integer "number", null: false
    t.datetime "updated_at", null: false
    t.index ["battle_id", "number"], name: "index_battle_rounds_on_battle_id_and_number", unique: true
    t.index ["battle_id"], name: "index_battle_rounds_on_battle_id"
  end

  create_table "battle_turns", force: :cascade do |t|
    t.bigint "battle_round_id", null: false
    t.datetime "created_at", null: false
    t.string "player_id", null: false
    t.string "player_name", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["battle_round_id", "position"], name: "index_battle_turns_on_battle_round_id_and_position", unique: true
    t.index ["battle_round_id"], name: "index_battle_turns_on_battle_round_id"
  end

  create_table "battles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "events", default: [], null: false
    t.bigint "game_id", null: false
    t.jsonb "left_payload", default: {}, null: false
    t.string "left_player_id", null: false
    t.string "left_player_name", null: false
    t.jsonb "right_payload", default: {}, null: false
    t.string "right_player_id", null: false
    t.string "right_player_name", null: false
    t.integer "round_number", null: false
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.string "winner_id", null: false
    t.string "winner_name", null: false
    t.index ["game_id", "round_number", "left_player_id", "right_player_id"], name: "index_battles_on_round_and_players"
    t.index ["game_id"], name: "index_battles_on_game_id"
  end

  create_table "catalog_versions", force: :cascade do |t|
    t.string "catalog_hash", null: false
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.string "rules_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["content_hash"], name: "index_catalog_versions_on_content_hash", unique: true
  end

  create_table "factions", force: :cascade do |t|
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "passive", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "vibe", null: false
    t.index ["position"], name: "index_factions_on_position"
    t.index ["slug"], name: "index_factions_on_slug", unique: true
  end

  create_table "game_entities", force: :cascade do |t|
    t.jsonb "abilities", default: [], null: false
    t.jsonb "combat", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "current_health", null: false
    t.jsonb "economy", default: {}, null: false
    t.string "external_key", null: false
    t.float "facing", default: 0.0, null: false
    t.jsonb "formation", default: {}, null: false
    t.bigint "game_player_id", null: false
    t.jsonb "health", default: {}, null: false
    t.jsonb "hero", default: {}, null: false
    t.jsonb "identity", default: {}, null: false
    t.boolean "is_routing", default: false, null: false
    t.string "kind", null: false
    t.string "lane_key", default: "center", null: false
    t.string "name", null: false
    t.jsonb "progression", default: {}, null: false
    t.string "row_key", default: "reserve", null: false
    t.string "template_key", null: false
    t.datetime "updated_at", null: false
    t.float "x", default: 0.0, null: false
    t.float "y", default: 0.0, null: false
    t.index ["game_player_id", "external_key"], name: "index_game_entities_on_game_player_id_and_external_key", unique: true
    t.index ["game_player_id"], name: "index_game_entities_on_game_player_id"
    t.index ["kind"], name: "index_game_entities_on_kind"
  end

  create_table "game_entity_attachments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "hero_entity_id", null: false
    t.string "slot", null: false
    t.bigint "unit_entity_id", null: false
    t.datetime "updated_at", null: false
    t.index ["hero_entity_id"], name: "index_game_entity_attachments_on_hero_entity_id", unique: true
    t.index ["unit_entity_id", "slot"], name: "index_game_entity_attachments_on_unit_entity_id_and_slot", unique: true
    t.index ["unit_entity_id"], name: "index_game_entity_attachments_on_unit_entity_id"
  end

  create_table "game_players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_key", null: false
    t.string "faction_key"
    t.bigint "game_id", null: false
    t.boolean "is_bot", default: false, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "recruit_access", default: 0, null: false
    t.string "recruit_strategy"
    t.jsonb "round_notes", default: [], null: false
    t.string "status", default: "active", null: false
    t.integer "treasury", default: 250, null: false
    t.datetime "updated_at", null: false
    t.integer "victories", default: 0, null: false
    t.index ["game_id", "external_key"], name: "index_game_players_on_game_id_and_external_key", unique: true
    t.index ["game_id", "position"], name: "index_game_players_on_game_id_and_position"
    t.index ["game_id"], name: "index_game_players_on_game_id"
  end

  create_table "games", force: :cascade do |t|
    t.integer "campaign_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "current_round", default: 1, null: false
    t.jsonb "last_round_report"
    t.integer "player_count", null: false
    t.bigint "rng_seed", default: 0, null: false
    t.jsonb "state_payload", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "winner_player_key"
    t.index ["status"], name: "index_games_on_status"
  end

  create_table "hero_upgrades", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.bigint "faction_id"
    t.boolean "general_only", default: false, null: false
    t.integer "min_level", default: 1, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "repeatable", default: false, null: false
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.string "upgrade_key", null: false
    t.index ["faction_id"], name: "index_hero_upgrades_on_faction_id"
    t.index ["position"], name: "index_hero_upgrades_on_position"
    t.index ["upgrade_key"], name: "index_hero_upgrades_on_upgrade_key", unique: true
  end

  create_table "player_actions", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id"
    t.integer "http_status", null: false
    t.jsonb "params", default: {}, null: false
    t.string "player_id"
    t.index ["game_id", "created_at"], name: "index_player_actions_on_game_id_and_created_at"
    t.index ["game_id"], name: "index_player_actions_on_game_id"
  end

  create_table "round_matchups", force: :cascade do |t|
    t.string "attacker_player_key", null: false
    t.string "attacker_player_name", null: false
    t.jsonb "attacker_snapshot", default: {}, null: false
    t.integer "campaign_round", null: false
    t.datetime "created_at", null: false
    t.string "defender_player_key", null: false
    t.string "defender_player_name", null: false
    t.jsonb "defender_snapshot", default: {}, null: false
    t.text "error_message"
    t.bigint "game_id", null: false
    t.integer "position", null: false
    t.jsonb "result_payload", default: {}
    t.bigint "seed", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "campaign_round", "position"], name: "index_round_matchups_on_game_round_position", unique: true
    t.index ["game_id", "campaign_round", "status"], name: "index_round_matchups_on_game_round_status"
    t.index ["game_id"], name: "index_round_matchups_on_game_id"
  end

  create_table "round_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "phase", null: false
    t.integer "round_number", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "round_number", "phase"], name: "index_round_snapshots_on_game_id_and_round_number_and_phase", unique: true
    t.index ["game_id"], name: "index_round_snapshots_on_game_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "army_template_abilities", "abilities"
  add_foreign_key "army_template_abilities", "army_templates"
  add_foreign_key "army_templates", "factions"
  add_foreign_key "balance_battle_rollups", "balance_simulation_runs"
  add_foreign_key "balance_battle_rollups", "catalog_versions"
  add_foreign_key "balance_battle_rollups", "games"
  add_foreign_key "balance_battle_rollups", "round_matchups"
  add_foreign_key "balance_counters", "catalog_versions"
  add_foreign_key "balance_duel_matrix_runs", "catalog_versions"
  add_foreign_key "balance_duel_runs", "catalog_versions"
  add_foreign_key "balance_simulation_runs", "catalog_versions"
  add_foreign_key "battle_phases", "battle_turns"
  add_foreign_key "battle_rounds", "battles"
  add_foreign_key "battle_turns", "battle_rounds"
  add_foreign_key "battles", "games"
  add_foreign_key "game_entities", "game_players"
  add_foreign_key "game_entity_attachments", "game_entities", column: "hero_entity_id"
  add_foreign_key "game_entity_attachments", "game_entities", column: "unit_entity_id"
  add_foreign_key "game_players", "games"
  add_foreign_key "hero_upgrades", "factions"
  add_foreign_key "player_actions", "games"
  add_foreign_key "round_matchups", "games"
  add_foreign_key "round_snapshots", "games"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
