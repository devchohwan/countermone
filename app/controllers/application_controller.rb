class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_security_headers

  private

  def set_security_headers
    response.set_header("X-Frame-Options", "DENY")
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Referrer-Policy", "strict-origin-when-cross-origin")
    response.set_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
  end
end
