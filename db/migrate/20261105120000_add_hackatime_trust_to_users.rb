# What Hackatime itself makes of someone's hours: its trust level, from the OAuth token when they link (and again
# whenever a ship's evidence is gathered), so a reviewer can see Hackatime's own call on the hours they're approving.
class AddHackatimeTrustToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :hackatime_trust_level
      t.datetime :hackatime_trust_checked_at
    end
  end
end
