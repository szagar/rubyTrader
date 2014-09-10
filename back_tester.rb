require "../zts/lib2/historical_prices"
require "../zts/lib2/price_series_helper"
require "../zts/lib2/date_time_helper"

#Env = "test"

class BackTester
  attr_reader :strategy

  def initialize(strategy)
    @strategy = strategy
    @date_ptr  = 0
    @tickers   = []
    @positions = {}
    @atrs      = {}
    @prices    = {}
    @price_data = {}
    @pnl = {peak: 0, holding_profit: 0, profit: 0, drawdown: 0}

    @bt_start_dt = 0

    @pos_fh  = File.open("positions.csv", 'a')
    @pos_fh.sync = true
    @rpt_fh  = File.open("report.csv", 'a')
    @rpt_fh.sync = true
    @xact_fh = File.open("xact.csv", 'w')
    @xact_fh.sync = true
    @xact_fh.write "descr,tkr,qty,price\n"
    env = Env
    @hp = HistoricalPrices.new(env)
  end

  def set_bt_start_dt(dt)
    puts "def set_bt_start_dt(#{dt})"
    @bt_start_dt = load_dates(dt).last
  end

  def reset(amount)
    @deposits = 0
    @pnl = {peak: 0, holding_profit: 0, profit: 0, drawdown: 0}
    @rebalance_dates = determine_rebalance_dates
    @positions = {}
    deposit(@bt_start_dt,amount)
    puts "reset: equity = #{equity(@bt_start_dt)}"
  end

  def deposit(asof,amount)
    @deposits += amount
    @positions[cash_tkr] = {}
    @positions[cash_tkr][:qty] = amount / price(cash_tkr,asof)
    puts "reset on #{@bt_start_dt} : #{@positions[cash_tkr][:qty]} at #{price(cash_tkr,asof)}"
    @positions[cash_tkr][:avg_px] = price(cash_tkr,asof)
  end

  def rebalance_period(type,count)
    @rebalance_str = "#{count}#{type}"
    case type
    when "daycnt"
      @rebalance_daycnt    = pd2daycnt(count)
    when "eom"
      @rebalance_pd_method = type
      @rebalance_pd        = count
    end
  end

  def eom_offset(offset)
    @eom_offset = offset
  end

  def add_ticker(tkr)
    @tickers << tkr if tkr_qualifies?(tkr)
  end

  def run
    @tickers.each { |tkr| @strategy.add_ticker(tkr) }
    puts "rebalance_dates = #{@rebalance_dates}"
    #load_dates(@bt_start_dt).each do |tdate|
    tdates = @hp.dates_array.select { |dt| dt >= @bt_start_dt }
    tdates.each do |tdate|
      puts "#{tdate}: pnl = #{metrics(tdate)}"
      check_exits(tdate)
      if @rebalance_dates.include?(tdate)
        target_pos = @strategy.run(asof: tdate)
        printf "PnL:%s %7.0f / %7.0f  targetPos: ",
               @strategy.report_desc,@pnl[:profit],@pnl[:drawdown]
        target_pos.each { |k,v| printf "%5s: %5.2f%%",k,target_pos[k] }
        printf "\n"
        rebalance2target(tdate,target_pos)
      end
    end

=begin
    @rebalance_dates.each do |asof|
      target_pos = @strategy.run(asof: asof)
      printf "PnL:%s %7.0f / %7.0f  targetPos: ",@strategy.report_desc,@pnl[:profit],@pnl[:drawdown]
      target_pos.each { |k,v| printf "%5s: %5.2f%%",k,target_pos[k] }
      printf "\n"
      today = @strategy.get_asof
      rebalance2target(today,target_pos)
puts "======> #{@pnl}"
    end
=end
  end  

  def report_hdr
    @rpt_fh.write sprintf "start_dt,%s,rebal_pd,eom_offset,profit,drawdown\n",@strategy.report_hdr
  end

  def report
    @rpt_fh.write sprintf "%d,%s,%s,%d,%.0f,%.0f\n",
                          @bt_start_dt,@strategy.report_desc,
                          @rebalance_str,@eom_offset,
                          @pnl[:profit],@pnl[:drawdown]
  end

  private

  def cash_tkr
    @strategy.cash
  end

  def tkr_qualifies?(tkr)
   @hp.volume(tkr) > 100_000 
  end

  def check_exits(asof)
    @positions.each do |tkr,h|
      next unless h[:qty] > 0
      stop_loss = @positions[tkr].fetch(:exit_price) { 0 }
      px = price(tkr,asof)
      if px < stop_loss
puts "Stop Loss Exit: #{tkr}  #{h}"
        puts "sell(#{asof},#{tkr},#{h[:qty]},#{px}) :: exit" 
        sell(asof,tkr,h[:qty],px) 
      end
    end
  end

  def set_exit(tkr,asof)
    atr = @atrs.fetch(tkr) { 
      prices = @hp.price_array(tkr,14*2,asof)
      #@atrs[tkr] = PriceSeriesHelper::set_atr(14,prices).last['atr']
      PriceSeriesHelper::set_atr(14,prices)
    }
    @positions[tkr][:exit_price] = (price(tkr,asof) - 3 * atr).round(2)
puts "atr=#{atr}"
puts "exit=#{@positions[tkr][:exit_price]}"
  end

  def rebalance2target(asof,target_pos)
    puts "def rebalance2target(#{asof},#{target_pos})"
    prev_equity = equity(asof)
    #puts "rebalance2target: @positions=#{@positions}"
    @positions.each do |tkr,h|
