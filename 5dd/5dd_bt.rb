#!/usr/bin/env ruby

require_relative 'five_days_down'
require_relative 'back_tester'
require_relative '../../zts/lib2/date_time_helper'

fdd = FiveDaysDown.new

bt = BackTester.new(fdd)
symbol_file = ARGV.shift
bt.set_symbol_file(symbol_file)
bt.reset_price_data
today = DateTimeHelper::integer_date

bt.report_hdr

bt.set_bt_start_dt(20090101)
bt.reset(100_000)
puts "run for num=#{num}"
bt.run
bt.report
 
