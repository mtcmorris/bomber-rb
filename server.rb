#!/usr/bin/env ruby

require 'eventmachine'
require 'thin'
require 'socket'
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
    
    # Check if ports are available
    check_port_availability(@websocket_port, "WebSocket")
    check_port_availability(@web_port, "Web")
    
    # Start the WebSocket server first
    @websocket_server = WebSocketServer.new(@websocket_port)
    
    # Start the web server in a separate thread
    web_thread = Thread.new do
      begin
        puts "Starting web server on port #{@web_port}..."
        @web_server = WebServer
        @web_server.set :port, @web_port
        @web_server.set :bind, '0.0.0.0'
        @web_server.set :logging, false  # Reduce Sinatra noise
        @web_server.game_server = @websocket_server
        @web_server.run!
      rescue => e
        puts "ERROR: Failed to start web server: #{e.message}"
        puts "This usually means port #{@web_port} is already in use."
        EventMachine.stop if EventMachine.reactor_running?
        exit 1
      end
    end
    
    # Give web server time to start
    sleep 2
    
    # Handle shutdown gracefully
    trap('INT') do
      puts "\nShutting down servers..."
      EventMachine.stop if EventMachine.reactor_running?
      web_thread.kill if web_thread
      exit 0
    end
    
    # Start the WebSocket server (this will block)
    puts "Starting WebSocket game server..."
    @websocket_server.start
  end
  
  private
  
  def check_port_availability(port, service_name)
    begin
      server = TCPServer.new('0.0.0.0', port)
      server.close
      puts "✓ Port #{port} (#{service_name}) is available"
    rescue Errno::EADDRINUSE
      puts "✗ ERROR: Port #{port} (#{service_name}) is already in use!"
      puts "  Try stopping any other servers or use different ports:"
      puts "  ruby server.rb [websocket_port] [web_port]"
      puts "  Example: ruby server.rb 8081 4568"
      exit 1
    rescue => e
      puts "WARNING: Could not check port #{port}: #{e.message}"
    end
  end
end

if __FILE__ == $0
  if ARGV.include?('--help') || ARGV.include?('-h')
    puts "Bomberman Game Server"
    puts "Usage: ruby server.rb [websocket_port] [web_port]"
    puts ""
    puts "Default ports:"
    puts "  WebSocket: 8080"
    puts "  Web:       4567"
    puts ""
    puts "Examples:"
    puts "  ruby server.rb              # Use default ports"
    puts "  ruby server.rb 8081         # WebSocket on 8081, Web on 4567"
    puts "  ruby server.rb 8081 4568    # WebSocket on 8081, Web on 4568"
    exit 0
  end
  
  begin
    websocket_port = ARGV[0]&.to_i || 8080
    web_port = ARGV[1]&.to_i || 4567
    
    # Validate port numbers
    [websocket_port, web_port].each do |port|
      if port < 1024 || port > 65535
        puts "ERROR: Port #{port} is invalid. Use ports between 1024-65535."
        exit 1
      end
    end
    
    if websocket_port == web_port
      puts "ERROR: WebSocket and Web ports cannot be the same!"
      exit 1
    end
    
    server = GameServer.new(websocket_port, web_port)
    server.start
    
  rescue Interrupt
    puts "\nServer stopped by user"
    exit 0
  rescue => e
    puts "FATAL ERROR: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end