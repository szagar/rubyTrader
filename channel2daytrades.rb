require "../zts/lib2/historical_prices"

Env = "test"

class Channel2DayTrades
  def initialize
    puts "Channel2DayTrades.new"
    env = Env
    @hp = HistoricalPrices.new(env)

    @tickers     = []
  end

  def add_ticker(tkr)
    @tickers << tkr
  end

  def run(params)
    @today = params.fetch(:asof)

    #YahooProxy.rm_empty_price_files

    buy_flag = prices.last[:close] > @tc.ema('close',200) && calc_williamsR(prices,period) <= -80.0
    buy_flag ? position_size(trades) : 0
  end

  def get_asof
    @today
  end

  def report_hdr
    "num,ma_pd,lt_pd,sh_pd"
  end

  def report_desc
    [@num,@ma_period,@lt_period,@st_period].join ","
  end

  private

  def calc_williamsR(prices,period)
    numerator = prices[period-1][:high] - prices.first[:close]
    denominator = prices[period-1][:high] - prices[period-1][:low]
    numerator / denominator * -100
  end

  def calc_return(prices,period)
    #puts "calc_return(#{period}): ((#{prices.first} - #{prices[period-1]}) / #{prices[period-1]}) * 100.0"
    ((prices.first - prices[period-1]) / prices[period-1]) * 100.0
  end

  def load_prices(tkr,period,today)
    #@hp.price_array_desc(tkr,period,today).map { |rec| rec[4] }
    @hp.price_array_desc(tkr,period,today)
  end

  def calc_sma(values,period)
    #puts "BMR#calc_sma: values=#{values[0...period]}"
    values[0..period].reduce( :+ ) / period
  end

  def position_size(trade)
    100
  end

  def print_report(today,positions)
    puts "Target positions, asof #{today}"
    positions.each { |tkr,pos_percent| print_trade(tkr,pos_percent) }
  end

  def print_trade(tkr,pos_percent)
    puts "#{pos_percent.round(0)}% in #{tkr}"
  end
end

