express = require('express')
app = express()
server = require('http').createServer(app)
options = require(__dirname + '/config.js').options

MtGoxClient = require("./mtgox")
Market = require(__dirname + '/market.js').Market

app.use(express.bodyParser())
twilio = require('twilio')(options.twilioSid, options.twilioToken)

value = null
valueHistory = []
orders = []
valueUpdateInterval = 60 * 1000
valueLastUpdate = 0
btc = null
usd = null
price = null
profit = null
state = "idle"
trend = "uninitialized"

mtgox = new MtGoxClient(options.mtGoxApiKey, options.mtGoxApiSecret)

app.use(express.static(__dirname + '/public'))

app.get '/', (req, res) ->
  res.sendfile(__dirname + '/public/interface.html')

app.get '/status', (req, res) ->
  res.send JSON.stringify(currentStatus())

app.get '/value', (req, res) ->
  since = parseInt(req.query.since); interval = parseInt(req.query.interval)
  since = Date.now() - 3 * 60 * 60 * 1000 unless req.query.since
  interval = 1000 * 60 unless req.query.interval
  res.send JSON.stringify getData(valueHistory, since, interval)


app.get '/market', (req, res) ->
  since = parseInt(req.query.since); interval = parseInt(req.query.interval)
  since = Date.now() - 3 * 24 * 60 * 60 * 1000 unless req.query.since
  interval = 1000 * 60 * 10 unless req.query.interval
  res.send JSON.stringify getData(market.data, since, interval)

app.get '/orders', (req, res) ->
  res.send JSON.stringify(orders)

app.post '/action', (req, res) ->
  unless req.body.password == options.password
    res.send(401)
    return
  else
    cmd = req.body.cmd
    console.log "Action #{cmd} requested"

    if cmd=="buy-stop"
      state = "idle"
      buy()
    else if cmd == "sell-stop"
      state = "idle"
      sell()
    else if cmd == "stop"
      state ="idle"
    else if cmd == "start"
      state = "trading"
    else if cmd == "buy" and state == "idle" # Only accept manual commands when not autotrading
      buy()
    else if cmd == "sell" and state == "idle"
      sell()
    else 
      res.send(200)
      return
    res.send(200)

getData = (arr, since, interval) ->
  afterTime = since
  ret = []
  for p in arr
    if p.time > afterTime
      console.log 
      ret.push p
      afterTime = p.time + interval
  ret

btcToUsd = (b) ->
  b * market.price()

newValue = (value) ->
  if Date.now() > valueUpdateInterval + valueLastUpdate
    valueLastUpdate = Date.now()
    valueHistory.push {value: value, time: valueLastUpdate}
    console.log "new value"

updateInfo = ->
  mtgox.info (err, json) ->
    if json == undefined or err
      console.log "No data returned by mtgox.info. #{err}"
      return
    data = json.data
    btc = parseFloat(data['Wallets']['BTC']['Balance']['value'])
    usd = parseFloat(data['Wallets']['USD']['Balance']['value'])
    value = usd + btcToUsd(btc)
    newValue(value)
    pastvalue = value12hAgo()
    profit = (value - pastvalue)/pastvalue

    trend = market.trend

value12hAgo = () ->
  return if valueHistory.length == 0
  since = Date.now() - 12 * 60 * 60 * 1000
  ret = valueHistory[0].value
  for p in [0..valueHistory.length]
    ret = p.value if p.time <= since
  ret

currentStatus = -> 
  {
    status: state,
    profit: profit,
    value: value,
    usd: usd,
    btc: btc,
    trend: trend
  }

sellPrice = null
start = ->
  console.log "Ready"
  updateInfo()
  setInterval(updateInfo, 10000)
  setInterval ->
    mtgox.ticker (err, json) ->
      unless err
        data = json.data
        console.log "[#{data.now}] Avg: #{data.avg.value}, last: #{data.last.value}, buy: #{data.buy.value}, sell: #{data.sell.value}, trend = #{trend}"
        sellPrice = data.sell.value
        market.newPrice(parseFloat(data.last.value), Math.floor(data.now/1000))
      else
        console.log "Unable to get ticker. #{err}"
  , 1000

  app.listen(3000)

lastBuyOrder = 0
buy = ->
  return if usd == 0.0
  return if (Date.now() - lastBuyOrder) < 60 * 1000
  return unless sellPrice
  mtgox.add("bid", "#{usd/sellPrice}", "#{sellPrice}", (err, json) ->
    if err
      console.log "Unable to place bid order. #{err}"
    else
      console.log "Bid order for #{usd/sellPrice} BTC placed at #{sellPrice}"
      lastBuyOrder = Date.now()
  )

lastSellOrder = 0
sell = ->
  return if btc == 0.0
  return if (Date.now() - lastSellOrder) < 60 * 1000
  mtgox.add("ask", "#{btc}", null, (err, json) ->
    if err
      console.log "Unable to place ask order. #{err}"
    else
      console.log "Ask order for #{btc} BTC placed"
      lastSellOrder = Date.now()
  )

lastNotification = null

notifyBuy = ->
  return if lastNotification == "buy"
  twilio.sms.messages.create {
    body: "MtgoxUSD: Uptrend detected. Bot is currently #{state}. Value = #{value}, btc = #{btc}, usd = #{usd}. Market price: #{market.price()} - BUY.",
    to: "+306980586851",
    from: "+14439917527"
  }, (err, msg) ->
    unless err
      console.log "Uptrend SMS notification sent"
      lastNotification = "buy"
    else
      console.log "Could not send SMS. #{err}"
  console.log "---> UPTREND"

notifySell = ->
  return if lastNotification == "sell"

  twilio.sms.messages.create {
    body: "MtgoxUSD: Downtrend detected. Bot is currently #{state}. Value = #{value}, btc = #{btc}, usd = #{usd}. Market price: #{market.price()} - SELL.",
    to: options.userPhoneNumber,
    from: options.twilioPhoneNumber
  }, (err, msg) ->
    unless err
      console.log "Downtrend SMS notification sent"
      lastNotification = "sell"
    else
      console.log "Could not send SMS. #{err}"
  console.log "---> DOWNTREND"

market = new Market(mtgox, 60000, start)

market.onTrendChange = (t) ->
  return if trend == "uninitialized"
  trend = t
  if trend == 'uptrend'
    notifyBuy()
  else
    notifySell()

setInterval( ->
  if trend == "uptrend"
    buy() if state == "trading"
  else
    sell() if state == "trading"
, 1000)

setInterval( ->
  mtgox.orders (err, json) ->
    unless err
      orders = json.data
    else
      console.log "Unable to retrieve orders. #{err}"
, 5000)
