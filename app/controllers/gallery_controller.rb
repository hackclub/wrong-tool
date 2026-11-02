# Every game that shipped, for anyone, signed in or not: each project's latest ship (as it was submitted), whatever
# review made of it, newest first, with who made it by the name everyone else sees them as (User#public_name).
# Filter by the wrong tool it was built in.
class GalleryController < ApplicationController
  def show
    ships = Ship.latest_per_project.includes(project: :user).with_attached_screenshot.order(created_at: :desc, id: :desc).to_a
    @tools = Project::TOOLS.select { |tool| ships.any? { |ship| ship.project.tool == tool } }
    @tool = params[:tool].presence_in(@tools)
    @total = ships.size
    @ships = @tool ? ships.select { |ship| ship.project.tool == @tool } : ships
  end
end
