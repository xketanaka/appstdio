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

ActiveRecord::Schema[8.1].define(version: 2026_09_04_210300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "tenant_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "role", default: "member", null: false
    t.string "status", default: "invited", null: false
    t.uuid "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tenant_id", "user_id"], name: "index_tenant_users_on_tenant_id_and_user_id", unique: true
    t.index ["user_id", "tenant_id"], name: "index_tenant_users_on_user_id_and_tenant_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'member'::character varying]::text[])", name: "tenant_users_role_check"
    t.check_constraint "status::text = ANY (ARRAY['invited'::character varying, 'active'::character varying, 'suspended'::character varying]::text[])", name: "tenant_users_status_check"
  end

  create_table "tenants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'suspended'::character varying]::text[])", name: "tenants_status_check"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "email_verification_token"
    t.datetime "email_verification_token_expires_at"
    t.datetime "email_verified_at"
    t.datetime "last_signed_in_at"
    t.string "password_digest", null: false
    t.string "password_reset_token"
    t.datetime "password_reset_token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["password_reset_token"], name: "index_users_on_password_reset_token", unique: true, where: "(password_reset_token IS NOT NULL)"
  end

  add_foreign_key "tenant_users", "tenants", on_delete: :cascade
  add_foreign_key "tenant_users", "users", on_delete: :cascade
end
