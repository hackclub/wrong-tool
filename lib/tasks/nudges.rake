namespace :nudges do
  # One of each kind of nudge Clippy sends, to someone on Slack, through the real thing (copy, moods, Clippy's
  # pictures, tracked links), with made-up numbers. Marked as tests, so they're never scored or counted. Run it
  # where the links should go, like production:
  #
  #   bin/rails "nudges:test[U05F4B48GBF]"
  desc "DM someone one of each kind of Clippy nudge, for testing"
  task :test, [ :slack_id ] => :environment do |_, args|
    user = User.find_by!(slack_id: args.fetch(:slack_id))
    vars = { first_name: user.first_name, title: "flappy sheets", tool_name: "Google Sheets", prize: "Miyoo", hours: 3.5,
             hours_left: 6.5, percent: 35, sessions_left: 9, session_percent: 8, pace: 45, build_time: "evening",
             finish_on: "Oct 17", local_time: "7pm", days_left: 9, streak: 4, streak_next: 5,
             next_reward: "flame on the leaderboard", days_to_reward: 1, peers: 6, days_idle: 3 }

    %w[progress tiny_step streak social done dramatic].each do |arm|
      nudge = user.nudges.new(kind: "test", arm:)
      nudge.deliver!(vars)
      puts "#{arm} (#{nudge.mood}): #{nudge.delivered ? "sent" : "not sent"}, #{nudge.link_url}"
    end
  end
end
