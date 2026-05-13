#!/usr/bin/env ruby
# encoding: utf-8

require "sinatra"
require "open-uri"
require "uri"
require "nokogiri"
require "json"

set :protection, :except => :path_traversal

# Cria diretório de logs se não existir
Dir.mkdir("logs") unless Dir.exist?("logs")

get "/" do
  "Usage: http://<hostname>[:<prt>]/api/<url>"
end

get "/api/*" do
  url = [params['splat'].first, request.query_string].reject(&:empty?).join("?")
  
  # Extração direta sem consulta ao cache
  jsonlinks = JSON.pretty_generate(extract_links(url))

  # Registro de log (Removido o status de HIT/MISS pois não há mais cache)
  cache_log = File.open("logs/extraction.log", "a")
  cache_log.puts "#{Time.now.to_i}\tREQUEST\t#{url}"
  cache_log.close

  status 200
  headers "content-type" => "application/json"
  body jsonlinks
end

def extract_links(url)
  links = []
  begin
    doc = Nokogiri::HTML(URI.open(url))
    doc.css("a").each do |link|
      text = link.text.strip.split.join(" ")
      begin
        links.push({
          text: text.empty? ? "[IMG]" : text,
          href: URI.join(url, link["href"])
        })
      rescue
        # Ignora links malformados
      end
    end
  rescue => e
    return { error: "Could not open URL: #{e.message}" }
  end
  links
end
