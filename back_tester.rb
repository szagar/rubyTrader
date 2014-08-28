require "../zts/lib2/historical_prices"

#Env = "test"

class BackTester
  attr_reader :strategy

  def initialize(strategy)
    @strategy = strategy
    @date_ptr = 0
    @tickers = []
    @positions = {}
    @prices = {}
    @price_data = {}
    @pnl = {profit: 0, drawdown: 0}

    @bt_start_dt = 0

    @rpt_fh  = File.open("report.csv", 'w')
    @xact_fh = File.open("xact.csv", 'w')
    @xact_fh.write "tkr,qty,price\n"
    env = Env
    @hp = HistoricalPrices.new(env)
  end

  def set_bt_start_dt(dt)
    @bt_start_dt = dt
  end

  def reset(today,amount)
    @equity = amount
    @rebalance_dates = determine_rebalance_dates
  end

  def rebalance_period(type,offset)
    @rebalance_str = "#{offset}#{type}"
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
    @positions['SHY'] = {}
    @positions['SHY'][:qty] = @equity / price('SHY',@rebalance_dates[0])
    @positions['SHY'][:avg_px] = price('SHY',@rebalance_dates[0])
    puts "@positions['SHY'] = #{@positions['SHY']}"
    @rebalance_dates.each do |asof|
      target_pos = @strategy.run(asof: asof)
      today = @strategy.get_asof
      rebalance2target(today,target_pos)
puts "======> #{@pnl}"
    end
  end  

  def report_hdr
    @rpt_fh.write sprintf "%s,rebal_pd,profit,drawdown\n",@strategy.report_hdr
  end

  def report
    @rpt_fh.write sprintf "%s,%s,%.0f,%.0f\n",@strategy.report_desc,@rebalance_str,@pnl[:profit],@pnl[:drawdown]
  end

  private

  def rebalance2target(asof,target_pos)
    puts "def rebalance2target(#{asof},#{target_pos})"
    prev_equity = @equity
    puts "rebalance2target: @positions=#{@positions}"
    @equity = @positions.map{|tkr,h| h[:qty] * price(tkr,asof)}.reduce(:+).round(2)
    @dd = [@dd||0,@equity-prev_equity].min
    puts "BackTester#rebalance2target: @equity #{asof} =#{@equity.round(0)}  drawdown=#{@dd.round(0)}"
    @positions.each do |tkr,h|
      dollars = target_pos.fetch(tkr) { 0 } / 100 * @equity
      px = price(tkr,asof)
      new_size = (dollars / px).to_i
      puts "buy(#{asof},#{tkr},#{new_size-h[:qty]},#{px}) :: adj pos" if new_size > h[:qty]
      buy(asof,tkr,new_size-h[:qty],px) if new_size > h[:qty]
      puts "sell(#{asof},#{tkr},#{h[:qty]-new_size},#{px}) :: adj pos" if h[:qty] > new_size
      sell(asof,tkr,h[:qty]-new_size,px) if h[:qty] > new_size
    end
    target_pos.each do |tkr,perc|
      px = price(tkr,asof)
      dollars = perc / 100 * @equity
      qty = (dollars / px).to_i
      puts "buy(#{asof},#{tkr},#{qty},#{px}) :: to target" unless @positions.has_key?(tkr)
      buy(asof,tkr,qty,px) unless @positions.has_key?(tkr)
    end
  end

  def price(tkr,date)
    #puts "def price(#{tkr},#{date})"
    rtn = @prices.fetch(tkr) { @prices[tkr] = Hash.new }
    rtn.fetch(date) { @prices[tkr] = load_prices(tkr,date) } 
    @prices[tkr][date][:c]
  end

  def load_prices(tkr,asof)
    @prices[tkr] = @hp.price_hash(tkr,5,asof)
  end

  def buy(asof,tkr,qty,price)
    @xact_fh.write sprintf "%s,Buy,%s,%s,%s\n",asof,tkr,qty,price
    @positions.fetch(tkr) { @positions[tkr] = {avg_px: 0.0, qty: 0 } }
    @positions[tkr][:avg_px] = (@positions[tkr][:avg_px]*@positions[tkr][:qty] + qty*price ) / (@positions[tkr][:qty] + qty)
    @positions[tkr][:qty] += qty
  end

  def sell(asof,tkr,qty,price)
    @xact_fh.write sprintf "%s,Sell,%s,%s,%s\n",asof,tkr,qty,price
    @pnl[:profit] += (price - @positions[tkr][:avg_px]) * qty
    @pnl[:drawdown] = @pnl[:profit] if @pnl[:profit] < @pnl[:drawdown]
    @positions[tkr][:qty] -= qty
  end

  def determine_rebalance_dates
    dates = case @rebalance_pd_method
    when "eom"
      eom_dates(@rebalance_pd).reverse
    end 
    dates
  end

  def eom_dates(offset=0)
    dates = []
    prev_m = 0
    off_set_cnt = 0
    load_dates(@bt_start_dt).each do |dt|
      m = dt.to_s[/\d\d\d\d(\d\d)\d\d/,1]
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
    dates[0..20]
  end

  def load_dates(start_dt=20140000)
    #@hp.dates_array.reverse
    #raw = @hp.dates_array
    #raw = raw.select { |dt| dt > start_dt }
    #raw.reverse
    @hp.dates_array.select { |dt| dt > start_dt }.reverse
    #raw.reverse
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
