# The fraud check, Terra's second axis: every ship waits on a fraud reviewer's trust score (FraudCheck) as well as a
# reviewer's approval, and completes once it has both. A reviewer can also send a ship on, to fraud or an admin, with
# a note (review_hold). Ships in review now start unchecked; decided ones were never checked, and stay that way.
class AddFraudCheckToShips < ActiveRecord::Migration[8.1]
  def up
    change_table :ships, bulk: true do |t|
      t.string :fraud_status
      t.integer :fraud_score
      t.string :review_hold
      t.text :hold_note
      t.datetime :review_approved_at
    end
    add_index :ships, %i[status fraud_status]
    change_table :review_decisions, bulk: true do |t|
      t.integer :trust_score
      t.boolean :mark_sus, null: false, default: false
    end
    execute "UPDATE ships SET fraud_status = 'unchecked' WHERE status = 'in_review'"
  end

  def down
    remove_index :ships, %i[status fraud_status]
    change_table :ships, bulk: true do |t|
      t.remove :fraud_status, :fraud_score, :review_hold, :hold_note, :review_approved_at
    end
    change_table :review_decisions, bulk: true do |t|
      t.remove :trust_score, :mark_sus
    end
  end
end
