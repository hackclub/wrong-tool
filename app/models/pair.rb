# Two projects building side by side: separate games in their own wrong tools, one pair streak. You're paired by
# accepting someone's invite link (or, later, being matched). A project is in one pair at most.
class Pair < ApplicationRecord
  # A program week counts as a pair week when you each log this much in it. What pair weeks earn is in Reward::PAIR.
  WEEKLY_HOURS = 4

  belongs_to :first_project, class_name: "Project"
  belongs_to :second_project, class_name: "Project"
  has_many :pomodoros, class_name: "BuddyPomodoro", dependent: :destroy
  has_many :rewards, dependent: :destroy

  validate :two_projects_not_paired_yet, on: :create

  def self.of(project)
    where(first_project: project).or(where(second_project: project)).first
  end

  def buddy_of(project)
    project == first_project ? second_project : first_project
  end

  def projects = [ first_project, second_project ]

  # Program weeks you both logged WEEKLY_HOURS in, from the week you paired up.
  def pair_weeks(today: Date.current)
    Program::WEEKS.count do |week|
      week.end >= started_on && week.begin <= today &&
        projects.all? { |project| project.user.hours_in(week) >= WEEKLY_HOURS }
    end
  end

  # You've both logged Reward::DESKTOP_HOURS.
  def desktop_ready?
    projects.all? { |project| project.user.hours_in(Program::HACKATIME_START..) >= Reward::DESKTOP_HOURS }
  end

  def earned?(key) = rewards.any? { |reward| reward.key == key }

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
