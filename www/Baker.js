/** 
 * A plugin to integrate Baker Newsstand.
 *
 * Copyright (c) Emmanuel Tabard 2014
 */

var Baker = (function () {
    this.issues = [];
});


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
        // protectCall(options.success, 'init::success');
    };
    var setupFailed = function () {
        log('setup failed');
        // protectCall(options.error, 'init::error');
    };
    exec('setup', [], setupOk, setupFailed);
};

Baker.prototype.restore = function() {
    var setupOk = function () {
        console.log('restore ok');
        // protectCall(options.success, 'init::success');
    };
    var setupFailed = function () {
        console.log('restore failed');
        // protectCall(options.error, 'init::error');
    };
    exec('restore', [], setupOk, setupFailed);
}

Baker.prototype.refresh = function() {
    var setupOk = function () {
        console.log('restore ok');
        // protectCall(options.success, 'init::success');
    };
    var setupFailed = function () {
        console.log('restore failed');
        // protectCall(options.error, 'init::error');
    };
    exec('refresh', [], setupOk, setupFailed);
}

Baker.prototype.getBooks = function (success) {
    var self = this;

    var setupOk = function (books) {
        var actualBookIds = {};

        books.forEach(function(book) {
            actualBookIds[book.ID] = book;

            var _exists = self.issues.filter(function(tmp_book) {
                return (tmp_book.ID == book.ID);
            }).pop();

            if (_exists) {
                _exists.update(book);
                return;
            }
            self.issues.push(new BakerIssue(book));
        });

        //remove old books
        self.issues.filter(function(obj){
            return !(obj.ID in actualBookIds);
        }).forEach(function(book) {
            self.issues.splice(self.issues.indexOf(book), 1);
        });
        protectCall(success, 'getBooks::success', self.issues);
    };
    var setupFailed = function () {
        console.log('restore failed');
        protectCall(options.error, 'init::error');
    };
    exec('getBooks', [], setupOk, setupFailed);
}

Baker.prototype.getBookById = function (id) {
    return this.issues.filter(function(book) {
        return (book.ID == id);
    }).pop();
}

Baker.prototype.purchase = function(BookId) {
    exec('purchase', [BookId], function() {}, function() {});
};

Baker.prototype.download = function(BookId) {
    exec('download', [BookId], function() {}, function() {});
};

Baker.prototype.archive = function(BookId) {
    exec('archive', [BookId], function() {}, function() {});
};

Baker.prototype.getBookInfos = function(BookId, success, error) {
    var getOk = function (infos) {
        protectCall(success, 'getBookInfos::success', infos);
    };
    var getFailed = function () {
        protectCall(error, 'getBookInfos::error');
    };
    exec('getBookInfos', [BookId], getOk, getFailed);
}



var BakerIssue = (function (values) {
    if (values) {
        Object.keys(values).forEach(function(key) {
            this[key] = values[key];
        }.bind(this));
    }
});

BakerIssue.prototype.update = function (values) {
    Object.keys(values).forEach(function(key) {
        if (this[key] && this[key] == values[key]) {
            return;
        }

        this[key] = values[key];
    }.bind(this));

}

BakerIssue.prototype.purchase = function () {
    BakerInstance.purchase(this.ID);
}

BakerIssue.prototype.download = function () {
    BakerInstance.download(this.ID);
}

BakerIssue.prototype.archive = function () {
    BakerInstance.archive(this.ID);
}

BakerIssue.prototype.getInfos = function (success, error) {
    BakerInstance.getBookInfos(this.ID, success, error);
}

var BakerInstance = new Baker();

module.exports = BakerInstance;
