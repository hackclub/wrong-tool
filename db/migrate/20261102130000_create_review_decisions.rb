# Reviewing ships, like Terra's review dashboard: people who aren't admins can review (users.review_roles), every
# call on a ship is kept (review_decisions), and "sent back" splits in two: changes requested (they can ship again)
# and rejected (final). Every ship sent back so far could ship again, so they're changes requested now, and each
# decision so far gets its row.
class CreateReviewDecisions < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :review_roles, :string, array: true, default: [], null: false

    create_table :review_decisions do |t|
      t.references :ship, null: false, foreign_key: true
      # Nobody, for one wrong tool made itself.
      t.references :reviewer, foreign_key: { to_table: :users }
      t.string :queue, null: false, default: "review"
      t.string :decision, null: false
      t.text :note_to_maker
      t.text :justification
      t.decimal :approved_hours, precision: 6, scale: 2
      t.text :deflation_reason
      t.string :video_url
      t.datetime :created_at, null: false
    end
    add_index :review_decisions, %i[reviewer_id created_at]

    execute "UPDATE ships SET status = 'changes_requested' WHERE status = 'rejected'"
    execute <<~SQL
      INSERT INTO review_decisions (ship_id, reviewer_id, queue, decision, approved_hours, created_at)
      SELECT id, decided_by_id, 'review', status, CASE WHEN status = 'approved' THEN approved_hours END,
             COALESCE(decided_at, updated_at)
      FROM ships WHERE status <> 'in_review'
    SQL
  end

  def down
    execute "UPDATE ships SET status = 'rejected' WHERE status = 'changes_requested'"
    drop_table :review_decisions
    remove_column :users, :review_roles
  end
end
