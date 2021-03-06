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
    #puts "def set_bt_start_dt(#{dt})"
    @bt_start_dt = load_dates(dt).last
  end

  def reset(amount)
    @deposits = 0
    @pnl = {peak: 0, holding_profit: 0, profit: 0, drawdown: 0}
    @rebalance_dates = determine_rebalance_dates
    @positions = {}
    @positions[cash_tkr] = {qty: 0, avg_px: 0}
    deposit(@bt_start_dt,amount)
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

  def reset_price_data
    puts "@hp.persist_yahoo_prices(#{@strategy.cash})"
    @hp.persist_yahoo_prices(@strategy.cash)
    @tickers.each { |tkr| @hp.persist_yahoo_prices(tkr) }
  end

  def set_symbol_file(fn)
    File.open(fn).each { |tkr| add_ticker(tkr.chomp.rstrip) }
    @symbol_file = File.basename(fn,".symbols")
  end

  def add_ticker(tkr)
    @tickers << tkr if tkr_qualifies?(tkr)
  end

  def run
    @tickers.each { |tkr| @strategy.add_ticker(tkr) }
    tdates = @hp.dates_array.select { |dt| dt >= @bt_start_dt }
    tdates.each do |tdate|
      check_exits(tdate)
      puts metrics(tdate)
        #printf "PnL:#{tdate}:%s %6.0f/%6.0f %6.0f/%-6.0f  targetPos: ",
        #       @strategy.report_desc,@pnl[:peak],equity(tdate),
        #       @pnl[:profit],@pnl[:drawdown]
      if @rebalance_dates.include?(tdate)
        target_pos = @strategy.run(asof: tdate)
        printf "Target Position #{tdate}: "
        target_pos.each { |k,v| printf "%5s: %5.2f%%",k,target_pos[k] }
        printf "\n"
        rebalance2target(tdate,target_pos)
      end
    end
  end  

  def report_hdr
    @rpt_fh.write sprintf "symbolList,start_dt,%s,rebal_pd,eom_offset,peak,profit,drawdown\n",@strategy.report_hdr
  end

  def report
    @rpt_fh.write sprintf "%s,%d,%s,%s,%d,%.0f,%.0f,%.0f\n",
                          @symbol_file,@bt_start_dt,@strategy.report_desc,
                          @rebalance_str,@eom_offset,
                          @pnl[:peak],
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
      next if tkr == cash_tkr
      next unless h[:qty] > 0
      stop_loss = @positions[tkr].fetch(:exit_price) { 0 }
      px = price(tkr,asof)
      sell(asof,tkr,h[:qty],px,"exit") if px < stop_loss
    end
  end

  def set_exit(tkr,asof)
    atr = @atrs.fetch(tkr) { 
      prices = @hp.price_array(tkr,14*2,asof)
      #@atrs[tkr] = PriceSeriesHelper::set_atr(14,prices).last['atr']
      PriceSeriesHelper::set_atr(14,prices)
    }
    @positions[tkr][:exit_price] = (price(tkr,asof) - 3 * atr).round(2)
  end

  def rebalance2target(asof,target_pos)
    #puts "def rebalance2target(#{asof},#{target_pos})"
    prev_equity = equity(asof)
    @positions.each do |tkr,h|
      next if tkr == cash_tkr
      dollars = target_pos.fetch(tkr) { 0 } / 100 * prev_equity
      px = price(tkr,asof)
      new_size = (dollars / px).to_i.round(0)
      pos_delta = new_size - h[:qty]
      next if pos_delta.abs < 5
      puts "rebalance2target: #{tkr} adj: #{h[:qty]} -> #{new_size}"
      buy(asof,tkr,pos_delta.abs,px,"adjustment")  if pos_delta > 0
      sell(asof,tkr,pos_delta.abs,px,"adjustment") if pos_delta < 0
    end
    target_pos.each do |tkr,perc|
      next if tkr == cash_tkr
      pos = @positions.fetch(tkr) { {qty: 0} }
      holding = pos[:qty]
      px = price(tkr,asof)
      dollars = perc / 100 * prev_equity
      new_size = (dollars / px).to_i.round(0)
      pos_delta = new_size - holding
      next if pos_delta < 5
      puts "rebalance2target: #{tkr} adj: #{holding} -> #{new_size}"
      buy(asof,tkr,pos_delta.abs,px,"new")
    end
  end

  def price(tkr,date)
    puts "def price(#{tkr},#{date})"
    rtn = @prices.fetch(tkr) { @prices[tkr] = Hash.new }
    rtn.fetch(date) {
      #@prices[tkr] = load_prices(tkr,date)
       lp = load_prices(tkr,date)
      puts "lp(#{tkr},#{date}) = #{lp}"
       @prices[tkr] = lp
    } 
