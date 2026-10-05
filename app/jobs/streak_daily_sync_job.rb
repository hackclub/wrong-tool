# Every streak, refreshed, so ones that broke overnight show it even if nobody's looked.
class StreakDailySyncJob < ApplicationJob
  def perform
    User.joins(:project).where.not(hackatime_uid: nil).find_each do |user|
      StreakSyncJob.perform_later(user.id) if user.project.tracking?
    end
  end
end
