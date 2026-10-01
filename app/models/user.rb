# Someone signed in with Hack Club Auth. hca_id is their HCA subject (ident!…); everything else is copied
# from HCA's claims each time they sign in, so it stays current.
class User < ApplicationRecord
  has_one :project, dependent: :destroy

  validates :hca_id, presence: true, uniqueness: true

  def self.from_omniauth(auth)
    claims = auth.extra.raw_info.to_h.with_indifferent_access
    find_or_initialize_by(hca_id: auth.uid).tap do |user|
      user.update!(
        email: auth.info.email,
        name: auth.info.name,
        first_name: auth.info.first_name,
        slack_id: claims[:slack_id],
        verification_status: claims[:verification_status],
        ysws_eligible: claims[:ysws_eligible] || false
      )
    end
  end
end
