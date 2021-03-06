var Module = require('module');

// If -i or --interactive were passed, or stdin is a TTY.
if (process.argv[0] == 'jmx-cli' && require('tty').isatty(0)) {
    // REPL
    var opts = {
      useGlobal: true,
      ignoreUndefined: false
    };
    if (parseInt(process.env['NODE_NO_READLINE'], 10)) {
      opts.terminal = false;
    }
    if (parseInt(process.env['NODE_DISABLE_COLORS'], 10)) {
      opts.useColors = false;
    }
    var repl = Module.requireRepl().start(opts);
    repl.on('exit', function() {
      process.exit();
    });
    process.stdin._readableState.objectMode = true;
    process.stdout._writableState.objectMode = true;
} else {
    // Read all of stdin - execute it.
    process.stdin.setEncoding('utf8');

    var code = '';
    process.stdin.on('data', function(d) {
      code += d;
    });

    process.stdin.on('end', function() {
      process._eval = code;
      evalScript('[stdin]');
    });
}



