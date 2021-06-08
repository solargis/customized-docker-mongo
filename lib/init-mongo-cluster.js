if (!Object.assign) Object.assign = function (result) {
	for (var i = 1; i < arguments.length; i++) {
		var arg = arguments[i];
		for (var k in arg) if (arg.hasOwnProperty(k)) result[k] = arg[k];
	}
	return result;
}
if (!Array.prototype.findIndex) Array.prototype.findIndex = function (callback, thisArg) {
	for (var i = 0; i < this.length; i++) {
		if (callback.call(thisArg, this[i], i, this)) return i;
	}
	return -1;
}
if (!Array.prototype.find) Array.prototype.find = function (callback, thisArg) {
	for (var i = 0; i < this.length; i++) {
		if (callback.call(thisArg, this[i], i, this)) return this[i];
	}
	return null;
}

var result = Object.assign(rs.status(), { config: config });

function explain(ready, msg) {
	(result.notYetReady || (result.notYetReady = [])).push(msg);
}

var hostPrefix = getHostName() + ":";

var thisNode = config.members.filter(function (m) { return m.host.startsWith(hostPrefix); });


function applyWithLog(label, fn) {
	var args = Array.prototype.slice.call(arguments, applyWithLog.length);
	var entry = { command: label, args: args, result: {} };
	try {
		entry.result = config.dryrun ? {ok:1, msg: 'dryrun'} : fn.apply(null, args);
	} catch (e) {
		entry.error = e.toString();
		entry.errorStack = e.stack.trim().split("\n");
	}
	(result.changes||(result.changes = [])).push(entry);
	return entry.result;
}

if (thisNode.length === 0) explain("Host '" + getHostName() + "' not found in configured members");
else if (thisNode.length > 1) explain("Host '" + getHostName() + "' found multiple times (" + thisNode.length + ") in configured members");
else {
	thisNode = thisNode[0];

	var primaryNodes = config.members
		.filter(function (m) { return !m.arbiterOnly && (!m.hasOwnProperty("priority") || m.priority > 0); })
		.sort(function (m1,m2) { return (m2.hasOwnProperty("priority") ? m2.priority : 1) - (m1.hasOwnProperty("priority") ? m1.priority : 1); });

	if (primaryNodes.length === 0) explain("No primary nodes configured");
	else {
		var isMaster = rs.isMaster();
		if (!isMaster.ok) explain("Unable chcek if host '" + getHostName() + "' is primary: " + JSON.stringify(isMaster));
		else if (result.ok === 1 && isMaster.ismaster) {
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
					var _id = i;
					// check if default _id is not already taken
					while (result.members.find(function (m) { return m._id === _id; }) || result.config.members.find(function (m) { return m._id === _id; })) _id++;
					c._id = _id;
					var lastResult = applyWithLog("rs.add", function (m) { return rs.add(m); }, c);
					if (!lastResult.ok) break;
				}
			}
		}
		else if (result.ok === 0 && (result.code === 94 || result.startupStatus === 3) && primaryNodes[0] === thisNode) {
			var version = db.version();
			version = version.split(".")
			version = version.map(function (_) { return parseInt(_); });

			for (var i = 0; i < config.members.length; i++) config.members[i]._id = i;

			if (version[0] < 3 || version[0] == 3 && version[1] <= 4) {
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
	}
}

if (result.ok === 1) {
	// every configured member must be an actual memeber
	var notInCluster = result.config.members
		.map(function (c) { return c.host; })
		.filter(function (host) { return !result.members.find(function (m) { return m.name === host; }); });
	if (notInCluster.length) explain("Nodes not included in cluster: " + notInCluster.join(", "));

	// has members must by heatly
	var unhealtyMembers = result.members.filter(function (m) { return !m.health; }).map(function (m) { return m.name; });
	if (unhealtyMembers.length) explain("Has unhealty members: " + unhealtyMembers.join(", "));

	// has primary node
	if (!result.members.find(function (m) { return m.state === 1; })) explain("No primary node found");
}

result.ready = result.ok === 1 && !result.notYetReady;
print(JSON.stringify(result));
