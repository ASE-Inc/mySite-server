require 'eventmachine'

EventMachine.run {
  require 'em-http'
  require './lib/mysite_server'
  require './lib/mysite_server/app'
  Thin::Server.start MySite_Server::App, "0.0.0.0", ENV["PORT"]
}