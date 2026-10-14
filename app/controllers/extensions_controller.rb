# Asking for more time to ship (Extension), from the schedule card: once, with why. The admins hear on Slack and decide on /admin/extensions.
class ExtensionsController < ApplicationController
  before_action :require_project

  def create
    return redirect_to project_path unless @project.extension_requestable?

    extension = @project.build_extension(extension_params)
    if extension.save
      ExtensionNotifier.requested(extension)
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "extension_requested"
      ) if Rails.configuration.x.posthog_configured
      PosthogLog.info("extension_requested")

      redirect_to project_path, flash: { clippy: "hop" }
    else
      redirect_to project_path(edit: "extension"), flash: { extension_alert: extension.errors.full_messages_for(:reason).first }
    end
  end

  private
    def require_project
      @project = current_user&.project
      redirect_to onboarding_path unless @project
    end

    def extension_params
      params.expect(extension: [ :reason ])
    end
end
