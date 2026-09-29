require "application_system_test_case"

class OnboardingTest < ApplicationSystemTestCase
  test "Start building in the app bar and the hero both open onboarding" do
    visit root_path
    assert_selector "a.app-bar__build-button[href='#{onboarding_path}']"
    assert_selector "a.hero__cta[href='#{onboarding_path}']"

    find(".app-bar__build-button").click
    assert_current_path onboarding_path
    assert_selector "h2", text: "Pick your wrong tool."
  end

  test "picking a tool, an idea and a prize, then signing in" do
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
    assert_selector ".onboarding-prize[data-claimed]", text: "CLAIMED"

    assert_selector "h2", text: "Save your project.", wait: 5
    assert_selector ".onboarding-receipt", text: "SSH"
    assert_selector ".onboarding-receipt__saved", exact_text: "#UNSAVED"
    assert_selector ".app-bar__title", text: /\.sh\z/
    click_on "Sign in with Hack Club"

    assert_selector ".onboarding-save__title", text: "Saved.", wait: 3
    assert_selector ".onboarding-receipt__saved", exact_text: "TRUE"
    assert_selector ".app-bar__progress", exact_text: "A1:A4 done"
    assert_selector ".onboarding__project-tab[aria-disabled=false]"
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
    fill_in "B1 · your idea", with: "a heist game in my drafts"
    click_on "Use my idea"
    assert_selector ".onboarding-row[data-state=done]", text: "A heist game in my drafts"

    all(".onboarding-row__summary")[1].click
    click_on "Skip for now"
    assert_selector ".onboarding-row[data-state=done]", text: "Not decided yet"
  end
end
