class AddAirtableSyncToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :airtable_record_id, :string
    add_column :ships, :airtable_synced_at, :datetime
  end
end
