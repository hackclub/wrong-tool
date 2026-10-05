# PSEUDO CODE (see Nudge).
#
# Everything Clippy says in a nudge. Clippy writes in lowercase, keeps it to a line or two, and is never actually
# mean: dramatic is fine, guilt isn't. Each arm has a few variants of about the same intensity, so the bandit learns
# which framing works rather than which sentence; we rotate through them so nobody gets the same one twice in a row.
#
# %{...} fills in from Nudge::Context#vars. A variant whose values aren't there (no streak yet, too few peers) isn't
# picked.
module Nudge::Copy
  # Bandit arms.
  ARMS = {
    # How close you are to the handheld.
    "progress" => [
      "%{hours} / 10 hours on %{title}. that's ~%{sessions_left} more %{pace}-min sessions until a %{prize} shows up at your door 📎",
      "you're %{percent}%% of the way to a %{prize}. clippy did the math. clippy loves math.",
      "%{hours_left} hours left. at %{pace} minutes a session, you're done by %{finish_on}.",
      "one %{pace}-min session is %{session_percent}%% of a %{prize}. that's a lot of handheld per minute."
    ],
    # Keep it going. Only for people with a streak.
    "streak" => [
      "🔥 %{streak}-day streak on %{title}. tonight makes it %{streak_next}.",
      "clippy has noticed you've built %{streak} days in a row. clippy would hate for that to stop. (no pressure.) (some pressure.)",
      "🔥 %{streak} days. %{days_to_reward} more and you unlock: %{next_reward}.",
      "20 minutes keeps the 🔥 alive. that's like one song. (a long song.)"
    ],
    # What you told us at the pledge, in your words and at your time.
    "pledge" => [
      "it's %{local_time}. you said %{build_time}, %{pace} minutes, %{title}. clippy is just the messenger.",
      "past you signed up for this exact moment. past you had good ideas. %{title} awaits.",
      "you pledged %{pace} minutes a session. clippy pledged to remind you. clippy keeps its promises.",
      "%{build_time} o'clock. you know what that means. (it means %{title}.)"
    ],
    # Make starting easy.
    "tiny_step" => [
      "no need to finish anything tonight. open %{tool_name}, fix one thing, close it. that counts.",
      "20 minutes. one feature. clippy will be here timing you. ⏱️",
      "tiny task: make one thing in %{title} slightly less broken. that's it. that's the whole task.",
      "you don't have to feel like it. just open %{tool_name}. feeling like it usually shows up around minute 5."
    ],
    # Other people are building.
    "social" => [
      "%{peers} people building in %{tool_name} logged time today. yours is the one clippy is rooting for.",
      "%{peers} people made %{tool_name} do something it was never meant to do today. your turn.",
      "someone just shipped a game in a tool that was never meant for games. %{title} could be next.",
      "#wrong is busy today. come show them %{title}."
    ],
    # Clippy being a bit much, on purpose. Capped at Nudge::DRAMATIC_CAP per person.
    "dramatic" => [
      "clippy has been staring at your empty %{tool_name} for %{days_idle} days. clippy is fine. clippy is totally fine. 📎",
      "it looks like you're trying to win a %{prize}. would you like help with that?\n[ yes ]   [ yes, but tonight ]",
      "clippy has started telling the other paperclips about %{title}. they have questions. clippy has no answers.",
      "breaking: local paperclip refreshes your hackatime again. still nothing. more at %{local_time}."
    ]
  }.freeze

  # Nudges that always send when they apply (see Nudge::Fixed).
  FIXED = {
    # Setup, one missing step at a time.
    "hackatime" => [ "your hours don't count until hackatime's linked. clippy can't count them either. it takes 2 minutes." ],
    "repo" => [ "%{title} needs a home. add your repo link so it counts when you ship." ],

    # Milestones.
    "first_session" => [ "first session logged!! %{title} exists now. clippy is emotional." ],
    "halfway" => [ "5 hours. halfway to a %{prize}. clippy is vibrating." ],
    "done" => [ "10 HOURS. you won a %{prize}. clippy is crying. go claim it. 🎉" ],

    # Program dates. "_done" is for people who already have their 10 hours.
    "kickoff" => [ "wrong tool starts today. %{title}, %{build_time}, %{pace} minutes. clippy's ready if you are." ],
    "three_days_left" => [ "3 days left. %{hours_left} more hours and a %{prize} is yours. clippy believes in you. (clippy has to, it's a paperclip.)" ],
    "three_days_left_done" => [ "3 days left, and you already won. anything you build now is just showing off. clippy loves showing off." ],
    "last_day" => [ "last day of wrong tool. whatever %{title} is right now, ship it. clippy's proud either way." ],
    "last_day_done" => [ "last day of wrong tool. you won a %{prize} building %{title} in %{tool_name}. clippy will tell its grandchildren." ],

    # Before a streak ends.
    "streak_saver" => [ "your 🔥 %{streak} ends at midnight. 20 minutes saves it." ]
  }.freeze

  # Where each nudge's one button goes.
  LINKS = {
    "progress" => [ "see your progress", :project ],
    "streak" => [ "keep it going", :project ],
    "pledge" => [ "open your project", :project ],
    "tiny_step" => [ "start 20 minutes", :project ],
    "social" => [ "see what people built", :slack ],
    "dramatic" => [ "make clippy happy", :project ],
    "hackatime" => [ "link hackatime", :hackatime ],
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

  # Email subject per kind, plus one per bandit arm. Same within an arm, so subjects don't skew what it learns.
  SUBJECTS = {
    "progress" => "clippy did the math on %{title}",
    "streak" => "🔥 your streak",
    "pledge" => "it's %{build_time}. you know what that means.",
    "tiny_step" => "one tiny thing for tonight",
    "social" => "people are building in %{tool_name}",
    "dramatic" => "clippy is fine. totally fine.",
    "setup" => "one more thing before your hours count",
    "milestone" => "📎 !!!",
    "program" => "wrong tool",
    "streak_saver" => "your 🔥 %{streak} ends at midnight"
  }.freeze

  SLACK_MUTE = "🔕 mute clippy"
  EMAIL_FOOTER = "you're getting this because you pledged to wrong tool, a Hack Club program. " \
                 "don't want clippy in your inbox? unsubscribe: %{unsubscribe_url}"

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

  # Returns [variant, text]: the next variant this person hasn't just had.
  def self.render(nudge, vars)
    options = renderable(nudge.arm, vars)
    last = nudge.user.nudges.where(arm: nudge.arm).order(:sent_at).last&.variant
    text, variant = options.reject { |_, index| index == last }.sample || options.sample
    [ variant, format(text, **vars) ]
  end

  def self.subject_for(nudge, vars)
    format(SUBJECTS[nudge.arm] || SUBJECTS.fetch(nudge.kind), **vars)
  end

  def self.link_for(arm)
    LINKS.fetch(arm)
  end

  def self.keys(text)
    text.scan(/%\{(\w+)\}/).flatten.map(&:to_sym)
  end
end
