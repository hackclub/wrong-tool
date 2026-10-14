# The shop: every console your hours can buy (Console::ALL, priced by Shop), as a sheet with Clippy at the counter.
# Changing which one's yours (what you're working towards), its colour and its extras, any time; buying is Order.
class ShopController < ApplicationController
  before_action :require_project

  # Your hours, as of the last sync (a sync's queued if it's time).
  def show
    current_user.sync_streak_if_stale!
  end

  # Picking a console, or a colour or extra on the one you have. From the counter that's JSON, and the
  # page carries on; without it, the page comes back and Clippy says what it takes.
  def update
    if @project.update(shop_params)
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "prize_changed",
        properties: { prize: @project.prize, prize_color: @project.console_color.id, prize_options: @project.prize_choices,
                      price: @project.prize_price }
      ) if Rails.configuration.x.posthog_configured

      respond_to do |format|
        format.html { flash[:shop] = "picked"; redirect_to shop_path }
        format.json { render json: helpers.shop_state_data(@project) }
      end
    else
      error = @project.errors.full_messages.first
      # The shop as it was, with why it didn't change.
      @project.restore_attributes(%w[prize prize_color prize_options])
      respond_to do |format|
        format.html { flash.now[:shop_error] = error; render :show, status: :unprocessable_entity }
        format.json { render json: { error: }, status: :unprocessable_entity }
      end
    end
  end

  private
    def require_project
      @project = current_user&.project
      redirect_to onboarding_path unless @project
    end

    def shop_params
      params.expect(project: [ :prize, :prize_color, prize_options: {} ])
    end
end
