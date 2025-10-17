#!/usr/bin/env ruby

require_relative 'websocket_client'

class SampleBot
  def initialize(server_url = 'ws://localhost:8080')
    @client = WebSocketClient.new(server_url)
    @last_state = nil
  end
  
  def run
    puts "Starting sample bot..."
    @client.connect
    
    loop do
      state = @client.wait_for_game_state
      break unless state
      
      @last_state = state
      
      # Skip if we're dead
      me = state['players'][state['you']]
      unless me && me['alive']
        sleep 0.1
        next
      end
      
      action = decide_action(state)
      puts "Tick #{state['tick']}: #{action}"
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
    
    # Check if we're in danger from any bombs
    if in_danger?(my_x, my_y, bombs, grid)
      safe_move = find_safe_move(my_x, my_y, bombs, grid, state['players'])
      return safe_move if safe_move
    end
    
    # Look for soft walls to bomb
    if me['bombs_available'] > 0 && should_place_bomb?(my_x, my_y, grid)
      return 'bomb'
    end
    
    # Move towards soft walls or powerups
    target_move = find_target_move(my_x, my_y, grid, state['players'])
    return target_move if target_move
    
    # Random move as fallback
    directions = ['up', 'down', 'left', 'right']
    valid_directions = directions.select do |dir|
      new_x, new_y = apply_direction(my_x, my_y, dir)
      can_move_to?(new_x, new_y, grid, bombs, state['players'])
    end
    
    valid_directions.empty? ? 'pass' : "move #{valid_directions.sample}"
  end
  
  def in_danger?(x, y, bombs, grid)
    bombs.any? do |bomb|
      bomb['ticks_until_explosion'] <= 2 && 
      will_hit?(x, y, bomb['x'], bomb['y'], bomb['blast_radius'], grid)
    end
  end
  
  def will_hit?(target_x, target_y, bomb_x, bomb_y, radius, grid)
    return true if target_x == bomb_x && target_y == bomb_y
    
    if target_x == bomb_x
      distance = (target_y - bomb_y).abs
      return false if distance > radius
      
      min_y, max_y = [bomb_y, target_y].minmax
      (min_y + 1...max_y).each do |check_y|
        return false if grid[check_y][bomb_x] == '#'
      end
      return true
    end
    
    if target_y == bomb_y
      distance = (target_x - bomb_x).abs
      return false if distance > radius
      
      min_x, max_x = [bomb_x, target_x].minmax
      (min_x + 1...max_x).each do |check_x|
        return false if grid[bomb_y][check_x] == '#'
      end
      return true
    end
    
    false
  end
  
  def find_safe_move(x, y, bombs, grid, players)
    directions = ['up', 'down', 'left', 'right']
    
    safe_directions = directions.select do |dir|
      new_x, new_y = apply_direction(x, y, dir)
      next false unless can_move_to?(new_x, new_y, grid, bombs, players)
      !in_danger?(new_x, new_y, bombs, grid)
    end
    
    return "move #{safe_directions.sample}" unless safe_directions.empty?
    
    # If no safe moves, try any valid move
    valid_directions = directions.select do |dir|
      new_x, new_y = apply_direction(x, y, dir)
      can_move_to?(new_x, new_y, grid, bombs, players)
    end
    
    valid_directions.empty? ? 'pass' : "move #{valid_directions.sample}"
  end
  
  def should_place_bomb?(x, y, grid)
    # Check if there are soft walls or powerups nearby
    [[-1, 0], [1, 0], [0, -1], [0, 1]].any? do |dx, dy|
      check_x, check_y = x + dx, y + dy
      next false unless valid_position?(check_x, check_y, grid)
      grid[check_y][check_x] == '+' || ['B', 'F', 'S'].include?(grid[check_y][check_x])
    end
  end
  
  def find_target_move(x, y, grid, players)
    directions = ['up', 'down', 'left', 'right']
    
    # Look for moves that get us closer to soft walls or powerups
    scored_moves = directions.map do |dir|
      new_x, new_y = apply_direction(x, y, dir)
      next [dir, -1000] unless can_move_to?(new_x, new_y, grid, [], players)
      
      score = 0
      
      # Score based on proximity to soft walls and powerups
      grid.each_with_index do |row, grid_y|
        row.each_with_index do |cell, grid_x|
          if cell == '+' || ['B', 'F', 'S'].include?(cell)
            distance = (new_x - grid_x).abs + (new_y - grid_y).abs
            score += cell == '+' ? (20 - distance) : (30 - distance)
          end
        end
      end
      
      [dir, score]
    end
    
    best_move = scored_moves.max_by { |_, score| score }
    best_move && best_move[1] > 0 ? "move #{best_move[0]}" : nil
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
  bot = SampleBot.new(server_url)
  bot.run
end