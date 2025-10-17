require 'json'

class Game
  GRID_SIZE = 15
  BOMB_TIMER = 3
  BLAST_RADIUS = 2
  
  attr_reader :grid, :players, :bombs, :tick, :powerups, :game_over, :winner, :leaderboard, :explosions
  
  def initialize
    @grid = generate_grid
    @players = {}
    @bombs = []
    @powerups = {}
    @tick = 0
    @game_over = false
    @winner = nil
    @leaderboard = {}
    @respawn_queue = []
    @explosions = []
  end
  
  def add_player(id, x = nil, y = nil)
    return false if @players.key?(id)
    
    # Find random spawn position if not provided
    if x.nil? || y.nil?
      spawn_pos = find_random_spawn_position
      return false unless spawn_pos
      x, y = spawn_pos
    else
      return false unless valid_position?(x, y) && @grid[y][x] == '.'
    end
    
    @players[id] = {
      x: x,
      y: y,
      alive: true,
      bombs_available: 1,
      blast_radius: BLAST_RADIUS,
      speed_boost_turns: 0,
      spawn_time: @tick
    }
    
    # Initialize leaderboard entry
    @leaderboard[id] ||= {
      kills: 0,
      deaths: 0,
      total_survival_time: 0,
      current_life_start: @tick,
      best_kills_in_life: 0,
      best_survival_time: 0,
      current_life_kills: 0
    }
    
    true
  end
  
  def process_action(player_id, action)
    return false unless @players[player_id] && @players[player_id][:alive]
    
    parts = action.strip.split
    command = parts[0]
    
    case command
    when 'move'
      direction = parts[1]
      move_player(player_id, direction)
    when 'bomb'
      place_bomb(player_id)
    when 'pass'
      true
    else
      false
    end
  end
  
  def tick!
    @tick += 1
    
    update_speed_boosts
    process_bombs
    check_explosions
    check_powerup_collection
    process_respawns
    process_explosions
    
    @tick
  end
  
  def state_for_player(player_id)
    {
      tick: @tick,
      you: player_id,
      players: @players,
      bombs: @bombs.map do |bomb|
        {
          x: bomb[:x],
          y: bomb[:y],
          owner: bomb[:owner],
          ticks_until_explosion: bomb[:timer],
          blast_radius: bomb[:blast_radius]
        }
      end,
      explosions: @explosions,
      grid: @grid
    }
  end
  
  private
  
  def generate_grid
    grid = Array.new(GRID_SIZE) { Array.new(GRID_SIZE, '.') }
    
    (0...GRID_SIZE).each do |y|
      (0...GRID_SIZE).each do |x|
        if x == 0 || x == GRID_SIZE - 1 || y == 0 || y == GRID_SIZE - 1
          grid[y][x] = '#'
        elsif x % 2 == 0 && y % 2 == 0
          grid[y][x] = '#'
        elsif rand < 0.4 # Reduced from 0.7 to 0.4 for fewer soft walls
          grid[y][x] = '+'
        end
      end
    end
    
    grid
  end
  
  def valid_position?(x, y)
    x >= 0 && x < GRID_SIZE && y >= 0 && y < GRID_SIZE
  end
  
  def can_move_to?(x, y)
    return false unless valid_position?(x, y)
    return false if @grid[y][x] == '#' || @grid[y][x] == '+'
    
    @bombs.none? { |bomb| bomb[:x] == x && bomb[:y] == y }
  end
  
  def move_player(player_id, direction)
    player = @players[player_id]
    dx, dy = direction_to_delta(direction)
    new_x = player[:x] + dx
    new_y = player[:y] + dy
    
    if can_move_to?(new_x, new_y)
      player[:x] = new_x
      player[:y] = new_y
      true
    else
      false
    end
  end
  
  def place_bomb(player_id)
    player = @players[player_id]
    return false if player[:bombs_available] <= 0
    
    existing_bomb = @bombs.find { |bomb| bomb[:x] == player[:x] && bomb[:y] == player[:y] }
    return false if existing_bomb
    
    @bombs << {
      x: player[:x],
      y: player[:y],
      owner: player_id,
      timer: BOMB_TIMER,
      blast_radius: player[:blast_radius]
    }
    
    player[:bombs_available] -= 1
    true
  end
  
  def direction_to_delta(direction)
    case direction
    when 'up' then [0, -1]
    when 'down' then [0, 1]
    when 'left' then [-1, 0]
    when 'right' then [1, 0]
    else [0, 0]
    end
  end
  
  def update_speed_boosts
    @players.each do |_, player|
      if player[:speed_boost_turns] > 0
        player[:speed_boost_turns] -= 1
      end
    end
  end
  
  def process_bombs
    @bombs.each { |bomb| bomb[:timer] -= 1 }
    
    exploding_bombs = @bombs.select { |bomb| bomb[:timer] <= 0 }
    exploding_bombs.each do |bomb| 
      explode_bomb(bomb)
      # Give bomb back to owner when it explodes
      if @players[bomb[:owner]]
        @players[bomb[:owner]][:bombs_available] += 1
      end
    end
    
    @bombs.reject! { |bomb| bomb[:timer] <= 0 }
  end
  
  def explode_bomb(bomb)
    explosion_coords = calculate_explosion(bomb[:x], bomb[:y], bomb[:blast_radius])
    killed_players = []
    
    # Add explosion visual effect that lasts for 2 ticks
    explosion_coords.each do |x, y|
      @explosions << {
        x: x,
        y: y,
        expires_at: @tick + 2
      }
    end
    
    explosion_coords.each do |x, y|
      if @grid[y][x] == '+'
        @grid[y][x] = '.'
        maybe_spawn_powerup(x, y)
      end
      
      @players.each do |player_id, player|
        if player[:x] == x && player[:y] == y && player[:alive]
          player[:alive] = false
          killed_players << player_id
          
          # Update leaderboard for killed player
          survival_time = @tick - @leaderboard[player_id][:current_life_start]
          @leaderboard[player_id][:deaths] += 1
          @leaderboard[player_id][:total_survival_time] += survival_time
          
          # Update best stats
          if @leaderboard[player_id][:current_life_kills] > @leaderboard[player_id][:best_kills_in_life]
            @leaderboard[player_id][:best_kills_in_life] = @leaderboard[player_id][:current_life_kills]
          end
          
          if survival_time > @leaderboard[player_id][:best_survival_time]
            @leaderboard[player_id][:best_survival_time] = survival_time
          end
          
          # Reset current life stats
          @leaderboard[player_id][:current_life_kills] = 0
          
          # Queue for respawn in 5 seconds
          @respawn_queue << {
            player_id: player_id,
            respawn_tick: @tick + 5
          }
        end
      end
      
      chain_bombs = @bombs.select { |other_bomb| other_bomb[:x] == x && other_bomb[:y] == y }
      chain_bombs.each do |chain_bomb|
        explode_bomb(chain_bomb) if chain_bomb[:timer] > 0
        chain_bomb[:timer] = 0
      end
    end
    
    # Award kill to bomb owner (don't award points for self-kills)
    if killed_players.length > 0 && @leaderboard[bomb[:owner]]
      non_self_kills = killed_players.reject { |killed_id| killed_id == bomb[:owner] }
      @leaderboard[bomb[:owner]][:kills] += non_self_kills.length
      @leaderboard[bomb[:owner]][:current_life_kills] += non_self_kills.length
    end
  end
  
  def calculate_explosion(x, y, radius)
    coords = [[x, y]]
    
    [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dx, dy|
      (1..radius).each do |distance|
        nx, ny = x + dx * distance, y + dy * distance
        break unless valid_position?(nx, ny)
        break if @grid[ny][nx] == '#'
        
        coords << [nx, ny]
        break if @grid[ny][nx] == '+'
      end
    end
    
    coords
  end
  
  def maybe_spawn_powerup(x, y)
    return unless rand < 0.3
    
    powerup_type = ['B', 'F', 'S'].sample
    @grid[y][x] = powerup_type
  end
  
  def check_explosions
  end
  
  def check_powerup_collection
    @players.each do |player_id, player|
      next unless player[:alive]
      
      x, y = player[:x], player[:y]
      cell = @grid[y][x]
      
      case cell
      when 'B'
        player[:bombs_available] += 1
        @grid[y][x] = '.'
      when 'F'
        player[:blast_radius] += 1
        @grid[y][x] = '.'
      when 'S'
        player[:speed_boost_turns] = 10
        @grid[y][x] = '.'
      end
    end
  end
  
  def process_respawns
    ready_to_respawn = @respawn_queue.select { |entry| entry[:respawn_tick] <= @tick }
    
    ready_to_respawn.each do |entry|
      player_id = entry[:player_id]
      next unless @players[player_id] # Player still exists
      
      # Find random available spawn position
      spawn_pos = find_random_spawn_position
      
      if spawn_pos
        x, y = spawn_pos
        @players[player_id][:x] = x
        @players[player_id][:y] = y
        @players[player_id][:alive] = true
        @players[player_id][:bombs_available] = 1
        @players[player_id][:blast_radius] = BLAST_RADIUS
        @players[player_id][:speed_boost_turns] = 0
        
        @leaderboard[player_id][:current_life_start] = @tick
        @leaderboard[player_id][:current_life_kills] = 0
        
        @respawn_queue.delete(entry)
      end
    end
  end
  
  def can_respawn_at?(x, y)
    return false unless valid_position?(x, y) && @grid[y][x] == '.'
    return false if @players.any? { |_, player| player[:x] == x && player[:y] == y && player[:alive] }
    return false if @bombs.any? { |bomb| bomb[:x] == x && bomb[:y] == y }
    
    # Check if position is safe from explosions
    @bombs.each do |bomb|
      next if bomb[:timer] > 2 # Only worry about bombs exploding soon
      explosion_coords = calculate_explosion(bomb[:x], bomb[:y], bomb[:blast_radius])
      return false if explosion_coords.include?([x, y])
    end
    
    true
  end
  
  def process_explosions
    @explosions.reject! { |explosion| explosion[:expires_at] <= @tick }
  end
  
  def find_random_spawn_position
    # Get all empty positions on the grid
    empty_positions = []
    (0...GRID_SIZE).each do |y|
      (0...GRID_SIZE).each do |x|
        if @grid[y][x] == '.' && 
           !@players.any? { |_, player| player[:x] == x && player[:y] == y && player[:alive] } &&
           !@bombs.any? { |bomb| bomb[:x] == x && bomb[:y] == y }
          empty_positions << [x, y]
        end
      end
    end
    
    return nil if empty_positions.empty?
    empty_positions.sample
  end
end