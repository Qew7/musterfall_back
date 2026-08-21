module Sim
  module Campaign
    module MagicLoadout
      module_function

      def build(template:, faction_id:, school_key:, rng:)
        wizard = template[:abilities].include?("wizard")
        return Result.failure("magic school is only valid for wizards") if !wizard && school_key.present?
        return Result.ok({}) unless wizard
        return Result.failure("magic school required") if school_key.blank?

        key = school_key.to_s
        available = Battle::Spells.schools_for(faction_id).map(&:to_s)
        return Result.failure("magic school unavailable for faction") unless available.include?(key)

        pool = Battle::Spells.spell_keys(key).map(&:to_s).uniq
        return Result.failure("magic school requires at least two spells") if pool.length < 2

        Result.ok(magic_school: key, spell_keys: 2.times.map { pool.delete_at(rng.rand(pool.length)) })
      end
    end
  end
end
