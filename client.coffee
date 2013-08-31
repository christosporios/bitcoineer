
status = "loading"
server = ""

updateStatus = ->
  $.getJSON("#{server}/status", (data) ->
    if data.trend == "uninitialized"
      $("#trend").html("Calculating market trend...")
    else $("#trend").html(data.trend)
    if data.status != status
      status = data.status
      $("#status").html("Currently #{status}")
      $(".command").hide()
      $(".#{status}-command").show()
    
    $("#profit-val").removeClass('good')
    $("#profit-val").removeClass('bad')
    if data.profit >= 0
      $("#profit-val").addClass('good')
      $("#profit-val").html("↗ " + data.profit.toFixed(2) + "%")
    else
      $("#profit-val").addClass('bad')
      $("#profit-val").html("↘ " + data.profit.toFixed(2) + "%")

    $("#worth").html(data.value.toFixed(2) + "$")
    $("#worth-btc").html(data.btc.toFixed(2) + "B⃦")
    $("#worth-usd").html(data.usd.toFixed(2) + "$")

  )

valueChart = null
marketChart = null

updateValueChart = ->
  $.getJSON("#{server}/value", (data) ->
    valueChart.setData data
  )

minute = 60 * 1000
hour = 60 *  minute
day = 24 * hour


updateMarketChart = (since, interval) ->
  $.getJSON("#{server}/market?since=#{since}&interval=#{interval}", (data) ->
    max = 0
    min = 100000
    for x in data
      max = x.average if x.average > max
      min = x.average if x.average < min

    max = Math.ceil(max)
    min = Math.floor(min)

    marketChart.options.ymax = max
    marketChart.options.ymin = min
    marketChart.setData data
  )

curRange = null
curInterval = null 

updateCharts = (range, interval) ->
  curRange = range; curInterval = interval
  since = Date.now() - range

  console.log "updating charts"
  updateValueChart(since, interval)
  updateMarketChart(since, interval)

$(document).ready ->
  setInterval(updateStatus, 1000)
  valueChart = new Morris.Line {
      element: 'value-chart',
      data: [],
      xkey: 'time',
      ykeys: ['value'],
      labels: ['value']
    }

  marketChart = new Morris.Line {
      element: 'market-chart',
      data: [],
      xkey: 'time',
      ykeys: ['average', 'sma12', 'sma24', 'sma48', 'ema'],
      lineColors: ["#C99A00", "#1CCAD6", "#1C9ED6", "#1B63E0", "#B50415"]
      labels: ['CUR', 'SMA12', 'SMA24', 'SMA48', 'EMA'],
      preUnits: "$",
      pointSize: 0,
      lineWidth: 1,
      smooth: false,
      yLabelFormat: (x) -> "$" + x.toFixed(2)
    }
  
  updateCharts(3 * hour, 1 * minute)

  setInterval( ->
    updateCharts(curRange, curInterval)
  , 5000)
  setInterval(updateWiseWords, 15000)

  $("#scale-select a").click (el) ->
    return if $(this).hasClass("active")
    $("#scale-select a.active").removeClass("active")
    $(this).addClass("active")
    val = $(this).attr("value")
    if val == "3h" then updateCharts(3 * hour, 1 * minute)
    else if val == "1d" then updateCharts(day, 10 * minute)
    else if val == "3d" then updateCharts(3 * day, 30 * minute)
    else if val == "10d" then updateCharts(10 * day, 1 * hour)
  
  $(".command").click ->
    command = $(this).attr("name")
    $.ajax({
      url: "#{server}/action",
      method: "post",
      data: {password: $("#password").val(), cmd: command},
      statusCode: {
        401: ->
          alert "Wrong password"
        200: ->
          console.log "Command OK"
      }
    })
    console.log "Sent #{$("#password").val()}"
    $("#password").val("")


updateWiseWords = ->
  wiseWords = ["See the future, trade in the moment", "Greed is, for the lack of a better word, good", "Be greedy", "Money makes the world go round", "Money: power at its most liquid", "When Donald Duck traded his wings for arms, was he trading up or trading down?"]
  pick = wiseWords[Math.floor(Math.random()*wiseWords.length)]
  $("#wisewords").html pick
