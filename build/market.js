(function() {
  var Market, rest,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  rest = require(__dirname + '/rest.js');

  Market = (function() {

    function Market(api, interval, onReady) {
      this.api = api;
      this.interval = interval != null ? interval : 60000;
      this.onReady = onReady;
      this.calculateIndicators = __bind(this.calculateIndicators, this);
      this.getHistory = __bind(this.getHistory, this);
      this.newPrice = __bind(this.newPrice, this);
      this.data = [];
      this.history = {};
      this.trend = "uninitialized";
      this.getHistory();
    }

    Market.prototype.price = function() {
      return this.data[this.data.length - 1].average;
    };

    Market.prototype.sma12 = function() {
      return this.data[this.data.length - 1].sma12;
    };

    Market.prototype.sma24 = function() {
      return this.data[this.data.length - 1].sma24;
    };

    Market.prototype.sma48 = function() {
      return this.data[this.data.length - 1].sma48;
    };

    Market.prototype.ema = function() {
      return this.data[this.data.length - 1].ema;
    };

    Market.prototype.newPrice = function(price, time) {
      var newTrend, trendChange;
      if (time > (this.lastTime + this.interval)) {
        console.log("Price updated, last time = " + this.lastTime + ", time = " + time);
        this.lastTime = time;
        this.data.push({
          time: time,
          average: price
        });
        this.calculateIndicators(this.data.length - 1);
        newTrend = this.findTrend();
        trendChange = newTrend !== this.trend;
        this.trend = newTrend;
        if (trendChange && typeof this.onTrendChange === 'function') {
          return this.onTrendChange(this.trend);
        }
      }
    };

    Market.prototype.getHistory = function() {
      var data, history, me;
      data = this.data;
      history = this.history;
      me = this;
      return rest.getJSON({
        host: 'bitcoincharts.com',
        path: '/charts/chart.json?m=mtgoxUSD&r=3&i=1-min',
        method: 'GET'
      }, function(status, res) {
        var p, _i, _len;
        for (_i = 0, _len = res.length; _i < _len; _i++) {
          p = res[_i];
          data.push({
            time: p[0] * 1000,
            open: p[1],
            high: p[2],
            low: p[3],
            close: p[4],
            average: p[7]
          });
          history[p[0]] = data[data.length - 1];
        }
        me.calculateIndicators();
        if (typeof me.onReady === 'function') return me.onReady();
      });
    };

    Market.prototype.calculateIndicators = function(lo) {
      var i, _ref;
      if (lo == null) lo = 0;
      for (i = lo, _ref = this.data.length; lo <= _ref ? i < _ref : i > _ref; lo <= _ref ? i++ : i--) {
        this.data[i]["sma48"] = this.averageInRange(this.data[i].time - 48 * 60 * 60 * 1000, this.data[i].time);
        this.data[i]["sma24"] = this.averageInRange(this.data[i].time - 24 * 60 * 60 * 1000, this.data[i].time);
        this.data[i]["sma12"] = this.averageInRange(this.data[i].time - 12 * 60 * 60 * 1000, this.data[i].time);
        this.data[i]["ema"] = this.emaInRange(this.data[i].time - 3 * 24 * 60 * 1000, this.data[i].time);
      }
      return this.lastTime = this.data[this.data.length - 1].time;
    };

    Market.prototype.averageInRange = function(lo, hi) {
      var avg, cnt, p, _i, _len, _ref;
      avg = 0;
      cnt = 0;
      _ref = this.data;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        p = _ref[_i];
        if (p.time >= lo && p.time <= hi) {
          avg += p.average;
          cnt += 1;
        }
      }
      return avg / cnt;
    };

    Market.prototype.emaInRange = function(lo, hi) {
      var alpha, ema, i, p, prices, _i, _len, _ref, _ref2;
      prices = [];
      _ref = this.data;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        p = _ref[_i];
        if (p.time >= lo && p.time <= hi) prices.push(p.average);
      }
      alpha = 2 / (prices.length + 1);
      ema = prices[0] * Math.pow(1 - alpha, prices.length - 1);
      for (i = 1, _ref2 = prices.length; 1 <= _ref2 ? i < _ref2 : i > _ref2; 1 <= _ref2 ? i++ : i--) {
        ema += alpha * Math.pow(1 - alpha, prices.length - i - 1) * prices[i];
      }
      return ema;
    };

    Market.prototype.findTrend = function() {
      if (this.ema() > this.sma12() && this.sma12() > this.sma24()) {
        return "uptrend";
      } else if (this.ema() > this.sma12()) {
        return "idle";
      } else {
        return "downtrend";
      }
    };

    return Market;

  })();

  exports.Market = Market;

}).call(this);
