# Brings one person's streak up to date from Hackatime.
class StreakSyncJob < ApplicationJob
  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    StreakActivity.sync_for_user!(user)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    # Try again on the next sync.
  end
end
