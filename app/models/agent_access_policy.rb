class AgentAccessPolicy < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
  validates :max_sessions, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 10
  }

  def allows_hour?(time = Time.zone.now)
    return true unless enabled?

    day_key = time.wday.to_s
    hour_key = time.hour.to_s

    schedule.dig(day_key, hour_key) == true
  end
end
