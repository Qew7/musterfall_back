module Sim
  # Rules own these contracts. Recruitment and deployment only evaluate them.
  # Demand/capacity are planning estimates, not extra combat restrictions.
  ArmySynergy = Struct.new(:consumer, :provider, :demand, :capacity, :range,
    :center_distance, :required, :benefit, keyword_init: true) do
    def consumer?(profile)
      consumer.call(profile)
    end

    def provider?(profile)
      provider.call(profile)
    end

    def demand_for(profile)
      consumer?(profile) ? (demand ? demand.call(profile) : 1.0) : 0.0
    end

    def capacity_for(profile)
      provider?(profile) ? capacity.call(profile) : 0.0
    end

    def benefits?(user, source)
      consumer?(user) && provider?(source) && (!benefit || benefit.call(user, source))
    end

    def placement(user, source)
      return unless benefits?(user, source)

      [ range.call(source), center_distance ]
    end
  end
end
