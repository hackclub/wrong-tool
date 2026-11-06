# Hackatime, where hours come from. Its public stats API lists the projects someone's logged time on.
Rails.application.config.x.hackatime_url = ENV.fetch("HACKATIME_URL", "https://hackatime.hackclub.com")

# An admin API key (hka_…, credentials only: hackatime: admin_api_key), so a ship's reviewer sees Hackatime's real trust
# level for the maker, yellow included, which their own OAuth token hides from an app Hackatime hasn't verified
# (Hackatime.trust). Only ever read with, never written. Without it, the OAuth token's answer stands.
Rails.application.config.x.hackatime_admin_api_key = Rails.application.credentials.dig(:hackatime, :admin_api_key).presence
