class BackTester
  def initialize(strategy)
    @strategy = strategy
    @date_ptr = 0
    @tickers = []
    @price_data = {}
  end

  def reset(today,amount)
    @balance = amount
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
    @rebalance_dates.each do |asof|
      @strategy.run(asof: asof)
    end
  end  

  def report
    puts "Report ... "
  end

  private

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
      eom_dates(@rebalance_pd)
    end 
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
    dates
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
