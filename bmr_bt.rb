require_relative 'bmr'
require_relative 'back_tester'
require_relative '../zts/lib2/date_time_helper'

bmr = BMR.new
bmr.set_num_positions(3)
bmr.set_short_term_period("3m")
bmr.set_long_term_period("6m")
bmr.set_ma_signal_period("4m")

bt = BackTester.new(bmr)
symbol_file = ARGV.shift
File.open(symbol_file).each { |tkr| bt.add_ticker(tkr.chomp) }
today = DateTimeHelper::integer_date
bt.rebalance_period("eom",3)
bt.reset(today,100_000)
bt.run
bt.report
