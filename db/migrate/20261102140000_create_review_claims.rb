# Who's reviewing a ship right now, so two people don't: opening a ship takes it, the page keeps it alive, and it
# goes after ReviewClaim::IDLE without a word. One per ship in each queue (review, and fraud later).
class CreateReviewClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :review_claims do |t|
      t.references :ship, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.string :queue, null: false, default: "review"
      t.datetime :claimed_at, null: false
      t.datetime :heartbeat_at, null: false
    end
    add_index :review_claims, %i[ship_id queue], unique: true
  end
end