puts "@prices=#{@prices}"
puts "@prices[tkr]=#{@prices[tkr]}"
puts "@prices[tkr][date]=#{@prices[tkr][date]}"
puts "@prices[#{tkr}][#{date}][:c]=#{@prices[tkr][date][:c]}"
    @prices[tkr][date][:c]
  end

  def load_prices(tkr,asof)
    puts "load_prices(#{tkr},#{asof})"
    @prices[tkr] = @hp.price_hash(tkr,5,asof)
puts "load_prices: #{@prices[tkr]}"
    @prices[tkr]
  end

  def buy(asof,tkr,qty,price,note="")
    puts "buy(#{asof},#{tkr},#{qty},#{price})  :: #{note}"
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

  def sell(asof,tkr,qty,price,note="")
    puts "sell(#{asof},#{tkr},#{qty},#{price})  PnL=#{qty*(price-@positions[tkr][:avg_px])} :: #{note}" 
    @xact_fh.write sprintf "%s,%s,Sell,%s,%s,%s\n",@strategy.descr,asof,tkr,qty,price
    move2cash(asof,qty*price)
    @positions[tkr][:qty] -= qty
  end

  def move2cash(asof,amount)
    puts "move2cash(#{asof},#{amount})"
    price = price(cash_tkr,asof)
    qty   = (amount / price).round(0)
    avg_price = (price*qty + @positions[cash_tkr][:qty]*@positions[cash_tkr][:avg_px]) / (qty+@positions[cash_tkr][:qty])
    @positions[cash_tkr][:qty] += qty
    @positions[cash_tkr][:avg_px] = avg_price
  end

  def deposit(asof,amount)
    @deposits += amount
    move2cash(asof,amount)
  end


  def withdraw_cash(asof,amount)
    price = price(cash_tkr,asof)
    qty   = (amount / price).round(0)
    @positions[cash_tkr][:qty] -= qty
  end

  def equity(asof)
    @positions.map{|tkr,h| 
      h[:qty] * price(tkr,asof)}.reduce(:+).round(2)
  end

  def metrics(date)
    bal = equity(date)
    @pnl[:peak]     = bal if bal > @pnl[:peak]
    @pnl[:profit]   = bal - @deposits
    @pnl[:drawdown] = (@pnl[:peak] - bal) if (@pnl[:peak] - bal) > @pnl[:drawdown]
    @pnl[:holding_profit]   = 0
    @positions.keys.each do |tkr|
      next unless @positions[tkr][:qty] > 0
      @pnl[:holding_profit] += @positions[tkr][:qty] * (price(tkr,date)-@positions[tkr][:avg_px])
    end
    sprintf "equity: %6.0f  profit: %6.0f  peak: %6.0f  drawdown: %6.0f \n",bal,@pnl[:profit],@pnl[:peak],@pnl[:drawdown]
  end

  def determine_rebalance_dates
    #puts "determine_rebalance_dates"
    dates = case @rebalance_pd_method
    when "eom"
      eom_dates(@eom_offset).reverse
    end 
    dates
  end

  def eom_dates(offset=0)
    #puts "eom_dates(offset=#{offset})"
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
    dates
  end

  def load_dates(start_dt)
    #puts "def load_dates(#{start_dt})"
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
