class Api::V1::Accounts::ConversationsController < Api::V1::Accounts::BaseController
  include Events::Types
  include DateRangeHelper
  include HmacConcern

  before_action :conversation, except: [:index, :meta, :search, :create, :filter, :kanban]
  before_action :inbox, :contact, :contact_inbox, only: [:create]

  ATTACHMENT_RESULTS_PER_PAGE = 100

  def index
    result = conversation_finder.perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  end

  def meta
    result = conversation_finder.perform_meta_only
    @conversations_count = result[:count]
  end

  def search
    result = conversation_finder.perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  end

  def attachments
    @attachments_count = @conversation.attachments.count
    @attachments = @conversation.attachments
                                .includes({ file_attachment: :blob }, message: [:inbox, { sender: { avatar_attachment: :blob } }])
                                .order(created_at: :desc)
                                .page(attachment_params[:page])
                                .per(ATTACHMENT_RESULTS_PER_PAGE)
  end

  def show
    auto_assign_conversation_on_view
  end

  def create
    ActiveRecord::Base.transaction do
      @conversation = ConversationBuilder.new(params: params, contact_inbox: @contact_inbox).perform
      Messages::MessageBuilder.new(Current.user, @conversation, params[:message]).perform if params[:message].present?
    end
  end

  def update
    @conversation.update!(permitted_update_params)
  end

  def filter
    result = ::Conversations::FilterService.new(params.permit!, current_user, current_account).perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  def kanban
  return head :forbidden unless Current.account_user&.administrator?

  per_page = [[params[:per_page].to_i, 1].max, 100].min
  page = [params[:page].to_i, 1].max
  column = params[:column].presence
  inbox_id = params[:inbox_id].presence

  visible_label_titles = Current.account.labels
                                      .where(show_on_sidebar: true)
                                      .pluck(:title)

  conversations = Current.account.conversations
                                 .includes(:assignee, :inbox, { contact: { avatar_attachment: :blob } })
                                 .where(status: [:open, :resolved])
                                 .order(last_activity_at: :desc)

  conversations = conversations.where(inbox_id: inbox_id) if inbox_id.present?

  conversations =
  if column == '__unlabeled__'
    conversations.where.not(
      id: ActsAsTaggableOn::Tagging
        .joins(:tag)
        .where(taggable_type: 'Conversation', context: 'labels')
        .where(tags: { name: visible_label_titles })
        .select(:taggable_id)
    )
  elsif visible_label_titles.include?(column)
    conversations.tagged_with(column, on: :labels)
  else
    conversations.none
  end

  total = conversations.count
  records = conversations.page(page).per(per_page)

  render json: {
    payload: records.map(&:push_event_data),
    total: total,
    page: page,
    per_page: per_page
  }
end

  total = conversations.count
  records = conversations.page(page).per(per_page)

  render json: {
    payload: records.map(&:push_event_data),
    total: total,
    page: page,
    per_page: per_page
  }
end

  def mute
    @conversation.mute!
    head :ok
  end

  def unmute
    @conversation.unmute!
    head :ok
  end

  def transcript
    render json: { error: 'email param missing' }, status: :unprocessable_entity and return if params[:email].blank?
    return render_payment_required('Email transcript is not available on your plan') unless @conversation.account.email_transcript_enabled?
    return head :too_many_requests unless @conversation.account.within_email_rate_limit?

    ConversationReplyMailer.with(account: @conversation.account).conversation_transcript(@conversation, params[:email])&.deliver_later
    @conversation.account.increment_email_sent_count
    head :ok
  end

  def toggle_status
    # FIXME: move this logic into a service object
    if pending_to_open_by_bot?
      @conversation.bot_handoff!
    elsif params[:status].present?
      set_conversation_status
      @status = @conversation.save!
    else
      @status = @conversation.toggle_status
    end
    assign_conversation if should_assign_conversation?
  end

  def pending_to_open_by_bot?
    return false unless Current.user.is_a?(AgentBot)

    @conversation.status == 'pending' && params[:status] == 'open'
  end

  def should_assign_conversation?
    @conversation.status == 'open' && Current.user.is_a?(User) && Current.account_user&.agent?
  end

  def toggle_priority
    @conversation.toggle_priority(params[:priority])
    head :ok
  end

  def toggle_typing_status
    typing_status_manager = ::Conversations::TypingStatusManager.new(@conversation, Current.user, params)
    typing_status_manager.toggle_typing_status
    head :ok
  end

  def update_last_seen
  auto_assign_conversation_on_view

  Notification::MarkConversationReadService.new(user: Current.user, account: Current.account, conversation: @conversation).perform
  return update_last_seen_on_conversation(DateTime.now.utc, true) if assignee? && @conversation.assignee_unread_messages.any?
  return update_last_seen_on_conversation(DateTime.now.utc, false) if !assignee? && @conversation.unread_messages.any?

  return unless should_update_last_seen?

  update_last_seen_on_conversation(DateTime.now.utc, assignee?)
