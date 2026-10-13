namespace :streaks do
  # One time: streak days synced while a linked Hackatime project with a comma in its name matched nothing (the
  # spans filter split on commas) stay at zero, since a sync only rewrites days from the day before the last one.
  # Rebuilds every day from the start for everyone with such a project.
  #
  #   bin/rails streaks:rebuild_comma_projects
  desc "Rebuild streaks for everyone with a comma in a linked Hackatime project's name"
  task rebuild_comma_projects: :environment do
    users = User.joins(:project).where.not(hackatime_uid: nil).select { |user| user.project.hackatime_projects.any? { |name| name.include?(",") } }
    users.each(&:refresh_streak!)
    puts "queued a rebuild for #{users.size} #{"user".pluralize(users.size)}"
  end
end
