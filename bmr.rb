require "../zts/lib2/historical_prices"

Env = "test"

class BMR
  attr_reader :cash

  def initialize(st_period=66, lt_period=132, st_wt=0.70, num=3)
    @st_period = st_period   # 3m * 22   short term period
    @lt_period = lt_period   # 6m * 22   long term period
    @st_wt     = st_wt       # blended wt for short term return
    @num       = num         # number of portfolio positions

    env = Env
    @hp = HistoricalPrices.new(env)

    @cash        = "SHY"
    @ma_period   = 4 * 22
    @top_tkrs    = []
    @tickers     = []
    @blended_ror = {}
  end

  def descr
    "#{@ma_period}:#{@cash}:#{@num}:#{@st_period}:#{@lt_period}"
  end

  def add_ticker(tkr)
    @tickers << tkr
  end

  def set_cash(tkr)
    @cash = tkr
  end

  def set_num_positions(num)
    @num = num
  end

  def set_short_term_period(pd)
    @st_period = pd
  end

  def set_long_term_period(pd)
    @lt_period = pd
  end

  def set_ma_signal_period(pd)
    @ma_period = pd
  end

  def run(params)
    @today = params.fetch(:asof) { DateTimeHelper::integer_date }

    YahooProxy.rm_empty_price_files

    blended_rors = generate_rors(@today)

    ranked = rank(blended_rors)

    top_rors = ranked[0...@num]

    trades = ma_filter(@today,top_rors)
    target_pos = position_size(trades)
    #print_report(@today,target_pos)
    target_pos
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

  def generate_rors(asof)
    blended_rors = {}
    @tickers.map do |tkr|
      prices = load_prices(tkr,@lt_period+1,asof)  #desc [0] is asof
      (puts "skip tkr #{tkr}/#{prices.count}"; next) unless prices.count > @lt_period
      st_ror = calc_return(prices,@st_period)
      lt_ror = calc_return(prices,@lt_period)
      blended_rors[tkr] = calc_blended_ror(st_ror,lt_ror)
      puts "Returns(#{tkr},#{asof}): #{st_ror.round(2)}/#{lt_ror.round(2)} = #{blended_rors[tkr].round(2)}"
    end
    blended_rors
  end

  def calc_blended_ror(st_ror,lt_ror)
      @st_wt * st_ror + (1.0-@st_wt) * lt_ror
  end

  def write_ranking_file(fn,ranked)
    outfile = "rptdir/#{rn}.ranking"
    File.open(outfile, 'w') { |fh| 
      ranked.each { |etf| fh.write "%10s %6.2f\n", etf[0],etf[1] }
    }
  end

  def calc_return(prices,period)
    #puts "calc_return(#{period}): ((#{prices.first} - #{prices[period-1]}) / #{prices[period-1]}) * 100.0"
puts "calc_return: prices=#{prices}"
    ((prices.first - prices[period-1]) / prices[period-1]) * 100.0
  end

  def load_prices(tkr,period,today)
    @hp.price_array_desc(tkr,period,today).map { |rec| rec[:c] }
  end

  def rank(h)
    (h.sort_by &:last).reverse
  end

  def ma_filter(today,top_n)
    filtered = top_n.map { |tkr,ror| ma_signal?(today,tkr) ? tkr : @cash }
    filtered
  end

  def ma_signal?(today,tkr)
    prices = load_prices(tkr, @ma_period,today)
    #prices.first > calc_sma(prices,@ma_period)
    px  = prices.first 
    sma = calc_sma(prices,@ma_period)
    #puts "BMR:ma_signal(#{today}/#{tkr}) #{px} > #{sma}"
    px > sma
  end

  def calc_sma(values,period)
    #puts "BMR#calc_sma: values=#{values[0...period]}"
    values[0..period].reduce( :+ ) / period
  end

  def position_size(trades)
    pos_percent    = (100.0 / @num).round(1)
    target         = {}
    target.default = 0
    target[@cash]  = 100.0
    trades.each_with_index do |tkr,idx|
      target[tkr] += pos_percent
      target[@cash] -= pos_percent
    end
    target.delete_if { |k,v| v < 1.0 }
    printf "target position: "
    target.keys.sort.each { |k| printf "%5s: %5.2f%%", k, target[k] }
    printf "\n"
    #printf "%5s: %5.2f%% %5s: %5.2f%% %5s: %5.2f%%\n",*target.to_a.flatten
    puts "target=#{target}"
    target
  end

  def print_report(today,positions)
    puts "Target positions, asof #{today}"
    positions.each { |tkr,pos_percent| print_trade(tkr,pos_percent) }
  end

  def print_trade(tkr,pos_percent)
    puts "#{pos_percent.round(0)}% in #{tkr}"
  end
end

