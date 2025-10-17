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
          connected: true
        }
      end
      clients.to_json
    else
      [].to_json
    end
  end
end