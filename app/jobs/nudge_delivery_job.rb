# Every 15 minutes: Clippy's nudges for everyone whose slot it is (see Nudge.deliver_due).
class NudgeDeliveryJob < ApplicationJob
  def perform
    Nudge.deliver_due
  end
end