end

  def unread
    last_incoming_message = @conversation.messages.incoming.last
    last_seen_at = last_incoming_message.created_at - 1.second if last_incoming_message.present?
    update_last_seen_on_conversation(last_seen_at, true)
  end

  def custom_attributes
    @conversation.custom_attributes = params.permit(custom_attributes: {})[:custom_attributes]
    @conversation.save!
  end

  def destroy
    authorize @conversation, :destroy?
    ::DeleteObjectJob.perform_later(@conversation, Current.user, request.ip)
    head :ok
  end

  private

  def auto_assign_conversation_on_view
    return unless should_auto_assign_conversation_on_view?

    assign_conversation
  end

  def should_auto_assign_conversation_on_view?
  account_user = Current.account_user

  Current.user.is_a?(User) &&
    (account_user&.agent? || account_user&.supervisor?) &&
    @conversation.status == 'open' &&
    @conversation.assignee_id.blank?
  end

  def permitted_update_params
    params.permit(:priority)
  end

  def attachment_params
    params.permit(:page)
  end

  def update_last_seen_on_conversation(last_seen_at, update_assignee)
    updates = { agent_last_seen_at: last_seen_at }
    updates[:assignee_last_seen_at] = last_seen_at if update_assignee.present?

    @conversation.update_columns(updates)

    ::Conversations::UnreadCounts::Notifier.new(@conversation).perform
  end

  def should_update_last_seen?
    agent_needs_update = @conversation.agent_last_seen_at.blank? || @conversation.agent_last_seen_at < 1.hour.ago
    return agent_needs_update unless assignee?

    assignee_needs_update = @conversation.assignee_last_seen_at.blank? || @conversation.assignee_last_seen_at < 1.hour.ago
    agent_needs_update || assignee_needs_update
  end

  def set_conversation_status
    @conversation.status = params[:status]
    @conversation.snoozed_until = parse_date_time(params[:snoozed_until].to_s) if params[:snoozed_until]
  end

  def assign_conversation
    Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: current_user.id,
      actor: Current.user
    ).perform
  rescue Conversations::AssignmentService::AssignmentError
    nil
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:id])
    authorize @conversation, :show?
  end

  def inbox
    return if params[:inbox_id].blank?

    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def contact
    return if params[:contact_id].blank?

    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def contact_inbox
    @contact_inbox = build_contact_inbox
    @contact_inbox ||= ::ContactInbox.find_by!(source_id: params[:source_id])
    authorize @contact_inbox.inbox, :show?
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'source_id should be unique' }, status: :unprocessable_entity
  end

  def build_contact_inbox
    return if @inbox.blank? || @contact.blank?

    ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: params[:source_id],
      hmac_verified: hmac_verified?
    ).perform
  end

  def conversation_finder
    @conversation_finder ||= ConversationFinder.new(Current.user, params)
  end

  def assignee?
    @conversation.assignee_id? && Current.user == @conversation.assignee
  end
end

Api::V1::Accounts::ConversationsController.prepend_mod_with('Api::V1::Accounts::ConversationsController')
