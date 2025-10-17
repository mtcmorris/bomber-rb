# Bomberman Bot Competition

## Overview

Write a Ruby bot to compete in a Bomberman-style arena! Place bombs strategically to destroy walls, collect powerups, and eliminate your opponents.

## Game Rules

### The Arena

- The game is played on a grid (default 15x15)
- Hard walls (`#`) are indestructible and line the perimeter and form a fixed pattern inside
- Soft walls (`+`) can be destroyed by bombs and may contain powerups
- Empty spaces (`.`) are walkable

### Your Bot

Each turn, your bot can perform ONE action:
- `move <direction>` - Move one space (up, down, left, right)
- `bomb` - Place a bomb at your current location
- `pass` - Do nothing this turn

### Bombs

- Bombs explode after 3 turns
- Explosions extend 2 spaces in all four cardinal directions (up, down, left, right)
- Explosions stop at hard walls but destroy soft walls
- Explosions destroy other bombs, causing them to explode immediately (chain reactions!)
- You can only have 1 bomb active at a time (unless you have powerups)
- You cannot move through your own bombs or other players' bombs

### Powerups

When soft walls are destroyed, they may reveal powerups:
- `B` - Extra bomb (allows you to place one additional bomb at a time)
- `F` - Increased blast radius (+1 range)
- `S` - Speed boost (move twice per turn for 10 turns)

### Winning

- Last bot standing wins!
- Bots are eliminated when caught in a bomb explosion
- If multiple bots are eliminated simultaneously in the final explosion, it's a draw

### Scoring (for tournaments)

- Win: 3 points
- Draw: 1 point
- Loss: 0 points

## Client Interface

### Input Format

Each turn, your bot receives a JSON object via STDIN:

```json
{
  "tick": 42,
  "you": "player1",
  "players": {
    "player1": {
      "x": 1,
      "y": 1,
      "alive": true,
      "bombs_available": 1,
      "blast_radius": 2,
      "speed_boost_turns": 0
    },
    "player2": {
      "x": 13,
      "y": 13,
      "alive": true,
      "bombs_available": 1,
      "blast_radius": 2,
      "speed_boost_turns": 0
    }
  },
  "bombs": [
    {
      "x": 5,
      "y": 5,
      "owner": "player1",
      "ticks_until_explosion": 2,
      "blast_radius": 2
    }
  ],
  "grid": [
    ["#", "#", "#", "#", "#"],
    ["#", ".", "+", ".", "#"],
    ["#", "+", ".", "B", "#"],
    ["#", ".", "+", ".", "#"],
    ["#", "#", "#", "#", "#"]
  ]
}
```

### Output Format

Your bot must output a single line with your action:

```
move up
move down
move left
move right
bomb
pass
```

### Sample Bot

```ruby
#!/usr/bin/env ruby
require 'json'

def get_state
  JSON.parse(STDIN.gets)
end

def output_action(action)
  puts action
  STDOUT.flush
end

# Main game loop
loop do
  state = get_state
  me = state['players'][state['you']]

  # Simple strategy: move randomly and place bombs
  if me['bombs_available'] > 0 && rand < 0.3
    output_action('bomb')
  else
    direction = ['up', 'down', 'left', 'right'].sample
    output_action("move #{direction}")
  end
end
```

## Strategy Tips

- **Escape routes**: Always plan your escape before placing a bomb!
- **Trap opponents**: Try to corner enemies with your explosions
- **Chain reactions**: Destroying walls or triggering other bombs can create devastating combos
- **Powerups**: Extra bombs and blast radius are powerful - control the center to get more powerups
- **Prediction**: Smart bots predict where explosions will be and avoid those spaces

## Running Your Bot

Save your bot as `bot.rb` and make it executable:

```bash
chmod +x bot.rb
./bot.rb
```

The game server will handle communication with your bot via STDIN/STDOUT.

## Development Tips

- Test your bot against simple AI opponents first
- Add logging to STDERR (not STDOUT!) to debug: `STDERR.puts "Debug info"`
- Handle invalid moves gracefully (server will skip your turn if you output invalid actions)
- Keep your bot responsive - you have a 1-second timeout per turn

Good luck, and may your bombs be ever strategic! 💣