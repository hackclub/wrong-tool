# Sign-in with Hack Club Auth, over OpenID Connect: https://auth.hackclub.com/docs/oidc-guide
#
# Register the app at https://auth.hackclub.com/developer/apps with the redirect URI below, then set the
# client ID and secret in credentials (hack_club_auth: client_id, client_secret) or the environment.
hack_club_auth = ->(key) { Rails.application.credentials.dig(:hack_club_auth, key) || ENV["HACK_CLUB_AUTH_#{key.upcase}"] }

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :openid_connect,
    name: :hackclub,
    issuer: "https://auth.hackclub.com",
    discovery: true,
    response_type: :code,
    # What community apps may ask for. slack_id and verification_status add those claims (and ysws_eligible).
    scope: %i[openid profile email slack_id verification_status],
    client_options: {
      identifier: hack_club_auth.(:client_id),
      secret: hack_club_auth.(:client_secret),
      redirect_uri: hack_club_auth.(:redirect_uri) || "http://localhost:3000/auth/hackclub/callback"
    }
end

OmniAuth.config.logger = Rails.logger
