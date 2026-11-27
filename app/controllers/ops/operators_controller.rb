module Ops
  # 運営者の管理。運営者に権限の区別は無く、全員が同じ操作をできる
  class OperatorsController < BaseController
    before_action :set_operator, only: [:edit, :update]

    def index
      @operators = Operator.order(:created_at)
    end

    def new
      @operator = Operator.new
    end

    def create
      attributes = params.expect(operator: [:email, :display_name])
      @operator = Operator.invite(email: attributes[:email], display_name: attributes[:display_name], by: current_operator)

      if @operator.persisted?
        redirect_to ops_operators_path, notice: t(".done", email: @operator.email)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @operator.update(params.expect(operator: [:display_name]))
        redirect_to ops_operators_path, notice: t("messages.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # 自分は止められない（有効な運営者が必ず1人は残る）
    def confirm_suspend
      @operator = others.active.find(params[:id])
    end

    def suspend
      operator = others.active.find(params[:id])
      operator.update!(status: :suspended)
      redirect_to edit_ops_operator_path(operator), notice: t(".done")
    end

    def resume
      operator = Operator.suspended.find(params[:id])
      operator.update!(status: :active)
      redirect_to edit_ops_operator_path(operator), notice: t(".done")
    end

    def resend_invitation
      operator = Operator.invited.find(params[:id])
      operator.send_invitation!(by: current_operator)
      redirect_to edit_ops_operator_path(operator), notice: t(".done")
    end

    # 招待の取り消し。一度もログインしていないので、停止ではなく行ごと消す
    def confirm_destroy
      @operator = Operator.invited.find(params[:id])
    end

    def destroy
      Operator.invited.find(params[:id]).destroy!
      redirect_to ops_operators_path, notice: t(".done")
    end

    private

    def set_operator
      @operator = Operator.find(params[:id])
    end

    def others
      Operator.where.not(id: current_operator.id)
    end
  end
end
