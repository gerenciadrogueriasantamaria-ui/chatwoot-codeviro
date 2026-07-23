class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper

  before_action :current_account
  before_action :ensure_agent_access_session!
  around_action :switch_locale_using_account_locale

  private

  def ensure_agent_access_session!
    return unless current_user
    return if Current.account_user&.administrator?

    guard = AgentAccess::SessionGuard.new(
      user: current_user,
      account: Current.account,
      request: request,
      client_id: request.headers['X-Agent-Access-Client-Id']
    )

    return render_agent_access_denied(guard.denial_reason) unless guard.allowed?

    guard.register!
  end

  def render_agent_access_denied(reason)
    render json: {
      error: agent_access_error_message(reason),
      error_code: reason
    }, status: :unauthorized
  end

  def agent_access_error_message(reason)
    case reason
    when 'session_revoked'
      'Tu sesión fue cerrada por un administrador.'
    when 'outside_schedule'
      'Tu sesión está fuera del horario permitido.'
    when 'max_sessions_reached'
      'Tu sesión excede el límite de sesiones activas.'
    else
      'Tu sesión ya no tiene acceso al CRM.'
    end
  end
end
