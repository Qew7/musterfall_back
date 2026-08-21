module Sim
  module Constants
    LANE_ORDER = %w[left center right].freeze
    ROW_ORDER = %w[front support rear reserve].freeze
    BATTLE_ROWS = %w[front support rear].freeze
    STARTING_TREASURY = 36
    WIN_REWARD = 12
    BYE_REWARD = 8
    MAX_BATTLE_ROUNDS = 6
    ATTACH_SLOTS = %w[front left right rear].freeze

    WEAPON_VS_ARMOR = {
      "heavy" => { "slash" => 0.85, "blunt" => 1.35, "puncture" => 1.1, "ranged" => 0.8, "magic" => 1.0, "breath" => 1.1, "demolish" => 1.4, "fire" => 0.9, "lightning" => 1.2, "nature" => 0.9, "shadow" => 1.0, "death" => 1.15, "chaos" => 1.1 },
      "medium" => { "slash" => 1.15, "blunt" => 0.85, "puncture" => 1.0, "ranged" => 1.0, "magic" => 1.0, "breath" => 1.05, "demolish" => 1.15, "fire" => 1.0, "lightning" => 1.05, "nature" => 1.0, "shadow" => 1.05, "death" => 1.0, "chaos" => 1.05 },
      "light" => { "slash" => 1.2, "blunt" => 0.95, "puncture" => 1.1, "ranged" => 1.15, "magic" => 1.1, "breath" => 1.2, "demolish" => 1.05, "fire" => 1.2, "lightning" => 1.0, "nature" => 1.1, "shadow" => 1.1, "death" => 0.95, "chaos" => 1.1 },
      "machine" => { "slash" => 0.55, "blunt" => 1.1, "puncture" => 0.7, "ranged" => 1.0, "magic" => 1.15, "breath" => 0.8, "demolish" => 1.5, "fire" => 0.8, "lightning" => 1.35, "nature" => 0.7, "shadow" => 0.9, "death" => 0.7, "chaos" => 1.2 },
      "magic" => { "slash" => 1.0, "blunt" => 1.0, "puncture" => 1.0, "ranged" => 0.95, "magic" => 1.3, "breath" => 1.1, "demolish" => 1.05, "fire" => 1.05, "lightning" => 1.05, "nature" => 1.0, "shadow" => 1.25, "death" => 1.2, "chaos" => 1.3 }
    }.freeze
  end
end
