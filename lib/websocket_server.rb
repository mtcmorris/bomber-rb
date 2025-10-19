require 'eventmachine'
require 'em-websocket'
require 'json'
require_relative 'game'

class WebSocketServer
  attr_reader :game, :clients, :port

  def initialize(port = 8080, tick_interval = 0.5)
    @port = port
    @tick_interval = tick_interval
    @game = Game.new
    @clients = {}
    @game_timer = nil
    @ip_connections = {} # Track connections per IP address
  end
  
  def start
    begin
      puts "Attempting to start WebSocket server on port #{@port}..."
      
      EventMachine.run do
        begin
          EventMachine::WebSocket.run(host: '0.0.0.0', port: @port) do |ws|
            ws.onopen { |handshake| handle_open(ws, handshake) }
            ws.onmessage { |message| handle_message(ws, message) }
            ws.onclose { handle_close(ws) }
            ws.onerror { |error| handle_error(ws, error) }
          end
          
          puts "WebSocket server successfully listening on port #{@port}"
          start_game_loop
          
        rescue => e
          puts "ERROR: Failed to start WebSocket server: #{e.message}"
          puts "This usually means port #{@port} is already in use."
          puts "Try stopping any other servers running on port #{@port} or use a different port."
          EventMachine.stop
          exit 1
        end
        
        # Handle EventMachine errors
        EventMachine.error_handler do |e|
          puts "EventMachine error: #{e.message}"
          puts e.backtrace.join("\n")
        end
      end
      
    rescue => e
      puts "FATAL ERROR: Could not start WebSocket server: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
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
    # Extract IP address from the socket's peer address
    ip_address = nil
    begin
      # Get the actual socket peer address
      peername = ws.get_peername
      if peername
        # Socket.unpack_sockaddr_in returns [port, ip_address]
        port, ip = Socket.unpack_sockaddr_in(peername)
        ip_address = ip
      end
    rescue => e
      puts "Could not extract IP address: #{e.message}"
    end

    # Fallback to checking headers if direct socket method fails
    ip_address ||= handshake.headers['X-Forwarded-For']&.split(',')&.first&.strip
    ip_address ||= 'unknown'

    puts "Client connected from IP: #{ip_address} (#{ws.object_id})"

    # Check if this IP already has a connection
    if @ip_connections[ip_address] && @ip_connections[ip_address] != ws
      puts "Rejecting connection: IP #{ip_address} already has a bot connected"
      ws.send(JSON.generate({
        type: 'error',
        message: 'Only one bot per IP address is allowed. Disconnect your other bot first.'
      }))
      ws.close_connection_after_writing
      return
    end

    # Track this IP
    @ip_connections[ip_address] = ws

    @clients[ws] = {
      player_id: nil,
      name: nil,
      last_action: nil,
      action_received: false,
      waiting_for_name: true,
      ip_address: ip_address
    }
  end
  
  def handle_message(ws, message)
    begin
      data = JSON.parse(message)
      client = @clients[ws]
      
      return unless client
      
      case data['type']
      when 'connect'
        if client[:waiting_for_name]
          name = data['name'] || 'Unknown'
          player_id = "#{name}_#{@clients.length}"
          
          if @game.add_player(player_id)
            client[:player_id] = player_id
            client[:name] = name
            client[:waiting_for_name] = false
            
            puts "Player '#{name}' joined as #{player_id}"
            
            send_to_client(ws, {
              type: 'connected',
              player_id: player_id,
              name: name,
              message: "Connected as #{name} (#{player_id})"
            })
            
            broadcast_game_state
          else
            ws.close_connection
          end
        end
      when 'action'
        unless client[:waiting_for_name]
          client[:last_action] = data['action']
          client[:action_received] = true
          puts "Received action from #{client[:name]} (#{client[:player_id]}): #{data['action']}"
        end
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
      # Remove IP tracking
      if client[:ip_address]
        @ip_connections.delete(client[:ip_address])
        puts "Freed IP slot: #{client[:ip_address]}"
      end

      if client[:player_id]
        puts "Player '#{client[:name]}' (#{client[:player_id]}) disconnected"
        @game.players.delete(client[:player_id])
        broadcast_game_state
      end
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
    puts "Game loop starting with tick interval: #{@tick_interval}s"
    @game_timer = EventMachine::PeriodicTimer.new(@tick_interval) do
      process_turn
    end
  end
  
  def process_turn
    puts "Processing turn #{@game.tick + 1}..."
    
    # Process actions for all connected clients
    @clients.each do |ws, client|
      next if client[:waiting_for_name]
      
      player = @game.players[client[:player_id]]
      next unless player&.dig(:alive)
      
      action = client[:action_received] ? client[:last_action] : 'pass'
      
      if action && action != 'pass'
        success = @game.process_action(client[:player_id], action)
        if success
          puts "#{client[:name]} (#{client[:player_id]}): #{action}"
        else
          puts "Invalid action from #{client[:name]} (#{client[:player_id]}): #{action}"
        end
      end
      
      # Reset for next turn
      client[:last_action] = nil
      client[:action_received] = false
    end
    
    # Always tick the game forward
    @game.tick!
    puts "Tick #{@game.tick} completed"
    
    # Send updated state to all clients
    broadcast_game_state
  end
end