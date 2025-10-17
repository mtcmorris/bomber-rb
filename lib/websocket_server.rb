require 'eventmachine'
require 'em-websocket'
require 'json'
require_relative 'game'

class WebSocketServer
  attr_reader :game, :clients, :port
  
  def initialize(port = 8080)
    @port = port
    @game = Game.new
    @clients = {}
    @game_timer = nil
    @turn_timeout = 1.0
  end
  
  def start
    EventMachine.run do
      EventMachine::WebSocket.run(host: '0.0.0.0', port: @port) do |ws|
        ws.onopen { |handshake| handle_open(ws, handshake) }
        ws.onmessage { |message| handle_message(ws, message) }
        ws.onclose { handle_close(ws) }
        ws.onerror { |error| handle_error(ws, error) }
      end
      
      puts "WebSocket server listening on port #{@port}"
      start_game_loop
    end
  end
  
  def broadcast_game_state
    @clients.each do |ws, client|
      state = @game.state_for_player(client[:player_id])
      send_to_client(ws, {
        type: 'game_state',
        state: state
      })
    end
  end
  
  private
  
  def handle_open(ws, handshake)
    puts "Client connected: #{ws.object_id}"
    
    player_id = "player#{@clients.length + 1}"
    
    spawn_positions = [[1, 1], [13, 13], [1, 13], [13, 1]]
    spawn_x, spawn_y = spawn_positions[@clients.length % spawn_positions.length]
    
    if @game.add_player(player_id, spawn_x, spawn_y)
      @clients[ws] = {
        player_id: player_id,
        last_action: nil,
        action_received: false
      }
      
      send_to_client(ws, {
        type: 'connected',
        player_id: player_id,
        message: "Connected as #{player_id}"
      })
      
      broadcast_game_state
    else
      ws.close_connection
    end
  end
  
  def handle_message(ws, message)
    begin
      data = JSON.parse(message)
      client = @clients[ws]
      
      return unless client
      
      case data['type']
      when 'action'
        client[:last_action] = data['action']
        client[:action_received] = true
        puts "Received action from #{client[:player_id]}: #{data['action']}"
      when 'ping'
        send_to_client(ws, { type: 'pong' })
      end
    rescue JSON::ParserError => e
      puts "Invalid JSON from client: #{e.message}"
    end
  end
  
  def handle_close(ws)
    client = @clients.delete(ws)
    if client
      puts "Client disconnected: #{client[:player_id]}"
      @game.players.delete(client[:player_id])
      broadcast_game_state
    end
  end
  
  def handle_error(ws, error)
    puts "WebSocket error: #{error}"
  end
  
  def send_to_client(ws, data)
    ws.send(JSON.generate(data))
  end
  
  def broadcast(data)
    @clients.each { |ws, _| send_to_client(ws, data) }
  end
  
  def start_game_loop
    @game_timer = EventMachine::PeriodicTimer.new(2.0) do
      process_turn
    end
  end
  
  def process_turn
    return if @game.game_over
    
    @clients.each do |ws, client|
      next unless @game.players[client[:player_id]]&.dig(:alive)
      
      action = client[:action_received] ? client[:last_action] : 'pass'
      
      if action && action != 'pass'
        success = @game.process_action(client[:player_id], action)
        unless success
          puts "Invalid action from #{client[:player_id]}: #{action}"
        end
      end
      
      client[:last_action] = nil
      client[:action_received] = false
    end
    
    @game.tick!
    broadcast_game_state
    
    if @game.game_over
      broadcast({
        type: 'game_over',
        winner: @game.winner,
        final_state: @game.state_for_player(@clients.values.first&.dig(:player_id) || 'player1')
      })
      
      @game_timer.cancel if @game_timer
      puts "Game over! Winner: #{@game.winner || 'Draw'}"
    end
  end
end