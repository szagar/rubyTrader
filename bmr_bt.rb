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
#File.open(symbol_file).each { |tkr| bt.add_ticker(tkr.chomp.rstrip) }
bt.set_symbol_file(symbol_file)
bt.strategy.set_cash("BLV")
#bt.strategy.set_cash("SHY")
bt.reset_price_data
today = DateTimeHelper::integer_date

bt.report_hdr

(2...5).each do |num|
  (22...66).step(22) do |ma_pd|
    (1...2).each do |months|
      (66...88).step(22) do |st_pd|
        (st_pd+66..st_pd+88).step(66) do |lt_pd|
          (0...3).each do |eom_offset|
            bt.eom_offset(eom_offset)
            bt.rebalance_period("eom",months)
            bt.set_bt_start_dt(20090101)
            bt.reset(100_000)
            bt.strategy.set_num_positions(num)
            bt.strategy.set_ma_signal_period(ma_pd)  # 88
            bt.strategy.set_short_term_period(st_pd)
            bt.strategy.set_long_term_period(lt_pd)
            puts "run for num=#{num}, ma_pd=#{ma_pd}, rebal=#{months}eom, st=#{st_pd}, lt=#{lt_pd}"
            bt.run
            bt.report
          end
        end
      end
    end
  end
end

=begin
bt.strategy.set_cash("BLV")
bt.eom_offset(0)
bt.rebalance_period("eom",1)
bt.set_bt_start_dt(20090101)
bt.reset(100_000)
bt.strategy.set_num_positions(3)
bt.strategy.set_ma_signal_period(44)  # 88
bt.strategy.set_short_term_period(66)
bt.strategy.set_long_term_period(132)
bt.run
bt.report
=end
 
