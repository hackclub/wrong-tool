# Someone signed in with Hack Club Auth. hca_id is their HCA subject (ident!…); everything else is copied
# from HCA's claims each time they sign in, so it stays current.
class User < ApplicationRecord
  include Streakable

  has_one :project, dependent: :destroy
  has_many :nudges, dependent: :destroy

  # Linking Hackatime gives us their Hackatime ID and a token that reads their projects and hours.
  encrypts :hackatime_access_token

  validates :hca_id, presence: true, uniqueness: true
  validates :hackatime_uid, uniqueness: { message: "is already linked to someone else here" }, allow_nil: true

  # Streak days run 2am to 2am local, so they're counted again in the new timezone.
  after_update_commit :refresh_streak!, if: -> { saved_change_to_timezone? && project&.tracking? }

  # Your picture: an animal on a colour, like Google Sheets' anonymous animals, picked from your Hack Club ID so it's
  # always the same one. (Silhouettes from Microsoft's Fluent Emoji, MIT: app/assets/images/animals.)
  ANIMALS = %w[fox cat dog panda koala tiger frog owl penguin rabbit hamster otter sloth raccoon turtle octopus hedgehog
               llama chipmunk beaver duck whale unicorn sauropod].freeze
  AVATAR_COLORS = %w[#ec3750 #1a73e8 #1e7b45 #b06000 #8430ce #00796b #c62828 #3949ab #e8710a #d01884 #0b8043 #5f6368].freeze

  def animal
    ANIMALS[avatar_seed % ANIMALS.size]
  end

  def avatar_color
    AVATAR_COLORS[avatar_seed / ANIMALS.size % AVATAR_COLORS.size]
  end

  def hackatime_linked?
    hackatime_uid.present? && hackatime_access_token.present?
  end

  # Your timezone (IANA, like "America/New_York"), from your browser whenever it says something different, so it
  # follows you when you travel. Anything that isn't a real timezone is ignored.
  def remember_timezone(name)
    name = TZInfo::Timezone.get(name.to_s).identifier
    update!(timezone: name) unless timezone == name
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  # "stop these messages" in one of Clippy's DMs (that nudge counts against what it said), and changing your mind.
  def mute_slack!(nudge)
    transaction do
      update!(slack_muted_at: Time.current) unless slack_muted_at
      nudge.update!(opted_out_at: Time.current) unless nudge.opted_out_at
    end
  end

  def unmute_slack!(nudge)
    transaction do
      update!(slack_muted_at: nil)
      nudge.update!(opted_out_at: nil)
    end
  end

  def admin?
    Rails.env.development? || (slack_id.present? && Rails.configuration.x.admin_slack_ids.include?(slack_id))
  end

  # Used by posthog-rails to associate automatic exception reports with this user.
  def posthog_distinct_id
    id.to_s
  end

  # Profile data belongs to the PostHog person, rather than event properties.
  def posthog_properties
    {
      email: email,
      name: name,
      verification_status: verification_status,
      ysws_eligible: ysws_eligible,
      timezone: timezone
    }
  end

  def self.from_omniauth(auth)
    claims = auth.extra.raw_info.to_h.with_indifferent_access
    find_or_initialize_by(hca_id: auth.uid).tap do |user|
      user.update!(
        email: auth.info.email,
        name: auth.info.name,
        first_name: auth.info.first_name,
        slack_id: claims[:slack_id],
        verification_status: claims[:verification_status],
        ysws_eligible: claims[:ysws_eligible] || false
      )
    end
  end

  private
    def avatar_seed
      @avatar_seed ||= Digest::SHA256.hexdigest(hca_id.to_s).first(12).to_i(16)
    end
end
