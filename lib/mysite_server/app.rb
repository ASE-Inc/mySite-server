require 'sinatra/base'
require 'eventmachine'
require 'thin'

options = {}
options = MySite_Server.configuration(options)
$mySite = MySite_Server::Site.new(options)

module MySite_Server
  class App < Sinatra::Base

    configure :production, :development do
      enable :logging
      set :public_folder, File.dirname(__FILE__)
    end

    before do
      cache_control :public, :must_revalidate, :max_age => 60
    end

    not_found do
      status 404
      headers \
        "Content-Type"=> "text/html"
      send_file "404.html"
    end
    
    error 403 do
      'Access forbidden'
    end

    error do
      'Sorry there was a nasty error - ' + env['sinatra.error'].name
    end

    get '/*' do |url|
      url = "/#{url}"
      if res = $mySite.getResponse(url)
        status 200
        headers \
          "Content-Encoding"            => "gzip",
          "X-UA-Compatible"             => "IE=Edge,chrome=1",
          "Access-Control-Allow-Origin" => "*"
        body res
      else
        send_file(url)
      end
    end
  end
end