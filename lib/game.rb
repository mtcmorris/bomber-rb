require 'json'

class Game
  GRID_SIZE = 15
  BOMB_TIMER = 5
  BLAST_RADIUS = 2
  DEATH_STAR_SPAWN_INTERVAL = 120

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
    @powerup_respawn_queue = []
    @last_death_star_spawn = 0
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

    process_bombs
    check_explosions
    check_powerup_collection
    process_respawns
    process_explosions
    process_powerup_respawns
    spawn_death_star_if_needed

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

  def can_move_to?(x, y, exclude_player_id = nil)
    return false unless valid_position?(x, y)
    return false if @grid[y][x] == '#' || @grid[y][x] == '+'

    # Check for bombs
    return false if @bombs.any? { |bomb| bomb[:x] == x && bomb[:y] == y }

    # Check for other players (collision detection)
    @players.each do |pid, player|
      next if pid == exclude_player_id # Ignore the moving player itself
      return false if player[:alive] && player[:x] == x && player[:y] == y
    end

    true
  end

  def move_player(player_id, direction)
    player = @players[player_id]
    dx, dy = direction_to_delta(direction)
    new_x = player[:x] + dx
    new_y = player[:y] + dy

    # Check if destination is valid (excluding current player to avoid self-collision check)
    if can_move_to?(new_x, new_y, player_id)
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

  def explode_bomb(bomb, chain_owners = [])
    # Mark this bomb as exploding to prevent infinite recursion
    return [] if bomb[:exploding]
    bomb[:exploding] = true

    # Track all owners in this bomb chain
    chain_owners = chain_owners.dup
    chain_owners << bomb[:owner] unless chain_owners.include?(bomb[:owner])

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

          # Reset powerups on death
          player[:bombs_available] = 1
          player[:blast_radius] = BLAST_RADIUS

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

      chain_bombs = @bombs.select { |other_bomb| other_bomb[:x] == x && other_bomb[:y] == y && !other_bomb[:exploding] }
      chain_bombs.each do |chain_bomb|
        chain_bomb[:timer] = 0
        # Pass chain_owners to track all participants in the bomb chain
        chain_killed = explode_bomb(chain_bomb, chain_owners)
        killed_players.concat(chain_killed)
      end
    end

    # Award kill to ALL bomb owners in the chain (don't award points for self-kills)
    if killed_players.length > 0
      chain_owners.uniq.each do |owner|
        next unless @leaderboard[owner]

        non_self_kills = killed_players.reject { |killed_id| killed_id == owner }
        if non_self_kills.length > 0
          @leaderboard[owner][:kills] += non_self_kills.length
          @leaderboard[owner][:current_life_kills] += non_self_kills.length
          puts "💥 #{owner} gets #{non_self_kills.length} kill(s) from bomb chain!"
        end
      end
    end

    # Return killed players for chain tracking
    killed_players
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

    powerup_type = ['B', 'F'].sample
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
        # Queue powerup for respawn in 15-25 seconds
        queue_powerup_respawn(x, y, 'B', rand(15..25))
      when 'F'
        player[:blast_radius] += 1
        @grid[y][x] = '.'
        # Queue powerup for respawn in 15-25 seconds
        queue_powerup_respawn(x, y, 'F', rand(15..25))
      when 'D'
        # Death star kills all other players
        kill_all_other_players(player_id)
        @grid[y][x] = '.'
        puts "Player #{player_id} activated death-star!"
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

  def queue_powerup_respawn(x, y, type, delay_ticks)
    @powerup_respawn_queue << {
      x: x,
      y: y,
      type: type,
      respawn_tick: @tick + delay_ticks
    }
  end

  def process_powerup_respawns
    ready_to_respawn = @powerup_respawn_queue.select { |entry| entry[:respawn_tick] <= @tick }

    ready_to_respawn.each do |entry|
      x, y = entry[:x], entry[:y]

      # Only respawn if the cell is empty
      if @grid[y][x] == '.'
        @grid[y][x] = entry[:type]
        puts "Powerup '#{entry[:type]}' respawned at (#{x}, #{y})"
      end

      @powerup_respawn_queue.delete(entry)
    end
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

  def spawn_death_star_if_needed
    # Spawn death-star every DEATH_STAR_SPAWN_INTERVAL (120) ticks, but only if one doesn't already exist
    if @tick - @last_death_star_spawn >= DEATH_STAR_SPAWN_INTERVAL
      # Check if a death-star already exists on the grid
      death_star_exists = @grid.any? { |row| row.include?('D') }

      if !death_star_exists
        spawn_pos = find_random_spawn_position
        if spawn_pos
          x, y = spawn_pos
          @grid[y][x] = 'D'
          @last_death_star_spawn = @tick
          puts "Death-star spawned at (#{x}, #{y}) on tick #{@tick}"
        end
      else
        puts "Death-star already exists on the grid, skipping spawn at tick #{@tick}"
      end
    end
  end

  def kill_all_other_players(survivor_id)
    killed_count = 0
    @players.each do |player_id, player|
      next if player_id == survivor_id
      next unless player[:alive]

      player[:alive] = false
      killed_count += 1

      # Reset powerups on death
      player[:bombs_available] = 1
      player[:blast_radius] = BLAST_RADIUS

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

    # Award kills to the survivor
    if killed_count > 0 && @leaderboard[survivor_id]
      @leaderboard[survivor_id][:kills] += killed_count
      @leaderboard[survivor_id][:current_life_kills] += killed_count
    end
  end
end