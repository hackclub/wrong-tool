require "test_helper"

# Lapse as it really answers (its OpenAPI is at https://api.lapse.hackclub.com/openapi.json), with the stubs off.
class LapseTest < ActiveSupport::TestCase
  RHYTHM = "/api/hackatime/timelapsesForProject?hackatimeUserId=1001&projectKey=rhythm-game".freeze
  ART = "/api/hackatime/timelapsesForProject?hackatimeUserId=1001&projectKey=beat-sheet-art".freeze

  def raw(id, at:, visibility: "PUBLIC", **extra)
    { id:, name: "Beat sheet, #{id}", playbackUrl: "https://cdn.lapse.test/#{id}.mp4", thumbnailUrl: "https://cdn.lapse.test/#{id}.jpg",
      duration: 1800.4, createdAt: at.to_i * 1000, visibility:, blocker: nil, **extra }
  end

  test "no program key means no Lapse at all: nothing's asked, and there's nothing to show a reviewer" do
    with_lapse_answering({}, key: nil) do
      assert_not Lapse.configured?
      assert_empty Lapse.timelapses("1001", [ "rhythm-game" ])
      assert_empty lapse_asked
    end
  end

  test "someone's timelapses, asked for each of the ship's Hackatime projects by their Hackatime ID, newest first" do
    timelapses = with_lapse_answering({
      RHYTHM => { ok: true, data: { count: 2, timelapses: [
        raw("tl1", at: Time.utc(2026, 10, 8, 20), visibility: "UNLISTED", private: { hackatimeProject: "rhythm-game", sourceDraftId: nil }),
        raw("tl2", at: Time.utc(2026, 10, 10, 20), blocker: "Shows someone's address")
      ] } },
      ART => { ok: true, data: { count: 1, timelapses: [ raw("tl3", at: Time.utc(2026, 10, 9, 20)) ] } }
    }) { Lapse.timelapses("1001", [ "rhythm-game", "beat-sheet-art" ]) }

    assert_equal %w[tl2 tl3 tl1], timelapses.map(&:id)
    unlisted = timelapses.last
    assert_equal [ "Beat sheet, tl1", "rhythm-game", 1800, "UNLISTED" ],
                 [ unlisted.name, unlisted.hackatime_project, unlisted.seconds, unlisted.visibility ]
    assert_equal "beat-sheet-art", timelapses.second.hackatime_project, "the project it was asked for, when Lapse doesn't say"
    assert_equal "Shows someone's address", timelapses.first.blocker
    assert_equal "https://cdn.lapse.test/tl1.mp4", unlisted.playback_url
    assert_equal "https://lapse.hackclub.com/timelapse/tl1", unlisted.page_url, "the watch page, which doesn't go stale"
    assert_equal Time.utc(2026, 10, 8, 20), unlisted.recorded_at, "Lapse counts in milliseconds"
    assert_equal [ "Bearer pk_lapse_test" ], lapse_asked.map(&:last).uniq, "the program key, which is what shows the unlisted ones"
  end

  test "a project name is sent as it's written, and nobody on Lapse with that Hackatime ID is none" do
    path = "/api/hackatime/timelapsesForProject?hackatimeUserId=1001&projectKey=Frog+Pad%21+%28hackpad%29"
    with_lapse_answering({ path => { ok: true, data: { count: 0, timelapses: [] } } }) do
      assert_empty Lapse.timelapses("1001", [ "Frog Pad! (hackpad)" ])
    end
  end

  test "a Lapse that says no, or isn't making sense, is unavailable rather than quietly nothing" do
    with_lapse_answering({ RHYTHM => [ 403, { defined: false, code: "FORBIDDEN", status: 403, message: "Missing required scope timelapse:read." } ] }) do
      error = assert_raises(Lapse::Unavailable) { Lapse.timelapses("1001", [ "rhythm-game" ]) }
      assert_equal "Lapse answered 403: Missing required scope timelapse:read.", error.message
    end

    with_lapse_answering({ RHYTHM => { ok: false, error: "HACKATIME_ERROR", message: "Hackatime is down" } }) do
      assert_equal "Lapse said HACKATIME_ERROR (Hackatime is down)",
                   assert_raises(Lapse::Unavailable) { Lapse.timelapses("1001", [ "rhythm-game" ]) }.message
    end

    with_lapse_answering({ RHYTHM => 502 }) do
      assert_equal "Lapse answered 502", assert_raises(Lapse::Unavailable) { Lapse.timelapses("1001", [ "rhythm-game" ]) }.message
    end
  end

  test "a ship with no Hackatime project, or someone with no Hackatime ID, has nothing to match" do
    with_lapse_answering({}) do
      assert_empty Lapse.timelapses("1001", [])
      assert_empty Lapse.timelapses(nil, [ "rhythm-game" ])
      assert_empty lapse_asked
    end
  end
end
