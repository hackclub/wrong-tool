module StatsHelper
  # A number, or "<3" where it's too few people to show (see PublicStats).
  def stat(value)
    value.nil? ? "<#{PublicStats::MIN_GROUP}" : number_with_delimiter(value)
  end

  def stat_share(share)
    share ? number_to_percentage(share * 100, precision: 0) : ""
  end

  # A round number at or above `max` (1, 2, 5, 10, 20, 50, …), for the top of an axis.
  def stat_axis_max(max)
    return 1 if max.to_f <= 0
    magnitude = 10**Math.log10(max).floor
    [ 1, 2, 5, 10 ].map { |step| step * magnitude }.find { |top| top >= max }
  end
end
