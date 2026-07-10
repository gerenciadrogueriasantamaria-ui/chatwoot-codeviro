class AgentAccess::SessionGuard
  SESSION_TTL = 12.hours
  TIME_ZONE = 'America/Bogota'

  def initialize(user:, account:, request:, client_id: nil)
    @user = user
    @account = account
    @request = request
    @client_id = client_id.presence || SecureRandom.uuid
  end

  attr_reader :client_id

  def allowed?
    return true if administrator?
    return false unless policy.enabled?
    return false unless policy.allows_hour?(current_time)
    return false if policy.max_sessions.zero?

    existing_session.present? || active_sessions.count < policy.max_sessions
  end

  def denial_reason
    return nil if allowed?
    return 'outside_schedule' unless policy.allows_hour?(current_time)
    return 'max_sessions_reached' if policy.max_sessions.zero?
    return 'max_sessions_reached' if active_sessions.count >= policy.max_sessions

    'access_denied'
  end

  def register!
    return nil if administrator?

    session = existing_session || @account.agent_access_sessions.new(
      user: @user,
      client_id: @client_id
    )

    session.assign_attributes(
      user_agent: @request.user_agent,
      ip_address: @request.remote_ip,
      last_seen_at: Time.zone.now,
      expires_at: SESSION_TTL.from_now,
      revoked_at: nil
    )

    session.save!
    session
  end

  private

  def current_time
    Time.current.in_time_zone(TIME_ZONE)
  end

  def administrator?
    account_user&.administrator?
  end

  def account_user
    @account_user ||= @account.account_users.find_by(user_id: @user.id)
  end

  def policy
    @policy ||= @account.agent_access_policies.find_or_create_by!(user: @user) do |access_policy|
      access_policy.enabled = true
      access_policy.max_sessions = 1
      access_policy.schedule = {}
    end
  end

  def active_sessions
    @active_sessions ||= @account.agent_access_sessions.active.where(user: @user)
  end

  def existing_session
    @existing_session ||= active_sessions.find_by(client_id: @client_id)
  end
end
