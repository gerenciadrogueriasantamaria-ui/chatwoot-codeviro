class Api::V1::Accounts::AgentAccessPoliciesController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator!
  before_action :fetch_user, only: [:show, :update, :destroy_session]

  def index
    users = Current.account.account_users
                           .includes(:user)
                           .where(role: [:agent, :supervisor])
                           .map(&:user)

    render json: {
      users: users.map { |user| user_payload(user) }
    }
  end

  def show
    policy = policy_for_user(@user)

    render json: {
      user: user_payload(@user),
      policy: policy_payload(policy),
      sessions: active_sessions_for_user(@user).map { |session| session_payload(session) }
    }
  end

  def update
    policy = policy_for_user(@user)
    policy.update!(policy_params)

    render json: {
      user: user_payload(@user),
      policy: policy_payload(policy),
      sessions: active_sessions_for_user(@user).map { |session| session_payload(session) }
    }
  end

  def destroy_session
    session = active_sessions_for_user(@user).find(params[:session_id])
    session.revoke!

    render json: {
      sessions: active_sessions_for_user(@user).map { |active_session| session_payload(active_session) }
    }
  end

  private

  def ensure_administrator!
    return if Current.account_user&.administrator?

    render_unauthorized('You are not authorized to access agent access settings')
  end

  def fetch_user
    @user = Current.account.users.find(params[:user_id])
  end

  def policy_for_user(user)
    Current.account.agent_access_policies.find_or_create_by!(user: user) do |policy|
      policy.enabled = true
      policy.max_sessions = 1
      policy.schedule = {}
    end
  end

  def active_sessions_for_user(user)
    Current.account.agent_access_sessions.active.where(user: user).order(last_seen_at: :desc)
  end

  def policy_params
    {
      enabled: params[:enabled],
      max_sessions: params[:max_sessions],
      schedule: schedule_params
    }.compact
  end

  def schedule_params
    return {} unless params[:schedule].present?

    params[:schedule].to_unsafe_h
  end

  def user_payload(user)
    account_user = Current.account.account_users.find_by(user_id: user.id)

    {
      id: user.id,
      name: user.name,
      email: user.email,
      role: account_user&.role
    }
  end

  def policy_payload(policy)
    {
      enabled: policy.enabled,
      max_sessions: policy.max_sessions,
      schedule: policy.schedule
    }
  end

  def session_payload(session)
    {
      id: session.id,
      client_id: session.client_id,
      user_agent: session.user_agent,
      ip_address: session.ip_address,
      last_seen_at: session.last_seen_at,
      expires_at: session.expires_at,
      revoked_at: session.revoked_at,
      created_at: session.created_at
    }
  end
end
