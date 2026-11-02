class AddLastCallDmedAtToProjects < ActiveRecord::Migration[8.1]
  def change
    # When Clippy DMed them that shipping's open again (ships:last_call), so nobody hears it twice.
    add_column :projects, :last_call_dmed_at, :datetime
  end
end
