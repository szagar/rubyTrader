#require "../zts/lib2/price_series_helper"
#require "../zts/lib2/date_time_helper"
require_relative "../../zts/lib2/tc_helper"

#Env = "test"

class BackTester
  attr_reader :strategy

  def initialize
    @strategies = []
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
  end

  def set_bt_start_dt(dt)
    #puts "def set_bt_start_dt(#{dt})"
    @bt_start_dt = @strategies[0].load_dates(dt).last
  end

  def reset(amount)
    @deposits = 0
    @pnl = {peak: 0, holding_profit: 0, profit: 0, drawdown: 0}
    @positions = {}
    @positions[cash_tkr] = {qty: 0, avg_px: 0}
    deposit(@bt_start_dt,amount)
  end

  def add_strategy(strategy,tc_fn)
    @strategies << strategy.new(tc_fn)
  end

  def run
    run_dates = @strategies[0].tc.dates.select {|d| d >= @bt_start_dt}
    run_dates.each do |tdate|
      @strategies.each do |strat|
        strat.tc.set_asof(tdate)
        entry = strat.entries(tdate)
        if entry
          submit_entry(entry)
          if entry.key_exists?(:init_stop) && entry[:init_stop] > 0
            submit_exit({stop_loss: entry[:init_stop]})
          end
        end
      end
      @positions.each do |pos|
        price_hash = @strategies[pos[:tkr]].tc.ohlc
        exit = exit_mgr(pos,price_hash)
        submit_exit(exit) if exit
      end
    end
  end

  def down_day?(tkr,tdate)
    price(tkr,date) < prev_close(tkr,date)
  end

  def check_entries(tdate)
    entries = []
    @tickers.each do |tkr|
      entries << buy(tdate,tkr) if down_days[tkr] >= 5
    end
  end

  def entry_stop_price(tdate,tkr)
    asof = prev_tdate(tdate)
    high(tkr,asof)
  end

  def prev_tdate(tdate)
  end

  def high(tkr,date)
  end

  def report_hdr
    puts "report_hdr entered."
    #@rpt_fh.write sprintf "symbolList,start_dt,%s,peak,profit,drawdown\n",@strategy.report_hdr
  end

  def report
    @rpt_fh.write sprintf "%s,%d,%s,%s,%d,%.0f,%.0f,%.0f\n",
                          @symbol_file,@bt_start_dt,@strategy.report_desc,
                          @pnl[:peak],
                          @pnl[:profit],@pnl[:drawdown]
  end

  private

  def buy(tdate,tkr)
    size = position_size(tdate,tkr,pos_risk)
    price = entry_stop_price(tdate,tkr)
    {:tkr => tkr, :quantity => size, :stop_price => price}
  end

  def pos_risk
    500
  end

  def position_size(tdate,tkr,risk_pos,cap_pos)
    atr = @tc.atr(asof,period)
    size = (risk_pos / (atr*atr_factor)).to_i
    return size if size*tc.last <= cap_pos
    return (cap_pos/tc.last).to_i if adj4cap?
    0
  end

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

  def high(tkr,date)
    rtn = @prices.fetch(tkr) { @prices[tkr] = Hash.new }
    rtn.fetch(date) { @prices[tkr] = load_prices(tkr,date) } 
    @prices[tkr][date][:h]
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
