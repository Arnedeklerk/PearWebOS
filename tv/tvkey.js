// tvkey: press remote buttons on the TV, for testing (PearWebOS).
//   node tvkey.js DOWN RIGHT RIGHT OK BACK
//   node tvkey.js HOLD_OK          (OK held for a second)
// Writes key events into the IR remote's evdev node ("LGE RCU"); 32-bit ARM,
// so an input_event is 16 bytes: timeval (2 x int32), type, code, value.
var fs = require('fs');

var CODES = { UP: 103, DOWN: 108, LEFT: 105, RIGHT: 106, OK: 28, BACK: 412, HOME: 172 };
// raw codes for probing: K412 sends evdev code 412
function codeOf(n) { return /^K\d+$/.test(n) ? parseInt(n.slice(1), 10) : CODES[n]; }
var DEV = process.env.TVKEY_DEV || '/dev/input/event1';

function ev(type, code, value) {
    var b = Buffer.alloc(16);
    var t = Date.now();
    b.writeInt32LE(Math.floor(t / 1000), 0);
    b.writeInt32LE((t % 1000) * 1000, 4);
    b.writeUInt16LE(type, 8);
    b.writeUInt16LE(code, 10);
    b.writeInt32LE(value, 12);
    return b;
}

function key(fd, code, value) {
    fs.writeSync(fd, ev(1, code, value));
    fs.writeSync(fd, ev(0, 0, 0));
}

var fd = fs.openSync(DEV, 'w');
var names = process.argv.slice(2);
var i = 0;
(function next() {
    if (i >= names.length) { fs.closeSync(fd); return; }
    var name = names[i++];
    var hold = name.indexOf('HOLD_') === 0;
    var code = codeOf(hold ? name.slice(5) : name);
    if (code === undefined) { console.error('unknown key ' + name); process.exit(2); }
    key(fd, code, 1);
    var held = 0;
    // a held key repeats like a real remote
    var rep = hold ? setInterval(function () { key(fd, code, 2); held += 100; }, 100) : null;
    setTimeout(function () {
        if (rep) clearInterval(rep);
        key(fd, code, 0);
        setTimeout(next, 450);
    }, hold ? 1100 : 80);
})();
