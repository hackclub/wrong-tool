module BuddiesHelper
  # Each of you logs this much in a program week for it to count as a pair week.
  def pair_weekly_hours = Pair::WEEKLY_HOURS

  # Their Slack display name, never their real name (see User#public_name).
  def buddy_name(project)
    project.user.public_name
  end


  # "wrong.hackclub.com/b/k3j9x2qa", for showing; the link itself is buddy_invite_url.
  def buddy_invite_link(project)
    buddy_invite_url(project.buddy_code!).delete_prefix("https://").delete_prefix("http://")
  end

  # What a pair earns (Reward::PAIR), and how far your pair is from each: earned, next up or later. The desktop
  # background is "taken" once another pair has it.
  def pair_rewards(pair = nil)
    weeks = pair ? pair.pair_weeks : 0
    desktop = Reward.desktop_pair
    rewards = Reward::PAIR.map do |reward|
      earned = pair&.earned?(reward[:key])
      taken = reward[:key] == "desktop" && desktop && desktop != pair
      status = if earned then "Earned"
      elsif taken then "Taken"
      elsif reward[:weeks] then "#{reward[:weeks] - weeks} wk left"
      elsif reward[:key] == "desktop" then "Open"
      else "Not yet"
      end
      reward.merge(earned:, taken:, status:)
    end
    upcoming = rewards.find { |reward| !reward[:earned] && !reward[:taken] }
    rewards.map { |reward| reward.merge(state: reward[:earned] ? "earned" : reward.equal?(upcoming) ? "next" : "later") }
  end
end
