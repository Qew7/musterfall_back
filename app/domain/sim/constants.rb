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
      "heavy" => { "slash" => 0.85, "blunt" => 1.35, "puncture" => 1.1, "ranged" => 0.8, "magic" => 1.0, "breath" => 1.1, "demolish" => 1.4 },
      "medium" => { "slash" => 1.15, "blunt" => 0.85, "puncture" => 1.0, "ranged" => 1.0, "magic" => 1.0, "breath" => 1.05, "demolish" => 1.15 },
      "light" => { "slash" => 1.2, "blunt" => 0.95, "puncture" => 1.1, "ranged" => 1.15, "magic" => 1.1, "breath" => 1.2, "demolish" => 1.05 },
      "machine" => { "slash" => 0.55, "blunt" => 1.1, "puncture" => 0.7, "ranged" => 1.0, "magic" => 1.15, "breath" => 0.8, "demolish" => 1.5 },
      "magic" => { "slash" => 1.0, "blunt" => 1.0, "puncture" => 1.0, "ranged" => 0.95, "magic" => 1.3, "breath" => 1.1, "demolish" => 1.05 }
    }.freeze
  end
end
