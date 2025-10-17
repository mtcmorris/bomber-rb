#!/usr/bin/env ruby

require 'eventmachine'
require 'thin'
require_relative 'lib/websocket_server'
require_relative 'lib/web_server'

class GameServer
  def initialize(websocket_port = 8080, web_port = 4567)
    @websocket_port = websocket_port
    @web_port = web_port
    @websocket_server = nil
    @web_server = nil
  end
  
  def start
    puts "Starting Bomberman Game Server..."
    puts "WebSocket server will run on port #{@websocket_port}"
    puts "Web interface will run on port #{@web_port}"
    puts "Visit http://localhost:#{@web_port} to view the game"
    puts ""
    
    # Start the WebSocket server first
    @websocket_server = WebSocketServer.new(@websocket_port)
    
    # Start the web server in a separate thread
    web_thread = Thread.new do
      @web_server = WebServer
      @web_server.set :port, @web_port
      @web_server.set :bind, '0.0.0.0'
      @web_server.game_server = @websocket_server
      @web_server.run!
    end
    
    # Give web server time to start
    sleep 1
    
    # Handle shutdown gracefully
    trap('INT') do
      puts "\nShutting down servers..."
      EventMachine.stop if EventMachine.reactor_running?
      web_thread.kill if web_thread
      exit 0
    end
    
    # Start the WebSocket server (this will block)
    @websocket_server.start
  end
end

if __FILE__ == $0
  websocket_port = ARGV[0]&.to_i || 8080
  web_port = ARGV[1]&.to_i || 4567
  
  server = GameServer.new(websocket_port, web_port)
  server.start
end