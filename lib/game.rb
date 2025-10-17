require 'json'

class Game
  GRID_SIZE = 15
  BOMB_TIMER = 3
  BLAST_RADIUS = 2
  
  attr_reader :grid, :players, :bombs, :tick, :powerups, :game_over, :winner
  
  def initialize
    @grid = generate_grid
    @players = {}
    @bombs = []
    @powerups = {}
    @tick = 0
    @game_over = false
    @winner = nil
  end
  
  def add_player(id, x = 1, y = 1)
    return false if @players.key?(id)
    return false unless valid_position?(x, y) && @grid[y][x] == '.'
    
    @players[id] = {
      x: x,
      y: y,
      alive: true,
      bombs_available: 1,
      blast_radius: BLAST_RADIUS,
      speed_boost_turns: 0
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
    check_game_over
    
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
        elsif rand < 0.7 && !(x == 1 && y == 1) && !(x == GRID_SIZE - 2 && y == GRID_SIZE - 2)
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
    exploding_bombs.each { |bomb| explode_bomb(bomb) }
    
    @bombs.reject! { |bomb| bomb[:timer] <= 0 }
    
    @players.each do |player_id, player|
      active_bombs = @bombs.count { |bomb| bomb[:owner] == player_id }
      total_bombs = player[:bombs_available] + active_bombs
      player[:bombs_available] = total_bombs - active_bombs
    end
  end
  
  def explode_bomb(bomb)
    explosion_coords = calculate_explosion(bomb[:x], bomb[:y], bomb[:blast_radius])
    
    explosion_coords.each do |x, y|
      if @grid[y][x] == '+'
        @grid[y][x] = '.'
        maybe_spawn_powerup(x, y)
      end
      
      @players.each do |player_id, player|
        if player[:x] == x && player[:y] == y && player[:alive]
          player[:alive] = false
        end
      end
      
      chain_bombs = @bombs.select { |other_bomb| other_bomb[:x] == x && other_bomb[:y] == y }
      chain_bombs.each do |chain_bomb|
        explode_bomb(chain_bomb) if chain_bomb[:timer] > 0
        chain_bomb[:timer] = 0
      end
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
  
  def check_game_over
    alive_players = @players.select { |_, player| player[:alive] }
    
    if alive_players.length <= 1
      @game_over = true
      @winner = alive_players.length == 1 ? alive_players.keys.first : nil
    end
  end
end