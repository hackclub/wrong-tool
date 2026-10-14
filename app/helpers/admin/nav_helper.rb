# The admin pages, in one list: the nav above each of them (admin/_nav) and the admin home (/admin) both read it.
# The ones with something waiting on an admin come first.
module Admin::NavHelper
  def admin_pages
    [
      { label: "Orders", path: admin_orders_path, about: "Consoles claimed with approved hours, to order and mark ordered." },
      { label: "Ships", path: admin_ships_path, about: "Every ship in full, screenshot and all, to approve or send back." },
      { label: "Extensions", path: admin_extensions_path, about: "Who's asked for more time to ship, and why." },
      { label: "Sellers", path: admin_seller_requests_path, about: "Who's asked for their console from another seller, to save on customs." },
      { label: "Projects", path: admin_projects_path, about: "Every project, searchable, and each in full." },
      { label: "People", path: admin_users_path, about: "Everyone who's signed in, and seeing the site as any of them." },
      { label: "Numbers", path: admin_metrics_path, about: "wrong tool's numbers, day by day." },
      { label: "Bandit", path: admin_nudges_path, about: "How Clippy's nudges are doing, and what the bandit's learned." },
      { label: "Blazer", path: "/admin/blazer", about: "SQL against the database." }
    ]
  end

  # What a count on the admin home means, for the page it's on.
  def admin_waiting_label(label)
    { "Orders" => "to order", "Ships" => "in review" }.fetch(label, "waiting")
  end
end
