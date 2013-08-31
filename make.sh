coffee -c config.coffee
coffee -c market.coffee
coffee -c app.coffee
coffee -c client.coffee

mv config.js build/
mv market.js build/
mv app.js build/
mv client.js build/public

node build/app.js
