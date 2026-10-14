# What someone pledged at the end of onboarding (their wrong tool, idea, prize, pace and when they build),
# and how far they've got setting up to build it.
class Project < ApplicationRecord
  TOOLS = %w[spreadsheet figma email ssh shaders other].freeze
  # The console you're building for (Console), and the colour and extras you picked for it in the shop.
  PRIZES = Console.ids
  PACES = [ 20, 45, 60, 120, 180 ].freeze
  BUILD_TIMES = [ "after school", "evening", "late night", "weekends" ].freeze

  # Tools you'd play a game "over" rather than "in".
  OVER = %w[email ssh].freeze
  # Tools you'd write code in, so Hackatime's editor extension tracks them; the rest record with Lapse, which syncs to
  # Hackatime. Under Other, a tool named like code (CMake, pure CSS, git commits) counts as code too.
  CODE = %w[ssh shaders].freeze
  CODE_NAMES = /\b(c|c\+\+|cpp|rust|python|java|javascript|js|typescript|html|css|bash|zsh|shell|terminal|cmake|make|git|github|commits?|sql|lua|brainf\w*|asm|vim|neovim|emacs|cli|latex|docker|regex|yaml|json)\b/i

  SCREENSHOT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  SCREENSHOT_MAX_SIZE = 5.megabytes

  belongs_to :user
  has_many :ships, dependent: :destroy
  has_one :extension, dependent: :destroy
  has_many :seller_requests, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_one :pair_as_first, class_name: "Pair", foreign_key: :first_project_id, dependent: :destroy, inverse_of: :first_project
  has_one :pair_as_second, class_name: "Pair", foreign_key: :second_project_id, dependent: :destroy, inverse_of: :second_project
  # Shows on the leaderboard and your ship post.
  has_one_attached :screenshot

  # Renaming it to nothing puts back the name it had (your idea and tool).
  normalizes :name, with: ->(name) { name.strip.presence }
  normalizes :hackatime_projects, with: ->(names) { Array(names).map { |name| name.to_s.strip }.compact_blank.uniq }
  normalizes :prize_options, with: ->(options) { Console.picks(options) }

  validates :tool, inclusion: { in: TOOLS }
  validates :prize, inclusion: { in: PRIZES }
  # Changing console drops the colour and extras, unless the new console has them too (grey, a 128 GB card).
  before_validation :drop_picks_of_other_console, if: :will_save_change_to_prize?
  validate :prize_color_is_one_it_comes_in
  validate :prize_options_are_ones_it_offers
  validates :pace_minutes, inclusion: { in: PACES }
  validates :build_time, inclusion: { in: BUILD_TIMES }
  validates :tool_name, :idea, :signed_on, presence: true
  validates :name, length: { maximum: 80 }
  validate :screenshot_is_an_image
  validate :picking_hackatime_projects_you_have
  after_update_commit :refresh_streak, if: :saved_change_to_hackatime_projects?

  validates :repo_url, format: { with: %r{\Ahttps?://\S+\z}, message: "should be a link, like https://github.com/you/game" },
                       allow_blank: true

  # The project's name, idea or tool, or who it's by (name, email or Slack), any part of it, for the admin's list.
  def self.search(query)
    pattern = "%#{sanitize_sql_like(query)}%"
    joins(:user).where("projects.name ILIKE :q OR projects.idea ILIKE :q OR projects.tool_name ILIKE :q OR " \
                       "users.name ILIKE :q OR users.email ILIKE :q OR users.slack_display_name ILIKE :q", q: pattern)
  end

  def self.preposition_for(tool)
    OVER.include?(tool) ? "over" : "in"
  end

  # What you renamed it to, or "A rhythm game in Spreadsheet".
  def title
    name || "#{idea} #{self.class.preposition_for(tool)} #{tool_name}".upcase_first
  end

  # One build day per session of pace_minutes until the hours your pick takes are in, starting the day wrong tool
  # does (or the day you signed, if later). Building on weekends, only Saturdays and Sundays count.
  def build_days
    sessions = (hours_needed * 60.0 / pace_minutes).ceil
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
    CODE.include?(tool) || (tool == "other" && tool_name.to_s.match?(CODE_NAMES))
  end

  # The console you're building for.
  def console
    Console.find(prize)
  end

  # The colour of it you picked, or the first it comes in.
  def console_color
    console && (console.color(prize_color) || console.default_color)
  end

  # "ANBERNIC RG35XX Pro in transparent teal"
  def prize_name
    "#{console.full} in #{console_color.label}"
  end

  # The extras you picked, with the defaults for any you didn't: { "storage" => "128", "bag" => "no" }.
  def prize_choices
    console.choices_for(prize_options)
  end

  # "ANBERNIC RG35XX Pro in transparent teal, 128 GB card"
  def prize_configuration
    [ prize_name, console.extras_label(prize_options) ].compact.join(", ")
  end

  # What your pick costs, as its maker charges it (Console#price_for).
  def prize_price
    console.price_for(prize_options)
  end

  # The hours your pick takes (Console#hours_for: a promised prize is 10 as it comes; the rest is priced), and how
  # many more that is than you've built.
  def hours_needed
    console.hours_for(prize_options)
  end

  def hours_to_go
    [ (hours_needed - hours_unspent_logged).round(1), 0 ].max
  end

  # Your hours, less what you've spent, cover your pick.
  def afford?(hours = hours_logged)
    hours - hours_spent >= hours_needed
  end

  # The hours your ships got approved with: the most of any approved ship, since each counts every hour logged up to
  # it (Ship#hours), and an admin can approve fewer (Ship#approved_hours). The shop spends them like money (Order).
  def hours_approved
    ships.select(&:approved?).map { |ship| ship.approved_hours || ship.hours }.max.to_f
  end

  # What you've spent in the shop (orders made, not one being made), and what's left of your approved hours to spend.
  def hours_spent
    orders.select(&:persisted?).sum(&:hours).to_f
  end

  def hours_to_spend
    [ (hours_approved - hours_spent).round(2), 0 ].max
  end

  # The hours you've logged that haven't been spent: what's working towards the next thing.
  def hours_unspent_logged
    [ hours_logged - hours_spent, 0 ].max
  end

  # Your order for a console, if you've bought one.
  def order_for(prize_id)
    orders.find { |order| order.persisted? && order.prize == prize_id }
  end

  # What's left to spend covers your pick as it's set up, and you've not bought one already.
  def claimable?
    order_for(prize).nil? && hours_to_spend >= hours_needed
  end

  # Where your hours come from: the Hackatime editor plugin if you're writing code, Lapse recordings otherwise.
  def tracker
    code_tool? ? "hackatime" : "lapse"
  end

  def lapse_tool?
    !code_tool?
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
  # any, it's linked for you (the one with the most time, if a few did) until you keep it or change it, and Clippy
  # DMs you to say so. Returns its name if it linked one just now.
  AUTO_LINKED_DM = "Hackatime has new time from you on *%{hackatime_project}*, so it's linked to *%{title}* now. Your hours " \
                   "count from here. Not the right one? Change it on your project page.\n:clippy-proud: clippy is doing a little happy wiggle. :blob-wiggle:"

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
    dm_about_auto_link(newest.name)
    newest.name
  end

  # Hours on your linked Hackatime projects since Hackatime time started counting (Program::HACKATIME_START), to a
  # tenth, from your synced streak days: the same days your weekly hours and the leaderboard count, so they always
  # agree. Nothing until Hackatime's linked and a project picked. `refresh` brings the days up to date from Hackatime
  # first (what we last saw, if it can't be reached right now).
  def hours_logged(refresh: false)
    return 0 unless tracking?

    @hours_logged = nil if refresh
    @hours_logged ||= begin
      refresh_hours if refresh
      user.hours_in(Program::HACKATIME_START..)
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

  # When you have to ship by: wrong tool's last day, or a week on once an extension's approved.
  def deadline
    extension&.approved? ? Program::DATES.end + Program::EXTENSION_DAYS : Program::DATES.end
  end

  # wrong tool's days, for you: the program's, running on to your deadline if it moved. Nudges go by this.
  def program_dates
    Program::DATES.begin..deadline
  end

  # Ship closes at the end of the deadline where you are, plus Program::SHIP_GRACE_DAYS nobody's told about.
  def ship_cutoff
    (deadline + Program::SHIP_GRACE_DAYS).in_time_zone(user.time_zone).end_of_day
  end

  def may_ship?(now: Time.current)
    now <= ship_cutoff
  end

  # You can ask for more time once: set up, not shipped, nothing asked yet, and the deadline (where you are) still to
  # come. Not through the quiet grace days, which would give them away.
  def extension_requestable?(now: Time.current)
    set_up? && !shipped? && extension.nil? && user.local_date(now) <= deadline
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

    # A DM from Clippy's bot, if they're on Slack and haven't stopped his messages. Noted as his latest DM as it's
    # queued, so a nudge or cheer in the same minute holds off.
    def dm_about_auto_link(hackatime_project)
      return if user.slack_id.blank? || user.slack_muted_at.present?
      user.slack_dmed!
      SlackMessageJob.perform_later(user.slack_id, format(AUTO_LINKED_DM, hackatime_project:, title:),
                                    link: [ "Open wrong tool", "#{Rails.configuration.x.app_url}/project" ])
    end

    def refresh_hours
      user.sync_streak_now!
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end

    def picking_hackatime_projects_you_have
      return if @picked_hackatime_projects.nil?
      return errors.add(:hackatime_projects, "need one picked") if @picked_hackatime_projects.empty?

      unknown = @picked_hackatime_projects - hackatime_projects_was.to_a - available_hackatime_projects.to_a.map(&:name)
      errors.add(:hackatime_projects, "don't include #{unknown.to_sentence} on Hackatime") if unknown.any?
    end

    def drop_picks_of_other_console
      self.prize_color = nil unless console&.color(prize_color)
      self.prize_options = Console.picks(prize_options).select { |option, choice| console&.option(option)&.choice(choice) }
    end

    def prize_options_are_ones_it_offers
      return if console.nil? || prize_options.blank?
      unknown = console.unknown_choices(prize_options)
      errors.add(:prize_options, "include #{unknown.to_sentence}, which the #{console.name} doesn't offer") if unknown.any?
    end

    def prize_color_is_one_it_comes_in
      return if prize_color.blank? || console.nil?
      errors.add(:prize_color, "isn't one the #{console.name} comes in") unless console.color(prize_color)
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
