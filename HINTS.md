# Bomberman Game Server - Development Hints

## Project Overview
This is a Ruby-based Bomberman game server for a programming camp. Students write bots that connect via WebSocket to compete in a turn-based arena.

## Architecture

### Core Components
- **`lib/game.rb`** - Core game logic (15x15 grid, bombs, powerups, players)
- **`lib/websocket_server.rb`** - WebSocket server using `em-websocket` gem
- **`lib/web_server.rb`** - Sinatra web interface for game visualization
- **`server.rb`** - Main orchestration server that runs both WebSocket and web servers
- **`client/websocket_client.rb`** - WebSocket client wrapper
- **`client/sample_bot.rb`** - Sample bot implementation

### Key Files
- **`Gemfile`** - Uses `em-websocket`, `sinatra`, `websocket-client-simple`, `eventmachine`, `thin`
- **`views/index.erb`** - HTML/JS web interface with real-time game visualization
- **`start_game.rb`** - Convenience startup script

## Game Rules (from README.md)
- 15x15 grid with hard walls (`#`), soft walls (`+`), empty spaces (`.`)
- Bombs explode after 3 turns, blast radius 2, chain reactions possible
- Powerups: `B` (extra bomb), `F` (fire range), `S` (speed boost)
- Actions: `move <direction>`, `bomb`, `pass`
- Last bot standing wins

## Network Protocol

### WebSocket Messages (Client ↔ Server)
**Client sends:**
```json
{"type": "action", "action": "move up"}
{"type": "ping"}
```

**Server sends:**
```json
{"type": "connected", "player_id": "player1", "message": "Connected as player1"}
{"type": "game_state", "state": {...}}
{"type": "game_over", "winner": "player1", "final_state": {...}}
{"type": "pong"}
```

### Game State Format
```json
{
  "tick": 42,
  "you": "player1",
  "players": {"player1": {"x": 1, "y": 1, "alive": true, "bombs_available": 1, "blast_radius": 2, "speed_boost_turns": 0}},
  "bombs": [{"x": 5, "y": 5, "owner": "player1", "ticks_until_explosion": 2, "blast_radius": 2}],
  "grid": [["#", ".", "+", ...], ...]
}
```

## Common Issues & Solutions

### WebSocket Client Context Issue
**Problem:** Callbacks in `websocket-client-simple` execute in the WebSocket's context, not our client's context.
**Solution:** Capture `self` in closure:
```ruby
client = self
@ws.on :message do |event|
  client.send(:handle_message, event.data)
end
```

### EventMachine Timer Cancellation
**Problem:** `EventMachine.stop_timer()` doesn't exist.
**Solution:** Use `@timer.cancel` on PeriodicTimer instances.

### Sinatra Class vs Instance Methods
**Problem:** Setting Sinatra config on wrong object type.
**Solution:** Use class methods (`WebServer.set`) and class variables (`@@game_server`).

## Running the System

### Start Server
```bash
ruby server.rb              # or
ruby start_game.rb          # convenience script
```
- WebSocket server: `ws://localhost:8080`
- Web interface: `http://localhost:4567`

### Connect Bots
```bash
ruby client/sample_bot.rb                    # localhost
ruby client/sample_bot.rb ws://server:8080   # remote server
```

### Game Timing
- Game ticks every 2 seconds automatically
- Bots have the full 2-second window to send actions
- Missing actions default to `pass`

## Development Tips

### Adding New Bot Logic
- Extend `SampleBot#decide_action(state)` method
- Use helper methods like `in_danger?`, `can_move_to?`, `will_hit?`
- Always check `me['alive']` before acting

### Debugging
- Server shows turn processing: "Processing turn X..." and "Tick X completed"
- Client shows messages: "Received message: {...}"
- Web interface updates in real-time at http://localhost:4567

### Game Logic Extensions
- Modify `Game` class in `lib/game.rb`
- Update `state_for_player` if adding new data to game state
- Consider backward compatibility for existing bots

## File Structure
```
bomber-rb/
├── lib/
│   ├── game.rb              # Core game logic
│   ├── websocket_server.rb  # WebSocket server
│   └── web_server.rb        # Sinatra web UI
├── client/
│   ├── websocket_client.rb  # WebSocket client wrapper
│   └── sample_bot.rb        # Sample bot implementation
├── views/
│   └── index.erb            # Web interface template
├── server.rb                # Main server orchestration
├── start_game.rb           # Convenience startup
├── Gemfile                 # Ruby dependencies
└── README.md               # Game rules and API docs
```

## Dependencies
- `em-websocket` - WebSocket server implementation
- `websocket-client-simple` - WebSocket client for bots
- `sinatra` - Web framework for visualization
- `eventmachine` - Event-driven I/O framework
- `thin` - Web server
- `json` - JSON parsing/generation