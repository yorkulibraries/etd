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

ActiveRecord::Schema[7.0].define(version: 2024_02_29_213839) do
  create_table "action_text_rich_texts", charset: "utf8", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", size: :long
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", charset: "utf8", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audits", id: :integer, charset: "utf8", force: :cascade do |t|
    t.integer "auditable_id"
    t.string "auditable_type"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.text "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.datetime "created_at", precision: nil
    t.string "request_uuid"
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "committee_members", id: :integer, charset: "utf8", force: :cascade do |t|
    t.string "full_name"
    t.string "role"
    t.integer "thesis_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "first_name"
    t.string "last_name"
  end

  create_table "delayed_jobs", id: :integer, charset: "utf8", force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at", precision: nil
    t.datetime "locked_at", precision: nil
    t.datetime "failed_at", precision: nil
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "documents", id: :integer, charset: "utf8", force: :cascade do |t|
    t.integer "thesis_id"
    t.integer "user_id"
    t.boolean "supplemental"
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "file"
    t.boolean "deleted", default: false
    t.integer "usage"
    t.index ["thesis_id"], name: "index_documents_on_thesis_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "export_logs", id: :integer, charset: "utf8", force: :cascade do |t|
    t.integer "user_id"
    t.date "published_date"
    t.boolean "production_export", default: false
    t.boolean "complete_thesis", default: true
    t.boolean "publish_thesis", default: true
    t.text "theses_ids"
    t.integer "theses_count"
    t.integer "failed_count"
    t.integer "successful_count"
    t.text "failed_ids"
    t.text "successful_ids"
    t.text "output_full"
    t.text "output_error"
    t.string "job_id"
    t.string "job_status"
    t.date "job_started_at"
    t.date "job_completed_at"
    t.date "job_cancelled_at"
    t.integer "job_cancelled_by_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "gem_records", id: :integer, charset: "utf8", force: :cascade do |t|
    t.string "studentname"
    t.integer "sisid"
    t.string "emailaddress"
    t.string "eventtype"
    t.date "eventdate"
    t.string "examresult"
    t.text "title"
    t.string "program"
    t.string "superv"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "seqgradevent"
    t.date "examdate"
  end

  create_table "loc_subjects", id: :integer, charset: "utf8", force: :cascade do |t|
    t.string "name"
    t.string "category"
    t.integer "code"
    t.string "callnumber"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "settings", charset: "utf8", force: :cascade do |t|
    t.string "var", null: false
    t.text "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["var"], name: "index_settings_on_var", unique: true
  end

  create_table "theses", id: :integer, charset: "utf8", force: :cascade do |t|
    t.text "title"
    t.string "author"
    t.string "supervisor"
    t.text "committee"
    t.integer "student_id"
    t.text "keywords"
    t.text "abstract"
    t.text "embargo"
    t.string "language"
    t.string "degree_name"
    t.string "degree_level"
    t.string "program"
    t.date "exam_date"
    t.date "published_date"
    t.string "status"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "gem_record_event_id"
    t.integer "assigned_to_id"
    t.date "student_accepted_terms_at"
    t.date "under_review_at"
    t.date "accepted_at"
    t.date "published_at"
    t.date "returned_at"
    t.boolean "embargoed", default: false
    t.datetime "embargoed_at", precision: nil
    t.integer "embargoed_by_id"
    t.index ["student_id"], name: "index_theses_on_student_id"
  end

  create_table "thesis_subjectships", id: :integer, charset: "utf8", force: :cascade do |t|
    t.integer "thesis_id"
    t.integer "loc_subject_id"
    t.integer "rank"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "users", id: :integer, charset: "utf8", force: :cascade do |t|
    t.string "username"
    t.string "name"
    t.string "type"
    t.string "email"
    t.integer "created_by_id"
    t.boolean "blocked", default: false
    t.string "role"
    t.string "sisid"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.date "invitation_sent_at"
    t.string "email_external"
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
end
