if (!Object.assign) Object.assign = function (result) {
	for (var i = 1; i < arguments.length; i++) {
		var arg = arguments[i];
		for (var k in arg) if (arg.hasOwnProperty(k)) result[k] = arg[k];
	}
	return result;
};
if (!Array.prototype.findIndex) Array.prototype.findIndex = function (callback, thisArg) {
	for (var i = 0; i < this.length; i++) {
		if (callback.call(thisArg, this[i], i, this)) return i;
	}
	return -1;
};
if (!Array.prototype.find) Array.prototype.find = function (callback, thisArg) {
	for (var i = 0; i < this.length; i++) {
		if (callback.call(thisArg, this[i], i, this)) return this[i];
	}
	return null;
};

var result = Object.assign(rs.status(), { config: config });

function applyWithLog(label, fn) {
	var args = Array.prototype.slice.call(arguments, applyWithLog.length);
	var entry = { command: label, args: args, result: {} };
	try {
		entry.result = fn.apply(null, args);
	} catch (e) {
		entry.error = e.toString();
		entry.errorStack = e.stack.trim().split("\n");
	}
	(result.changes||(result.changes = [])).push(entry);
	return entry.result;
}

if (result.ok === 0 && (result.code === 94 || result.startupStatus === 3)) {
	var version = db.version();
	version = version.split(".")
	version = version.map(function (_) { return parseInt(_); });

	if (version[0] < 3 || version[0] == 3 && version[1] <= 4) {
		var hostPrefix = getHostName() + ":";
		var members = config.members.slice();
		var primary = members.splice(members.findIndex(function (m) { return m.host.startsWith(hostPrefix); }), 1)[0];

		var lastResult = applyWithLog("rs.initiate", rs.initiate, Object.assign({}, config, { members: [primary] }));

		if (lastResult.ok) {
			for (var i = 0; i < members.length; i++) {
				var member = members[i];
				lastResult = applyWithLog("rs.add", function (m) { return rs.add(m); }, member);
				var count = 0;
				while (lastResult.ok === 0 && lastResult.codeName === "NotMaster" && ++count < 5) {
					sleep(count * 10);
					lastResult = applyWithLog("rs.add", function (m) { return rs.add(m); }, member);
				}
				if (!lastResult.ok) break;
			}
		}
	}
	else applyWithLog("rs.initiate", rs.initiate, config);
}

if (result.ok === 1) {
	// remove unhealty and unconfigured nodes
	for (var i = 0; i < result.members.length; i++) {
		var m = result.members[i];
		if (!m.health && !result.config.members.find(function (c) { return m.name === c.host; })) {
			var lastResult = applyWithLog("rs.remove", function (n) { return rs.remove(n); }, m.name);
			if (!lastResult.ok) break;
		}
	}
	// add missing configured nodes
	for (var i = 0; i < result.config.members.length; i++) {
		var c = result.config.members[i];
		if (!result.members.find(function (m) { return m.name === c.host; })) {
			var lastResult = applyWithLog("rs.add", function (m) { return rs.add(m); }, c);
			if (!lastResult.ok) break;
		}
	}
}

result.ready = result.ok === 1
	// every configured member is actual memeber
	&& !result.config.members.find(function (c) { return !!result.members.find(function (m) { return m.name === c.host; }) })
	// has unhealty members
	&& !!result.members.find(function (m) { return !m.health; })
	// has primary node
	&& !!result.members.find(function (m) { return m.state === 1; });
print(JSON.stringify(result));
