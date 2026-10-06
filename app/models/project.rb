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
  has_one :pair_as_first, class_name: "Pair", foreign_key: :first_project_id, dependent: :destroy, inverse_of: :first_project
  has_one :pair_as_second, class_name: "Pair", foreign_key: :second_project_id, dependent: :destroy, inverse_of: :second_project
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
  after_update_commit :refresh_streak, if: :saved_change_to_hackatime_projects?

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

  # Which day of building it is: 1 on the first, counting up from there.
  def day_number(today: Date.current)
    [ (today - build_days.first).to_i + 1, 1 ].max
  end

  def code_tool?
    CODE.include?(tool)
  end

  # Setting up, in order: link Hackatime, then which Hackatime project this is, add a repo (or say you'll add it before
  # you ship) and bring a buddy (or skip it). Everyone's added to #wrong on Slack for them.
  SETUP_STEPS = %w[hackatime hackatime_project repo buddy].freeze
  # You're set up once Hackatime's linked. Which Hackatime project this is can wait: with nothing on Hackatime since it
  # started counting there's nothing to pick yet, and the first new project you log time on links itself
  # (auto_link_hackatime_project). The repo and a buddy can wait too.
  REQUIRED_STEPS = %w[hackatime].freeze

  def step_done?(step)
    case step
    when "hackatime" then hackatime_linked?
    when "hackatime_project" then hackatime_projects.any?
    when "repo" then (repo_url.present? && errors[:repo_url].none?) || repo_later?
    when "buddy" then buddy.present? || buddy_invited? || buddy_skipped?
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
      (!step_done?(step) || step == "hackatime_project" || (step == "repo" && repo_url.blank?) || (step == "buddy" && buddy.nil?))
  end

  def required_steps_done
    REQUIRED_STEPS.count { |step| step_done?(step) }
  end

  # Optional steps you haven't done, put off or skipped (a Hackatime project with nothing to pick yet isn't one).
  def optional_steps_left
    (SETUP_STEPS - REQUIRED_STEPS).count { |step| !step_settled?(step) }
  end

  # What setup needs: Hackatime linked. That's what unlocks shipping and the leaderboard.
  def set_up?
    required_steps_done == REQUIRED_STEPS.size
  end

  # You've been through every step: done, put off or skipped. Until then your project page walks you through them,
  # one at a time, and once you're through it turns into your schedule (and Clippy congratulates you).
  def setup_finished?
    set_up? && SETUP_STEPS.all? { |step| step_settled?(step) }
  end

  # Done, or (your Hackatime project) nothing to pick yet, since it links itself.
  def step_settled?(step)
    step_done?(step) || (step == "hackatime_project" && waiting_for_hackatime_project?)
  end

  # Hours count once Hackatime knows which project this is.
  def tracking?
    hackatime_linked? && hackatime_projects.any?
  end

  # Hackatime's linked but has nothing since it started counting to pick from, so the first project you log time on
  # will link itself. Only known once available_hackatime_projects has been asked for.
  def waiting_for_hackatime_project?
    hackatime_linked? && hackatime_projects.none? && available_hackatime_projects&.none?
  end

  def pair
    pair_as_first || pair_as_second
  end

  # Who you're building alongside, if anyone.
  def buddy
    pair&.buddy_of(self)
  end

  # A new invite code: random, so the link says nothing about who you are.
  def self.new_buddy_code
    loop do
      code = SecureRandom.alphanumeric(8).downcase
      return code unless exists?(buddy_code: code)
    end
  end

  # Your invite link's code (/b/<code>), made the first time it's asked for.
  def buddy_code!
    return buddy_code if buddy_code.present?

    code = self.class.new_buddy_code
    update_column(:buddy_code, code) # just the code: whatever else is mid-edit (and maybe invalid) isn't saved
    code
  end

  # Pairs you up with another project, if neither of you has a buddy yet. Returns the pair: saved, or with why not.
  def pair_with(other)
    Pair.create(first_project: other, second_project: self, started_on: Date.current)
  end

  # Linking Hackatime is yours, not the project's: it's who you are on Hackatime.
  def hackatime_linked?
    user.hackatime_linked?
  end

  # The Hackatime projects you can link: the ones Hackatime says you've logged time on. Set before linking one (and
  # on your project page, while you haven't).
  attr_accessor :available_hackatime_projects

  # The Hackatime projects you ticked: these become the linked ones. Any you hadn't linked before have to be
  # ones Hackatime has.
  def hackatime_project_names=(names)
    names = Array(names).map { |name| name.to_s.strip }.compact_blank.uniq
    @picked_hackatime_projects = names
    self.hackatime_projects = names
    self.hackatime_auto_linked = false
  end

  # Your first new Hackatime project links itself. The first time we look after you link Hackatime, we note the
  # projects you already have there (that's all this does then); if one you didn't have shows up before you've picked
  # any, it's linked for you (the one with the most time, if a few did) until you keep it or change it. Returns its
  # name if it linked one just now.
  def auto_link_hackatime_project(available)
    return unless hackatime_linked? && hackatime_projects.none?

    if hackatime_baseline.nil?
      update_columns(hackatime_baseline: available.map(&:name))
      return
    end

    newest = available.reject { |project| hackatime_baseline.include?(project.name) }.select { |project| project.seconds.positive? }
                      .max_by(&:seconds)
    return unless newest

    update_columns(hackatime_projects: [ newest.name ], hackatime_auto_linked: true)
    refresh_streak
    newest.name
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

  # This program week (Program::WEEKS), as of the last streak sync. Nothing outside the program.
  def hours_this_week(today: user.streak_today_date)
    (week = Program.week_of(today)) ? user.hours_in(week) : 0
  end

  # As of the last sync (see User::Streakable).
  def streak = user.current_streak

  # Once a ship's approved.
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
    def refresh_streak
      user.refresh_streak!
    end

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
