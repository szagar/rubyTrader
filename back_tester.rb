require "../zts/lib2/historical_prices"
require "../zts/lib2/date_time_helper"

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
    @pnl = {peak: 0, holding_profit: 0, profit: 0, drawdown: 0}

    @bt_start_dt = 0

    @rpt_fh  = File.open("report.csv", 'w')
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
puts "@bt_start_dt=#{@bt_start_dt}"
  end

  def reset(amount)
    @deposits = amount
    @pnl = {peak: 0, holding_profit: 0, profit: 0, drawdown: 0}
    @rebalance_dates = determine_rebalance_dates
    @positions = {}
    @positions['SHY'] = {}
    #@positions['SHY'][:qty] = amount / price('SHY',@rebalance_dates[0])
    @positions['SHY'][:qty] = amount / price('SHY',@bt_start_dt)
    puts "reset on #{@bt_start_dt} : #{@positions['SHY'][:qty]} at #{price('SHY',@bt_start_dt)}"
    @positions['SHY'][:avg_px] = price('SHY',@bt_start_dt)
    puts "reset: equity = #{equity(@bt_start_dt)}"
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
    @rpt_fh.write sprintf "%s,rebal_pd,profit,drawdown\n",@strategy.report_hdr
  end

  def report
    @rpt_fh.write sprintf "%s,%s,%.0f,%.0f\n",@strategy.report_desc,@rebalance_str,@pnl[:profit],@pnl[:drawdown]
  end

  private

  def tkr_qualifies?(tkr)
   @hp.volume(tkr) > 100_000 
  end

  def check_exits(asof)
    @positions.each do |tkr,h|
    end
  end

  def rebalance2target(asof,target_pos)
    puts "def rebalance2target(#{asof},#{target_pos})"
    prev_equity = equity(asof)
    #puts "rebalance2target: @positions=#{@positions}"
    @positions.each do |tkr,h|
puts "1 dollars = #{target_pos.fetch(tkr) { 0 }} / 100 * #{prev_equity}"
      dollars = target_pos.fetch(tkr) { 0 } / 100 * prev_equity
      px = price(tkr,asof)
      new_size = (dollars / px).to_i
      puts "buy(#{asof},#{tkr},#{new_size-h[:qty]},#{px}) :: adj pos" if new_size > h[:qty]
      buy(asof,tkr,new_size-h[:qty],px) if new_size > h[:qty]
      puts "sell(#{asof},#{tkr},#{h[:qty]-new_size},#{px}) :: adj pos" if h[:qty] > new_size
      sell(asof,tkr,h[:qty]-new_size,px) if h[:qty] > new_size
    end
    target_pos.each do |tkr,perc|
puts "2 rebalance2target: tkr= = #{tkr}  perc = #{perc}"
puts "2 rebalance2target: asof= = #{asof}"
      px = price(tkr,asof)
puts "2 rebalance2target: px = #{px}"
puts "2 dollars = #{perc} / 100 * #{prev_equity}"
      dollars = perc / 100 * prev_equity
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
    @positions.fetch(tkr) { @positions[tkr] = {avg_px: 0.0, qty: 0 } }
    @positions[tkr][:avg_px] = (@positions[tkr][:avg_px]*@positions[tkr][:qty] + qty*price ) / (@positions[tkr][:qty] + qty)
    @positions[tkr][:qty] += qty
  end

  def sell(asof,tkr,qty,price)
    @xact_fh.write sprintf "%s,%s,Sell,%s,%s,%s\n",@strategy.descr,asof,tkr,qty,price
    #@pnl[:profit] += (price - @positions[tkr][:avg_px]) * qty
    #@pnl[:drawdown] = @pnl[:profit] if @pnl[:profit] < @pnl[:drawdown]
    @positions[tkr][:qty] -= qty
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
      eom_dates(@rebalance_pd).reverse
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
