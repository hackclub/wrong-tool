# Who can see the admin pages (like /admin/nudges): Kartikey (slack.kartikey_id), plus anyone whose Slack ID is in
# admin_slack_ids in Rails credentials. In development, anyone signed in.
Rails.application.config.x.admin_slack_ids =
  (Array(Rails.application.credentials.admin_slack_ids) + [ Rails.application.credentials.dig(:slack, :kartikey_id) ]).compact_blank.uniq
