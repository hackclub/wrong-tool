# wrong tool in numbers (PublicStats), for anyone, signed in or not.
class StatsController < ApplicationController
  def show
    @stats = PublicStats.cached
    # Where the projected DAU's new builders come from (Growth::Simulator): with everyone's friends, or steady.
    @signups = params[:signups].presence_in(Growth::Simulator::SIGNUPS) || "word_of_mouth"
  end
end
