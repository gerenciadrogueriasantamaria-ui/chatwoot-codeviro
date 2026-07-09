class AgentAccessSession < ApplicationRecord
  belongs_to :account
  belongs_to :user

  scope :active, -> {
    where(revoked_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.zone.now)
  }

  def revoke!
    update!(revoked_at: Time.zone.now)
  end
end