puts "1 dollars = #{target_pos.fetch(tkr) { 0 }} / 100 * #{prev_equity}"
      dollars = target_pos.fetch(tkr) { 0 } / 100 * prev_equity
      px = price(tkr,asof)
      new_size = (dollars / px).to_i.round(0)
      puts "buy(#{asof},#{tkr},#{new_size-h[:qty]},#{px}) :: adj pos" if new_size > h[:qty]
      buy(asof,tkr,new_size-h[:qty],px) if new_size > h[:qty]
      puts "rebalance2target: sell(#{asof},#{tkr},#{h[:qty]-new_size},#{px}) :: adj pos" if h[:qty] > new_size
      sell(asof,tkr,h[:qty]-new_size,px) if h[:qty] > new_size
    end
    target_pos.each do |tkr,perc|
puts "2 rebalance2target: tkr= = #{tkr}  perc = #{perc}"
puts "2 rebalance2target: asof= = #{asof}"
      px = price(tkr,asof)
puts "2 rebalance2target: px = #{px}"
puts "2 dollars = #{perc} / 100 * #{prev_equity}"
      dollars = perc / 100 * prev_equity
      qty = (dollars / px).to_i.round(0)
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

=begin
  def volume(tkr,date=false)
    puts "volume(#{tkr},#{date})"
    @vdate = date if date
    @vdate || @vdate = load_dates[0]
puts "@vdate=#{vdate}"
    rtn = @prices.fetch(tkr) { @prices[tkr] = Hash.new }
    rtn.fetch(vdate) { @prices[tkr] = load_prices(tkr,vdate) } 
    v = @prices[tkr][vdate][:v]
    puts "volume for #{tkr} is #{v}"
    v
  rescue
    0
  end
=end

  def load_prices(tkr,asof)
    @prices[tkr] = @hp.price_hash(tkr,5,asof)
  end

  def buy(asof,tkr,qty,price)
    @xact_fh.write sprintf "%s,%s,Buy,%s,%s,%s\n",@strategy.descr,asof,tkr,qty,price
    withdraw_cash(asof,qty*price)
    @positions.fetch(tkr) { @positions[tkr] = {avg_px: 0.0, qty: 0 } }
    pre_value = @positions[tkr][:avg_px]*@positions[tkr][:qty] 
    add_value = qty*price
    new_qty   = @positions[tkr][:qty] + qty
    @positions[tkr][:avg_px] = (pre_value + add_value ) / new_qty
    @positions[tkr][:qty] = new_qty
    set_exit(tkr,asof)
  end

  def sell(asof,tkr,qty,price)
    puts "sell(#{asof},#{tkr},#{qty},#{price})"
    @xact_fh.write sprintf "%s,%s,Sell,%s,%s,%s\n",@strategy.descr,asof,tkr,qty,price
    deposit_cash(asof,qty*price)
    @positions[tkr][:qty] -= qty
  end

  def deposit_cash(asof,amount)
    puts "deposit_cash(#{asof},#{amount})"
    price = price(cash_tkr,asof)
    qty   = amount / price
puts "deposit_cash: price = #{price}"
puts "deposit_cash: qty   = #{qty}"
puts "deposit_cash: @positions = #{@positions}"
puts "deposit_cash: @positions[#{cash_tkr}][:qty] = #{@positions[cash_tkr][:qty]}"
puts "deposit_cash: @positions[#{cash_tkr}][:avg_px] = #{@positions[cash_tkr][:avg_px]}"
    avg_price = (price*qty + @positions[cash_tkr][:qty]*@positions[cash_tkr][:avg_px]) / (qty+@positions[cash_tkr][:qty])
    @positions[cash_tkr][:qty] += qty
    @positions[cash_tkr][:avg_px] = avg_price
  end

  def withdraw_cash(asof,amount)
    price = price(cash_tkr,asof)
    qty   = amount / price
    @positions[cash_tkr][:qty] -= qty
  end

  def equity(asof)
    puts "def equity(#{asof})"
    @positions.map{|tkr,h| puts "#{h[:qty]} * #{price(tkr,asof)}"; h[:qty] * price(tkr,asof)}.reduce(:+).round(2)
  end

  def metrics(date)
    bal = equity(date)
    @pnl[:peak]     = bal if bal > @pnl[:peak]
    @pnl[:profit]   = bal - @deposits
    @pnl[:drawdown] = (@pnl[:peak] - bal) if (@pnl[:peak] - bal) > @pnl[:drawdown]
    @pnl[:holding_profit]   = 0
    @positions.keys.each do |tkr|
      next unless @positions[tkr][:qty] > 0
      puts "holding_profit calc #{tkr} on #{date}: (#{@pnl[:holding_profit]}) : #{@positions[tkr][:qty]} * (#{price(tkr,date)}-#{@positions[tkr][:avg_px]})"
      @pnl[:holding_profit] += @positions[tkr][:qty] * (price(tkr,date)-@positions[tkr][:avg_px])
    end
    sprintf "equity: %6.0f  profit: %6.0f  peak: %6.0f  drawdown: %6.0f \n",bal,@pnl[:profit],@pnl[:peak],@pnl[:drawdown]
  end

  def determine_rebalance_dates
    puts "determine_rebalance_dates"
    puts "@rebalance_pd_method=#{@rebalance_pd_method}"
    dates = case @rebalance_pd_method
    when "eom"
      eom_dates(@eom_offset).reverse
    end 
    dates
  end

  def eom_dates(offset=0)
    puts "eom_dates(offset=#{offset})"
    dates = []
    prev_m = 0
    off_set_cnt = 0
    puts "eom_dates: @bt_start_dt=#{@bt_start_dt}"
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
    dates
  end

  #def load_dates(start_dt=20140001)
  def load_dates(start_dt)
  puts "def load_dates(#{start_dt})"
    @hp.dates_array.select { |dt| dt > start_dt }.reverse
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
