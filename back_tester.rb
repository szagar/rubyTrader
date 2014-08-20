class BackTester
  def initialize(strategy)
    @strategy = strategy
    @date_ptr = 0
    @tickers = []
    @positions = {}
    @prices = {}
    @price_data = {}
    @pnl = {profit: 0, drawdown: 0}
  end

  def reset(today,amount)
    @equity = amount
    @rebalance_dates = determine_rebalance_dates
    #load_price_data
  end

  def rebalance_period(type,offset)
    case type
    when "daycnt"
      @rebalance_daycnt    = pd2daycnt(offset)
    when "eom"
      @rebalance_pd_method = type
      @rebalance_pd        = offset
    end
  end

  def add_ticker(tkr)
    @tickers << tkr
  end

  def run
    @tickers.each { |tkr| @strategy.add_ticker(tkr) }
    @rebalance_dates.each do |asof|
      @positions['SHY'] = {}
      @positions['SHY'][:qty] = @equity / price('SHY',asof)
      @positions['SHY'][:avg_px] = price('SHY',asof)
      target_pos = @strategy.run(asof: asof)
      today = @strategy.get_asof
      rebalance2target(today,target_pos)
puts "======> #{@pnl}"
    end
  end  

  def report
    puts "Report ... "
  end

  private

  def rebalance2target(today,target_pos)
    puts "def rebalance2target(#{today},#{target_pos})"
    @equity = 0
    @positions.each do |tkr,h|
      puts "#{@equity} += (#{h[:qty]} * #{price(tkr,today)})"
      @equity += (h[:qty] * price(tkr,today))
    end
    @positions.each do |tkr,h|
      dollars = target_pos.fetch(tkr) { 0 } / 100 * @equity
      px = price(tkr,today)
      new_size = (dollars / px).to_i
      puts "buy(#{tkr},#{new_size-h[:qty]},#{px}) if #{new_size} > #{h[:qty]}" if new_size > h[:qty]
      buy(tkr,new_size-h[:qty],px) if new_size > h[:qty]
      puts "sell(#{tkr},#{h[:qty]-new_size},#{px}) if #{h[:qty]} > #{new_size}" if h[:qty] > new_size
      sell(tkr,h[:qty]-new_size,px) if h[:qty] > new_size
    end
    target_pos.each do |tkr,perc|
      px = price(tkr,today)
      dollars = perc / 100 * @equity
      qty = (dollars / px).to_i
puts "px: #{px}, dollars: #{dollars}, qty: #{qty}"
      puts "buy(#{tkr},#{qty},#{px}) unless @positions.has_key?(#{tkr})"
      buy(tkr,qty,px) unless @positions.has_key?(tkr)
    end
  end

  def price(tkr,date)
    rtn = @prices.fetch(tkr) { @prices[tkr] = Hash.new }
    rtn.fetch(date) { @prices[tkr] = load_prices(tkr) } 
    #(@prices[tkr] && @prices[tkr][date]) ? @prices[tkr][date] : load_prices(tkr)[date]
    @prices[tkr][date]
  end

  def load_prices(tkr)
    puts "def load_prices(#{tkr})"
    if File.exists?(price_file(tkr))
      @prices[tkr] = load_price_file(price_file(tkr))
    else
      @prices[tkr] = load_price_file(create_price_file(tkr))
    end
    @prices[tkr]
  end

  def price_file(tkr)
    "prices/#{tkr}_yahoo.data"
  end

  def create_price_file(tkr)
    YahooProxy.create_price_file(tkr)
  end
  def load_price_file(fn,today=99999999)
    prices = {}
    File.readlines(fn).map { |rec|
      next unless rec.split(",")[0].to_i < today
      d,o,h,l,c,v,adj = rec.split(",")
      prices[d] = c.to_f
    }
    prices
  end

  def buy(tkr,qty,price)
    puts "def buy(#{tkr},#{qty},#{price})"
    @positions.fetch(tkr) { @positions[tkr] = {avg_px: 0.0, qty: 0 } }
    @positions[tkr][:avg_px] = (@positions[tkr][:avg_px]*@positions[tkr][:qty]
                                + qty*price ) /
                                (@positions[tkr][:qty] + qty)
    @positions[tkr][:qty] += qty
  end

  def sell(tkr,qty,price)
    puts "@pnl[:profit] += (#{@positions[tkr][:qty]} * #{@positions[tkr][:avg_px]}) - (#{qty} * #{price})"
    @pnl[:profit] += (@positions[tkr][:avg_px] - price) * qty
    @pnl[:drawdown] = @pnl[:profit] if @pnl[:profit] < @pnl[:drawdown]
    @positions[tkr][:qty] -= qty
  end

=begin
  def load_price_data
    rebalance_dates = determine_rebalance_dates
    @tickers.each do |tkr|
      @price_data[tkr] = load_price_for_dates(tkr,rebalance_dates)
    end
  end
=end

=begin
  def load_price_for_dates(tkr,rebalance_dates)
    #  [rebalance_date] = close
    #  [rebalance_date] = close
    # 
    # 
    dates = YahooProxy.historical_eod(tkr,10).map { |p| p.split(",")[0] }
  end
=end

  def determine_rebalance_dates
    dates = case @rebalance_pd_method
    when "eom"
      eom_dates(@rebalance_pd).reverse
    end 
puts "dates=#{dates}"
    dates
  end

  def eom_dates(offset=0)
    dates = []
    prev_m = 0
    off_set_cnt = 0
    load_dates.each do |dt|
      m = dt[/\d\d\d\d(\d\d)\d\d/,1]
      if prev_m == 0
        prev_m = m
        next
      end
      if m != prev_m
        off_set_cnt = offset
      end
      if m == prev_m
        off_set_cnt -= 1
      end
      if off_set_cnt == 0
        dates << dt
        off_set_cnt = 999999
      end
      prev_m = m
    end
    dates[0..10]
  end

  def load_dates
    dates = YahooProxy.historical_eod("IBM",10).map { |p| p.split(",")[0] }
  end

  def increment_asof(asof)
    @rebalance_daycnt.times { asof = next_date(asof) }
    asof
  end

  def next_date(asof)
    dates(@date_ptr)
    @date_ptr += 1
  end

  def pd2daycnt(pd)
    case pd
    when /(\d+)d/
      $1.to_f
    when /(\d+)m/
      $1.to_f * 22
    when /(\d+)y/
      $1.to_f * 22 *  12
    end
  end
end
