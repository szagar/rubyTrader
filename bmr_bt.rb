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

(3...4).each do |num|
  bt.strategy.set_num_positions(num)
  (22...66).step(22) do |ma_pd|
    bt.strategy.set_ma_signal_period(ma_pd)  # 88
    (1...2).each do |months|
      bt.rebalance_period("eom",months)
      (66...88).step(22) do |st_pd|
        (st_pd+66..st_pd+88).step(66) do |lt_pd|
          bt.strategy.set_long_term_period(lt_pd)
          bt.set_bt_start_dt(20130000)
          bt.reset(today,100_000)
          puts "run for num=#{num}, ma_pd=#{ma_pd}, rebal=#{months}eom, st=#{st_pd}, lt=#{lt_pd}"
          bt.run
          bt.report
        end
      end
    end
  end
end
