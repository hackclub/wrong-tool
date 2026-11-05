# Lapse (https://lapse.hackclub.com), where people record a timelapse of themselves building and tie it to a Hackatime
# project. A reviewer sees the ones that match the ship's Hackatime projects (Lapse, ShipEvidence); nobody else does.
#
# It takes a program key (pk_lapse_…, with the user:read and timelapse:read scopes) to look someone up by email and
# read their timelapses, private fields and all. Ask Lapse's maintainers for one, then put it in credentials as
# lapse: program_key, or LAPSE_PROGRAM_KEY. Without it the integration does nothing at all.
Rails.application.config.x.lapse_url = ENV.fetch("LAPSE_URL", "https://lapse.hackclub.com").delete_suffix("/")
Rails.application.config.x.lapse_program_key = (Rails.application.credentials.dig(:lapse, :program_key) || ENV["LAPSE_PROGRAM_KEY"]).presence
