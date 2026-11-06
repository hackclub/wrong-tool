# Lapse (https://lapse.hackclub.com), where people record a timelapse of themselves building and tie it to a Hackatime
# project. A reviewer sees the ones for the ship's Hackatime projects (Lapse, ShipEvidence); nobody else does.
#
# It takes a program key (pk_lapse_…, with the timelapse:read scope), which is what shows us someone's unlisted
# timelapses too. Lapse's maintainers issue them. Put it in credentials as lapse: program_key, or LAPSE_PROGRAM_KEY.
# Without it the integration does nothing at all. LAPSE_URL and LAPSE_API_URL only for a local Lapse.
Rails.application.config.x.lapse_url = ENV.fetch("LAPSE_URL", "https://lapse.hackclub.com").delete_suffix("/")
Rails.application.config.x.lapse_api_url = ENV.fetch("LAPSE_API_URL", "https://api.lapse.hackclub.com").delete_suffix("/")
Rails.application.config.x.lapse_program_key = (Rails.application.credentials.dig(:lapse, :program_key) || ENV["LAPSE_PROGRAM_KEY"]).presence
