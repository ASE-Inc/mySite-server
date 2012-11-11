require 'eventmachine'
require "sinatra"

EventMachine.run {
  require 'em-http'
  require './lib/mysite_server'
  require './lib/mysite_server/app'
  puts "starting..."
  run MySite_Server::App
  puts "Started."
}