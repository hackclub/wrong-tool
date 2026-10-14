Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
  get "start" => "onboarding#show", as: :onboarding
  resource :project, only: %i[show create update] do
    resource :ship, only: %i[show create]
    resource :extension, only: :create
    get :hours
    resource :streak, only: :update
  end
  resource :leaderboard, only: :show
  # The consoles you can build for: changing which one's yours, and its colour, and asking for one from another
  # seller (to save on customs).
  resource :shop, only: %i[show update], controller: "shop" do
    resources :seller_requests, only: :create
    # Claiming your pick with your approved hours.
    resource :order, only: :create
  end
  # wrong tool in numbers, for anyone: totals only, never anyone on their own (PublicStats).
  get "stats" => "stats#show", as: :stats
  resource :buddy, only: :show do
    # A pomodoro together: start one, see how it's going (polled), and join your buddy's.
    resource :pomodoro, only: %i[show create], controller: "buddy_pomodoros" do
      post :join
    end
  end
  # Someone's buddy invite: see who wants to build with you, and accept.
  get "b/:code" => "buddy_invites#show", as: :buddy_invite
  post "b/:code" => "buddy_invites#accept"

  # The links in Clippy's messages: the button (tracked, then on to where it says), and stopping his messages.
  get "n/:token" => "nudge_links#show", as: :nudge_link
  get "n/:token/stop" => "nudge_links#stop", as: :nudge_stop
  post "n/:token/stop" => "nudge_links#mute"
  delete "n/:token/stop" => "nudge_links#unmute"

  # How Clippy's nudges are doing, and what the bandit's learned, wrong tool's numbers day by day, everyone who's
  # signed in, with seeing the site as any of them, who's asked for more time to ship or for another seller, and every ship in full, to
  # approve or send back. Admins only.
  namespace :admin do
    # Every admin page, and what's waiting on an admin.
    root "home#show"
    resources :nudges, only: :index
    resources :metrics, only: :index
    resources :extensions, only: %i[index update]
    resources :seller_requests, only: %i[index update]
    resources :orders, only: %i[index update]
    resources :ships, only: %i[index show update]
    resources :projects, only: %i[index show]
    resources :users, only: :index do
      resource :impersonation, only: :create
    end
    # Stopping has to work while you're someone who isn't an admin.
    resource :impersonation, only: :destroy
  end

  # SQL against the database (config/blazer.yml). Anyone who isn't an admin, or is viewing as someone, gets a not
  # found, as with the admin pages.
  constraints ->(request) { User.find_by(id: request.session[:user_id])&.admin? } do
    mount Blazer::Engine, at: "admin/blazer"
  end

  # Hack Club Auth. Signing in is a POST to /auth/hackclub (OmniAuth's middleware), which comes back here.
  # Linking Hackatime comes back here; it doesn't sign you in.
  get "auth/hackatime/callback" => "hackatime_links#create", as: :hackatime_link_callback
  get "auth/:provider/callback" => "sessions#create", as: :auth_callback
  get "auth/failure" => "sessions#failure", as: :auth_failure
  delete "logout" => "sessions#destroy", as: :logout
end
