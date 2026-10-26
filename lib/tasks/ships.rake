namespace :ships do
  # One time, the day before the deadline: Clippy DMs everyone who hasn't shipped (nothing approved or in review, so
  # someone sent back is asked again) to ship what they've got. DRY_RUN=1 lists who'd hear without sending. Nothing
  # notes who's had it, so run it once.
  #
  #   bin/rails ships:remind DRY_RUN=1
  #   bin/rails ships:remind
  desc "DM everyone who hasn't shipped to ship before the deadline"
  task remind: :environment do
    dm = "wrong tool ends %{deadline}, and *%{title}* hasn't shipped yet. If it's playable, ship it, finished or not.\n" \
         ":clippy-hopeful: clippy is holding the door open for you. :blob-wiggle:"
    dry_run = ENV["DRY_RUN"].present?
    owed = Project.where.not(id: Ship.where(status: %w[approved in_review]).select(:project_id)).includes(:user).order(:id)

    sent = owed.count do |project|
      user = project.user
      reachable = user.slack_id.present? && user.slack_muted_at.nil?
      puts format("%-20s %-30s %5.1f hrs  %s", user.public_name[0, 20], project.title[0, 30], project.hours_logged,
                  reachable ? (dry_run ? "would DM" : "DMed") : "skipped (not on Slack, or stopped Clippy)")
      if reachable && !dry_run
        user.slack_dmed!
        text = format(dm, title: project.title, deadline: project.deadline.strftime("%b %-d"))
        SlackMessageJob.perform_later(user.slack_id, text, link: [ "Ship it", "#{Rails.configuration.x.app_url}/ship" ])
      end
      reachable
    end

    puts
    puts "#{sent} of #{owed.size} #{dry_run ? "would be " : ""}DMed."
  end
end
