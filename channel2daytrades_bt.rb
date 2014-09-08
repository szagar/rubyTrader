#!/usr/bin/env ruby

require_relative 'channel2daytrades'
require_relative 'back_tester_2'
require_relative '../zts/lib2/date_time_helper'

chnl = Channel2DayTrades.new

bt = BackTester.new(chnl)
symbol_file = ARGV.shift
File.open(symbol_file).each { |tkr| bt.add_ticker(tkr.chomp.rstrip) }
today = DateTimeHelper::integer_date

bt.report_hdr

bt.reset(today,100_000)
bt.set_bt_start_dt(20130000)
puts "run ..."
bt.run
bt.report
