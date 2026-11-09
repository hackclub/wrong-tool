# Airtable, where every decided ship goes for Hack Club's Unified YSWS (ShipSubmission): the "YSWS - Wrong" base's
# YSWS Project Submission table. It takes a personal access token with data.records:read and data.records:write on that
# base: put it in credentials as airtable: api_key, or AIRTABLE_API_KEY. Without it nothing's sent.
# AIRTABLE_BASE_ID and AIRTABLE_TABLE_ID only for another base.
airtable = ->(key) { Rails.application.credentials.dig(:airtable, key) || ENV["AIRTABLE_#{key.upcase}"] }
Rails.application.config.x.airtable_api_key = airtable.(:api_key).presence
Rails.application.config.x.airtable_base_id = airtable.(:base_id).presence || "appz5aSVO8OW3U3mG"
Rails.application.config.x.airtable_table_id = airtable.(:table_id).presence || "tblbzqNUnURxnpeC0"
