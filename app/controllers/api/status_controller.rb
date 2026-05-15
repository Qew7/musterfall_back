module Api
  class StatusController < ApplicationController
    def show
      render json: {
        name: "Musterfall",
        status: "ok",
        server_time: Time.current.iso8601,
        services: {
          api: true,
          database: database_available?
        }
      }
    end

    private

    def database_available?
      ActiveRecord::Base.connection.active?
    rescue ActiveRecord::ActiveRecordError
      false
    end
  end
end