# wrong tool in numbers (PublicStats), for anyone, signed in or not.
class StatsController < ApplicationController
  def show
    @stats = PublicStats.cached
  end
end
