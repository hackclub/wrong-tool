namespace :ships do
  # One time, the day before the deadline: Clippy DMs everyone who hasn't shipped (nothing approved, in review or
  # rejected, so someone asked for changes is asked again) to ship what they've got. DRY_RUN=1 lists who'd hear without sending. Nothing
  # notes who's had it, so run it once.
  #
  #   bin/rails ships:remind DRY_RUN=1
  #   bin/rails ships:remind
  desc "DM everyone who hasn't shipped to ship before the deadline"
  task remind: :environment do
    dm = "wrong tool ends %{deadline}, and *%{title}* hasn't shipped yet. If it's playable, ship it, finished or not.\n" \
         ":clippy-hopeful: clippy is holding the door open for you. :blob-wiggle:"
    dry_run = ENV["DRY_RUN"].present?
    owed = Project.where.not(id: Ship.where(status: %w[approved in_review rejected]).select(:project_id)).includes(:user).order(:id)

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

  # Last call, after shipping closed: Clippy DMs everyone who never shipped (nothing approved, in review or rejected)
  # but logged an hour or more that shipping's open for them again, through Program::LAST_CALL_THROUGH. Noted on the project
  # (last_call_dmed_at), so running it twice sends nothing new. DRY_RUN=1 lists who'd hear without sending.
  #
  #   bin/rails ships:last_call DRY_RUN=1
  #   bin/rails ships:last_call
  desc "DM everyone who never shipped that shipping's open again for last call"
  task last_call: :environment do
    dm = "Shipping's open again for anyone who didn't make it. *%{title}* can ship until the end of %{until}, " \
         "finished or not. If it plays, ship it.\n:clippy-hopeful: clippy propped the door back open for you. :blob-wiggle:"
    dry_run = ENV["DRY_RUN"].present?
    owed = Project.where(last_call_dmed_at: nil)
                  .where.not(id: Ship.where(status: %w[approved in_review rejected]).select(:project_id))
                  .includes(:user).order(:id)
                  .select { |project| project.hours_logged >= 1 }

    sent = owed.count do |project|
      user = project.user
      reachable = user.slack_id.present? && user.slack_muted_at.nil?
      puts format("%-20s %-30s %5.1f hrs  %s", user.public_name[0, 20], project.title[0, 30], project.hours_logged,
                  reachable ? (dry_run ? "would DM" : "DMed") : "skipped (not on Slack, or stopped Clippy)")
      if reachable && !dry_run
        user.slack_dmed!
        project.update_column(:last_call_dmed_at, Time.current)
        text = format(dm, title: project.title, until: Program::LAST_CALL_THROUGH.strftime("%b %-d"))
        SlackMessageJob.perform_later(user.slack_id, text, link: [ "Ship it", "#{Rails.configuration.x.app_url}/ship" ])
      end
      reachable
    end

    puts
    puts "#{sent} of #{owed.size} #{dry_run ? "would be " : ""}DMed."
  end

  # Resync for every ship waiting in review or on the fraud check (ShipEvidence.request_waiting): its evidence gathered
  # again in the background, say once Hackatime's trust level comes in. DRY_RUN=1 lists them without asking.
  #
  #   bin/rails ships:resync DRY_RUN=1
  #   bin/rails ships:resync
  desc "Gather the evidence again for every ship waiting on a review or the fraud check"
  task resync: :environment do
    if ENV["DRY_RUN"].present?
      ships = Ship.in_review.includes(project: :user).order(:id)
      ships.each { |ship| puts format("#%-6d %-30s %s", ship.id, ship.title[0, 30], ship.project.user.public_name) }
      puts "\n#{ships.size} would be gathered again."
    else
      puts "#{ShipEvidence.request_waiting.size} gathered again in the background."
    end
  end
end
