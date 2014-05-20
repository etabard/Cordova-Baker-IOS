/** 
 * A plugin to integrate Baker Newsstand.
 *
 * Copyright (c) Emmanuel Tabard 2014
 */

var Baker = function () {
};

var noop = function () {};
var log = noop;

var exec = function (methodName, options, success, error) {
    cordova.exec(success, error, "Baker", methodName, options);
};

var protectCall = function (callback, context) {
    if (callback && typeof callback === 'function') {
        try {
            var args = Array.prototype.slice.call(arguments, 2); 
            callback.apply(this, args);
        }
        catch (err) {
            log('exception in ' + context + ': "' + err + '"');
        }
    }
};

Baker.prototype.init = function (options) {
    options = options || {}
    if (options.debug) {
        // exec('debug', [], noop, noop);
        log = function (msg) {
            console.log("Baker[js]: " + msg);
        };
    }
    var that = this;
    var setupOk = function () {
        log('setup ok');
        protectCall(options.success, 'init::success');
    };
    var setupFailed = function () {
        log('setup failed');
        protectCall(options.error, 'init::error');
    };
    exec('setup', [], setupOk, setupFailed);
};

Baker.prototype.restore = function() {
    var setupOk = function () {
        console.log('restore ok');
        protectCall(options.success, 'init::success');
    };
    var setupFailed = function () {
        console.log('restore failed');
        protectCall(options.error, 'init::error');
    };
    exec('restore', [], setupOk, setupFailed);
}

Baker.prototype.refresh = function() {
    var setupOk = function () {
        console.log('restore ok');
        protectCall(options.success, 'init::success');
    };
    var setupFailed = function () {
        console.log('restore failed');
        protectCall(options.error, 'init::error');
    };
    exec('refresh', [], setupOk, setupFailed);
}


module.exports = new Baker();
