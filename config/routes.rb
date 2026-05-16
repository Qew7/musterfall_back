Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "api/status" => "api/status#show"
  get "api/game_catalog" => "api/game_catalog#show"
  resources :games, only: [:create, :show, :update], controller: "api/games", path: "api/games" do
    resources :battles, only: :create, controller: "api/battles", path: "battles"
    resources :round_snapshots, only: :create, controller: "api/round_snapshots", path: "round_snapshots"
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
