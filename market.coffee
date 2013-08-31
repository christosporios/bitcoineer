rest = require(__dirname + '/rest.js')

class Market
  constructor: (@api, @interval = 60000, @onReady) ->
    @data = []
    @history = {}
    @trend = "uninitialized"

    @getHistory()

  price: -> @data[@data.length - 1].average
  sma12: -> @data[@data.length - 1].sma12
  sma24: -> @data[@data.length - 1].sma24
  sma48: -> @data[@data.length - 1].sma48
  ema: -> @data[@data.length - 1].ema

  newPrice: (price, time) =>
    if time > (@lastTime + @interval)
      console.log "Price updated, last time = #{@lastTime}, time = #{time}"
      @lastTime = time
      @data.push {time: time, average: price}
      @calculateIndicators(@data.length-1)

      newTrend = @findTrend()
      trendChange = (newTrend != @trend)
      @trend = newTrend
      @onTrendChange(@trend) if trendChange and typeof(@onTrendChange) == 'function'

  getHistory: =>
    data = @data
    history = @history
    me = this
    rest.getJSON({host: 'bitcoincharts.com', path: '/charts/chart.json?m=mtgoxUSD&r=3&i=1-min', method: 'GET'}, (status, res) ->
      for p in res
        data.push {time: p[0] * 1000, open: p[1], high: p[2], low: p[3], close: p[4], average: p[7]}
        history[p[0]] = data[data.length - 1]
      me.calculateIndicators()
      me.onReady() if typeof(me.onReady) == 'function'
    )

  calculateIndicators: (lo = 0)=>
    for i in [lo...@data.length]
      @data[i]["sma48"] = @averageInRange(@data[i].time - 48 * 60 * 60 * 1000, @data[i].time)
      @data[i]["sma24"] = @averageInRange(@data[i].time - 24 * 60 * 60 * 1000, @data[i].time)
      @data[i]["sma12"] = @averageInRange(@data[i].time - 12 * 60 * 60 * 1000, @data[i].time)
      @data[i]["ema"] = @emaInRange(@data[i].time - 3 * 24 * 60 * 1000, @data[i].time)

    @lastTime = @data[@data.length - 1].time


  averageInRange: (lo, hi) ->
    avg = 0
    cnt = 0
    for p in @data
      if p.time >= lo and p.time <= hi
        avg += p.average
        cnt += 1
    
    avg / cnt

  emaInRange: (lo, hi) ->
    prices = []
    for p in @data
      prices.push p.average if p.time >= lo and p.time <= hi

    alpha = 2/(prices.length+1)

    ema = prices[0] * Math.pow(1-alpha, prices.length-1)
    for i in [1...prices.length]
      ema += alpha * Math.pow(1-alpha, prices.length-i-1) * prices[i]
    ema

  findTrend: ->
    if @ema() > @sma12() and @sma12() > @sma24()
      return "uptrend"
    else if @ema() > @sma12()
      return "idle"
    else return "downtrend"


exports.Market = Market
