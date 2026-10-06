// PostHog in the browser (loaded by app/views/layouts/_posthog.html.erb; without it, all of this does nothing).
// Signed in, you're identified as your user ID, the same distinct ID the server's events use, so what you did
// before signing in (onboarding) joins up with what you do after. Logging out forgets you.

// `options` go to posthog.capture: { transport: "sendBeacon" } gets an event out before the page goes.
export function capture(event, properties = {}, options) {
  window.posthog?.capture(event, properties, options)
}

// Turbo shows a cached copy of a page before the real one arrives; nothing on it is someone doing anything.
export function previewing() {
  return document.documentElement.hasAttribute("data-turbo-preview")
}

addEventListener("turbo:load", () => {
  const userId = document.body.dataset.posthogUserId
  if (userId && window.posthog?.get_distinct_id() !== userId) window.posthog.identify(userId)
})

// Links and buttons with data-capture="event" send it when clicked, with data-capture-location as where from.
addEventListener("click", ({ target }) => {
  const element = target.closest?.("[data-capture]")
  if (element) capture(element.dataset.capture, { location: element.dataset.captureLocation })
}, true)

addEventListener("submit", ({ target }) => {
  if (target.matches("[data-posthog-reset]")) window.posthog?.reset()
}, true)
