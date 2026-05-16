class Unit < ArmyTemplate
  default_scope { where(kind: "unit") }
end