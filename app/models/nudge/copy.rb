# Everything Clippy says in a nudge, in two parts: the message, which is plain and short (what's true and one easy
# next step, never guilt), and a line under it with how Clippy feels about it (see MOODS). Clippy writes in
# lowercase. Each arm has a few variants of about the same intensity, so the bandit learns which framing works
# rather than which sentence; we rotate through them so nobody gets the same one twice in a row.
#
# %{...} fills in from Nudge::Context#vars. A variant whose values aren't there (no streak yet, too few peers) isn't
# picked.
module Nudge::Copy
  # Bandit arms.
  ARMS = {
    # How close you are to the handheld.
    "progress" => [
      "%{hours} of 10 hours on %{title}. about %{sessions_left} more %{pace}-minute sessions to a %{prize}.",
      "you're %{percent}%% of the way to a %{prize}.",
      "%{hours_left} hours left. at %{pace} minutes a session, you'd finish by %{finish_on}.",
      "one %{pace}-minute session gets you %{session_percent}%% closer to a %{prize}."
    ],
    # Keep it going. Only for people with a streak.
    "streak" => [
      "🔥 %{streak} days in a row on %{title}. today makes it %{streak_next}.",
      "you've built %{streak} days in a row. 20 minutes today keeps it going.",
      "🔥 %{streak} days. %{days_to_reward} more and you unlock %{next_reward}.",
      "20 minutes today keeps your 🔥 going."
    ],
    # What you told us at the pledge, in your words and at your time.
    "pledge" => [
      "it's %{local_time}. you said %{build_time}, %{pace} minutes on %{title}.",
      "this is the time you picked for %{title}.",
      "you pledged %{pace} minutes a session. here's your reminder.",
      "it's %{build_time}. %{title} is ready when you are."
    ],
    # Make starting easy.
    "tiny_step" => [
      "no need to finish anything today. open %{tool_name}, fix one thing, close it. that counts.",
      "20 minutes, one small feature. that's enough for today.",
      "one small task: make one thing in %{title} a little less broken.",
      "you don't have to feel like it. just open %{tool_name}. it usually gets easier after a few minutes."
    ],
    # Other people are building.
    "social" => [
      "%{peers} people building in %{tool_name} logged time today.",
      "%{peers} people made %{tool_name} do something new today. your turn.",
      "people are shipping games in tools never meant for games. %{title} could be next.",
      "#wrong is busy today. come share %{title}."
    ],
    # The leaderboard: who's just above you and how little it takes to pass them. Only when you have hours this
    # week and they're within a session (Nudge::Context#leaderboard_vars). The last one's for when they went past
    # you since yesterday.
    "overtake" => [
      "%{above} is %{gap_minutes} minutes ahead of you on the leaderboard. one session passes them.",
      "you're #%{rank} this week. %{gap_minutes} minutes puts you past %{above}.",
      "%{gap_minutes} minutes between you and %{above}. that's less than one session.",
      "%{passed_by} passed you since yesterday. %{gap_minutes} minutes takes the spot back."
    ],
    # Clippy being a bit much, on purpose: the whole message is the bit, so there's no mood line. Capped at
    # Nudge::DRAMATIC_CAP per person.
    "dramatic" => [
      "clippy has been staring at your empty %{tool_name} for %{days_idle} days. clippy is fine. clippy is totally fine. 📎",
      "it looks like you're trying to win a %{prize}. would you like help with that?",
      "clippy has started telling the other paperclips about %{title}. they have questions. clippy has no answers.",
      "breaking: local paperclip refreshes your hackatime again. still nothing. more at %{local_time}."
    ],

    # Cheers, sent right after the day's 20 minutes (Nudge::Cheer). %{day} is "today" or "yesterday", and
    # %{next_day} "tomorrow" or "today", so a cheer held for the morning still reads right.
    # Just that they did it.
    "cheer_done" => [
      "%{minutes} minutes on %{title} %{day}. that's a build day.",
      "you built %{day}. %{minutes} minutes, logged and counted.",
      "%{day} counts. %{minutes} minutes on %{title}.",
      "%{minutes} minutes in %{tool_name} %{day}. that's not nothing. that's a lot, actually."
    ],
    # What it added up to.
    "cheer_progress" => [
      "%{minutes} minutes %{day}. that's %{hours} of 10 hours, %{hours_left} to a %{prize}.",
      "%{day}'s %{minutes} minutes put you at %{percent}%% of a %{prize}.",
      "%{hours} hours on %{title} so far. %{sessions_left} more sessions at your pace and it's a %{prize}."
    ],
    # The streak it kept going. Only for people with one.
    "cheer_streak" => [
      "🔥 %{streak} days in a row on %{title}. %{next_day} makes it %{streak_next}.",
      "that's %{streak} days running. %{days_to_reward} more and you unlock %{next_reward}.",
      "🔥 %{streak}. %{minutes} minutes %{day} kept it going."
    ],
    # The next one.
    "cheer_tomorrow" => [
      "%{minutes} minutes %{day}. same again %{next_day}? %{build_time}, %{pace} minutes.",
      "you built %{day}. the hard part of %{next_day} is done already: you know it works.",
      "%{day}: done. %{next_day}: %{build_time}. clippy will be there."
    ],
    # Who else did.
    "cheer_social" => [
      "%{peers} people built in %{tool_name} %{day}. you're one of them.",
      "you and %{peers} others logged time %{day}. #wrong would like to see %{title}."
    ]
  }.freeze

  # Nudges that always send when they apply (see Nudge::Fixed).
  FIXED = {
    # Setup, one missing step at a time.
    "hackatime" => [ "your hours start counting once hackatime is linked. it takes about 2 minutes." ],
    "lapse" => [ "nothing from you has reached hackatime yet. record your next session on %{title} with lapse and it links itself." ],
    "plugin" => [ "nothing from you has reached hackatime yet. turn the hackatime plugin on in your editor and write a line: %{title} links itself." ],
    "hackatime_project" => [ "hackatime has time from you, but %{title} isn't linked to any of it yet. pick your project and your hours count." ],
    "repo" => [ "add your repo link to %{title} so it counts when you ship." ],

    # Milestones.
    "first_session" => [ "first session logged. %{title} exists now!" ],
    "halfway" => [ "5 hours. you're halfway to a %{prize}." ],
    "done" => [ "10 hours. you've earned a %{prize}. go claim it 🎉" ],

    # Program dates. "_done" is for people who already have their 10 hours.
    "kickoff" => [ "wrong tool starts today. %{title}, %{build_time}, %{pace} minutes." ],
    "three_days_left" => [ "3 days left. %{hours_left} more hours and a %{prize} is yours." ],
    "three_days_left_done" => [ "3 days left, and you've already won. anything you build now is a bonus." ],
    "last_day" => [ "last day of wrong tool. whatever %{title} is right now, ship it." ],
    "last_day_done" => [ "last day of wrong tool. you earned a %{prize} building %{title} in %{tool_name}." ],

    # Before a streak ends.
    "streak_saver" => [ "your 🔥 %{streak} ends at midnight. 20 minutes saves it." ]
  }.freeze

  # How Clippy feels, the small line under every message, with a picture of him acting it out. Picked at random
  # within the mood, so it isn't something the bandit learns (it does go with the arm, so an arm's results include
  # its mood). The big ones are for moments that earn them. Dramatic's mood is the whole message, so it has no line.
  MOODS = {
    "hopeful" => [ "📎 clippy believes in you.", "📎 clippy is rooting for you.", "📎 clippy saved you a seat.",
                   "📎 clippy believes in you. (clippy has to, it's a paperclip.)" ],
    "proud" => [ "📎 clippy is quietly proud.", "📎 clippy is doing a little happy wiggle.", "📎 clippy did the math. clippy loves math." ],
    "excited" => [ "📎 clippy is vibrating.", "📎 clippy can't sit still.", "📎 clippy is very excited about this." ],
    "emotional" => [ "📎 clippy is crying. happy tears.", "📎 clippy is emotional.", "📎 clippy will tell its grandchildren about this." ]
  }.freeze

  MOOD_FOR = {
    "progress" => "proud", "streak" => "excited", "pledge" => "hopeful", "tiny_step" => "hopeful", "social" => "excited",
    "overtake" => "excited",
    "cheer_done" => "proud", "cheer_progress" => "proud", "cheer_streak" => "excited", "cheer_tomorrow" => "hopeful",
    "cheer_social" => "excited",
    "hackatime" => "hopeful", "lapse" => "hopeful", "plugin" => "hopeful", "hackatime_project" => "hopeful", "repo" => "hopeful",
    "first_session" => "emotional", "halfway" => "excited", "done" => "emotional",
    "kickoff" => "excited", "three_days_left" => "hopeful", "three_days_left_done" => "proud",
    "last_day" => "emotional", "last_day_done" => "emotional", "streak_saver" => "hopeful"
  }.freeze

  # Where each nudge's one button goes.
  LINKS = {
    "progress" => [ "see your progress", :project ],
    "streak" => [ "keep it going", :project ],
    "pledge" => [ "open your project", :project ],
    "tiny_step" => [ "start 20 minutes", :project ],
    "social" => [ "see what people built", :slack ],
    "overtake" => [ "see the leaderboard", :leaderboard ],
    "dramatic" => [ "make clippy happy", :project ],
    "cheer_done" => [ "see your progress", :project ],
    "cheer_progress" => [ "see your progress", :project ],
    "cheer_streak" => [ "see your streak", :project ],
    "cheer_tomorrow" => [ "open your project", :project ],
    "cheer_social" => [ "show #wrong", :slack ],
    "hackatime" => [ "link hackatime", :hackatime ],
    "lapse" => [ "get lapse", :lapse ],
    "plugin" => [ "set up the plugin", :hackatime_site ],
    "hackatime_project" => [ "pick your project", :project ],
    "repo" => [ "add your repo", :project ],
    "first_session" => [ "see your progress", :project ],
    "halfway" => [ "see your progress", :project ],
    "done" => [ "claim your handheld", :project ],
    "kickoff" => [ "open your project", :project ],
    "three_days_left" => [ "open your project", :project ],
    "three_days_left_done" => [ "show #wrong", :slack ],
    "last_day" => [ "ship it", :project ],
    "last_day_done" => [ "show #wrong", :slack ],
    "streak_saver" => [ "save your streak", :project ]
  }.freeze

  SLACK_MUTE = "stop these messages"

  def self.variants_for(arm)
    ARMS[arm] || FIXED.fetch(arm)
  end

  # Variants with everything they need. If none fit, the arm can't be sent right now.
  def self.renderable(arm, vars)
    variants_for(arm).each_with_index.select { |text, _| (keys(text) - vars.keys).empty? }
  end

  def self.renderable?(arm, vars)
    renderable(arm, vars).any?
  end

  # Returns [variant, text, mood, mood_text]: the next variant this person hasn't just had, and how Clippy feels
  # about it (no mood_text for dramatic, which is all mood).
  def self.render(nudge, vars)
    options = renderable(nudge.arm, vars)
    last = nudge.user.nudges.where(arm: nudge.arm).order(:sent_at).last&.variant
    text, variant = options.reject { |_, index| index == last }.sample || options.sample
    mood = mood_for(nudge.arm)
    [ variant, format(text, **vars), mood, MOODS[mood]&.sample ]
  end

  def self.mood_for(arm)
    MOOD_FOR.fetch(arm, "dramatic")
  end

  # Clippy acting out the mood, next to the message: public/clippy/<mood>.gif, from his sprite sheet
  # (script/clippy_gifs.py).
  def self.image_url(mood)
    "#{Rails.configuration.x.app_url}/clippy/#{mood}.gif"
  end

  def self.link_for(arm)
    LINKS.fetch(arm)
  end

  def self.keys(text)
    text.scan(/%\{(\w+)\}/).flatten.map(&:to_sym)
  end
end
