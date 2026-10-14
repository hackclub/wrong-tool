# What the shop would cost, from everyone's hours right now: whose hours cover their pick (a promised prize at 10
# hours, the rest priced), what those picks cost us, and the total against what the old deal (a handheld at 10
# hours, +$85 at 20) would have cost on the same hours. HANDHELD=65 is the old deal's average console cost,
# shipping included; change it to taste.
#
#   bin/rails shop:forecast
namespace :shop do
  desc "Cost of everyone's picks at today's hours, against the old 10-hour deal"
  task forecast: :environment do
    handheld = ENV.fetch("HANDHELD", 65).to_f
    seconds = StreakActivity.where(activity_date: Program::HACKATIME_START..).group(:user_id).sum(:coded_seconds)

    rows = Project.includes(:user).map do |project|
      hours = (seconds.fetch(project.user_id, 0) / 3600.0).round(1)
      { name: project.user.public_name, hours:, needed: project.hours_needed, pick: project.console.name, price: project.prize_price,
        afford: project.afford?(hours), old: (hours >= 10 ? handheld : 0) + (hours >= 20 ? 85 : 0) }
    end

    puts format("%-14s %6s %7s  %-12s %7s  %s", "who", "hours", "needs", "pick", "price", "")
    rows.sort_by { |row| -row[:hours] }.each do |row|
      puts format("%-14s %6.1f %7.1f  %-12s %7s  %s", row[:name][0, 14], row[:hours], row[:needed], row[:pick],
                  "$#{row[:price]}", row[:afford] ? "covered" : "")
    end

    new_cost = rows.select { |row| row[:afford] }.sum { |row| row[:price] }
    old_cost = rows.sum { |row| row[:old] }
    puts
    puts "#{rows.count { |row| row[:afford] }} of #{rows.size} picks covered."
    puts "Shop, at today's hours:   $#{new_cost.round(2)}"
    puts "Old deal, same hours:     $#{old_cost.round(2)}  (#{rows.count { |row| row[:hours] >= 10 }} past 10 hrs × $#{handheld.to_i}, " \
         "#{rows.count { |row| row[:hours] >= 20 }} past 20 hrs × $85)"
    puts "Saved:                    $#{(old_cost - new_cost).round(2)}"
  end
end
