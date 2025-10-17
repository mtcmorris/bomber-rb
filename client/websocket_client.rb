require 'websocket-client-simple'
require 'json'

class WebSocketClient
  attr_reader :player_id, :connected

  def initialize(url = 'ws://localhost:8080')
    @url = url
    @connected = false
    @player_id = nil
    @game_state = nil
    @ws = nil
  end

  def connect
    @ws = WebSocket::Client::Simple.connect(@url)

    client = self  # Capture self in closure

    @ws.on :open do |event|
      puts "Connected to game server"
      client.instance_variable_set(:@connected, true)
    end

    @ws.on :message do |event|
      puts "Received message: #{event.data}"
      client.send(:handle_message, event.data)
    end

    @ws.on :close do |event|
      puts "Disconnected from game server"
      client.instance_variable_set(:@connected, false)
    end

    @ws.on :error do |event|
      puts "WebSocket error: #{event.inspect}"
    end

    # Wait for connection
    sleep 0.1 until @connected
  end

  def send_action(action)
    return false unless @connected && @ws

    message = {
      type: 'action',
      action: action
    }

    @ws.send(JSON.generate(message))
    true
  end

  def wait_for_game_state
    start_time = Time.now
    while @game_state.nil? && (Time.now - start_time) < 5.0
      sleep 0.01
    end
    @game_state
  end

  def close
    @ws&.close
    @connected = false
  end

  private
  
  def handle_message(data)
    begin
      message = JSON.parse(data)

      case message['type']
      when 'connected'
        @player_id = message['player_id']
        puts "Assigned player ID: #{@player_id}"
      when 'game_state'
        @game_state = message['state']
      when 'game_over'
        puts "Game over! Winner: #{message['winner'] || 'Draw'}"
        @game_state = message['final_state']
      when 'pong'
        # Handle ping response
      end
    rescue JSON::ParserError => e
      puts "Failed to parse message: #{e.message}"
    end
  end
end