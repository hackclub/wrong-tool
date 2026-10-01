# What someone pledged at the end of onboarding (their wrong tool, idea, prize, pace and when they build),
# and how far they've got setting up to build it.
class Project < ApplicationRecord
  TOOLS = %w[spreadsheet figma email ssh shaders other].freeze
  PRIZES = %w[rg35xx miyoo].freeze
  PACES = [ 20, 45, 60, 120, 180 ].freeze
  BUILD_TIMES = [ "after school", "evening", "late night", "weekends" ].freeze
  TRACKERS = %w[hackatime].freeze

  # Tools you'd play a game "over" rather than "in".
  OVER = %w[email ssh].freeze
  # Tools you'd write code in, so Hackatime's editor extension tracks them; the rest record with Lapse, which syncs to
  # Hackatime.
  CODE = %w[ssh shaders].freeze

  SCREENSHOT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  SCREENSHOT_MAX_SIZE = 5.megabytes

  belongs_to :user
  has_many :ships, dependent: :destroy
  # Shows on the leaderboard and your ship post.
  has_one_attached :screenshot

  # Renaming it to nothing puts back the name it had (your idea and tool).
  normalizes :name, with: ->(name) { name.strip.presence }
  normalizes :hackatime_projects, with: ->(names) { Array(names).map { |name| name.to_s.strip }.compact_blank.uniq }

  validates :tool, inclusion: { in: TOOLS }
  validates :prize, inclusion: { in: PRIZES }
  validates :pace_minutes, inclusion: { in: PACES }
  validates :build_time, inclusion: { in: BUILD_TIMES }
  validates :tracker, inclusion: { in: TRACKERS }, allow_nil: true
  validates :tool_name, :idea, :signed_on, presence: true
  validates :name, length: { maximum: 80 }
  validate :screenshot_is_an_image
  validate :linking_a_hackatime_project_you_have
  validates :repo_url, format: { with: %r{\Ahttps?://\S+\z}, message: "should be a link, like https://github.com/you/game" },
                       allow_blank: true

  def self.preposition_for(tool)
    OVER.include?(tool) ? "over" : "in"
  end

  # What you renamed it to, or "A rhythm game in Spreadsheet".
  def title
    name || "#{idea} #{self.class.preposition_for(tool)} #{tool_name}".upcase_first
  end

  # One build day per session of pace_minutes until the hours are in, starting the day wrong tool does (or the
  # day you signed, if later). Building on weekends, only Saturdays and Sundays count.
  def build_days
    sessions = (Program::HOURS_PER_REWARD * 60.0 / pace_minutes).ceil
    day = [ Program::DATES.begin, signed_on ].max
    days = []
    until days.size == sessions
      days << day if build_time != "weekends" || day.on_weekend?
      day += 1
    end
    days
  end

  def finish_on
    build_days.last
  end

  def code_tool?
    CODE.include?(tool)
  end

  # Setting up, in order: link Hackatime, then which Hackatime project this is, join the Slack channel, add a repo
  # (or say you'll add it before you ship) and post your idea (or skip it).
  SETUP_STEPS = %w[hackatime hackatime_project slack repo idea].freeze
  # You're set up once your hours count and you're in the channel; the repo and your idea post can wait.
  REQUIRED_STEPS = SETUP_STEPS.first(3).freeze

  def step_done?(step)
    case step
    when "hackatime" then tracker.present?
    when "hackatime_project" then hackatime_projects.any?
    when "slack" then slack_joined?
    when "repo" then (repo_url.present? && errors[:repo_url].none?) || repo_later?
    when "idea" then idea_posted? || idea_skipped?
    end
  end

  # The Hackatime project needs Hackatime linked first.
  def step_locked?(step)
    step == "hackatime_project" && tracker.blank?
  end

  # Steps you can still open: anything not done, the Hackatime projects (to change which are linked) and the repo
  # while it's only promised for later.
  def step_open?(step)
    SETUP_STEPS.include?(step) && !step_locked?(step) &&
      (!step_done?(step) || step == "hackatime_project" || (step == "repo" && repo_url.blank?))
  end

  def required_steps_done
    REQUIRED_STEPS.count { |step| step_done?(step) }
  end

  def optional_steps_left
    (SETUP_STEPS - REQUIRED_STEPS).count { |step| !step_done?(step) }
  end

  def set_up?
    required_steps_done == REQUIRED_STEPS.size
  end

  # Hours count once Hackatime knows which project this is.
  def tracking?
    tracker.present? && hackatime_projects.any?
  end

  # The Hackatime projects you can link: the ones Hackatime says you've logged time on. Set before linking one.
  attr_accessor :available_hackatime_projects

  # Linking one more Hackatime project, picked from the ones you have.
  def link_hackatime_project=(name)
    @linking_hackatime_project = name.to_s.strip
    self.hackatime_projects = hackatime_projects + [ @linking_hackatime_project ]
  end

  def unlink_hackatime_project=(name)
    self.hackatime_projects = hackatime_projects - [ name.to_s ]
  end

  # Hours and streaks come from Hackatime, which isn't wired up yet: until it is, nobody's logged anything.
  def hours_logged = 0
  def hours_this_week = 0
  def streak = 0

  # In the Hall of Wrong once a ship's approved.
  def shipped?
    ships.any? { |ship| ship.status == "approved" }
  end

  def ship_in_review
    ships.in_review.order(:created_at).last
  end

  # Shipping: what you submit becomes your project's name and repo too, and the screenshot you pick (or the one you
  # had) is kept with the ship.
  def ship!(params)
    upload = params.delete(:screenshot)
    ship = ships.build(params.merge(hackatime_projects:, hours: hours_logged))
    if upload.present? then ship.screenshot.attach(upload)
    elsif screenshot.attached? then ship.screenshot.attach(screenshot.blob)
    end

    if ship.save
      screenshot.attach(ship.screenshot.blob) if upload.present?
      update!(name: ship.title, repo_url: ship.repo_url)
    end
    ship
  end

  private
    def linking_a_hackatime_project_you_have
      return if @linking_hackatime_project.nil?

      if @linking_hackatime_project.blank?
        errors.add(:hackatime_projects, "need one picked")
      elsif !available_hackatime_projects.to_a.map(&:name).include?(@linking_hackatime_project)
        errors.add(:hackatime_projects, "don't include #{@linking_hackatime_project} on Hackatime")
      end
    end

    def screenshot_is_an_image
      return unless screenshot.attached?

      if !SCREENSHOT_TYPES.include?(screenshot.blob.content_type)
        errors.add(:screenshot, "should be a PNG, JPEG, WebP or GIF")
      elsif screenshot.blob.byte_size > SCREENSHOT_MAX_SIZE
        errors.add(:screenshot, "should be under 5 MB")
      end
    end
end
