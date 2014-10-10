/*jshint strict:true */
/** 
 * A plugin to integrate Baker Newsstand.
 *
 * Copyright (c) Emmanuel Tabard 2014
 */
(function () {
    "use strict";

    var Baker = (function () {
        this.issues = [];
        this.ready = false;
        this.subscriptions = [];
        this.hasSubscribed = false;
        this.subscriptionExpiration = null;
        this.appID = null;
        this.userID = null;
    });


    var noop = function () {};
    var log = noop;

    var deferredEvents = [];

    var eventHandler = function (e, deferred) {
        var fireEvent = true;
        var eventType = e.eventType;
        var eventData = e.data;
        var book;
        var bookChanged = false;


        if (BakerInstance.ready && e.data.issue) {
            book = BakerInstance.getBookById(e.data.issue.ID);
        }

        if (BakerInstance.ready && e.data.issue && book) {
            //Prevent from updating old deferred datas
            if (!deferred) {
                bookChanged = book.update(e.data.issue);
            }
            eventData = book;
        } else if (BakerInstance.ready && e.data.issue && !book && e.eventType != 'BakerIssueAdded') {
            return;
        }
        switch(e.eventType) {
            case 'BakerRefreshStateChanged':
                if (!BakerInstance.ready && e.data.state === false) {
                    //First refresh ended
                    prepareBaker();
                } else if (!BakerInstance.ready && e.data.state === true) {
                    //First refresh is starting do nothing
                }
            break;
            case 'BakerSubscriptionStateChanged':
                BakerInstance.hasSubscribed = e.data.state;
                BakerInstance.subscriptionExpiration = e.data.expiration;
            break;
            case 'BakerIssueStateChanged':
                if (BakerInstance.ready) {
                    if (!bookChanged) {
                        fireEvent = false;
                    }

                    if (book.status != 'downloading') {
                        book.downloading = false;
                    }
                }
            break;
            case 'BakerIssueAdded':
                if (BakerInstance.ready) {
                    var newIssue = new BakerIssue(e.data.issue);
                    BakerInstance.issues.splice(e.data.index, 0, newIssue);
                    eventData = {
                        'index': e.data.index,
                        'issue': newIssue
                    }
                } else {
                    fireEvent = false;
                }
            break;
            case 'BakerIssueDeleted':
                if (BakerInstance.ready) {
                    var index = BakerInstance.issues.indexOf(book);
                    BakerInstance.issues.slice(index);
                    eventData = {
                        'index': index,
                        'issue': book
                    }
                } else {
                    fireEvent = false;
                }
            break;
            case 'BakerIssueCoverReady':
                if (!BakerInstance.ready) {
                    fireEvent = false;

                    deferredEvents.push(e);
                } else {
                    book.coverReady = true;
                }
            break;
            case 'BakerSubscriptionsUpdated':
                BakerInstance.subscriptions = e.data.subscriptions;
            break;
            case 'BakerIssueDownloadProgress':
                if (BakerInstance.ready) {
                    var progress = Math.round(e.data.progress * 100);

                    if (book.downloading && book.downloading.progress == progress) {
                        fireEvent = false;
                    }
                    book.downloading = {
                        progress: progress,
                        total: e.data.total,
                        written: e.data.written
                    };
                }
            break;
        }
        if (fireEvent) {
            fireDocumentEvent(eventType, eventData);
        }

        //Release data as we keep a reference
        book = null;
        eventType = null;
        eventData = null;
        e = null;
    };

    function createEvent(type, data) {
        var event = document.createEvent('Events');
        event.initEvent(type, false, false);
        if (data) {
            for (var i in data) {
                if (data.hasOwnProperty(i)) {
                    event[i] = data[i];
                }
            }
        }
        return event;
    }

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
                console.log('exception in ' + context + ': "' + err + '"');
            }
        }
    };

    var fireDocumentEvent = function(type, data) {
        console.log('[Baker] [JS] [Event] ', type);
        cordova.fireDocumentEvent(type, data);
    };

    var prepareBaker = function () {
        BakerInstance.getBooks(function () {
            BakerInstance.getSubscriptions(function () {
                BakerInstance.ready = true;
                fireDocumentEvent('BakerApplicationReady', BakerInstance);
                deferredEvents.forEach(function(e) {
                    eventHandler(e, true);
                });
            });
        });
    };

    Baker.prototype.init = function (options) {
        options = options || {};

        

        if (options.debug) {
            // exec('debug', [], noop, noop);
            log = function (msg) {
                console.log("Baker[js]: " + msg);
            };
        }
        var that = this;
        var setupOk = function (response) {
            BakerInstance.appID = response.appID;
            BakerInstance.userID = response.userID;
            log('setup ok');
            
            // protectCall(options.success, 'init::success');
        };
        var setupFailed = function () {
            log('setup failed');
            // protectCall(options.error, 'init::error');
        };
        var eventProtectHandler = function (e) {
            protectCall(eventHandler, 'eventHandler', e);
        };
        
        exec('startEventHandler', [], eventProtectHandler, noop);


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
    };

    Baker.prototype.refresh = function() {
        var setupOk = function () {
            console.log('refresh ok');
            // protectCall(options.success, 'init::success');
        };
        var setupFailed = function () {
            console.log('refresh failed');
            // protectCall(options.error, 'init::error');
        };
        exec('refresh', [], setupOk, setupFailed);
    };

    Baker.prototype.logout = function(success) {
        var setupOk = function (uuid) {
            console.log('logout ok');
            console.log(uuid);
            BakerInstance.userID = uuid;
            protectCall(success, 'logout::success');
            // protectCall(options.success, 'init::success');
        };
        var setupFailed = function () {
            console.log('logout failed');
            // protectCall(options.error, 'init::error');
        };

        exec('logout', [], setupOk, setupFailed);
    };

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
    };

    Baker.prototype.getBookById = function (id) {
        return this.issues.filter(function(book) {
            return (book.ID == id);
        }).pop();
    };

    Baker.prototype.purchase = function(BookId) {
        exec('purchase', [BookId], function() {}, function() {});
    };

    Baker.prototype.download = function(BookId) {
        exec('download', [BookId], function() {}, function() {});
    };

    Baker.prototype.cancelDownload = function(BookId) {
        exec('cancelDownload', [BookId], function() {}, function() {});
    };

    Baker.prototype.archive = function(BookId, silent) {
        if (silent) {
            exec('silentArchive', [BookId], function() {}, function() {});
        } else {
            exec('archive', [BookId], function() {}, function() {});
        }
        
    };

    Baker.prototype.getBookInfos = function(BookId, success, error) {
        var getOk = function (infos) {
            protectCall(success, 'getBookInfos::success', infos);
        };
        var getFailed = function () {
            protectCall(error, 'getBookInfos::error');
        };
        exec('getBookInfos', [BookId], getOk, getFailed);
    };

    Baker.prototype.getSubscriptions = function(success, error) {
        var getOk = function (infos) {
            BakerInstance.subscriptions = infos;
            protectCall(success, 'getSubscriptions::success', infos);
        };
        var getFailed = function () {
            protectCall(error, 'getSubscriptions::error');
        };
        exec('getSubscriptions', [], getOk, getFailed);
    };

    Baker.prototype.getSubscriptionById = function (productId) {
        return this.subscriptions.filter(function(sub) {
            return (sub.ID == productId);
        }).pop();
    }

    Baker.prototype.subscribe = function (productId) {
        exec('subscribe', [productId], function() {}, function() {});
    };



    var BakerIssue = (function (values) {
        this.downloading = false;
        this.coverReady = false;

        if (values) {
            Object.keys(values).forEach(function(key) {
                this[key] = values[key];
            }.bind(this));
        }

        if (!this.status) {
            this.status = null;
        }
    });

    BakerIssue.prototype.update = function (values) {
        var changed = false;
        Object.keys(values).forEach(function(key) {
            if (this[key] && this[key] == values[key]) {
                return;
            }
            changed = true;
            this[key] = values[key];
        }.bind(this));
        return changed;
    };

    BakerIssue.prototype.purchase = function () {
        BakerInstance.purchase(this.ID);
    };

    BakerIssue.prototype.download = function () {
        BakerInstance.download(this.ID);
    };

    BakerIssue.prototype.cancelDownload = function () {
        BakerInstance.cancelDownload(this.ID);
    };

    BakerIssue.prototype.archive = function (silent) {
        BakerInstance.archive(this.ID, silent);
    };

    BakerIssue.prototype.getInfos = function (success, error) {
        BakerInstance.getBookInfos(this.ID, success, error);
    };

    var BakerInstance = new Baker();

    module.exports = BakerInstance;

})();
