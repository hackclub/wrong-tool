class AddAirtableSubmittedAtToShips < ActiveRecord::Migration[8.1]
  def change
    # When ShipSubmission first ticked it for Unified YSWS on Airtable: an approved ship without it is looked at again.
    add_column :ships, :airtable_submitted_at, :datetime
  end
end
