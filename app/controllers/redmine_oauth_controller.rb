require 'account_controller'
require 'json'

class RedmineOauthController < AccountController
  def oauth_google
    if Setting.openid?
      redirect_to oauth_client.auth_code.authorize_url(redirect_uri: oauth_google_callback_url, scope: scopes)
    else
      password_authentication
    end
  end

  def oauth_google_callback
    token = oauth_client.auth_code.get_token(params[:code], redirect_uri: oauth_google_callback_url)
    result = token.get('https://www.googleapis.com/oauth2/v1/userinfo')
    info = JSON.parse(result.body)
    if info && info["verified_email"]
      user = User.find_or_initialize_by_mail(info["email"])
      if user.new_record?
        # Self-registration off
        redirect_to(home_url) && return unless Setting.self_registration?
        # Create on the fly
        user.firstname, user.lastname = info["name"].split(' ') unless info['name'].nil?
        user.firstname ||= info[:given_name]
        user.lastname ||= info[:family_name]
        user.mail = info["email"]
        user.login = email_prefix(info["email"])
        user.login ||= [user.firstname, user.lastname]*"."
        user.random_password
        user.register

        case Setting.self_registration
        when '1'
          register_by_email_activation(user) do
            onthefly_creation_failed(user)
          end
        when '3'
          register_automatically(user) do
            onthefly_creation_failed(user)
          end
        else
          register_manually_by_administrator(user) do
            onthefly_creation_failed(user)
          end
        end
      else
        # Existing record
        if user.active?
          successful_authentication(user)
        else
          account_pending
        end
      end
    else
      flash[:error] = l(:notice_unable_to_obtain_google_credentials)
      redirect_to signin_path
    end
  end

  def email_prefix email
    prefix = email.match(/(.+?)@/) if email
    prefix[1] if prefix
  end

  def oauth_client
    @client ||= OAuth2::Client.new(settings[:client_id], settings[:client_secret],
      site: 'https://accounts.google.com',
      authorize_url: '/o/oauth2/auth',
      token_url: '/o/oauth2/token')
  end

  def settings
    @settings ||= Setting.plugin_redmine_omniauth_google
  end

  def scopes
    'https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile'
  end
end