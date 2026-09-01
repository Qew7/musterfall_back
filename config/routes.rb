Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "api/status" => "api/status#show"
  get "api/game_catalog" => "api/game_catalog#show"
  namespace :api do
    namespace :admin do
      get "balance" => "balance#show"
      get "balance/units" => "balance#units"
      post "balance/backfill" => "balance#backfill"
      post "balance/simulations" => "balance#start_simulation"
      post "balance/simulations/stop" => "balance#stop_all_simulations"
      post "balance/simulations/:id/stop" => "balance#stop_simulation"
      post "balance/duels" => "balance#run_duel"
      post "balance/duel_matrix" => "balance#start_duel_matrix"
      post "balance/duel_matrix/:id/stop" => "balance#stop_duel_matrix"
    end
  end
  resources :games, only: [ :create, :show ], controller: "api/games", path: "api/games" do
    member do
      post :assign_faction
      post :recruit
      post :dismiss
      post :attach_hero
      post :deploy
      post :prepare_hero_draft
      post :pick_hero_draft
      post :upgrade_access
      post :restore_unit
      post :prepare_round
      post :advance_round
    end
    resources :battles, only: :create, controller: "api/battles", path: "battles" do
      collection do
        post :replay
      end
    end
    resources :round_snapshots, only: :create, controller: "api/round_snapshots", path: "round_snapshots"
  end
end
