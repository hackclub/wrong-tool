module BuddiesHelper
  # Each of you logs this much a week for it to count as a pair week.
  def pair_weekly_hours
    4
  end

  def buddy_name(project)
    project.user.first_name.presence || project.user.name
  end

  def buddy_initial(project)
    buddy_name(project).to_s[0]&.upcase
  end

  # "wrong.hackclub.com/b/orpheus", for showing; the link itself is buddy_invite_url.
  def buddy_invite_link(project)
    buddy_invite_url(project.buddy_code!).delete_prefix("https://").delete_prefix("http://")
  end

  # What a pair earns, and how far you are from each (pair weeks count once hours are in).
  def pair_rewards(pair_weeks: 0)
    upcoming = Pair::REWARDS.find { |reward| reward[:weeks].nil? || reward[:weeks] > pair_weeks }
    Pair::REWARDS.map do |reward|
      earned = reward[:weeks] && pair_weeks >= reward[:weeks]
      left = reward[:weeks].to_i - pair_weeks
      reward.merge(state: earned ? "earned" : reward.equal?(upcoming) ? "next" : "later",
                   status: earned ? "Earned" : reward[:weeks] ? pluralize(left, "wk") : "Both ship",
                   short: reward[:weeks] ? "#{reward[:weeks]} wk" : "Ship")
    end
  end
end
