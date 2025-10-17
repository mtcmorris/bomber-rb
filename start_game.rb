#!/usr/bin/env ruby

puts "Bomberman Game Server Setup"
puts "=" * 30
puts

# Install gems if needed
unless File.exist?('Gemfile.lock')
  puts "Installing gems..."
  system('bundle install')
  puts
end

puts "Starting game server..."
puts "- WebSocket server: ws://localhost:8080"
puts "- Web interface: http://localhost:4567"
puts
puts "To connect a bot, run:"
puts "  ruby client/sample_bot.rb"
puts
puts "Press Ctrl+C to stop the server"
puts

exec('ruby server.rb')