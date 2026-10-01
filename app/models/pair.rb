# Two projects building side by side: separate games in their own wrong tools, one pair streak. You're paired by
# accepting someone's invite link (or, later, being matched). A project is in one pair at most.
class Pair < ApplicationRecord
  # What a pair earns: by pair weeks (both hit the weekly goal), and once you've both shipped.
  REWARDS = [
    { weeks: 2, label: "2 pair weeks", reward: "Sticker sheet, mailed to both" },
    { weeks: 4, label: "4 pair weeks", reward: "+3 bonus hours each" },
    { weeks: nil, label: "Both ship", reward: "Co-op slot at Play party" }
  ].freeze

  belongs_to :first_project, class_name: "Project"
  belongs_to :second_project, class_name: "Project"
  has_many :pomodoros, class_name: "BuddyPomodoro", dependent: :destroy

  validate :two_projects_not_paired_yet, on: :create

  def self.of(project)
    where(first_project: project).or(where(second_project: project)).first
  end

  def buddy_of(project)
    project == first_project ? second_project : first_project
  end

  # The pomodoro you're doing together right now, if there is one.
  def live_pomodoro
    pomodoros.live.first.then { |pomodoro| pomodoro if pomodoro&.live? }
  end

  private
    def two_projects_not_paired_yet
      if first_project == second_project
        errors.add(:base, "You can't pair with yourself")
      elsif [ first_project, second_project ].any? { |project| Pair.of(project) }
        errors.add(:base, "One of you already has a buddy")
      end
    end
end
