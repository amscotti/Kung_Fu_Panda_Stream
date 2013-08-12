#!/usr/bin/env ruby

require 'sinatra'
require 'panda'
require 'json'
require 'YAML'
require 'rethinkdb'


class KungFu < Sinatra::Base
	RDB_CONFIG = {
	  :host => ENV['RDB_HOST'] || 'localhost', 
	  :port => ENV['RDB_PORT'] || 28015,
	  :db   => ENV['RDB_DB']   || 'panda'
	}

	r = RethinkDB::RQL.new

	configure do
		Panda.configure(YAML.load_file(File.join(settings.root, "config/panda.yml")))

		set :db, RDB_CONFIG[:db]
		connection = RethinkDB::Connection.new(:host => RDB_CONFIG[:host], :port => RDB_CONFIG[:port])
		begin
			r.db_create(RDB_CONFIG[:db]).run(connection)
			r.db(RDB_CONFIG[:db]).table_create("file_list").run(connection)
			r.db(RDB_CONFIG[:db]).table_create("encoded_list").run(connection)
		rescue RethinkDB::RqlRuntimeError => err
	    	puts "Database and table already exist."
	  	ensure
	    	connection.close
	  	end

	end

	get '/check' do
  		"Hello World!"
	end

	post '/encode' do
		data = JSON.parse(request.body.read)
		puts data
		video = Panda::Video.create!(:source_url => data['FilePath'])
		data["id"] = video.id
		begin
			connection = r.connect(:host => RDB_CONFIG[:host], :port => RDB_CONFIG[:port])
			r.db("panda").table('file_list').insert(data).run(connection)	
		rescue Exception => e
			puts "Cannot connect to RethinkDB database #{RDB_CONFIG[:host]}:#{RDB_CONFIG[:port]} (#{e.message})"
		ensure
			connection.close
		end
		return {:status => "ok", :time => Time.now.to_i, :id => video.id}.to_json
	end

	get '/encode/:id' do
		begin
			video = Panda::Video.find(params[:id])
			h264 = video.encodings['h264']
			webm = video.encodings['webm.hi']
			return_data = { :status => video.status, 
							:h264_status => h264.status, :h264_progress => h264.encoding_progress, 
							:webm_status => webm.status, :webm_progress => webm.encoding_progress }
		rescue Exception => e
			return_data = {:status => "error", :error => e}
		end
		
		return return_data.to_json
	end

	post '/webhook' do
		puts params
		video_id = params[:video_id]
		begin
			video = Panda::Video.find(video_id)
        	data = {:h264_file => video.encodings['h264'].files[0], :webm_file => video.encodings['webm.hi'].files[0], :id => video_id }

        	begin
        		connection = r.connect(:host => RDB_CONFIG[:host], :port => RDB_CONFIG[:port])
        		r.db("panda").table('encoded_list').insert(data).run(connection)
        	rescue Exception => e
        		puts "Cannot connect to RethinkDB database #{RDB_CONFIG[:host]}:#{RDB_CONFIG[:port]} (#{e.message})"
        	ensure
	    		connection.close
        	end

		rescue Exception => e
			puts "Error: #{e}"
		end

       	return ""
	end

end