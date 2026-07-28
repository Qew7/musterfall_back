Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "api/status" => "api/status#show"
  get "api/game_catalog" => "api/game_catalog#show"
  resources :games, only: [ :create, :show ], controller: "api/games", path: "api/games" do
    member do
      post :assign_faction
      post :recruit
      post :dismiss
      post :attach_hero
      post :deploy
      post :prepare_hero_draft
      post :pick_hero_draft
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
