# WeedProxite
Run Mirror Proxy Site.

## Setup

1. Create mirror site directory and install WeedProxite (You need to install Node.js and NPM first):
  ```
  mkdir my-site
  cd my-site
  npm install --production git+https://github.com/Behemouth/WeedProxite.git
  # If you want to install global, add '-g' option
  # npm install --production -g git+https://github.com/Behemouth/WeedProxite.git
  ```

2. Init site:
  ```
  export PATH="$(npm bin):$PATH";
  proxite init
  # Or use relative path
  # ./node_modules/.bin/proxite init
  ```

3. Configure, edit `config.js`:
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

4. Run `node main.js` or use [PM2](https://www.npmjs.com/package/pm2) `pm2 start main.js --name my-mirror` for production.

5. Don't forget to set a daily restart Node.js server cronjob on production server if you enabled `httpsOptions` coz of Node.js HTTPS module memory leaks.

## Config Options

More config options please see `lib/Config.coffee`.


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


## Example sites:

https://github.com/Behemouth/sites
