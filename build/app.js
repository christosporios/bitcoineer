(function() {
  var Market, MtGoxClient, app, btc, btcToUsd, buy, currentStatus, express, getData, lastBuyOrder, lastNotification, lastSellOrder, market, mtgox, newValue, notifyBuy, notifySell, options, orders, price, profit, sell, sellPrice, server, start, state, trend, twilio, updateInfo, usd, value, value12hAgo, valueHistory, valueLastUpdate, valueUpdateInterval;

  express = require('express');

  app = express();

  server = require('http').createServer(app);

  options = require(__dirname + '/config.js').options;

  MtGoxClient = require("./mtgox");

  Market = require(__dirname + '/market.js').Market;

  app.use(express.bodyParser());

  twilio = require('twilio')(options.twilioSid, options.twilioToken);

  value = null;

  valueHistory = [];

  orders = [];

  valueUpdateInterval = 60 * 1000;

  valueLastUpdate = 0;

  btc = null;

  usd = null;

  price = null;

  profit = null;

  state = "idle";

  trend = "uninitialized";

  mtgox = new MtGoxClient(options.mtGoxApiKey, options.mtGoxApiSecret);

  app.use(express.static(__dirname + '/public'));

  app.get('/', function(req, res) {
    return res.sendfile(__dirname + '/public/interface.html');
  });

  app.get('/status', function(req, res) {
    return res.send(JSON.stringify(currentStatus()));
  });

  app.get('/value', function(req, res) {
    var interval, since;
    since = parseInt(req.query.since);
    interval = parseInt(req.query.interval);
    if (!req.query.since) since = Date.now() - 3 * 60 * 60 * 1000;
    if (!req.query.interval) interval = 1000 * 60;
    return res.send(JSON.stringify(getData(valueHistory, since, interval)));
  });

  app.get('/market', function(req, res) {
    var interval, since;
    since = parseInt(req.query.since);
    interval = parseInt(req.query.interval);
    if (!req.query.since) since = Date.now() - 3 * 24 * 60 * 60 * 1000;
    if (!req.query.interval) interval = 1000 * 60 * 10;
    return res.send(JSON.stringify(getData(market.data, since, interval)));
  });

  app.get('/orders', function(req, res) {
    return res.send(JSON.stringify(orders));
  });

  app.post('/action', function(req, res) {
    var cmd;
    if (req.body.password !== options.password) {
      res.send(401);
    } else {
      cmd = req.body.cmd;
      console.log("Action " + cmd + " requested");
      if (cmd === "buy-stop") {
        state = "idle";
        buy();
      } else if (cmd === "sell-stop") {
        state = "idle";
        sell();
      } else if (cmd === "stop") {
        state = "idle";
      } else if (cmd === "start") {
        state = "trading";
      } else if (cmd === "buy" && state === "idle") {
        buy();
      } else if (cmd === "sell" && state === "idle") {
        sell();
      } else {
        res.send(200);
        return;
      }
      return res.send(200);
    }
  });

  getData = function(arr, since, interval) {
    var afterTime, p, ret, _i, _len;
    afterTime = since;
    ret = [];
    for (_i = 0, _len = arr.length; _i < _len; _i++) {
      p = arr[_i];
      if (p.time > afterTime) {
        console.log;
        ret.push(p);
        afterTime = p.time + interval;
      }
    }
    return ret;
  };

  btcToUsd = function(b) {
    return b * market.price();
  };

  newValue = function(value) {
    if (Date.now() > valueUpdateInterval + valueLastUpdate) {
      valueLastUpdate = Date.now();
      valueHistory.push({
        value: value,
        time: valueLastUpdate
      });
      return console.log("new value");
    }
  };

  updateInfo = function() {
    return mtgox.info(function(err, json) {
      var data, pastvalue;
      if (json === void 0 || err) {
        console.log("No data returned by mtgox.info. " + err);
        return;
      }
      data = json.data;
      btc = parseFloat(data['Wallets']['BTC']['Balance']['value']);
      usd = parseFloat(data['Wallets']['USD']['Balance']['value']);
      value = usd + btcToUsd(btc);
      newValue(value);
      pastvalue = value12hAgo();
      profit = (value - pastvalue) / pastvalue;
      return trend = market.trend;
    });
  };

  value12hAgo = function() {
    var p, ret, since, _ref;
    if (valueHistory.length === 0) return;
    since = Date.now() - 12 * 60 * 60 * 1000;
    ret = valueHistory[0].value;
    for (p = 0, _ref = valueHistory.length; 0 <= _ref ? p <= _ref : p >= _ref; 0 <= _ref ? p++ : p--) {
      if (p.time <= since) ret = p.value;
    }
    return ret;
  };

  currentStatus = function() {
    return {
      status: state,
      profit: profit,
      value: value,
      usd: usd,
      btc: btc,
      trend: trend
    };
  };

  sellPrice = null;

  start = function() {
    console.log("Ready");
    updateInfo();
    setInterval(updateInfo, 10000);
    setInterval(function() {
      return mtgox.ticker(function(err, json) {
        var data;
        if (!err) {
          data = json.data;
          console.log("[" + data.now + "] Avg: " + data.avg.value + ", last: " + data.last.value + ", buy: " + data.buy.value + ", sell: " + data.sell.value + ", trend = " + trend);
          sellPrice = data.sell.value;
          return market.newPrice(parseFloat(data.last.value), Math.floor(data.now / 1000));
        } else {
          return console.log("Unable to get ticker. " + err);
        }
      });
    }, 1000);
    return app.listen(3000);
  };

  lastBuyOrder = 0;

  buy = function() {
    if (usd === 0.0) return;
    if ((Date.now() - lastBuyOrder) < 60 * 1000) return;
    if (!sellPrice) return;
    return mtgox.add("bid", "" + (usd / sellPrice), "" + sellPrice, function(err, json) {
      if (err) {
        return console.log("Unable to place bid order. " + err);
      } else {
        console.log("Bid order for " + (usd / sellPrice) + " BTC placed at " + sellPrice);
        return lastBuyOrder = Date.now();
      }
    });
  };

  lastSellOrder = 0;

  sell = function() {
    if (btc === 0.0) return;
    if ((Date.now() - lastSellOrder) < 60 * 1000) return;
    return mtgox.add("ask", "" + btc, null, function(err, json) {
      if (err) {
        return console.log("Unable to place ask order. " + err);
      } else {
        console.log("Ask order for " + btc + " BTC placed");
        return lastSellOrder = Date.now();
      }
    });
  };

  lastNotification = null;

  notifyBuy = function() {
    if (lastNotification === "buy") return;
    twilio.sms.messages.create({
      body: "MtgoxUSD: Uptrend detected. Bot is currently " + state + ". Value = " + value + ", btc = " + btc + ", usd = " + usd + ". Market price: " + (market.price()) + " - BUY.",
      to: "+306980586851",
      from: "+14439917527"
    }, function(err, msg) {
      if (!err) {
        console.log("Uptrend SMS notification sent");
        return lastNotification = "buy";
      } else {
        return console.log("Could not send SMS. " + err);
      }
    });
    return console.log("---> UPTREND");
  };

  notifySell = function() {
    if (lastNotification === "sell") return;
    twilio.sms.messages.create({
      body: "MtgoxUSD: Downtrend detected. Bot is currently " + state + ". Value = " + value + ", btc = " + btc + ", usd = " + usd + ". Market price: " + (market.price()) + " - SELL.",
      to: options.userPhoneNumber,
      from: options.twilioPhoneNumber
    }, function(err, msg) {
      if (!err) {
        console.log("Downtrend SMS notification sent");
        return lastNotification = "sell";
      } else {
        return console.log("Could not send SMS. " + err);
      }
    });
    return console.log("---> DOWNTREND");
  };

  market = new Market(mtgox, 60000, start);

  market.onTrendChange = function(t) {
    if (trend === "uninitialized") return;
    trend = t;
    if (trend === 'uptrend') {
      return notifyBuy();
    } else {
      return notifySell();
    }
  };

  setInterval(function() {
    if (trend === "uptrend") {
      if (state === "trading") return buy();
    } else {
      if (state === "trading") return sell();
    }
  }, 1000);

  setInterval(function() {
    return mtgox.orders(function(err, json) {
      if (!err) {
        return orders = json.data;
      } else {
        return console.log("Unable to retrieve orders. " + err);
      }
    });
  }, 5000);

}).call(this);
