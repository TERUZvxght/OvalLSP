# frozen_string_literal: true

class UsersController
  def show
    @user = User.find(params[:id])
  end
end
