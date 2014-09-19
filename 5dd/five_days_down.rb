# 5 days down:
#  * Swing Day Pattern
#  * markets: large cap ETFs
#             broad indecies
#             DOW 30
#  * setup: closes 5 days lower
#  * entry: buy breakout above yesterday's high
#  * exits: stop loss below yesterdays low
#  * notes: in bear market, if it fails below stop, then stop and reverse

require_relative "../../zts/lib2/mystdlib/tc_data"
require_relative "../../zts/lib2/tc_helper"

Env = "test"

class FiveDaysDown
  attr_reader :cash, :tc

  def initialize(tkr,tc_data)
    @tkr = tkr
    @tc = TcData.new(tc_data)
    @tc.set_atr_h(14)
  end

  def descr
    "5dd"
  end

  def entries(tdate)
    setup? ? buy_entry(tdate) : nil
  end

  def buy_entry_price(tdate)
    @tc.prev("high")
  end

  def init_stop_loss(tdate)
    # previous days low 
    @tc.prev("low")
  end

  def exits(tdate)
   # previous days low 
  end

  private

  def setup?
    @tc.consecutive_down_days > 5
  end

  def buy_entry(tdate)
    tags = tags_of_interest
    tags += "," + format_tag("setup_src", "5dd")

    { tkr:        @tkr,
      entry_stop: buy_entry_price(tdate),
      init_stop:  init_stop_loss(tdate),
      atr:        tc.last('atr14').round(2),
      o:          tc.last('open'),
      h:          tc.last('high'),
      l:          tc.last('low'),
      c:          tc.last('close'),
      tags:       tags
    }
  end

  def tags_of_interest
    tags = ""
    (tags += "," + format_tag("bop", tc.last("balance_of_power").round(0))) rescue nil
    (tags += "," + format_tag("trend_dir", trend_dir(tc))) rescue nil
    (tags += "," + format_tag("bop_rank", tc.series("balance_of_power").reverse.rank.round(2))) rescue nil
    (tags += "," + format_tag("bop_5d_rank", tc.series("balance_of_power",5).reverse.rank.round(2))) rescue nil
    tags += "," + format_tag("rsi_signal1") if rsi_signal1?(tc)
    tags += "," + format_tag("rsi_signal2") if rsi_signal2?(tc)
    tags += "," + format_tag("NH10p")       if tc.series("close").reverse.rank >= 0.90
    tags += "," + format_tag("NH5p")        if tc.series("close").reverse.rank >= 0.95
    tags += "," + format_tag("NH6m10p")     if tc.series("close",125).reverse.rank >= 0.90
    tags += "," + format_tag("NH6m5p")      if tc.series("close",125).reverse.rank >= 0.95
    tags += "," + format_tag("volsig1")     if volume_signal1?(tc)
    tags += "," + format_tag("bopsig1")     if bop_signal1?(tc)
    tags += "," + format_tag("trendsig1")   if trend_signal1?(tc)
    tags
  end

  def format_tag(name,value=nil)
    value ? "#{name}:#{value}" : name
  end
end

