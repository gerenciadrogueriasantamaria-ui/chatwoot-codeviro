class Conversations::AssignmentService
  MAX_ACTIVE_ASSIGNMENTS = 5
  ACTIVE_ASSIGNMENT_STATUSES = %i[open pending snoozed].freeze

  class AssignmentError < StandardError; end

  def initialize(conversation:, assignee_id:, assignee_type: nil, actor: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
    @actor = actor
  end

  def perform
    agent_bot_assignment? ? assign_agent_bot : assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type, :actor

  def assign_agent
    assigned_agent = nil

    conversation.with_lock do
      ensure_actor_can_manage_existing_assignment!

      if assignee.blank?
        conversation.assignee = nil
        conversation.assignee_agent_bot = nil
        conversation.save!
        next
      end

      ensure_conversation_available_for!(assignee)
      ensure_assignee_has_capacity!(assignee)

      conversation.assignee = assignee
      conversation.assignee_agent_bot = nil
      conversation.save!
      assigned_agent = assignee
    end

    assigned_agent
  end

  def assign_agent_bot
    return unless agent_bot

    conversation.with_lock do
      ensure_actor_can_manage_existing_assignment!

      conversation.assignee = nil
      conversation.assignee_agent_bot = agent_bot
      conversation.save!
    end

    agent_bot
  end

  def ensure_actor_can_manage_existing_assignment!
  return if actor.blank?
  return if actor_can_override_assignment?
  return if conversation.assignee_id.blank?
  return if conversation.assignee_id == actor.id

  raise AssignmentError, 'Esta conversación ya está asignada a otro agente'
end

def ensure_conversation_available_for!(new_assignee)
  return if actor_can_override_assignment?
  return if conversation.assignee_id.blank?
  return if conversation.assignee_id == new_assignee.id

  raise AssignmentError, 'Esta conversación ya está asignada a otro agente'
end
  
  def ensure_assignee_has_capacity!(new_assignee)
    return if unlimited_assignment_user?(new_assignee)

    active_count = conversation.account.conversations
                               .where(assignee_id: new_assignee.id, status: ACTIVE_ASSIGNMENT_STATUSES)
                               .where.not(id: conversation.id)
                               .count

    return if active_count < MAX_ACTIVE_ASSIGNMENTS

    raise AssignmentError, 'El agente ya tiene 5 conversaciones activas asignadas'
  end

  def actor_can_override_assignment?
  return false if actor.blank?

  account_user_can_override?(actor_account_user)
  end

  def actor_account_user
  return @actor_account_user if defined?(@actor_account_user)

  @actor_account_user =
    if defined?(Current) &&
       Current.respond_to?(:account_user) &&
       Current.account_user&.user_id == actor.id &&
       Current.account_user&.account_id == conversation.account_id
      Current.account_user
    else
      account_user_for(actor)
    end
end

def account_user_can_override?(account_user)
  return false if account_user.blank?

  account_user.administrator? ||
    account_user.supervisor? ||
    %w[administrator supervisor].include?(account_user.role.to_s) ||
    account_user.permissions.include?('administrator') ||
    account_user.permissions.include?('supervisor')
end

  def unlimited_assignment_user?(user)
  account_user = account_user_for(user)
  account_user&.administrator? || account_user&.supervisor?
  end

  def account_user_for(user)
    conversation.account.account_users.find_by(user_id: user.id)
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  def agent_bot
    @agent_bot ||= AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end
