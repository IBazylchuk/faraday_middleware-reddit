# encoding: utf-8

require 'faraday'

module FaradayMiddleware
  module Reddit
    # Request middleware that automatically handles user login.
    #
    # Requires that either a `user` and `password` are provided or a
    # pre-generated `cookie`. Performs an additional login request when no
    # valid login cookie is available.
    class Authentication < Faraday::Middleware
      include ModhashHelpers

      AUTH_DOMAIN = 'https://ssl.reddit.com'.freeze
      AUTH_PATH   = "/api/login".freeze
      AUTH_URL    = "#{AUTH_DOMAIN}#{AUTH_PATH}"

      def initialize(app, options)
        super(app)
        @options      = options
        @user         = @options[:user]
        @passwd       = @options[:password]
        @rem          = @options[:remember]
        @access_token = @options[:access_token]
        @cookie       = @options[:cookie]

        unless (@options[:user] && @options[:password]) || @options[:cookie] || @options[:access_token]
          fail ArgumentError, 'Either `user` and `password`, `cookie`, or `access_token` need to be provided as options to the :reddit_authentication middleware'
        end
      end

      def call(env)
        if @access_token
          apply_access_token(env)
        elsif @cookie
          apply_cookie(env)
        else
          authenticate(env)
          apply_cookie(env)
        end

        @app.call(env)
      end

      def apply_access_token(env)
        env.url.scheme = 'https'
        env.url.port = 443
        env.url.host = 'oauth.reddit.com'
        env[:request_headers]['Authorization'] = "bearer #{@access_token}"
      end

      def apply_cookie(env)
        upstream_cookies = env[:request_headers]['Cookie']
        env[:request_headers]['Cookie'] = upstream_cookies ? "#{upstream_cookies}; #{@cookie}" : @cookie
      end

      def authenticate(env)
        response = connection(env).post AUTH_PATH, user: @user, passwd: @passwd, rem: @rem, api_type: 'json'
        env[:modhash] = extract_modhash(response.env)
        @cookie = response.headers['set-cookie']
      end

      def connection(env)
        Faraday.new(url: AUTH_DOMAIN, headers: env['request_headers']) do |faraday|
          faraday.request  :url_encoded
          faraday.request  :retry, max: 5, interval: 2, exceptions: FaradayMiddleware::Reddit::RETRIABLE_ERRORS
          faraday.response :reddit_raise_error
          faraday.adapter  Faraday.default_adapter
        end
      end
    end
  end
end
