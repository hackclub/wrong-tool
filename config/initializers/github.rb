# GitHub, for the commits and repo behind a ship (Github, ShipEvidence). Public repos read without a token, but only
# 60 times an hour; a token (any account's, no scopes needed) gets 5,000. In credentials as github.token, or
# GITHUB_TOKEN.
Rails.application.config.x.github_token = Rails.application.credentials.dig(:github, :token) || ENV["GITHUB_TOKEN"]
