class SessionsController < ApplicationController

  skip_before_action :login_required

  def index
  end

  def new
  end
end
