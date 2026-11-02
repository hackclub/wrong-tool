# What a reviewer sees about a ship besides what was submitted (ShipEvidence): its Hackatime sessions, its repo and
# commits, whether the demo opens and whether another project shipped the same links, gathered once it's shipped
# (and again on Resync). And what's odd about it (ShipFlag): warnings, and red flags that hold up approving it
# until someone dismisses them with why.
class CreateShipEvidencesAndFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :ship_evidences do |t|
      t.references :ship, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.jsonb :data, null: false, default: {}
      t.jsonb :sources, null: false, default: {}
      t.text :error
      t.datetime :built_at
      t.timestamps
    end

    create_table :ship_flags do |t|
      t.references :ship, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.string :severity, null: false
      t.string :title, null: false
      t.jsonb :details, null: false, default: {}
      t.references :dismissed_by, foreign_key: { to_table: :users }
      t.datetime :dismissed_at
      t.text :dismiss_reason
      t.timestamps
    end
    add_index :ship_flags, %i[ship_id kind], unique: true
  end
end
