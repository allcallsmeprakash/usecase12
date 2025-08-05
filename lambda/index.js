const https = require('https');
const querystring = require('querystring');

exports.handler = async (event) => {
  const code = event.queryStringParameters.code;

  const data = querystring.stringify({
    grant_type: 'authorization_code',
    client_id: '3eja0v1phajaecl3gf2oo2d07m',
    code: code,
    redirect_uri: 'https://d1y2b2h22gr5ly.cloudfront.net/index.html'
  });

  const options = {
    hostname: 'hello-world-app-prod-domain.auth.us-east-1.amazoncognito.com',
    path: '/oauth2/token',
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': data.length
    }
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
                 body: body
        });
      });
    });

    req.on('error', (e) => {
      reject({
        statusCode: 500,
        body: JSON.stringify({ error: e.message })
      });
    });

    req.write(data);
    req.end();
  });
};
