# WeedProxite
Run Mirror Proxy Site.

## Setup

1. Clone project:

  ```
  git clone https://github.com/Behemouth/WeedProxite
  ```
2. Install:
  ```
  cd WeedProxite
  npm install -g
  ```

3. Init site:
  ```
  mkdir /var/www/my-mirror
  cd /var/www/my-mirror
  proxite init
  ```
4. Configure: `vi config.js`
  ```
  module.exports = {
    upstream: "http://upstream-target-site.com",
    port:"1984",
    mirrorLinks: ["http://your-host-name:1984/"]
  };
  ```

5. Just run: `proxite run` or use PM2 `pm2 start main.js --name my-mirror`

6. Don't forget to set a daily restart Node.js server cronjob coz of Node.js memory leaks.

## Config Options

Please see `lib/Config.coffee`.
