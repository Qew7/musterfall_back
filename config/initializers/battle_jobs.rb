# Battle simulation job execution:
# - inline: perform_now in the request (test + default development DX)
# - async: perform_later via Solid Queue workers (production; opt-in development)
Rails.application.config.x.battle_jobs.execution_mode = :inline
