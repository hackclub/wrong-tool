# What someone pledged at the end of onboarding (their wrong tool, idea, prize, pace and when they build),
# and how far they've got setting up to build it.
class Project < ApplicationRecord
  TOOLS = %w[spreadsheet figma email ssh shaders other].freeze
  PRIZES = %w[rg35xx miyoo].freeze
  PACES = [ 20, 45, 60, 120, 180 ].freeze
  BUILD_TIMES = [ "after school", "evening", "late night", "weekends" ].freeze

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
  validates :tool_name, :idea, :signed_on, presence: true
  validates :name, length: { maximum: 80 }
  validate :screenshot_is_an_image
  validate :picking_hackatime_projects_you_have
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
    when "hackatime" then hackatime_linked?
    when "hackatime_project" then hackatime_projects.any?
    when "slack" then slack_joined?
    when "repo" then (repo_url.present? && errors[:repo_url].none?) || repo_later?
    when "idea" then idea_posted? || idea_skipped?
    end
  end

  # The Hackatime project needs Hackatime linked first.
  def step_locked?(step)
    step == "hackatime_project" && !hackatime_linked?
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
    hackatime_linked? && hackatime_projects.any?
  end

  # Linking Hackatime is yours, not the project's: it's who you are on Hackatime.
  def hackatime_linked?
    user.hackatime_linked?
  end

  # The Hackatime projects you can link: the ones Hackatime says you've logged time on. Set before linking one.
  attr_accessor :available_hackatime_projects

  # The Hackatime projects you ticked: these become the linked ones. Any you hadn't linked before have to be
  # ones Hackatime has.
  def hackatime_project_names=(names)
    names = Array(names).map { |name| name.to_s.strip }.compact_blank.uniq
    @picked_hackatime_projects = names
    self.hackatime_projects = names
  end

  # Hours on your linked Hackatime projects since Hackatime time started counting (Program::HACKATIME_START), to a
  # tenth. Nothing if Hackatime isn't linked or can't be reached right now. `refresh` asks Hackatime again.
  def hours_logged(refresh: false)
    @hours_logged = nil if refresh
    @hours_logged ||= begin
      seconds = tracking? ? Hackatime.projects(user, refresh:).select { |project| hackatime_projects.include?(project.name) }.sum(&:seconds) : 0
      (seconds / 3600.0).round(1)
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      0
    end
  end

  # Weekly hours and streaks aren't wired up to Hackatime yet: until they are, they're nothing.
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
    def picking_hackatime_projects_you_have
      return if @picked_hackatime_projects.nil?
      return errors.add(:hackatime_projects, "need one picked") if @picked_hackatime_projects.empty?

      unknown = @picked_hackatime_projects - hackatime_projects_was.to_a - available_hackatime_projects.to_a.map(&:name)
      errors.add(:hackatime_projects, "don't include #{unknown.to_sentence} on Hackatime") if unknown.any?
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
