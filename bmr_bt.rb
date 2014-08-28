#!/usr/bin/env ruby

require_relative 'bmr'
require_relative 'back_tester'
require_relative '../zts/lib2/date_time_helper'

bmr = BMR.new
bmr.set_num_positions(2)
bmr.set_short_term_period(66)
bmr.set_long_term_period(132)
bmr.set_ma_signal_period(88)  # 88

bt = BackTester.new(bmr)
symbol_file = ARGV.shift
File.open(symbol_file).each { |tkr| bt.add_ticker(tkr.chomp.rstrip) }
today = DateTimeHelper::integer_date

bt.report_hdr

(1..5).each do |months|
  [22,44,66,88].each do |st_pd|
    (st_pd+22..st_pd+88).step(22) do |lt_pd|
      bt.rebalance_period("eom",months)
      bt.set_bt_start_dt(20130000)
      bt.reset(today,100_000)
      bt.run
      bt.report
    end
  end
end
