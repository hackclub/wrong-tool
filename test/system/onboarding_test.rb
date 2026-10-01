require "application_system_test_case"

class OnboardingTest < ApplicationSystemTestCase
  test "Start building in the app bar and the hero both open onboarding" do
    visit root_path
    assert_selector "a.app-bar__build-button[href='#{onboarding_path}']"
    assert_selector "a.hero__cta[href='#{onboarding_path}']"

    find(".app-bar__build-button").click
    assert_current_path onboarding_path
    assert_selector "h2", text: "Pick your platform."
  end

  test "picking a tool, an idea and a prize, then signing in with Hack Club" do
    mock_hack_club_auth
    visit onboarding_path
    assert_selector ".formula-bar__name", exact_text: "A1"
    assert_selector ".app-bar__progress", exact_text: "Step 1 of 4"

    click_on "SSH"
    assert_selector "h2", text: "What are you building?"
    assert_selector ".onboarding-row[data-state=done]", text: "SSH"

    assert_button "Roll again", wait: 5
    idea = find(".formula-bar__content").text.delete_prefix('="').delete_suffix('"')
    assert_match(/\Aan? .+/, idea)
    genre = all(".onboarding-reel").first.text
    click_on "Use this idea"

    assert_selector "h2", text: "Pick your prize."
    click_on "Mini Plus"
    assert_selector "h2", text: "Set your pace.", wait: 0.5
    assert_selector ".onboarding-mascot__bubble", text: "Nice pick! The Mini Plus is yours after 10 hours."
    assert_selector ".onboarding-prize[data-claimed]", text: "Mini Plus", visible: :all

    # Nothing's picked for you, so there's nothing to sign yet.
    assert_equal [ "20 min", "45 min", "1 hr", "2 hrs", "3 hrs" ], all(".onboarding-chip").first(5).map(&:text)
    assert_no_checked_field "45 min", visible: :all
    assert_button "Hold to sign with Hack Club", disabled: true
    assert_selector ".onboarding-commit__sign-hint", text: "Answer both to sign."
    assert_selector ".onboarding-pledge__signature", visible: :hidden
    assert_selector ".onboarding-pledge__text", text: /and ship an? #{Regexp.escape(genre)}/
    assert_selector ".onboarding-pledge__text", text: "every day and ship"
    assert_selector ".onboarding-pledge__text", text: "over SSH by"
    assert_selector ".onboarding-pledge__accountable", text: "Clippy will check in to keep you on track."

    find(".onboarding-chip", text: "45 min").click
    assert_selector ".onboarding-pledge__text", text: "I'll build 45 min every day"
    assert_selector ".onboarding-commit__finish", text: /\AYou'd finish by [A-Z][a-z]{2} \d+\.\z/
    assert_selector ".onboarding-commit__sign-hint", text: "Pick a time first."
    assert_selector ".formula-bar__content", text: /\A=SHIP\("#{Regexp.escape(genre)}","SSH",DATE\(\d+,\d+\)\)\z/
    assert_button "Hold to sign with Hack Club", disabled: true
    find(".onboarding-chip", text: "evening").click
    assert_selector ".app-bar__title", text: /\.sh\z/
    assert_selector ".onboarding-commit__sign-hint", text: "Hold, then sign in with Hack Club to finish."
    assert_selector ".onboarding-pledge__accountable", text: "Clippy will check in every evening to keep you on track."

    # A click isn't a hold, and letting go early runs it back.
    click_on "Hold to sign with Hack Club"
    assert_current_path onboarding_path
    hold_sign_button(seconds: 0.4)
    assert_selector ".onboarding-commit__sign-hint", text: "Almost. Hold until it's signed."
    assert_no_selector ".onboarding-commit[data-pledged]"

    hold_sign_button(seconds: 1.6)

    # Back from Hack Club Auth, signed in, with the answers from before the trip: the pledge signs itself.
    assert_current_path onboarding_path
    assert_selector ".onboarding-commit[data-pledged]"
    assert_selector ".onboarding-pledge__name", exact_text: "Heidi"
    assert_selector ".onboarding-mascot__bubble", text: "Signed. I'll check in every evening to keep you on track."
    assert_selector ".formula-bar__content", text: /→ TRUE\z/
    assert_selector ".app-bar__progress", exact_text: "Day 1"

    # Then the pledge is saved as your project, and that's where you land.
    assert_current_path project_path, wait: 5
    project = User.find_by!(hca_id: "ident!heidi").project
    assert_equal [ "ssh", "SSH", "Miyoo Mini Plus", 45, "evening" ],
                 [ project.tool, project.tool_name, ProjectsHelper::PRIZE_NAMES[project.prize], project.pace_minutes, project.build_time ]
    assert_selector "h1", text: /\AAn? #{Regexp.escape(genre)} over SSH\z/
    assert_selector ".project__day", text: "Day 1 starts now."
    assert_selector ".sheet-tab[aria-current=page]", text: "My project"
  end

  test "Other asks for the tool's name" do
    visit onboarding_path
    click_on "Other"
    fill_in "Which tool?", with: "Google Slides"
    assert_selector ".formula-bar__content", exact_text: %(=PICK("Google Slides"))
    click_on "Use this tool"

    assert_selector "h2", text: "What are you building?"
    assert_selector ".onboarding-row[data-state=done]", text: "Google Slides"
  end

  test "writing your own idea, or skipping it for later" do
    visit onboarding_path
    click_on "Email"
    click_on "I already have an idea"
    find("[aria-label='Your idea']").fill_in with: "a heist game in my drafts"
    click_on "Use my idea"
    assert_selector ".onboarding-row[data-state=done]", text: "A heist game in my drafts"

    all(".onboarding-row__summary")[1].click
    click_on "Skip for now"
    assert_selector ".onboarding-row[data-state=done]", text: "Not decided yet"
  end

  test "a skipped idea ships as something cursed, and weekends only count weekends" do
    visit onboarding_path
    click_on "Figma"
    click_on "Skip for now"
    click_on "RG35XX Pro"

    assert_selector ".onboarding-pledge__text", text: "and ship something cursed in Figma"
    find(".onboarding-chip", text: "3 hrs").click
    weekdays = find(".onboarding-commit__finish").text
    find(".onboarding-chip", text: "weekends").click
    assert_not_equal weekdays, find(".onboarding-commit__finish").text
    assert_selector ".onboarding-pledge__text", text: "I'll build 3 hrs every weekend day"
    assert_selector ".formula-bar__content", text: /\A=SHIP\("something cursed","Figma",DATE/
  end


  test "someone already signed in to Hack Club sees their name go on as they hold, before signing in here" do
    mock_hack_club_auth
    with_whoami(signed_in: true, email: "heidi@hackclub.com", first_name: "Heidi") do
      visit onboarding_path
      click_on "Email"
      click_on "Skip for now"
      click_on "RG35XX Pro"
      find(".onboarding-chip", text: "1 hr").click
      find(".onboarding-chip", text: "late night").click
      assert_selector ".onboarding-commit__sign-hint", text: "Holding signs your name to this pledge."

      button = find_button("Hold to sign with Hack Club")
      page.driver.browser.action.click_and_hold(button.native).perform
      assert_selector ".onboarding-pledge__name", text: /\AH/
      sleep 1.4
      page.driver.browser.action.release.perform

      # Still signs in with Hack Club Auth; the name comes back the same.
      assert_selector ".onboarding-commit[data-pledged]"
      assert_selector ".onboarding-pledge__name", exact_text: "Heidi"
      assert_selector ".onboarding-mascot__bubble", text: "Signed. I'll check in late at night to keep you on track."
      assert_current_path project_path, wait: 5
    end
  end

  private
    # Presses the sign button and keeps it down, the way you'd hold it.
    def hold_sign_button(seconds:)
      button = find_button("Hold to sign with Hack Club")
      page.driver.browser.action.click_and_hold(button.native).perform
      sleep seconds
      page.driver.browser.action.release.perform
    end

    # Hack Club Auth's whoami, answering with `identity` (a data: URL stands in for it).
    def with_whoami(**identity)
      config = Rails.application.config.x
      config.hack_club_auth_whoami_url = "data:application/json,#{ERB::Util.url_encode(identity.to_json)}"
      yield
    ensure
      config.hack_club_auth_whoami_url = nil
    end
end
