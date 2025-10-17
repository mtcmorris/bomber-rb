#!/usr/bin/env ruby

require_relative 'websocket_client'

class SampleBot
  def initialize(server_url = 'ws://localhost:8080', name = nil)
    @name = name || `whoami`.strip
    @client = WebSocketClient.new(server_url, @name)
    @last_state = nil
    @last_processed_tick = -1
  end
  
  def run
    puts "Starting sample bot '#{@name}'..."
    @client.connect
    
    loop do
      state = @client.wait_for_game_state
      break unless state
      
      # Skip if we've already processed this tick
      current_tick = state['tick']
      if current_tick <= @last_processed_tick
        sleep 0.1
        next
      end
      
      @last_state = state
      @last_processed_tick = current_tick
      
      # Skip if we're dead
      me = state['players'][state['you']]
      unless me && me['alive']
        sleep 0.1
        next
      end
      
      action = decide_action(state)
      puts "Tick #{current_tick}: #{action}"
      @client.send_action(action)
      
      break if state['game_over'] rescue false
      sleep 0.1
    end
    
    @client.close
    puts "Bot finished"
  end
  
  private
  
  def decide_action(state)
    me = state['players'][state['you']]
    grid = state['grid']
    bombs = state['bombs']
    
    my_x, my_y = me['x'], me['y']
    
    # 20% chance to drop a bomb if we have one available
    if me['bombs_available'] > 0 && rand < 0.2
      return 'bomb'
    end
    
    # Try to move in a random direction
    directions = ['up', 'down', 'left', 'right']
    valid_directions = directions.select do |dir|
      new_x, new_y = apply_direction(my_x, my_y, dir)
      can_move_to?(new_x, new_y, grid, bombs, state['players'])
    end
    
    valid_directions.empty? ? 'pass' : "move #{valid_directions.sample}"
  end
  
  
  def apply_direction(x, y, direction)
    case direction
    when 'up' then [x, y - 1]
    when 'down' then [x, y + 1]
    when 'left' then [x - 1, y]
    when 'right' then [x + 1, y]
    else [x, y]
    end
  end
  
  def can_move_to?(x, y, grid, bombs, players)
    return false unless valid_position?(x, y, grid)
    return false if grid[y][x] == '#' || grid[y][x] == '+'
    return false if bombs.any? { |bomb| bomb['x'] == x && bomb['y'] == y }
    return false if players.any? { |_, player| player['x'] == x && player['y'] == y && player['alive'] }
    true
  end
  
  def valid_position?(x, y, grid)
    x >= 0 && x < grid[0].length && y >= 0 && y < grid.length
  end
end

if __FILE__ == $0
  server_url = ARGV[0] || 'ws://localhost:8080'
  name = ARGV[1]
  bot = SampleBot.new(server_url, name)
  bot.run
end