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

ActiveRecord::Schema[8.1].define(version: 2026_10_05_170000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "buddy_pomodoros", force: :cascade do |t|
    t.integer "pair_id", null: false
    t.integer "started_by_id", null: false
    t.integer "minutes", null: false
    t.datetime "started_at", null: false
    t.datetime "joined_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pair_id"], name: "index_buddy_pomodoros_on_pair_id"
    t.index ["started_by_id"], name: "index_buddy_pomodoros_on_started_by_id"
  end

  create_table "nudges", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "channel", default: "slack", null: false
    t.string "kind", null: false
    t.string "bucket"
    t.string "arm", null: false
    t.integer "variant"
    t.string "mood"
    t.text "text"
    t.text "mood_text"
    t.float "propensity"
    t.boolean "holdout", default: false, null: false
    t.string "token", null: false
    t.datetime "sent_at"
    t.boolean "delivered", default: false, null: false
    t.string "slack_channel"
    t.string "slack_ts"
    t.datetime "clicked_at"
    t.integer "clicks", default: 0, null: false
    t.datetime "opted_out_at"
    t.integer "reward"
    t.datetime "rewarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_nudges_on_token", unique: true
    t.index ["user_id", "sent_at"], name: "index_nudges_on_user_id_and_sent_at"
    t.index ["user_id"], name: "index_nudges_on_user_id"
  end

  create_table "pairs", force: :cascade do |t|
    t.integer "first_project_id", null: false
    t.integer "second_project_id", null: false
    t.date "started_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["first_project_id"], name: "index_pairs_on_first_project_id", unique: true
    t.index ["second_project_id"], name: "index_pairs_on_second_project_id", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "tool", null: false
    t.string "tool_name", null: false
    t.string "idea", null: false
    t.string "prize", null: false
    t.integer "pace_minutes", null: false
    t.string "build_time", null: false
    t.date "signed_on", null: false
    t.string "repo_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "hackatime_projects", default: [], null: false
    t.boolean "repo_later", default: false, null: false
    t.boolean "party_queued", default: false, null: false
    t.string "name"
    t.string "buddy_code"
    t.boolean "buddy_invited", default: false, null: false
    t.boolean "buddy_skipped", default: false, null: false
    t.json "hackatime_baseline"
    t.boolean "hackatime_auto_linked", default: false, null: false
    t.index ["buddy_code"], name: "index_projects_on_buddy_code", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id", unique: true
  end

  create_table "rewards", force: :cascade do |t|
    t.integer "user_id"
    t.integer "pair_id"
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_rewards_on_desktop", unique: true, where: "key = 'desktop'"
    t.index ["pair_id", "key"], name: "index_rewards_on_pair_id_and_key", unique: true
    t.index ["pair_id"], name: "index_rewards_on_pair_id"
    t.index ["user_id", "key"], name: "index_rewards_on_user_id_and_key", unique: true
    t.index ["user_id"], name: "index_rewards_on_user_id"
  end

  create_table "ships", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "repo_url", null: false
    t.string "demo_url", null: false
    t.json "hackatime_projects", default: [], null: false
    t.decimal "hours", precision: 6, scale: 2, default: "0.0", null: false
    t.string "status", default: "in_review", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_ships_on_project_id"
  end

  create_table "streak_activities", force: :cascade do |t|
    t.integer "user_id", null: false
    t.date "activity_date", null: false
    t.integer "coded_seconds", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "activity_date"], name: "index_streak_activities_on_user_id_and_activity_date", unique: true
    t.index ["user_id"], name: "index_streak_activities_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "hca_id", null: false
    t.string "email"
    t.string "name"
    t.string "slack_id"
    t.string "verification_status"
    t.boolean "ysws_eligible", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "hackatime_uid"
    t.text "hackatime_access_token"
    t.integer "current_streak", default: 0, null: false
    t.datetime "streak_synced_at"
    t.string "timezone"
    t.date "streak_skip_used_on"
    t.datetime "slack_channels_joined_at"
    t.datetime "slack_muted_at"
    t.datetime "slack_dm_failed_at"
    t.index ["hackatime_uid"], name: "index_users_on_hackatime_uid", unique: true
    t.index ["hca_id"], name: "index_users_on_hca_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "buddy_pomodoros", "pairs"
  add_foreign_key "buddy_pomodoros", "projects", column: "started_by_id"
  add_foreign_key "nudges", "users"
  add_foreign_key "pairs", "projects", column: "first_project_id"
  add_foreign_key "pairs", "projects", column: "second_project_id"
  add_foreign_key "projects", "users"
  add_foreign_key "rewards", "pairs"
  add_foreign_key "rewards", "users"
  add_foreign_key "ships", "projects"
  add_foreign_key "streak_activities", "users"
end
