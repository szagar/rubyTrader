#!/usr/bin/env ruby

require_relative 'five_days_down'
require_relative 'back_tester'
require_relative '../../zts/lib2/date_time_helper'

DataDir = "/Users/szagar/rubyTrader/5dd/test_data/inbox/5dd"

bt = BackTester.new

search_str = "#{DataDir}/**/*.txt"
puts "search_str=#{search_str}"
strategy_cnt = 0
Dir.glob(search_str).sort_by{|f| File.mtime(f)}.each do |raw_fn|
  working_dir = File.dirname(raw_fn).sub("inbox","archive")
  system 'mkdir', '-p', working_dir
  fn = archive_file(working_dir, raw_fn)
  bt.add_strategy(FiveDaysDown,fn)
  strategy_cnt += 1
end

exit unless strategy_cnt > 0

today = DateTimeHelper::integer_date

bt.report_hdr

bt.set_bt_start_dt(20090101)
bt.reset(100_000)
bt.run
bt.report
 
