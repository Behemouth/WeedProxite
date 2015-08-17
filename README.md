# WeedProxite
Run Mirror Proxy Site.

## Setup

1. Clone project:
  ```
  git clone https://github.com/Behemouth/WeedProxite
  ```

2. Install:
  ```
  # You need to install Node.js and NPM first.
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
    mirrorLinks: ["http://your-mirror-site-domain:1984/"],
    allowHosts:[
      "sub-domain-of.upstream-target-site.com",
      "another-example-target-site.com"
    ]
  };
  ```

5. Run `node main.js` or use [PM2](https://www.npmjs.com/package/pm2) `pm2 start main.js --name my-mirror` for production.

6. Don't forget to set a daily restart Node.js server cronjob on production server if you enabled `httpsOptions` coz of Node.js HTTPS module memory leaks.

## Config Options

More config options please see `lib/Config.coffee`.

## Deploy to remote server.

1. Follow above steps to init site.

2. Upload your site directory to remote server.

3. Run `npm install --production` under your server site directory, the `--production` option will reduce dependent packages to download.

4. Run `node main.js` or use [PM2](https://www.npmjs.com/package/pm2) `pm2 start main.js --name my-mirror` to start server.

## Use Nginx

1. Please refer to this turtorial to install Nginx:  https://www.digitalocean.com/community/tutorials/how-to-configure-nginx-as-a-reverse-proxy-for-apache

2. Run mirror site: `node main.js`

3. Proxy pass to Node.js app server, for example your bind host is lo and port is 1984 :
    ```
    location / {
      proxy_set_header X-Real-IP  $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header Host $host;
      # ....Other configurations
      proxy_pass http://127.0.0.1:1984;
    }
    ```


