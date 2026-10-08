# Clippy cheering someone on, right after they've built: the moment a sync (StreakActivity) shows a streak day
# crossing its 20 minutes, a cheer is queued (NudgeCheerJob) and sent then, or first thing in the morning if it's
# late. One per day at most, and never counted against the slot nudges' weekly cap: these are earned.
#
# The bandit picks how Clippy cheers (its "cheer" bucket), and learns from whether they come back and build
# 20 minutes the next day (Nudge#window), so it finds the cheer that gets people building again rather than the
# one that reads nicest.
module Nudge::Cheer
  BUCKET = "cheer"

  def self.queue(user, built_on)
    NudgeCheerJob.perform_later(user.id, built_on)
  end

  # Their cheer for that day, if it's still due.
  def self.deliver(context)
    return unless context.may_cheer?

    nudge = Nudge::Bandit.nudge_for(context, kind: "cheer", bucket: BUCKET) or return
    nudge.built_on = context.built_on
    nudge.deliver!(context.vars)
    nudge
  end
end
