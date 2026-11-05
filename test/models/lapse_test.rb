require "test_helper"

# Lapse as it really answers (its contracts live in packages/api/src/contracts in hackclub/lapse), with the stubs off.
class LapseTest < ActiveSupport::TestCase
  ORPHEUS = "/api/user/queryByEmail?email=orpheus%40hackclub.com".freeze
  THEIRS = "/api/timelapse/findByUser?user=lapse-orpheus".freeze

  test "no program key means no Lapse at all: nothing's asked, and there's nothing to show a reviewer" do
    with_lapse_answering({}, key: nil) do
      assert_not Lapse.configured?
      assert_empty Lapse.timelapses("orpheus@hackclub.com", [ "rhythm-game" ])
      assert_empty lapse_asked
    end
  end

  test "someone's timelapses, by their email, with the Hackatime project only a program key is told" do
    timelapses = with_lapse_answering({ ORPHEUS => { ok: true, data: { user: { id: "lapse-orpheus", handle: "orpheus" } } },
                                        THEIRS => { ok: true, data: { timelapses: [
                                        { id: "tl1", name: "Beat sheet, hour 3", playbackUrl: "https://cdn.lapse.test/tl1.mp4",
                                          thumbnailUrl: "https://cdn.lapse.test/tl1.jpg", duration: 73.4, createdAt: 1_760_000_000_000,
                                          visibility: "UNLISTED", private: { hackatimeProject: "rhythm-game" } },
                                        { id: "tl2", name: "Dotfiles", playbackUrl: "https://cdn.lapse.test/tl2.mp4", duration: 10,
                                          createdAt: 1_761_000_000_000, visibility: "PUBLIC", private: { hackatimeProject: "dotfiles" } },
                                        { id: "tl3", name: "Never synced with Hackatime", playbackUrl: "https://cdn.lapse.test/tl3.mp4",
                                          duration: 10, createdAt: 1_762_000_000_000, visibility: "PUBLIC", private: { hackatimeProject: nil } }
                                      ] } } }) do
      Lapse.timelapses("orpheus@hackclub.com", [ "rhythm-game", "beat-sheet-art" ])
    end

    assert_equal 1, timelapses.size, "only the ones for a project the ship's hours came from"
    timelapse = timelapses.first
    assert_equal [ "tl1", "Beat sheet, hour 3", "rhythm-game", 73, "UNLISTED" ],
                 [ timelapse.id, timelapse.name, timelapse.hackatime_project, timelapse.seconds, timelapse.visibility ]
    assert_equal "https://cdn.lapse.test/tl1.mp4", timelapse.playback_url
    assert_equal "https://lapse.hackclub.com/timelapse/tl1", timelapse.page_url, "the watch page, which doesn't go stale"
    assert_equal Time.utc(2025, 10, 9, 8, 53, 20), timelapse.recorded_at, "Lapse counts in milliseconds"
    assert_equal [ "Bearer pk_lapse_test" ], lapse_asked.map(&:last).uniq, "the program key, which is what's shown a private field"
  end

  test "nobody on Lapse with that email, and an email Lapse has never heard of, come back empty" do
    with_lapse_answering({ ORPHEUS => { ok: true, data: { user: nil } } }) do
      assert_empty Lapse.timelapses("orpheus@hackclub.com", [ "rhythm-game" ])
    end
    with_lapse_answering({ ORPHEUS => 404 }) do
      assert_empty Lapse.timelapses("orpheus@hackclub.com", [ "rhythm-game" ])
    end
  end

  test "a Lapse that says no, or isn't making sense, is unavailable rather than quietly nothing" do
    with_lapse_answering({ ORPHEUS => { ok: false, error: "NO_PERMISSION", message: "the key can't read users" } }) do
      error = assert_raises(Lapse::Unavailable) { Lapse.timelapses("orpheus@hackclub.com", [ "rhythm-game" ]) }
      assert_equal "Lapse said NO_PERMISSION (the key can't read users)", error.message
    end

    with_lapse_answering({ ORPHEUS => 500 }) do
      assert_equal "Lapse answered 500", assert_raises(Lapse::Unavailable) {
        Lapse.timelapses("orpheus@hackclub.com", [ "rhythm-game" ])
      }.message
    end
  end

  test "a ship with no Hackatime project, or someone we have no email for, has nothing to match" do
    with_lapse_answering({}) do
      assert_empty Lapse.timelapses("orpheus@hackclub.com", [])
      assert_empty Lapse.timelapses(nil, [ "rhythm-game" ])
      assert_empty lapse_asked
    end
  end
end
