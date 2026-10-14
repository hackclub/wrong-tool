# Hack Club Slack's emotes, by name, so the lines about how Clippy feels (Nudge::Copy::MOODS) can show them on the
# site the way Slack shows them: a picture each. The ones the site's own lines use (:yay:, :heavysob:, …) are kept
# here as public/emotes/<name>.gif|png, saved from Slack, so they never need it; Clippy's own (:clippy-<mood>:) are
# public/clippy/<mood>.gif. Any other name is looked up in Slack's list (emoji.list; the bot needs emoji:read),
# kept for a day, with an alias ("alias:blob-yay") followed to its picture. A name nobody knows is nil, and stays
# as text.
module SlackEmoji
  CACHE_FOR = 1.day
  # If Slack couldn't be asked, ask again sooner.
  RETRY_AFTER = 5.minutes
  CLIPPY = /\Aclippy-(\w+)\z/
  BUNDLED = Rails.root.join("public/emotes").glob("*.{gif,png}").to_h { |path| [ path.basename(".*").to_s, "/emotes/#{path.basename}" ] }.freeze

  mattr_accessor :stubbed

  def self.url(name)
    if (mood = name[CLIPPY, 1]) then "/clippy/#{mood}.gif"
    else BUNDLED[name] || all[name]
    end
  end

  def self.all
    return stubbed if stubbed

    Rails.cache.read("slack_emoji/v1") || fetch.tap { |emoji| Rails.cache.write("slack_emoji/v1", emoji, expires_in: emoji.empty? ? RETRY_AFTER : CACHE_FOR) }
  end

  def self.fetch
    return {} unless Rails.configuration.x.slack_configured

    emoji = Slack::Web::Client.new.emoji_list.emoji.to_h
    emoji.transform_values { |url| url.start_with?("alias:") ? emoji[url.delete_prefix("alias:")] : url }.compact
  rescue Slack::Web::Api::Errors::SlackError, Faraday::Error => error
    Rails.logger.warn("Slack emoji list failed: #{error.message}")
    {}
  end
end
