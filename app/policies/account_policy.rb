class AccountPolicy < ApplicationPolicy
  def show?
    staff_user?
  end

  def cache_keys?
    staff_user?
  end

  def limits?
    staff_user?
  end

  def update?
    @account_user.administrator?
  end

  def update_active_at?
    true
  end

  def subscription?
    @account_user.administrator?
  end

  def checkout?
    @account_user.administrator?
  end

  def toggle_deletion?
    @account_user.administrator?
  end

  def topup_checkout?
    @account_user.administrator?
  end

  private

  def staff_user?
    @account_user.administrator? || @account_user.agent? || @account_user.supervisor?
  end
end
