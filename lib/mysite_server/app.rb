require 'sinatra/base'
require 'eventmachine'
require 'thin'
require 'newrelic_rpm'

options = {}
options = MySite_Server.configuration(options)
$mySite = MySite_Server::Site.new(options)

module MySite_Server
  class App < Sinatra::Base

    configure :production, :development do
      disable :logging
      set :public_folder, File.dirname(__FILE__)
    end

    before do
      cache_control :public, :must_revalidate, :max_age => 60
    end

    not_found do
      status 404
      if res = $mySite.getResponse("404.html")
        headers \
          "Content-Type"                => "text/html",
          "Vary"                        => "Accept-Encoding",
          "Content-Encoding"            => "gzip",
          "X-UA-Compatible"             => "IE=Edge,chrome=1",
          "Access-Control-Allow-Origin" => "*"
        etag res[:etag]
        body res[:body]
      else
        send_file("404.html")
      end
    end
    
    error 403 do
      'Access forbidden'
    end

    error do
      'Sorry there was a nasty error - ' + env['sinatra.error'].name
    end

    get '/*' do |url|
      if res = $mySite.getResponse(url)
        status 200
        headers \
          "Vary"                        => "Accept-Encoding",
          "Content-Encoding"            => "gzip",
          "X-UA-Compatible"             => "IE=Edge,chrome=1",
          "Access-Control-Allow-Origin" => "*",
          "X-XSS-Protection"            => "1; mode=block",
          "X-Frame-Options"             => "SAMEORIGIN",
          "Date"                        => Time.now.httpdate
        etag res[:etag]
        body res[:body]
      else
        send_file(url)
      end
    end
  end
end