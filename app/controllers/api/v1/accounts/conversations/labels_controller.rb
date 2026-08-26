class Api::V1::Accounts::Conversations::LabelsController < Api::V1::Accounts::Conversations::BaseController
  include LabelConcern

  def create
    labels = Array(params[:labels]).compact_blank
    selected_label = labels.last

    @conversation.label_list = selected_label.present? ? [selected_label] : []
    @conversation.save!
  end

  def destroy
    @conversation.label_list.remove(params[:id])
    @conversation.save!
  end

  private

  def model
    @model ||= @conversation
  end

  def permitted_params
    params.permit(:conversation_id, labels: [])
  end
end
