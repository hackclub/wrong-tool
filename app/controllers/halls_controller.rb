# The Hall of Wrong: every wrong tool and the games shipped in it. Public, so anyone can see what's been built.
class HallsController < ApplicationController
  def show
    @project = current_user&.project
  end
end
