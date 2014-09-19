# 5 days down:
#  * Swing Day Pattern
#  * markets: large cap ETFs
#             broad indecies
#             DOW 30
#  * setup: closes 5 days lower
#  * entry: buy breakout above yesterday's high
#  * exits: stop loss below yesterdays low
#  * notes: in bear market, if it fails below stop, then stop and reverse

require "../zts/lib2/historical_prices"

Env = "test"

class FiveDaysDown
  attr_reader :cash

  def initialize(tkr,tc_data)
    @tkr = tkr
  end

  def descr
    "5dd"
  end

  def entries(tdate)
    number_of_consecutive_days_down > 5) ? buy(tdate,tkr) : nil
  end

  def init_stop_loss(tdate)
   # previous days low 
  end

  def exits(tdate)
   # previous days low 
  end

  private

  def number_of_consecutive_days_down
  end

  def buy(tdate,tkr)
  end

  def position_size(tdate,tkr,risk_pos,cap_pos)
    atr = @tc.atr(asof,period)
    size = (risk_pos / (atr*atr_factor)).to_i
    return size if size*tc.last() <= cap_pos
    0
  end
end

