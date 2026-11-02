namespace :review do
  # Gathers the evidence (ShipEvidence) for every ship in review that doesn't have it yet: the ones shipped before it
  # was gathered. Each is queued (ShipEvidenceJob), so this returns at once. Opening one on /review asks for it too.
  #
  #   bin/rails review:evidence
  desc "Queue evidence for every ship in review without it"
  task evidence: :environment do
    ships = Ship.in_review.where.missing(:evidence)
    ships.find_each { |ship| ShipEvidence.request(ship) }
    puts "Queued #{ships.size}."
  end
end
