require_relative 'yahoo_proxy'


File.open(ARGV.shift).each { |tkr| puts tkr;YahooProxy.create_price_file(tkr.chomp) }
