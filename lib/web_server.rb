require 'sinatra/base'
require 'json'

class WebServer < Sinatra::Base
  set :public_folder, File.dirname(__FILE__) + '/../public'
  set :views, File.dirname(__FILE__) + '/../views'
  
  @@game_server = nil
  
  def self.game_server=(server)
    @@game_server = server
  end
  
  def self.game_server
    @@game_server
  end
  
  get '/' do
    erb :index
  end
  
  get '/api/game_state' do
    content_type :json
    
    if @@game_server && @@game_server.game
      game = @@game_server.game
      state = {
        tick: game.tick,
        players: game.players,
        bombs: game.bombs.map do |bomb|
          {
            x: bomb[:x],
            y: bomb[:y],
            owner: bomb[:owner],
            ticks_until_explosion: bomb[:timer],
            blast_radius: bomb[:blast_radius]
          }
        end,
        grid: game.grid,
        game_over: game.game_over,
        winner: game.winner
      }
      state.to_json
    else
      { error: 'Game not running' }.to_json
    end
  end
  
  get '/api/clients' do
    content_type :json
    
    if @@game_server
      clients = @@game_server.clients.map do |connection, client|
        {
          player_id: client[:player_id],
          name: client[:name],
          connected: true
        }
      end
      clients.to_json
    else
      [].to_json
    end
  end
  
  get '/api/leaderboard' do
    content_type :json
    
    if @@game_server && @@game_server.game
      leaderboard = @@game_server.game.leaderboard.map do |player_id, stats|
        current_survival = 0
        if @@game_server.game.players[player_id]&.dig(:alive)
          current_survival = @@game_server.game.tick - stats[:current_life_start]
        end
        
        {
          player_id: player_id,
          name: player_id.split('_')[0..-2].join('_'), # Remove the _N suffix
          kills: stats[:kills],
          deaths: stats[:deaths],
          total_survival_time: stats[:total_survival_time] + current_survival,
          current_survival: current_survival,
          alive: @@game_server.game.players[player_id]&.dig(:alive) || false
        }
      end.sort_by { |p| [-p[:kills], -p[:total_survival_time]] }
      
      leaderboard.to_json
    else
      [].to_json
    end
  end
end