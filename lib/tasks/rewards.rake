namespace :rewards do
  # One time, right after the hours shoutout reward ships: everyone already past 5 hours gets theirs, as one post in
  # #wrong naming them all rather than one each (plus their DM). Hours are brought up to date from Hackatime first.
  # Run it before the hourly streak sweep gets to them, or they're posted one at a time by it.
  #
  #   bin/rails rewards:backfill_hours_shoutouts
  desc "Award the hours shoutout to everyone already past it, with one roundup post in #wrong"
  task backfill_hours_shoutouts: :environment do
    had = Reward.where(key: "hours_shoutout").pluck(:user_id)
    Reward.quietly do
      User.joins(:project).find_each do |user|
        next unless user.project.tracking?
        StreakActivity.sync_for_user!(user)
      rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
        Reward.award_hours!(user) # with the hours we last saw
      end
    end
    rewards = Reward.includes(user: :project).where(key: "hours_shoutout").where.not(user_id: had).order(:created_at).to_a
    RewardNotifier.roundup_hours_shoutouts(rewards)
    puts "#{had.size} already had a shoutout, #{rewards.size} awarded now: #{rewards.map { |reward| reward.user.public_name }.join(", ")}"
  end
end
