class Hero < ArmyTemplate
  default_scope { where(kind: "hero") }
end
