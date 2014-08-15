require_relative 'yahoo_proxy'

class BMR
  def initialize(st_period=66, lt_period=132, st_wt=0.70, num=3)
    @st_period = st_period   # 3m * 22   short term period
    @lt_period = lt_period   # 6m * 22   long term period
    @st_wt     = st_wt       # blended wt for short term return
    @num       = num         # number of portfolio positions

    @cash        = "SHY"
    @ma_period   = 4 * 22
    @top_tkrs    = []
    @tickers     = []
    @blended_ror = {}
  end

  def add_ticker(tkr)
    @tickers << tkr
  end

  def set_cash(tkr)
    @cash = tkr
  end

  def run
    @tickers.each do |tkr|
      prices = load_prices(tkr,@lt_period)
      st_ror = calc_return(prices,@st_period)
      lt_ror = calc_return(prices,@lt_period)
      puts "@blended_ror[#{tkr}] = #{@st_wt} * #{st_ror} + (1.0-#{@st_wt}) * #{lt_ror}"
      @blended_ror[tkr] = @st_wt * st_ror + (1.0-@st_wt) * lt_ror
    end

    @blended_ror.keys.sort.each do |k|
      puts "tkr: #{k}  = #{@blended_ror[k]}"
    end

    top_rors = rank(@blended_ror)[0...@num]
    top_tkrs = cash_override(top_rors)
    print_report(top_tkrs)
  end

  def create_price_file(tkr)
    pfile = "prices/#{tkr}_yahoo.data"
    return if File.exists?(pfile)
    File.open(pfile, 'w') do |fh|
      YahooProxy.historical_eod(tkr, 10).each { |rec|
        puts rec
        #{:date=>"20040817", :o=>"33.12", :h=>"33.44", :l=>"32.99", :c=>"33.26", :v=>"89573100", :adj=>"30.71"}
        fh.write "#{rec}\n"
      }
    end
  end

  private

  def calc_return(prices,period)
    puts "(#{prices.first} - #{prices[period-1]}) / #{prices[period-1]}"
    ((prices.first - prices[period-1]) / prices[period-1]) * 100.0
  end

  def load_prices(tkr,period)
    puts "load_prices(#{tkr},#{period})"
    return load_price_file(price_file(tkr)) if File.exists?(price_file(tkr))
puts "!!!!!!"
return
    YahooProxy.historical_eod(tkr, (period/264+1)).map { |rec| rec[:c].to_f }
  end

  def load_price_file(fn)
    puts "File.readlines(#{fn}).map { |rec| rec[:c].to_f }"
    File.readlines(fn).map { |rec|
      puts rec
      puts rec.class
      puts rec[:c]
      rec[:c].to_f
    }
  end

  def price_file(tkr)
    "prices/#{tkr}_yahoo.data"
  end

  def rank(h)
    (h.sort_by &:last).reverse
  end

  def cash_override(tkrs)
    puts "cash_override(#{tkrs})"
    tkrs.map { |tkr| ma_signal?(tkr) ? tkr : @cash }
  end

  def ma_signal?(tkr)
    prices = load_prices(tkr, @ma_period)
    prices.last > calc_sma(prices,@ma_period)
  end

  def calc_sma(values,period)
    values[0...period].reduce( :+ ) / period
  end

  def print_report(trades)
    pos_percent = 100.0 / @num
    cash_amt    = 0
    trades.each do |tkr|
      (tkr == @cash) ? cash_amt += pos_percent : print_trade(tkr,pos_percent)
    end
    print_trade(@cash,pos_percent) if cash_amt > 0
  end

  def print_trade(tkr,pos_percent)
    puts "#{pos_percent.round(0)}% in #{tkr}"
  end
end

bmr = BMR.new
#bmr.send "load_prices", "Z", 132
symbol_file = ARGV.shift
#File.open(symbol_file).each { |tkr| bmr.add_ticker(tkr.chomp) }
#allocs = bmr.run

File.open(symbol_file).each { |tkr| puts tkr;bmr.create_price_file(tkr.chomp) }
