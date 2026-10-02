#!/usr/bin/env node
// Prints the Sonos household ID that contains the given room (default "Kitchen").
//
// node-sonos-http-api latches onto whichever speaker answers discovery first.
// The Roam SL (a separate S2 system) often wins, and then Kitchen disappears.
// Putting this ID in node-sonos-http-api/settings.json as "household" fixes that.
//
// Note: this is the short ID from the SSDP X-RINCON-HOUSEHOLD header. The longer
// HouseholdControlID on :1400/status/zp does NOT work.
//
// Usage: node find-household.js [Room]      (add --all to list every speaker)

const dgram = require('dgram');
const http = require('http');

const room = process.argv.slice(2).find((a) => !a.startsWith('--')) || 'Kitchen';
const listAll = process.argv.includes('--all');

const search = Buffer.from([
  'M-SEARCH * HTTP/1.1',
  'HOST: 239.255.255.250:1900',
  'MAN: "ssdp:discover"',
  'MX: 1',
  'ST: urn:schemas-upnp-org:device:ZonePlayer:1',
  '', ''
].join('\r\n'));

const speakers = new Map(); // ip -> household

function roomName(ip) {
  return new Promise((resolve) => {
    http.get({ host: ip, port: 1400, path: '/xml/device_description.xml', timeout: 3000 }, (res) => {
      let body = '';
      res.on('data', (d) => { body += d; });
      res.on('end', () => {
        const m = /<roomName>([^<]*)<\/roomName>/.exec(body);
        resolve(m ? m[1] : '?');
      });
    }).on('error', () => resolve('?')).on('timeout', function () { this.destroy(); });
  });
}

const socket = dgram.createSocket('udp4');
socket.on('message', (buf, rinfo) => {
  const m = /X-RINCON-HOUSEHOLD: *(\S+)/i.exec(buf.toString());
  if (m) speakers.set(rinfo.address, m[1]);
});

socket.bind(0, () => {
  socket.setBroadcast(true);
  let sent = 0;
  const timer = setInterval(() => {
    socket.send(search, 1900, sent++ % 2 ? '255.255.255.255' : '239.255.255.250');
    if (sent < 8) return;
    clearInterval(timer);
    setTimeout(finish, 2000);
  }, 1000);
});

async function finish() {
  socket.close();
  let found = null;
  for (const [ip, household] of speakers) {
    const name = await roomName(ip);
    if (listAll) console.error(`${ip}\t${name}\t${household}`);
    if (name.toLowerCase() === room.toLowerCase()) found = household;
  }
  if (!found) {
    console.error(`No speaker named "${room}" answered (${speakers.size} speakers found). Is it powered on?`);
    process.exit(1);
  }
  console.log(found);
}
