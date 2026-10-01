Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
  get "start" => "onboarding#show", as: :onboarding
  resource :project, only: %i[show create update] do
    resource :ship, only: %i[show create]
    get :hours
  end
  resource :leaderboard, only: :show
  get "hall" => "halls#show", as: :hall

  # Hack Club Auth. Signing in is a POST to /auth/hackclub (OmniAuth's middleware), which comes back here.
  # Linking Hackatime comes back here; it doesn't sign you in.
  get "auth/hackatime/callback" => "hackatime_links#create", as: :hackatime_link_callback
  get "auth/:provider/callback" => "sessions#create", as: :auth_callback
  get "auth/failure" => "sessions#failure", as: :auth_failure
  delete "logout" => "sessions#destroy", as: :logout
end
