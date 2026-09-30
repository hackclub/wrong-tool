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
    click_on "Use this idea"

    assert_selector "h2", text: "Pick your prize."
    click_on "Mini Plus"
    assert_selector "h2", text: "Last step.", wait: 0.5
    assert_selector ".onboarding-mascot[data-visible]", text: "Nice pick! The Mini Plus is yours after 10 hours."
    assert_selector ".onboarding-prize[data-claimed]", text: "Mini Plus", visible: :all
    assert_selector ".onboarding-save__title", text: "#{idea[0].upcase}#{idea[1..]}."
    assert_selector ".onboarding-receipt", text: "SSH"
    assert_selector ".app-bar__title", text: /\.sh\z/
    click_on "Get started"

    # Back from Hack Club Auth, signed in, with the answers from before the trip.
    assert_current_path onboarding_path
    assert_selector ".onboarding-save__title", text: "You're in."
    assert_selector ".onboarding-row[data-state=done]", text: "SSH"
    assert_selector ".onboarding-row[data-state=done]", text: "Miyoo Mini Plus"
    assert_selector ".app-bar__progress", exact_text: "A1:A4 done"
    assert_selector ".onboarding__project-tab[aria-disabled=false]"
    assert User.exists?(hca_id: "ident!heidi")
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
end
